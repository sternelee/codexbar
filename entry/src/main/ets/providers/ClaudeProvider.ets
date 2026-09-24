/**
 * Claude（Web 会话方式）用量查询
 *
 * 迁移自 macOS 版 Sources/CodexBarCore/Providers/Claude/ClaudeWeb/ClaudeWebAPIFetcher.swift：
 * 1. GET https://claude.ai/api/organizations           （Cookie: sessionKey=...）→ 取组织 uuid
 * 2. GET https://claude.ai/api/organizations/{uuid}/usage
 *    → five_hour / seven_day / seven_day_opus(.sonnet) 三个窗口（utilization 0-100 + resets_at ISO8601）
 *      + extra_usage（Extra usage 本月已用/上限，单位：分）
 * 3. 尽力而为：GET .../{uuid}/overage_spend_limit（extra_usage 缺失时的费用来源）
 *              GET .../{uuid}/prepaid/credits（预付余额，覆盖费用卡余额）
 */

import { Http } from '../net/Http';
import { asArray, asObj, Json, optNum, optStr, str } from '../net/Json';
import {
  makeWindow,
  NamedRateWindow,
  ProviderCostSnapshot,
  ProviderDescriptor,
  ProviderSetting,
  RateWindow,
  UsageSnapshot,
  AuthKind
} from '../model/Models';
import { Format } from '../common/Format';
import { UsageProvider, UrlUtil } from './ProviderBase';

class ClaudeWebProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'claude',
    title: 'Claude',
    authKind: AuthKind.SESSION,
    accentColor: '#CC7C5E',
    authHint: '粘贴 claude.ai 的 sessionKey（sk-ant-sid01-… 开头），或在设置页「网页登录」直接登录',
    authUrl: 'https://claude.ai/settings/billing',
  };

  private headers(sessionKey: string): Record<string, string> {
    const h: Record<string, string> = {
      'cookie': `sessionKey=${sessionKey}`,
      'accept': 'application/json',
      'user-agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36',
    };
    return h;
  }

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const key = setting.credential.trim();
    if (key.length === 0) {
      return UsageSnapshot.failure('未配置 sessionKey');
    }
    const headers = this.headers(key);

    // 第一步：组织列表
    const orgResp = await Http.get('https://claude.ai/api/organizations', headers);
    if (!orgResp.ok) {
      return UsageSnapshot.failure(orgResp.errorText());
    }
    const orgs = asArray(orgResp.json());
    if (orgs == null || orgs.length === 0) {
      return UsageSnapshot.failure('未找到组织，sessionKey 可能已失效');
    }
    let orgId = '';
    let orgName = '';
    let email = '';
    // 若填了第二凭证（组织 ID）则精确匹配
    const wanted = setting.credential2.trim();
    for (let i = 0; i < orgs.length; i++) {
      const o = asObj(orgs[i]);
      if (o == null) {
        continue;
      }
      const uuid = str(o, 'uuid');
      if (wanted.length > 0 && uuid !== wanted) {
        continue;
      }
      orgId = uuid;
      orgName = str(o, 'name');
      email = str(o, 'email');
      break;
    }
    if (orgId.length === 0 && wanted.length === 0) {
      const first = asObj(orgs[0]);
      if (first != null) {
        orgId = str(first, 'uuid');
        orgName = str(first, 'name');
        email = str(first, 'email');
      }
    }
    if (orgId.length === 0) {
      return UsageSnapshot.failure('无法解析组织信息');
    }

    // 第二步：用量
    const usageUrl = `https://claude.ai/api/organizations/${UrlUtil.encode(orgId)}/usage`;
    const usageResp = await Http.get(usageUrl, headers);
    if (!usageResp.ok) {
      return UsageSnapshot.failure(usageResp.errorText());
    }
    const root = asObj(usageResp.json());
    if (root == null) {
      return UsageSnapshot.failure('响应解析失败');
    }

    const session = ClaudeWebProvider.windowOf(root, 'five_hour');
    const weekly = ClaudeWebProvider.windowOf(root, 'seven_day');
    let opus = ClaudeWebProvider.windowOf(root, 'seven_day_sonnet');
    if (opus == null) {
      opus = ClaudeWebProvider.windowOf(root, 'seven_day_opus');
    }

    // 第三步（尽力而为，对照 ClaudeWebAPIFetcher）：Extra usage 费用与预付余额
    // /usage 里的 extra_usage；缺失时回退 /overage_spend_limit；最后用 /prepaid/credits 覆盖余额
    let cost = claudeExtraUsageCost(root['extra_usage']);
    const orgBase = `https://claude.ai/api/organizations/${UrlUtil.encode(orgId)}`;
    if (cost == null) {
      const overage = await Http.get(`${orgBase}/overage_spend_limit`, headers);
      if (overage.ok) {
        cost = claudeOverageSpendLimitCost(overage.json());
      }
    }
    const prepaid = await Http.get(`${orgBase}/prepaid/credits`, headers);
    if (prepaid.ok) {
      cost = claudePrepaidBalanceCost(prepaid.json(), cost);
    }

    // 主窗口缺失但 Extra usage 开启：源工程把它当"消费限额窗口"展示
    let primary = session;
    if (primary == null && cost != null && cost.limit != null && cost.limit > 0) {
      const pct = Math.max(0, Math.min(100, (cost.used / cost.limit) * 100));
      primary = makeWindow(pct, 0, true);
    }

    const snap = UsageSnapshot.success(primary, weekly, opus);
    // 附加泳道：模型限定周额度（"X only"）在前、Daily Routines 在后（对照 ClaudeWebExtraRateWindowParser）
    snap.extraRateWindows = claudeExtraRateWindows(root);
    snap.identity = { accountEmail: email, accountOrganization: orgName, loginMethod: 'sessionKey' };
    if (cost != null) {
      snap.providerCost = cost;
    }
    return snap;
  }

  /** 解析 {"utilization": 0-100, "resets_at": ISO} 形状 */
  private static windowOf(root: Record<string, Json>, key: string): RateWindow | null {
    const o = asObj(root[key]);
    if (o == null) {
      return null;
    }
    const util = optNum(o, 'utilization');
    if (util == null) {
      return null;
    }
    const percent = Math.max(0, Math.min(100, util));
    let resets = 0;
    const iso = optStr(o, 'resets_at');
    if (iso != null && iso.length > 0) {
      const parsed = Date.parse(iso);
      if (!isNaN(parsed)) {
        resets = parsed;
      }
    }
    return makeWindow(percent, resets, true);
  }
}

/** ISO8601 → 毫秒；缺失或解析失败为 0 */
function claudeIsoMs(iso: string | null): number {
  if (iso == null || iso.length === 0) {
    return 0;
  }
  const parsed = Date.parse(iso);
  return isNaN(parsed) ? 0 : parsed;
}

/**
 * 泳道 ID 用的 slug（对照 ClaudeScopedWeeklyLimitMapper.slug）：非字母数字压成单个 "-"，去掉首尾 "-"。
 * 例："Claude 3.5 Sonnet" → "claude-3-5-sonnet"。
 */
export function claudeSlug(value: string): string {
  const lower = value.toLowerCase();
  let out = '';
  let lastDash = false;
  for (let i = 0; i < lower.length; i++) {
    const ch = lower.charAt(i);
    const isAlnum = (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9');
    if (isAlnum) {
      out += ch;
      lastDash = false;
    } else if (!lastDash) {
      out += '-';
      lastDash = true;
    }
  }
  while (out.length > 0 && out.charAt(0) === '-') {
    out = out.slice(1);
  }
  while (out.length > 0 && out.charAt(out.length - 1) === '-') {
    out = out.slice(0, out.length - 1);
  }
  return out;
}

/** "All models" 范围不算模型限定泳道（标题等价 all-models，或 modelID 以 -all-models 结尾） */
export function claudeIsAllModelsScope(modelID: string, modelName: string): boolean {
  if (claudeSlug(modelName) === 'all-models') {
    return true;
  }
  if (modelID.length === 0) {
    return false;
  }
  const idSlug = claudeSlug(modelID);
  return idSlug === 'all-models' || idSlug.endsWith('-all-models');
}

/** Daily Routines 在响应里的候选键（对照 ClaudeWebExtraRateWindowParser.definitions） */
const CLAUDE_ROUTINES_KEYS: string[] = [
  'seven_day_routines',
  'seven_day_claude_routines',
  'claude_routines',
  'routines',
  'routine',
  'seven_day_cowork',
  'cowork',
];

/**
 * /usage 响应的附加泳道（对照 ClaudeWebExtraRateWindowParser.parse）：
 * 1. limits[] 里 kind=weekly_scoped / group=weekly 的模型限定周额度 → id `claude-weekly-scoped-<slug>`、标题 `"<模型名> only"`；
 *    all-models 范围与重复 id 跳过。
 * 2. Daily Routines（seven_day_routines 等候选键，取第一个形状对的）。
 */
export function claudeExtraRateWindows(root: Record<string, Json>): NamedRateWindow[] {
  const out: NamedRateWindow[] = [];
  const limits = asArray(root['limits']);
  if (limits != null) {
    const seen: string[] = [];
    for (let i = 0; i < limits.length; i++) {
      const entry = asObj(limits[i]);
      if (entry == null) {
        continue;
      }
      if (optStr(entry, 'group') !== 'weekly' || optStr(entry, 'kind') !== 'weekly_scoped') {
        continue;
      }
      const percent = optNum(entry, 'percent');
      if (percent == null || !isFinite(percent)) {
        continue;
      }
      const scope = asObj(entry['scope']);
      const model = scope != null ? asObj(scope['model']) : null;
      const modelName = model != null ? optStr(model, 'display_name') : null;
      const modelID = model != null ? optStr(model, 'id') : null;
      if (modelName == null || modelName.length === 0) {
        continue;
      }
      if (claudeIsAllModelsScope(modelID ?? '', modelName)) {
        continue;
      }
      const slug = claudeSlug(modelID != null && modelID.length > 0 ? modelID : modelName);
      if (slug.length === 0) {
        continue;
      }
      const id = `claude-weekly-scoped-${slug}`;
      let duplicated = false;
      for (let j = 0; j < seen.length; j++) {
        if (seen[j] === id) {
          duplicated = true;
          break;
        }
      }
      if (duplicated) {
        continue;
      }
      seen.push(id);
      out.push({
        id: id,
        title: `${modelName} only`,
        window: makeWindow(percent, claudeIsoMs(optStr(entry, 'resets_at'))),
      });
    }
  }
  for (let i = 0; i < CLAUDE_ROUTINES_KEYS.length; i++) {
    const w = asObj(root[CLAUDE_ROUTINES_KEYS[i]]);
    if (w == null) {
      continue;
    }
    const utilization = optNum(w, 'utilization');
    if (utilization == null) {
      continue;
    }
    out.push({
      id: 'claude-routines',
      title: 'Daily Routines',
      window: makeWindow(utilization, claudeIsoMs(optStr(w, 'resets_at'))),
    });
    break;
  }
  return out;
}

/**
 * /usage 响应里的 extra_usage → 费用快照（对照 ClaudeWebExtraUsageCost.parse）。
 * 字段：used_credits / monthly_limit（或 monthly_credit_limit）/ currency，单位是"分"。
 * 缺失或 limit <= 0 时返回 null。
 */
export function claudeExtraUsageCost(value: Json | null): ProviderCostSnapshot | null {
  const u = asObj(value);
  if (u == null) {
    return null;
  }
  const used = optNum(u, 'used_credits');
  let limit = optNum(u, 'monthly_limit');
  if (limit == null) {
    limit = optNum(u, 'monthly_credit_limit');
  }
  if (used == null || limit == null || limit <= 0) {
    return null;
  }
  return claudeUsageCost(used, limit, optStr(u, 'currency'), 'Monthly cap');
}

/** /overage_spend_limit 响应 → 费用快照（is_enabled !== true 时不展示） */
export function claudeOverageSpendLimitCost(value: Json): ProviderCostSnapshot | null {
  const o = asObj(value);
  if (o == null) {
    return null;
  }
  const enabled = o['is_enabled'];
  if (enabled !== true) {
    return null;
  }
  const used = optNum(o, 'used_credits');
  const limit = optNum(o, 'monthly_credit_limit');
  if (used == null || limit == null || limit <= 0) {
    return null;
  }
  return claudeUsageCost(used, limit, optStr(o, 'currency'), 'Monthly cap');
}

/**
 * /prepaid/credits 响应 → 用预付余额覆盖 remaining（对照 applyingPrepaidBalance）：
 * 币种不同则保留原费用；原本没有费用时以余额单独立卡（period = Extra usage）。
 */
export function claudePrepaidBalanceCost(value: Json, existing: ProviderCostSnapshot | null): ProviderCostSnapshot | null {
  const p = asObj(value);
  if (p == null) {
    return existing;
  }
  const amount = optNum(p, 'amount');
  const currency = optStr(p, 'currency');
  if (amount == null || currency == null || currency.length === 0) {
    return existing;
  }
  if (existing != null) {
    if (existing.currency.toUpperCase() !== currency.toUpperCase()) {
      return existing;
    }
    const updated: ProviderCostSnapshot = {
      remaining: amount,
      used: existing.used,
      currency: existing.currency,
      displayText: Format.money(amount, existing.currency),
      period: existing.period,
      limit: existing.limit,
    };
    return updated;
  }
  const fresh: ProviderCostSnapshot = {
    remaining: amount,
    used: 0,
    currency: currency,
    displayText: Format.money(amount, currency),
    period: 'Extra usage',
    limit: 0,
  };
  return fresh;
}

/** 分 → 元，并按源工程文案组织费用快照 */
function claudeUsageCost(usedCredits: number, monthlyCreditLimit: number, currency: string | null, period: string): ProviderCostSnapshot {
  const code = currency != null && currency.length > 0 ? currency : 'USD';
  const used = usedCredits / 100;
  const limit = monthlyCreditLimit / 100;
  const cost: ProviderCostSnapshot = {
    remaining: Math.max(0, limit - used),
    used: used,
    currency: code,
    displayText: Format.money(Math.max(0, limit - used), code),
    period: period,
    limit: limit,
  };
  return cost;
}

export function createClaudeProvider(): UsageProvider {
  return new ClaudeWebProvider();
}
