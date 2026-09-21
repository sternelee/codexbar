/**
 * API-Key 型服务商用量查询合集
 *
 * 端点来源（对应 macOS 版 Providers/ 各目录）：
 * - OpenRouter:  GET https://openrouter.ai/api/v1/credits            → data.total_credits / total_usage
 * - DeepSeek:    GET https://api.deepseek.com/user/balance           → balance_infos[].total_balance
 * - Kimi/Moonshot: GET https://api.moonshot.cn/v1/users/me/balance   → data.available_balance
 * - SiliconFlow: GET https://api.siliconflow.cn/v1/user/info         → data.totalBalance
 * - OpenAI Platform（遗留 dashboard 端点）: subscription + credit_grants
 * - Anthropic Console（Admin API）: usage_report / cost_report（月度 token 与花费）
 */

import { Http } from '../net/Http';
import { asArray, asObj, num, optStr, str } from '../net/Json';
import {
  AuthKind,
  makeWindow,
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

function bearer(key: string): Record<string, string> {
  const h: Record<string, string> = {
    'authorization': `Bearer ${key}`,
    'accept': 'application/json',
  };
  return h;
}

function parseMoney(raw: string | null, currency: string): number {
  if (raw == null) {
    return 0;
  }
  const v = parseFloat(raw);
  return isNaN(v) ? 0 : v;
}

// ---------------------------------------------------------------------------
// OpenRouter
// ---------------------------------------------------------------------------

class OpenRouterProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'openrouter',
    title: 'OpenRouter',
    authKind: AuthKind.API_KEY,
    accentColor: '#8B5CF6',
    authHint: '粘贴 OpenRouter API Key（sk-or-v1-… 开头）',
    authUrl: 'https://openrouter.ai/settings/credits',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const key = setting.credential.trim();
    if (key.length === 0) {
      return UsageSnapshot.failure('未配置 API Key');
    }
    const resp = await Http.get('https://openrouter.ai/api/v1/credits', bearer(key));
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    const root = asObj(resp.json());
    const data = root != null ? asObj(root['data']) : null;
    if (data == null) {
      return UsageSnapshot.failure('响应解析失败');
    }
    const total = parseMoney(optStr(data, 'total_credits'), 'USD');
    const used = parseMoney(optStr(data, 'total_usage'), 'USD');
    const remaining = Math.max(0, total - used);
    const percent = total > 0 ? Math.min(100, (used / total) * 100) : 0;

    const snap = UsageSnapshot.success(makeWindow(percent, 0, total > 0), null, null);
    snap.providerCost = {
      remaining: remaining, used: used, currency: 'USD',
      displayText: Format.money(remaining, 'USD'),
    };
    return snap;
  }
}

// ---------------------------------------------------------------------------
// DeepSeek
// ---------------------------------------------------------------------------

class DeepSeekProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'deepseek',
    title: 'DeepSeek',
    authKind: AuthKind.API_KEY,
    accentColor: '#4D6BFE',
    authHint: '粘贴 DeepSeek 开放平台 API Key（sk-… 开头）',
    authUrl: 'https://platform.deepseek.com/api_keys',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const key = setting.credential.trim();
    if (key.length === 0) {
      return UsageSnapshot.failure('未配置 API Key');
    }
    const resp = await Http.get('https://api.deepseek.com/user/balance', bearer(key));
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    const root = asObj(resp.json());
    if (root == null) {
      return UsageSnapshot.failure('响应解析失败');
    }
    const infos = asArray(root['balance_infos']);
    if (infos == null || infos.length === 0) {
      return UsageSnapshot.failure('未返回余额信息');
    }
    const info = asObj(infos[0]);
    if (info == null) {
      return UsageSnapshot.failure('未返回余额信息');
    }
    const currency = str(info, 'currency', 'CNY');
    const total = parseMoney(optStr(info, 'total_balance'), currency);
    const granted = parseMoney(optStr(info, 'granted_balance'), currency);
    const snap = UsageSnapshot.success(null, null, null);
    snap.providerCost = {
      remaining: total, used: 0, currency: currency,
      displayText: `${Format.money(total, currency)}${granted > 0 ? `（含赠 ${Format.money(granted, currency)}）` : ''}`,
    };
    snap.details = [{
      title: '余额构成',
      rows: [
        { label: '总额', value: Format.money(total, currency) },
        { label: '赠送余额', value: Format.money(granted, currency) },
        { label: '充值余额', value: Format.money(Math.max(0, total - granted), currency) },
      ],
    }];
    return snap;
  }
}

// ---------------------------------------------------------------------------
// Kimi / Moonshot
// ---------------------------------------------------------------------------

class MoonshotProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'moonshot',
    title: 'Kimi (Moonshot)',
    authKind: AuthKind.API_KEY,
    accentColor: '#17C0AA',
    authHint: '粘贴 Moonshot 开放平台 API Key（sk-… 开头）',
    authUrl: 'https://platform.moonshot.cn/console/api-keys',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const key = setting.credential.trim();
    if (key.length === 0) {
      return UsageSnapshot.failure('未配置 API Key');
    }
    const resp = await Http.get('https://api.moonshot.cn/v1/users/me/balance', bearer(key));
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    const root = asObj(resp.json());
    const data = root != null ? asObj(root['data']) : null;
    if (data == null) {
      return UsageSnapshot.failure('响应解析失败');
    }
    const available = parseMoney(optStr(data, 'available_balance'), 'CNY');
    const voucher = parseMoney(optStr(data, 'voucher_balance'), 'CNY');
    const cash = parseMoney(optStr(data, 'cash_balance'), 'CNY');
    const snap = UsageSnapshot.success(null, null, null);
    snap.providerCost = {
      remaining: available, used: 0, currency: 'CNY',
      displayText: Format.money(available, 'CNY'),
    };
    snap.details = [{
      title: '余额构成',
      rows: [
        { label: '可用余额', value: Format.money(available, 'CNY') },
        { label: '代金券', value: Format.money(voucher, 'CNY') },
        { label: '现金余额', value: Format.money(cash, 'CNY') },
      ],
    }];
    return snap;
  }
}

// ---------------------------------------------------------------------------
// SiliconFlow 硅基流动
// ---------------------------------------------------------------------------

class SiliconFlowProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'siliconflow',
    title: 'SiliconFlow 硅基流动',
    authKind: AuthKind.API_KEY,
    accentColor: '#7C3AED',
    authHint: '粘贴 SiliconFlow API Key（sk-… 开头）',
    authUrl: 'https://cloud.siliconflow.cn/account/ak',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const key = setting.credential.trim();
    if (key.length === 0) {
      return UsageSnapshot.failure('未配置 API Key');
    }
    const resp = await Http.get('https://api.siliconflow.cn/v1/user/info', bearer(key));
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    const root = asObj(resp.json());
    const data = root != null ? asObj(root['data']) : null;
    if (data == null) {
      return UsageSnapshot.failure('响应解析失败');
    }
    const balance = parseMoney(optStr(data, 'balance'), 'CNY');
    const charge = parseMoney(optStr(data, 'chargeBalance'), 'CNY');
    const total = parseMoney(optStr(data, 'totalBalance'), 'CNY');
    const snap = UsageSnapshot.success(null, null, null);
    snap.providerCost = {
      remaining: total > 0 ? total : balance, used: 0, currency: 'CNY',
      displayText: Format.money(total > 0 ? total : balance, 'CNY'),
    };
    snap.details = [{
      title: '余额构成',
      rows: [
        { label: '总余额', value: Format.money(total, 'CNY') },
        { label: '充值余额', value: Format.money(charge, 'CNY') },
        { label: '赠送余额', value: Format.money(balance, 'CNY') },
      ],
    }];
    return snap;
  }
}

// ---------------------------------------------------------------------------
// OpenAI Platform（遗留 dashboard 计费端点）
// ---------------------------------------------------------------------------

class OpenAIPlatformProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'openai',
    title: 'OpenAI Platform',
    authKind: AuthKind.API_KEY,
    accentColor: '#10A37F',
    authHint: '粘贴 OpenAI 平台 API Key（sk-… 开头）',
    authUrl: 'https://platform.openai.com/api-keys',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const key = setting.credential.trim();
    if (key.length === 0) {
      return UsageSnapshot.failure('未配置 API Key');
    }
    const headers = bearer(key);

    const subResp = await Http.get('https://api.openai.com/v1/dashboard/billing/subscription', headers);
    const grantResp = await Http.get('https://api.openai.com/v1/dashboard/billing/credit_grants', headers);
    if (!subResp.ok && !grantResp.ok) {
      return UsageSnapshot.failure(subResp.code === 404 ? '服务商已下线该查询端点' : subResp.errorText());
    }

    let hardLimit = 0;
    let accessUntil = 0;
    if (subResp.ok) {
      const sub = asObj(subResp.json());
      if (sub != null) {
        hardLimit = num(sub, 'hard_limit_usd', 0);
        const until = num(sub, 'access_until', 0);
        if (until > 0) {
          accessUntil = until * 1000;
        }
      }
    }
    let granted = 0;
    let used = 0;
    let available = 0;
    if (grantResp.ok) {
      const g = asObj(grantResp.json());
      if (g != null) {
        granted = num(g, 'total_granted', 0);
        used = num(g, 'total_used', 0);
        available = num(g, 'total_available', 0);
      }
    }

    let primary: RateWindow | null = null;
    if (hardLimit > 0) {
      primary = makeWindow(Math.min(100, (used / hardLimit) * 100), accessUntil, true);
    }
    const snap = UsageSnapshot.success(primary, null, null);
    if (granted > 0 || available > 0) {
      snap.providerCost = {
        remaining: available, used: used, currency: 'USD',
        displayText: Format.money(available, 'USD'),
      };
    }
    const rows: ProviderDetailRow[] = [];
    if (hardLimit > 0) {
      rows.push({ label: '额度上限', value: Format.money(hardLimit, 'USD') });
    }
    if (granted > 0) {
      rows.push({ label: '累计授予', value: Format.money(granted, 'USD') });
      rows.push({ label: '累计使用', value: Format.money(used, 'USD') });
    }
    if (rows.length > 0) {
      const section: ProviderDetailSection = { title: '计费', rows: rows };
      snap.details = [section];
    }
    return snap;
  }
}

// ---------------------------------------------------------------------------
// Anthropic Console（Admin API：月度用量与花费）
// ---------------------------------------------------------------------------

class AnthropicConsoleProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'anthropic-console',
    title: 'Anthropic 控制台',
    authKind: AuthKind.API_KEY,
    accentColor: '#D97757',
    authHint: '粘贴 Anthropic Admin API Key（需要组织管理员权限，sk-ant-admin…）',
    authUrl: 'https://console.anthropic.com/settings/keys',
  };

  private monthParam(d: Date, offset: number = 0): string {
    const m = d.getMonth() + 1 + offset;
    const year = d.getFullYear() + Math.floor((m - 1) / 12);
    const month = ((m - 1) % 12 + 12) % 12 + 1;
    return `${year}-${month.toString().padStart(2, '0')}`;
  }

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const key = setting.credential.trim();
    if (key.length === 0) {
      return UsageSnapshot.failure('未配置 Admin API Key');
    }
    const headers: Record<string, string> = {
      'x-api-key': key,
      'anthropic-version': '2023-06-01',
      'accept': 'application/json',
    };
    const now = new Date();
    const url =
      `https://api.anthropic.com/v1/organizations/usage_report/messages` +
      `?starting_month=${this.monthParam(now)}&ending_month=${this.monthParam(now, 1)}&bucket_width=1d`;

    const usageResp = await Http.get(url, headers);
    if (!usageResp.ok) {
      return UsageSnapshot.failure(usageResp.errorText());
    }
    const root = asObj(usageResp.json());
    if (root == null) {
      return UsageSnapshot.failure('响应解析失败');
    }
    const days = asArray(root['data']);
    let inputTokens = 0;
    let outputTokens = 0;
    let cacheWrite = 0;
    let cacheRead = 0;
    if (days != null) {
      for (let i = 0; i < days.length; i++) {
        const d = asObj(days[i]);
        if (d == null) {
          continue;
        }
        inputTokens += num(d, 'uncached_input_tokens', 0);
        outputTokens += num(d, 'output_tokens', 0);
        cacheWrite += num(d, 'cache_creation_input_tokens', 0);
        cacheRead += num(d, 'cache_read_input_tokens', 0);
      }
    }

    const snap = UsageSnapshot.success(null, null, null);
    snap.details = [{
      title: `本月 Token 用量（${now.getFullYear()}年${now.getMonth() + 1}月）`,
      rows: [
        { label: '输入', value: Format.compact(inputTokens) },
        { label: '输出', value: Format.compact(outputTokens) },
        { label: '缓存写入', value: Format.compact(cacheWrite) },
        { label: '缓存读取', value: Format.compact(cacheRead) },
      ],
    }];
    snap.identity = { accountEmail: '', accountOrganization: 'Anthropic 组织', loginMethod: 'Admin API Key' };
    return snap;
  }
}

// ---------------------------------------------------------------------------

export function createOpenRouterProvider(): UsageProvider {
  return new OpenRouterProvider();
}

export function createDeepSeekProvider(): UsageProvider {
  return new DeepSeekProvider();
}

export function createMoonshotProvider(): UsageProvider {
  return new MoonshotProvider();
}

export function createSiliconFlowProvider(): UsageProvider {
  return new SiliconFlowProvider();
}

export function createOpenAIPlatformProvider(): UsageProvider {
  return new OpenAIPlatformProvider();
}

export function createAnthropicConsoleProvider(): UsageProvider {
  return new AnthropicConsoleProvider();
}
