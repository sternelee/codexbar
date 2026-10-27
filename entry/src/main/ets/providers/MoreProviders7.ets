/**
 * 服务商第八批（对照源工程插件逐行迁移）：
 * - Trae CN:    Cookie → POST api.trae.cn/cloudide/api/v3/common/GetUserToken 换 Cloud-IDE-JWT
 *               → POST api.trae.cn/trae/api/v2/pay/user_current_entitlement_list
 * - Zed:        Cookie（cloud.zed.dev/frontend/billing/usage）或 Editor API（第二凭证 + extraConfig API_URL）
 * - Vercel AI Gateway: GET ai-gateway.vercel.sh/v1/credits（Bearer AI Gateway Key）
 */

import { Http, HttpResult } from '../net/Http';
import { asArray, asObj, Json, optNum, optStr } from '../net/Json';
import {
  AuthKind,
  makeWindow,
  NamedRateWindow,
  ProviderDescriptor,
  ProviderDetailRow,
  ProviderDetailSection,
  ProviderIdentitySnapshot,
  ProviderSetting,
  RateWindow,
  UsageSnapshot
} from '../model/Models';
import { UsageProvider } from './ProviderBase';
import { Format } from '../common/Format';
import { LT } from '../common/I18n';

// ---------------------------------------------------------------------------
// Trae CN（trae.cn 会话 Cookie → Cloud-IDE-JWT → 权益用量）
// ---------------------------------------------------------------------------

class TraeCnProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'traecn',
    title: LT('Trae CN'),
    authKind: AuthKind.SESSION,
    accentColor: '#0A7CFF',
    authHint: LT('粘贴 trae.cn 的会话 Cookie（浏览器 Network 面板整段复制）'),
    authUrl: 'https://www.trae.cn',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const cookie = setting.credential.trim();
    if (cookie.length === 0) {
      return UsageSnapshot.failure(LT('未配置会话 Cookie'));
    }
    const baseHeaders: Record<string, string> = {
      'cookie': cookie,
      'origin': 'https://www.trae.cn',
      'referer': 'https://www.trae.cn/',
    };
    const signIn = LT('请先登录 trae.cn，再粘贴会话 Cookie');

    // 1. Cookie → 一次性 Cloud-IDE-JWT（对照源工程 GetUserToken）
    const tokenResp = await Http.post('https://api.trae.cn/cloudide/api/v3/common/GetUserToken', baseHeaders, '');
    if (tokenResp.code === 401 || tokenResp.code === 403 ||
      (tokenResp.code >= 300 && tokenResp.code < 400)) {
      return UsageSnapshot.failure(signIn);
    }
    if (!tokenResp.ok) {
      return UsageSnapshot.failure(tokenResp.errorText());
    }
    const tokenRoot = asObj(tokenResp.json());
    const result = tokenRoot != null ? asObj(tokenRoot['Result']) : null;
    const token = result != null ? optStr(result, 'Token') : null;
    if (token == null || token.trim().length === 0) {
      return UsageSnapshot.failure(LT('Trae CN 响应格式已变化'));
    }

    // 2. JWT → 权益用量（对照源工程 user_current_entitlement_list）
    const usageHeaders: Record<string, string> = {
      'cookie': cookie,
      'origin': 'https://www.trae.cn',
      'referer': 'https://www.trae.cn/',
      'authorization': `Cloud-IDE-JWT ${token.trim()}`,
      'content-type': 'application/json',
    };
    const usageResp = await Http.post(
      'https://api.trae.cn/trae/api/v2/pay/user_current_entitlement_list',
      usageHeaders,
      '{"require_usage":true,"full_data":true}'
    );
    if (usageResp.code === 401 || usageResp.code === 403 ||
      (usageResp.code >= 300 && usageResp.code < 400)) {
      return UsageSnapshot.failure(signIn);
    }
    if (!usageResp.ok) {
      return UsageSnapshot.failure(usageResp.errorText());
    }
    const payload = asObj(usageResp.json());
    if (payload == null) {
      return UsageSnapshot.failure(LT('Trae CN 响应格式已变化'));
    }
    const code = optNum(payload, 'code');
    if (code === 1001) {
      return UsageSnapshot.failure(signIn);
    }
    if (boolIs(payload, 'is_credits_billing') !== true) {
      return UsageSnapshot.failure(LT('Trae CN 响应格式已变化'));
    }
    const summary = asObj(payload['usage_summary']);
    const total = summary != null ? optNum(summary, 'total_amount') : null;
    const used = summary != null ? optNum(summary, 'consumed_amount') : null;
    if (total == null || used == null) {
      return UsageSnapshot.failure(LT('Trae CN 响应格式已变化'));
    }

    // 3. 套餐名：group_type=0 且 status=1（或缺省）的权益包 display_desc
    let plan = '';
    const packs = asArray(payload['user_entitlement_pack_list']);
    if (packs != null) {
      for (let i = 0; i < packs.length && plan.length === 0; i++) {
        const pack = asObj(packs[i]);
        if (pack == null) {
          continue;
        }
        const groupType = optNum(pack, 'group_type');
        const status = optNum(pack, 'status');
        const desc = optStr(pack, 'display_desc');
        if (groupType === 0 && (status == null || status === 1) && desc != null && desc.trim().length > 0) {
          plan = desc.trim();
        }
      }
    }

    const primary: RateWindow | null =
      total > 0 ? makeWindow(Math.min(100, (used / total) * 100), 0, true) : null;
    const snap = UsageSnapshot.success(primary, null, null);
    if (plan.length > 0) {
      snap.identity = { accountEmail: '', accountOrganization: '', loginMethod: plan };
    }
    snap.details = [{
      title: 'Credits',
      rows: [
        { label: LT('已用'), value: Format.creditsNumber(used) },
        { label: LT('总量'), value: Format.creditsNumber(total) },
        { label: LT('剩余'), value: Format.creditsNumber(Math.max(0, total - used)) },
      ],
    }];
    return snap;
  }
}

/** bool 读取（本地 Json 工具无 bool 版） */
function boolIs(o: Record<string, Json>, key: string): boolean {
  return o[key] === true;
}

// ---------------------------------------------------------------------------
// Zed（cloud.zed.dev Cookie 或 Editor API）
// ---------------------------------------------------------------------------

const ZED_USAGE_URL = 'https://cloud.zed.dev/frontend/billing/usage';

class ZedProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'zed',
    title: LT('Zed'),
    authKind: AuthKind.SESSION,
    accentColor: '#084CCF',
    authHint: LT('粘贴 zed.dev 的会话 Cookie；或第二栏填 Editor 凭证、API URL 栏填地址走 API 模式'),
    authUrl: 'https://zed.dev',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const cookie = setting.credential.trim();
    const apiAuth = setting.credential2.trim();
    const apiUrl = extraValue(setting.extraConfig, 'api_url');
    // API 模式：明确填了 API URL 或 Editor 凭证（无 "=" 视为 token，整段 Cookie 必含 "="）
    const useApi = apiUrl.length > 0 || (apiAuth.length > 0 && apiAuth.indexOf('=') < 0);
    if (cookie.length === 0 && !useApi) {
      return UsageSnapshot.failure(LT('未配置会话 Cookie'));
    }

    let resp: HttpResult;
    let web = false;
    if (useApi) {
      if (apiUrl.length === 0 || !apiUrl.toLowerCase().startsWith('https://')) {
        return UsageSnapshot.failure(LT('Zed API 模式需要 https 的 API URL'));
      }
      if (apiAuth.length === 0) {
        return UsageSnapshot.failure(LT('Zed API 模式需要 Editor 凭证'));
      }
      resp = await Http.get(apiUrl, {
        'accept': 'application/json',
        'authorization': apiAuth,
      });
    } else {
      web = true;
      resp = await Http.get(ZED_USAGE_URL, {
        'accept': 'application/json',
        'cookie': cookie,
      });
    }
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    const root = asObj(resp.json());
    if (root == null) {
      return UsageSnapshot.failure(LT('Zed 响应解析失败'));
    }
    return web ? this.parseWeb(root) : this.parseApi(root);
  }

  /** Web 模式：token_spend 费用 + edit_predictions 主窗口 + 订阅周期副窗口（对照 zed.js web 分支） */
  private parseWeb(root: Record<string, Json>): UsageSnapshot {
    const currentUsage = asObj(root['current_usage']);
    const spend = currentUsage != null ? asObj(currentUsage['token_spend']) : null;
    if (spend == null) {
      return UsageSnapshot.failure(LT('Zed 响应解析失败'));
    }
    const spentCents = optNum(spend, 'spend_in_cents');
    if (spentCents == null) {
      return UsageSnapshot.failure(LT('Zed 响应解析失败'));
    }
    const spent = spentCents / 100;
    const limitCents = optNum(spend, 'limit_in_cents');

    // 主窗口：edit_predictions（可无 → 只出费用）
    let primary: RateWindow | null = null;
    const predictions = currentUsage != null ? asObj(currentUsage['edit_predictions']) : null;
    if (predictions != null) {
      const used = optNum(predictions, 'used');
      const rawLimit = predictions['limit'];
      const unlimited = rawLimit === 'unlimited' || rawLimit == null;
      const limit = !unlimited && typeof rawLimit === 'object' ? optNum(asObj(rawLimit) ?? {}, 'limited') : null;
      const limitNum = !unlimited && typeof rawLimit === 'number' ? rawLimit as number : limit;
      if (used != null && limitNum != null && limitNum > 0) {
        primary = makeWindow(Math.min(100, (used / limitNum) * 100), 0, true);
      } else if (used != null && unlimited) {
        primary = makeWindow(0, 0, true);
      }
    }

    const snap = UsageSnapshot.success(primary, null, null);
    if (limitCents != null && limitCents > 0) {
      snap.providerCost = {
        remaining: Math.max(0, limitCents / 100 - spent),
        used: spent,
        currency: 'USD',
        displayText: Format.money(spent, 'USD'),
        period: LT('本计费周期'),
        limit: limitCents / 100,
      };
    }
    const rows: ProviderDetailRow[] = [
      { label: LT('已花费'), value: Format.money(spent, 'USD') },
      { label: LT('花费上限'), value: limitCents != null ? Format.money(limitCents / 100, 'USD') : LT('未上报') },
    ];
    if (limitCents != null) {
      rows.push({ label: LT('剩余预算'), value: Format.money(Math.max(0, limitCents / 100 - spent), 'USD') });
    }
    snap.details = [{ title: LT('Token 花费'), rows: rows }];
    return snap;
  }

  /** API 模式：plan.plan_v3 / plan.usage / user.github_login / 周期与逾期（对照 zed.js API 分支） */
  private parseApi(root: Record<string, Json>): UsageSnapshot {
    const plan = asObj(root['plan']);
    const planNameRaw = plan != null ? optStr(plan, 'plan_v3') : null;
    const planName = planNameRaw != null ? planNameRaw.replace(/_/g, ' ').trim() : '';
    const usage = plan != null ? asObj(plan['usage']) : null;
    const predictions = usage != null ? asObj(usage['edit_predictions']) : null;

    // 主窗口：edit_predictions
    let primary: RateWindow | null = null;
    if (predictions != null) {
      const used = optNum(predictions, 'used');
      const rawLimit = predictions['limit'];
      const unlimited = rawLimit === 'unlimited';
      const limitObj = typeof rawLimit === 'object' ? asObj(rawLimit) : null;
      const limit = typeof rawLimit === 'number' ? rawLimit as number :
        (limitObj != null ? optNum(limitObj, 'limited') : null);
      if (used != null && limit != null && limit > 0) {
        primary = makeWindow(Math.min(100, (used / limit) * 100), 0, true);
      } else if (unlimited) {
        primary = makeWindow(0, 0, true);
      }
    }

    // 身份：GitHub 登录名 + 显示名
    const user = asObj(root['user']);
    const identity: ProviderIdentitySnapshot = {
      accountEmail: user != null ? optStr(user, 'github_login') ?? '' : '',
      accountOrganization: user != null ? optStr(user, 'name') ?? '' : '',
      loginMethod: planName.length > 0 ? planName : 'Zed',
    };

    // 订阅周期 → 副窗口
    let secondary: RateWindow | null = null;
    const period = plan != null ? asObj(plan['subscription_period']) : null;
    if (period != null) {
      const startIso = optStr(period, 'started_at');
      const endIso = optStr(period, 'ended_at');
      if (startIso != null && endIso != null) {
        const start = Date.parse(startIso);
        const end = Date.parse(endIso);
        if (!isNaN(start) && !isNaN(end)) {
          const now = Date.now();
          const pct = end > start ? ((now - start) / (end - start)) * 100 : 0;
          // 周期进度（对照源工程 subscription_period → secondary）
          secondary = makeWindow(Math.min(100, Math.max(0, pct)), end, true);
        }
      }
    }

    const snap = UsageSnapshot.success(primary, secondary, null);
    snap.identity = identity;

    // 逾期账单 → Billing 附加窗口
    if (plan != null && plan['has_overdue_invoices'] === true) {
      const overdue: NamedRateWindow[] = [{
        id: 'zed.overdue-invoices',
        title: LT('账单'),
        window: makeWindow(100, 0, false),
      }];
      snap.extraRateWindows = overdue;
    }

    const rows: ProviderDetailRow[] = [];
    if (user != null) {
      rows.push({ label: 'GitHub', value: optStr(user, 'github_login') ?? '' });
    }
    if (rows.length > 0) {
      snap.details = [{ title: 'Account', rows: rows }];
    }
    return snap;
  }
}

/** 读取 extraConfig（JSON 文本）里的单个键 */
function extraValue(text: string, key: string): string {
  if (text == null || text.length === 0) {
    return '';
  }
  try {
    const map = JSON.parse(text) as Record<string, string>;
    const v = map[key];
    return typeof v === 'string' ? v : '';
  } catch (e) {
    return '';
  }
}

// ---------------------------------------------------------------------------
// Vercel AI Gateway（API Key → credits 余额）
// ---------------------------------------------------------------------------

class VercelProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'vercel',
    title: LT('Vercel AI Gateway'),
    authKind: AuthKind.API_KEY,
    accentColor: '#000000',
    authHint: LT('粘贴 Vercel AI Gateway Key（ai-gateway.vercel.sh 控制台生成）'),
    authUrl: 'https://vercel.com/ai-gateway',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const key = setting.credential.trim();
    if (key.length === 0) {
      return UsageSnapshot.failure(LT('未配置 API Key'));
    }
    const resp = await Http.get('https://ai-gateway.vercel.sh/v1/credits', {
      'authorization': `Bearer ${key}`,
      'accept': 'application/json',
    });
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    const data = asObj(resp.json());
    if (data == null) {
      return UsageSnapshot.failure(LT('Vercel AI Gateway 响应解析失败'));
    }
    const balanceRaw = optStr(data, 'balance');
    const spentRaw = optStr(data, 'total_used');
    const balance = moneyNumber(balanceRaw);
    const spent = moneyNumber(spentRaw);
    if (balance == null || spent == null || spent < 0) {
      return UsageSnapshot.failure(LT('Vercel AI Gateway 响应解析失败'));
    }
    const snap = UsageSnapshot.success(null, null, null);
    snap.providerCost = {
      remaining: balance,
      used: spent,
      currency: 'USD',
      displayText: Format.money(balance, 'USD'),
    };
    snap.identity = { accountEmail: '', accountOrganization: '', loginMethod: 'API' };
    snap.details = [{
      title: LT('团队额度'),
      rows: [
        { label: LT('可用余额'), value: Format.money(balance, 'USD') },
        { label: LT('累计消费'), value: Format.money(spent, 'USD') },
      ],
    }];
    return snap;
  }
}

/** 字符串金额（对照源工程 money()：纯数字串，可负可小）；导出供单元测试覆盖 */
export function moneyNumber(value: string | null): number | null {
  if (value == null || !/^-?\d+(?:\.\d+)?$/.test(value)) {
    return null;
  }
  const n = Number(value);
  return isFinite(n) ? n : null;
}

export function createTraeCnProvider(): UsageProvider {
  return new TraeCnProvider();
}

export function createZedProvider(): UsageProvider {
  return new ZedProvider();
}

export function createVercelProvider(): UsageProvider {
  return new VercelProvider();
}
