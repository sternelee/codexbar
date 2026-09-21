/**
 * API-Key / 会话型服务商第二批（对照 macOS 版逐家迁移）：
 * - ZenMux:   GET zenmux.ai/api/v1/management/subscription/detail + payg/balance（Management Key）
 * - Manus:    POST api.manus.im/user.v1.UserService/GetAvailableCredits（会话 token）
 * - DeepInfra: GET api.deepinfra.com/payment/checklist + /payment/usage（Bearer Key）
 * - Perplexity: GET perplexity.ai/rest/billing/credits（会话 Cookie）
 * - Kimi(kimi.com 编码版): POST apiv2 BillingService/GetUsages（authToken）
 */

import { Http } from '../net/Http';
import { asArray, asObj, bool, Json, num, optNum, optStr, str } from '../net/Json';
import {
  AuthKind,
  makeWindow,
  NamedRateWindow,
  ProviderCostSnapshot,
  ProviderDescriptor,
  ProviderDetailRow,
  ProviderDetailSection,
  ProviderSetting,
  RateWindow,
  UsageSnapshot
} from '../model/Models';
import { UsageProvider } from './ProviderBase';
import { Format } from '../common/Format';

/** ISO8601 → 毫秒；失败返回 0 */
function isoToMs(iso: string | null): number {
  if (iso == null || iso.length === 0) {
    return 0;
  }
  const parsed = Date.parse(iso);
  return isNaN(parsed) ? 0 : parsed;
}

// ---------------------------------------------------------------------------
// ZenMux
// ---------------------------------------------------------------------------

class ZenMuxProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'zenmux',
    title: 'ZenMux',
    authKind: AuthKind.API_KEY,
    accentColor: '#6366F1',
    authHint: '粘贴 ZenMux Management API Key（普通推理 Key 不支持）',
    authUrl: 'https://zenmux.ai/settings/management-keys',
  };

  private static quotaOf(parent: Record<string, Json> | null, key: string): RateWindow | null {
    if (parent == null) {
      return null;
    }
    const q = asObj(parent[key]);
    if (q == null) {
      return null;
    }
    const fraction = optNum(q, 'usage_percentage');
    if (fraction == null) {
      return null;
    }
    return makeWindow(Math.max(0, Math.min(100, fraction * 100)), isoToMs(optStr(q, 'resets_at')), true);
  }

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const key = setting.credential.trim();
    if (key.length === 0) {
      return UsageSnapshot.failure('未配置 Management API Key');
    }
    const headers: Record<string, string> = {
      'authorization': `Bearer ${key}`,
      'accept': 'application/json',
    };
    const base = 'https://zenmux.ai/api/v1/management';

    const subResp = await Http.get(`${base}/subscription/detail`, headers);
    if (!subResp.ok) {
      return UsageSnapshot.failure(subResp.errorText());
    }
    const subRoot = asObj(subResp.json());
    const subData = subRoot != null ? asObj(subRoot['data']) : null;
    if (subData == null) {
      return UsageSnapshot.failure('响应解析失败');
    }
    const plan = asObj(subData['plan']);
    const tier = plan != null ? str(plan, 'tier') : '';
    const expiresAt = plan != null ? isoToMs(optStr(plan, 'expires_at')) : 0;

    const snap = UsageSnapshot.success(
      ZenMuxProvider.quotaOf(subData, 'quota_5_hour'),
      ZenMuxProvider.quotaOf(subData, 'quota_7_day'),
      null
    );

    // PAYG 余额（失败不阻塞主数据）
    const balResp = await Http.get(`${base}/payg/balance`, headers);
    if (balResp.ok) {
      const balRoot = asObj(balResp.json());
      const balData = balRoot != null ? asObj(balRoot['data']) : null;
      if (balData != null) {
        const credits = optNum(balData, 'total_credits');
        if (credits != null) {
          const cost: ProviderCostSnapshot = {
            remaining: credits, used: 0, currency: str(balData, 'currency', 'USD'),
            displayText: Format.money(credits, str(balData, 'currency', 'USD')),
          };
          snap.providerCost = cost;
        }
      }
    }

    const rows: ProviderDetailRow[] = [];
    if (tier.length > 0) {
      rows.push({ label: '套餐', value: tier });
    }
    if (expiresAt > 0) {
      rows.push({ label: '到期时间', value: Format.dateTime(expiresAt) });
    }
    if (rows.length > 0) {
      const section: ProviderDetailSection = { title: '订阅', rows: rows };
      snap.details = [section];
    }
    snap.identity = { accountEmail: '', accountOrganization: '', loginMethod: tier.length > 0 ? `${tier} plan` : 'Management Key' };
    return snap;
  }
}

// ---------------------------------------------------------------------------
// Manus
// ---------------------------------------------------------------------------

class ManusProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'manus',
    title: 'Manus',
    authKind: AuthKind.OAUTH_TOKEN,
    accentColor: '#5B6CFF',
    authHint: '粘贴 manus.im 的会话 token',
    authUrl: 'https://manus.im',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const token = setting.credential.trim();
    if (token.length === 0) {
      return UsageSnapshot.failure('未配置会话 token');
    }
    const headers: Record<string, string> = {
      'authorization': `Bearer ${token}`,
      'content-type': 'application/json',
      'connect-protocol-version': '1',
      'accept': 'application/json',
      'origin': 'https://manus.im',
    };
    const resp = await Http.post(
      'https://api.manus.im/user.v1.UserService/GetAvailableCredits', headers, '{}');
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    const root = asObj(resp.json());
    if (root == null) {
      return UsageSnapshot.failure('响应解析失败');
    }
    // 信封兼容：credits / data / result 三种包裹
    let credits = asObj(root['credits']);
    if (credits == null) {
      credits = asObj(root['data']);
    }
    if (credits == null) {
      credits = asObj(root['result']);
    }
    if (credits == null) {
      return UsageSnapshot.failure('响应解析失败');
    }
    const total = num(credits, 'totalCredits', 0);
    const rows: ProviderDetailRow[] = [];
    const labels: string[] = ['免费额度', '周期额度', '加购额度', '刷新额度', 'Pro 月度额度'];
    const keys: string[] = ['freeCredits', 'periodicCredits', 'addonCredits', 'refreshCredits', 'proMonthlyCredits'];
    for (let i = 0; i < keys.length; i++) {
      const v = optNum(credits, keys[i]);
      if (v != null) {
        rows.push({ label: labels[i], value: `${Math.round(v)}` });
      }
    }
    const nextRefresh = isoToMs(optStr(credits, 'nextRefreshTime'));
    if (nextRefresh > 0) {
      rows.push({ label: '下次刷新', value: `${Format.dateTime(nextRefresh)}（${Format.countdown(nextRefresh - Date.now())}后）` });
    }

    const snap = UsageSnapshot.success(null, null, null);
    snap.providerCost = {
      remaining: total, used: 0, currency: 'CREDITS',
      displayText: `${total.toFixed(0)} credits`,
    };
    if (rows.length > 0) {
      const section: ProviderDetailSection = { title: '额度构成', rows: rows };
      snap.details = [section];
    }
    return snap;
  }
}

// ---------------------------------------------------------------------------
// DeepInfra
// ---------------------------------------------------------------------------

class DeepInfraProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'deepinfra',
    title: 'DeepInfra',
    authKind: AuthKind.API_KEY,
    accentColor: '#0EA5E9',
    authHint: '粘贴 DeepInfra API Key',
    authUrl: 'https://deepinfra.com/dash/api_keys',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const key = setting.credential.trim();
    if (key.length === 0) {
      return UsageSnapshot.failure('未配置 API Key');
    }
    const headers: Record<string, string> = {
      'authorization': `Bearer ${key}`,
      'accept': 'application/json',
    };
    const checklistResp = await Http.get('https://api.deepinfra.com/payment/checklist?compute_owed=true', headers);
    if (!checklistResp.ok) {
      return UsageSnapshot.failure(checklistResp.errorText());
    }
    const cl = asObj(checklistResp.json());
    if (cl == null) {
      return UsageSnapshot.failure('响应解析失败');
    }
    const stripeBalance = num(cl, 'stripe_balance', 0);
    const recent = Math.max(0, num(cl, 'recent', 0));
    const limit = optNum(cl, 'limit');
    const netBalance = stripeBalance + recent;

    let monthCostUSD = 0;
    const usageResp = await Http.get('https://api.deepinfra.com/payment/usage?from=current', headers);
    if (usageResp.ok) {
      const u = asObj(usageResp.json());
      if (u != null) {
        monthCostUSD = num(u, 'total_cost', 0) / 100; // 美分 → 美元
      }
    }

    let primary: RateWindow | null = null;
    if (limit != null && limit > 0) {
      primary = makeWindow(Math.min(100, (monthCostUSD / limit) * 100), 0, true);
    }
    const snap = UsageSnapshot.success(primary, null, null);
    snap.providerCost = {
      remaining: netBalance, used: monthCostUSD, currency: 'USD',
      displayText: Format.money(netBalance, 'USD'),
    };
    const rows: ProviderDetailRow[] = [];
    rows.push({ label: '本月花费', value: Format.money(monthCostUSD, 'USD') });
    if (limit != null && limit > 0) {
      rows.push({ label: '消费上限', value: Format.money(limit, 'USD') });
    }
    rows.push({ label: '账户余额', value: Format.money(stripeBalance, 'USD') });
    if (bool(cl, 'suspended')) {
      rows.push({ label: '状态', value: `已暂停（${str(cl, 'suspend_reason', '未知原因')}）` });
    }
    const section: ProviderDetailSection = { title: '计费', rows: rows };
    snap.details = [section];
    return snap;
  }
}

// ---------------------------------------------------------------------------
// Perplexity
// ---------------------------------------------------------------------------

class PerplexityProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'perplexity',
    title: 'Perplexity',
    authKind: AuthKind.SESSION,
    accentColor: '#20808D',
    authHint: '粘贴 perplexity.ai 的会话 Cookie（浏览器 Network 面板整段复制）',
    authUrl: 'https://www.perplexity.ai/account/usage',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const cookie = setting.credential.trim();
    if (cookie.length === 0) {
      return UsageSnapshot.failure('未配置会话 Cookie');
    }
    const headers: Record<string, string> = {
      'cookie': cookie,
      'accept': 'application/json',
      'user-agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36',
    };
    const resp = await Http.get(
      'https://www.perplexity.ai/rest/billing/credits?version=2.18&source=default', headers);
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    const root = asObj(resp.json());
    if (root == null) {
      return UsageSnapshot.failure('响应解析失败');
    }
    const balanceCents = num(root, 'balance_cents', 0);
    const usedCents = num(root, 'total_usage_cents', 0);
    const renewal = optNum(root, 'renewal_date_ts');

    const snap = UsageSnapshot.success(null, null, null);
    snap.providerCost = {
      remaining: balanceCents / 100, used: usedCents / 100, currency: 'USD',
      displayText: Format.money(balanceCents / 100, 'USD'),
    };
    const rows: ProviderDetailRow[] = [];
    rows.push({ label: '本期已购', value: Format.money(num(root, 'current_period_purchased_cents', 0) / 100, 'USD') });
    rows.push({ label: '累计使用', value: Format.money(usedCents / 100, 'USD') });
    if (renewal != null && renewal > 0) {
      const renewalMs = renewal > 1e12 ? renewal : renewal * 1000;
      rows.push({ label: '下次续费', value: Format.dateTime(renewalMs) });
    }
    const grants = asArray(root['credit_grants']);
    if (grants != null && grants.length > 0) {
      for (let i = 0; i < grants.length && i < 3; i++) {
        const g = asObj(grants[i]);
        if (g == null) {
          continue;
        }
        const amount = num(g, 'amount_cents', 0) / 100;
        const exp = optNum(g, 'expires_at_ts');
        let line = Format.money(amount, 'USD');
        if (exp != null && exp > 0) {
          const expMs = exp > 1e12 ? exp : exp * 1000;
          line += `（${Format.dateTime(expMs)} 过期）`;
        }
        rows.push({ label: `赠金 #${i + 1}`, value: line });
      }
    }
    const section: ProviderDetailSection = { title: '余额明细', rows: rows };
    snap.details = [section];
    return snap;
  }
}

// ---------------------------------------------------------------------------
// Kimi（kimi.com 编码版）
// ---------------------------------------------------------------------------

class KimiCodingProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'kimi-coding',
    title: 'Kimi 编码版',
    authKind: AuthKind.OAUTH_TOKEN,
    accentColor: '#6E56CF',
    authHint: '粘贴 kimi.com 的 authToken，或 Kimi Code API Key（sk-… 开头）',
    authUrl: 'https://www.kimi.com/code/console',
  };

  /** API Key 模式（对照 macOS fetchCodeAPIUsage：Bearer 调 Code usages API） */
  private async fetchWithAPIKey(key: string): Promise<UsageSnapshot> {
    const resp = await Http.get('https://api.kimi.com/coding/v1/usages', {
      'authorization': `Bearer ${key}`,
      'accept': 'application/json',
    });
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    const root = asObj(resp.json());
    if (root == null) {
      return UsageSnapshot.failure('响应解析失败');
    }
    // usages 池（limit_5h / limit_7d / limit_month_total）或 usage 明细，两者字段同构
    const pools = asObj(root['usages']) ?? asObj(root['usage']);
    if (pools == null) {
      return UsageSnapshot.failure('未返回用量数据');
    }
    const snap = UsageSnapshot.success(
      KimiCodingProvider.windowOf(pools, 'limit_5h'),
      KimiCodingProvider.windowOf(pools, 'limit_7d'),
      KimiCodingProvider.windowOf(pools, 'limit_month_total')
    );
    // 会员等级 → 计划名（对照 macOS planName 映射）
    const user = asObj(root['user']);
    const membership = user != null ? asObj(user['membership']) : null;
    const level = membership != null ? optStr(membership, 'level') : null;
    if (level != null && level.length > 0 && level !== 'LEVEL_UNSPECIFIED') {
      const names: Record<string, string> = {
        'LEVEL_FREE': 'Adagio',
        'LEVEL_TRIAL': 'Andante',
        'LEVEL_BASIC': 'Moderato',
        'LEVEL_INTERMEDIATE': 'Allegretto',
        'LEVEL_ADVANCED': 'Allegro',
      };
      const plan = names[level] != null ? names[level] : level;
      snap.details = [{ title: '订阅', rows: [{ label: '计划', value: plan }] }];
    }
    return snap;
  }

  private headers(token: string): Record<string, string> {
    const h: Record<string, string> = {
      'authorization': `Bearer ${token}`,
      'cookie': `kimi-auth=${token}`,
      'content-type': 'application/json',
      'connect-protocol-version': '1',
      'accept': '*/*',
      'origin': 'https://www.kimi.com',
      'referer': 'https://www.kimi.com/code/console',
      'x-msh-platform': 'web',
    };
    return h;
  }

  private static windowOf(parent: Record<string, Json> | null, key: string): RateWindow | null {
    if (parent == null) {
      return null;
    }
    const w = asObj(parent[key]);
    if (w == null) {
      return null;
    }
    const ratio = optNum(w, 'used_ratio');
    if (ratio == null) {
      return null;
    }
    const reset = isoToMs(optStr(w, 'reset_time'));
    return makeWindow(Math.max(0, Math.min(100, ratio * 100)), reset, true);
  }

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const token = setting.credential.trim();
    if (token.length === 0) {
      return UsageSnapshot.failure('未配置 authToken');
    }
    // sk- 开头视为 Kimi Code API Key
    if (token.startsWith('sk-')) {
      return this.fetchWithAPIKey(token);
    }
    const resp = await Http.post(
      'https://www.kimi.com/apiv2/kimi.gateway.billing.v1.BillingService/GetUsages',
      this.headers(token), '{}');
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    const root = asObj(resp.json());
    if (root == null) {
      return UsageSnapshot.failure('响应解析失败');
    }
    const usages = asArray(root['usages']);
    if (usages == null || usages.length === 0) {
      return UsageSnapshot.failure('未返回用量数据（token 可能已失效）');
    }
    let target: Record<string, Json> | null = null;
    for (let i = 0; i < usages.length; i++) {
      const u = asObj(usages[i]);
      if (u != null && str(u, 'scope') === 'FEATURE_CODING') {
        target = u;
        break;
      }
    }
    if (target == null) {
      const first = asObj(usages[0]);
      target = first;
    }
    if (target == null) {
      return UsageSnapshot.failure('响应解析失败');
    }
    const snap = UsageSnapshot.success(
      KimiCodingProvider.windowOf(target, 'limit_5h'),
      KimiCodingProvider.windowOf(target, 'limit_7d'),
      KimiCodingProvider.windowOf(target, 'limit_month_total')
    );
    return snap;
  }
}


// ---------------------------------------------------------------------------
// Chutes（别名容错解析，对照 macOS 版 ChutesUsageParser 的多别名策略）
// ---------------------------------------------------------------------------

/** 在字典中按别名列表取第一个存在的值 */
function firstOf(o: Record<string, Json>, keys: string[]): Json {
  for (let i = 0; i < keys.length; i++) {
    const v = o[keys[i]];
    if (v != null) {
      return v;
    }
  }
  return null;
}

function firstNum(o: Record<string, Json>, keys: string[]): number | null {
  const v = firstOf(o, keys);
  if (typeof v === 'number') {
    return v as number;
  }
  if (typeof v === 'string') {
    const parsed = parseFloat(v as string);
    if (!isNaN(parsed)) {
      return parsed;
    }
  }
  return null;
}

function firstStr(o: Record<string, Json>, keys: string[]): string | null {
  const v = firstOf(o, keys);
  if (typeof v === 'string') {
    return v as string;
  }
  return null;
}

export function chutesWindow(payload: Record<string, Json>, defaultLabel: string): RateWindow | null {
  const used = firstNum(payload, ['used', 'usage', 'used_amount', 'consumed', 'consumed_amount', 'current', 'current_usage']);
  const limit = firstNum(payload, ['limit', 'cap', 'max', 'usage_limit', 'limit_amount']);
  const remaining = firstNum(payload, ['remaining', 'available', 'balance', 'left', 'available_amount']);
  let percent = firstNum(payload, ['percent_used', 'usage_percent', 'used_percent', 'utilization', 'utilization_percent']);
  if (percent == null) {
    const remainPercent = firstNum(payload, ['percent_remaining', 'remaining_percent', 'remainingPercent']);
    if (remainPercent != null) {
      percent = 100 - remainPercent;
    }
  }
  if (percent == null && used != null && limit != null && limit > 0) {
    percent = (used / limit) * 100;
  }
  if (percent == null) {
    return null;
  }
  let resets = 0;
  const resetRaw = firstStr(payload, ['reset_at', 'resets_at', 'reset_time', 'resetAt', 'resetsAt']);
  if (resetRaw != null) {
    resets = isoToMs(resetRaw);
  }
  if (resets === 0) {
    const resetNum = firstNum(payload, ['reset_at', 'resets_at']);
    if (resetNum != null && resetNum > 1e9) {
      resets = resetNum > 1e12 ? resetNum : resetNum * 1000;
    }
  }
  const label = firstStr(payload, ['label', 'name', 'title', 'type', 'period']) ?? defaultLabel;
  return makeWindow(Math.max(0, Math.min(100, percent)), resets, true);
}

class ChutesProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'chutes',
    title: 'Chutes',
    authKind: AuthKind.API_KEY,
    accentColor: '#F97316',
    authHint: '粘贴 Chutes API Key（chutes.ai 用户设置中获取）',
    authUrl: 'https://chutes.ai/settings/api',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const key = setting.credential.trim();
    if (key.length === 0) {
      return UsageSnapshot.failure('未配置 API Key');
    }
    const headers: Record<string, string> = {
      'authorization': `Bearer ${key}`,
      'accept': 'application/json',
    };
    const resp = await Http.get('https://api.chutes.ai/users/me/subscription_usage', headers);
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    let root = asObj(resp.json());
    if (root == null) {
      return UsageSnapshot.failure('响应解析失败');
    }
    // 兼容 {data:...} / {result:...} 包裹
    const inner = asObj(firstOf(root, ['data', 'result']));
    if (inner != null) {
      root = inner;
    }

    // 滚动 4h 窗口（别名匹配）
    let rollingRaw = asObj(firstOf(root, ['rolling', 'rolling_window', 'rollingWindow', 'rolling_4h', 'rolling4h', 'four_hour', 'fourHour', 'window_4h']));
    // 月度窗口（别名匹配）
    const monthlyRaw = asObj(firstOf(root, ['monthly', 'monthly_usage', 'monthlyUsage', 'billing_period', 'billingPeriod']));

    // 容错：quotas 数组兜底
    let extras: NamedRateWindow[] = [];
    const quotas = asArray(firstOf(root, ['quotas', 'quota', 'quota_usage', 'limits']));
    if (quotas != null) {
      for (let i = 0; i < quotas.length && extras.length < 4; i++) {
        const q = asObj(quotas[i]);
        if (q == null) {
          continue;
        }
        const label = firstStr(q, ['label', 'name', 'title', 'type', 'period']) ?? `配额 ${i + 1}`;
        const w = chutesWindow(q, label);
        if (w != null) {
          extras.push({ id: `q_${i}`, title: label, window: w });
        }
      }
    }

    const rolling = rollingRaw != null ? chutesWindow(rollingRaw, '4 小时窗口') : null;
    const monthly = monthlyRaw != null ? chutesWindow(monthlyRaw, '月度窗口') : null;

    // 过滤与主窗口重复的 extras
    const filtered: NamedRateWindow[] = [];
    for (let i = 0; i < extras.length; i++) {
      const e = extras[i];
      const dupRolling = rolling != null && e.window.usedPercent === rolling.usedPercent && e.window.resetsAt === rolling.resetsAt;
      const dupMonthly = monthly != null && e.window.usedPercent === monthly.usedPercent && e.window.resetsAt === monthly.resetsAt;
      if (!dupRolling && !dupMonthly) {
        filtered.push(e);
      }
    }

    const snap = UsageSnapshot.success(rolling ?? monthly, monthly, null);
    snap.extraRateWindows = filtered;
    if (snap.primary == null && snap.secondary == null && filtered.length === 0) {
      return UsageSnapshot.failure('未识别到用量窗口（账户可能无订阅）');
    }

    // 订阅状态/计划名
    const sub = asObj(firstOf(root, ['subscription', 'subscription_usage', 'current_subscription', 'currentSubscription', 'plan']));
    if (sub != null) {
      const plan = firstStr(sub, ['plan_name', 'planName', 'name', 'tier']);
      const status = firstStr(sub, ['status', 'state', 'subscription_status']);
      const rows: ProviderDetailRow[] = [];
      if (plan != null) {
        rows.push({ label: '套餐', value: plan });
      }
      if (status != null) {
        rows.push({ label: '状态', value: status });
      }
      if (rows.length > 0) {
        const section: ProviderDetailSection = { title: '订阅', rows: rows };
        snap.details = [section];
      }
    }
    return snap;
  }
}

export function createChutesProvider(): UsageProvider {
  return new ChutesProvider();
}

export function createZenMuxProvider(): UsageProvider {
  return new ZenMuxProvider();
}

export function createManusProvider(): UsageProvider {
  return new ManusProvider();
}

export function createDeepInfraProvider(): UsageProvider {
  return new DeepInfraProvider();
}

export function createPerplexityProvider(): UsageProvider {
  return new PerplexityProvider();
}

export function createKimiCodingProvider(): UsageProvider {
  return new KimiCodingProvider();
}
