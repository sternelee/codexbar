/**
 * 服务商第四批（对照 macOS 版 UsageFetcher 与 QuickJS 插件逐家迁移）：
 * - xAI:        GET management-api.x.ai/v1/billing/teams/{team}/prepaid/balance（Management Key + Team ID）
 * - Qoder:      GET {qoder.com|qoder.com.cn}/api/v2/me/usages/big_model_credits（Cookie）
 * - Venice:     GET api.venice.ai/api/v1/billing/balance（Bearer）
 * - Nous:       GET {portal}/api/oauth/account（Bearer Portal Token）
 * - Muse Code:  POST api.meta.ai/muse-code/key（Bearer 设备令牌）
 * - Deepgram:   GET api.deepgram.com/v1/projects + usage/breakdown（Token 认证）
 * - ClinePass:  GET api.cline.bot/api/v1/users/me/plan/usage-limits（Bearer）
 * - Crof:       GET crof.ai/usage_api/（Bearer）
 * - Synthetic:  GET api.synthetic.new/v2/quotas（Bearer，别名容错）
 * - ClawRouter: GET {base}/usage（Cookie，micros 预算换算）
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

function pickNum(o: Record<string, Json>, keys: string[]): number | null {
  for (let i = 0; i < keys.length; i++) {
    const v = o[keys[i]];
    if (typeof v === 'number') {
      return v as number;
    }
    if (typeof v === 'string') {
      const parsed = parseFloat(v as string);
      if (!isNaN(parsed)) {
        return parsed;
      }
    }
  }
  return null;
}

function pickStr(o: Record<string, Json>, keys: string[]): string | null {
  for (let i = 0; i < keys.length; i++) {
    const v = o[keys[i]];
    if (typeof v === 'string') {
      return v as string;
    }
  }
  return null;
}

function isoMs(iso: string | null): number {
  if (iso == null || iso.length === 0) {
    return 0;
  }
  const parsed = Date.parse(iso);
  return isNaN(parsed) ? 0 : parsed;
}

// ---------------------------------------------------------------------------
// xAI（Grok）
// ---------------------------------------------------------------------------

class XaiProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'xai',
    title: 'xAI (Grok)',
    authKind: AuthKind.API_KEY,
    accentColor: '#111111',
    authHint: '粘贴 xAI Management API Key；第二栏必填 Team ID（Console → Management Keys）',
    authUrl: 'https://console.x.ai',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const key = setting.credential.trim();
    const team = setting.credential2.trim();
    if (key.length === 0 || team.length === 0) {
      return UsageSnapshot.failure('需要 Management API Key 与 Team ID');
    }
    const headers: Record<string, string> = {
      'authorization': `Bearer ${key}`,
      'accept': 'application/json',
    };
    const url = `https://management-api.x.ai/v1/billing/teams/${encodeURIComponent(team)}/prepaid/balance`;
    const resp = await Http.get(url, headers);
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    const root = asObj(resp.json());
    const total = root != null ? asObj(root['total']) : null;
    const rawVal = total != null ? optStr(total, 'val') : null;
    if (rawVal == null) {
      return UsageSnapshot.failure('响应解析失败');
    }
    // 美分字符串，负数表示余额
    const balance = -parseFloat(rawVal) / 100;
    const snap = UsageSnapshot.success(null, null, null);
    snap.providerCost = {
      remaining: balance, used: 0, currency: 'USD',
      displayText: Format.money(balance, 'USD'),
    };
    snap.identity = { accountEmail: '', accountOrganization: `Team ${team}`, loginMethod: 'Management API' };
    return snap;
  }
}

// ---------------------------------------------------------------------------
// Qoder
// ---------------------------------------------------------------------------

class QoderProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'qoder',
    title: 'Qoder',
    authKind: AuthKind.SESSION,
    accentColor: '#2563EB',
    authHint: '粘贴 qoder.com（或 qoder.com.cn）的会话 Cookie',
    authUrl: 'https://qoder.com/account/usage',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const cookie = setting.credential.trim();
    if (cookie.length === 0) {
      return UsageSnapshot.failure('未配置会话 Cookie');
    }
    const sites = ['https://qoder.com', 'https://qoder.com.cn'];
    let root: Record<string, Json> | null = null;
    let lastError = '';
    for (let i = 0; i < sites.length && root == null; i++) {
      const headers: Record<string, string> = {
        'cookie': cookie,
        'accept': 'application/json',
        'origin': sites[i],
        'referer': `${sites[i]}/account/usage`,
        'x-requested-with': 'XMLHttpRequest',
        'bx-v': '2.5.35',
      };
      const resp = await Http.get(`${sites[i]}/api/v2/me/usages/big_model_credits`, headers);
      if (resp.ok) {
        const parsed = asObj(resp.json());
        if (parsed != null) {
          root = parsed;
          break;
        }
      } else {
        lastError = resp.errorText();
      }
    }
    if (root == null) {
      return UsageSnapshot.failure(lastError.length > 0 ? lastError : '凭证被拒绝');
    }
    const container = asObj(firstOfObj(root, ['totalQuota', 'total_quota']));
    const shared = asObj(firstOfObj(root, ['sharedQuota', 'shared_quota']));
    const summary = container != null ? asObj(firstOfObj(container, ['quotaSummary', 'quota_summary'])) : null;
    const sharedSummary = shared != null ? asObj(firstOfObj(shared, ['quotaSummary', 'quota_summary'])) : null;
    if (summary == null) {
      return UsageSnapshot.failure('响应缺少配额摘要');
    }
    let used = pickNum(summary, ['usedValue', 'used_value']) ?? 0;
    let total = pickNum(summary, ['limitValue', 'limit_value']) ?? 0;
    let percent = pickNum(summary, ['usagePercentage', 'usage_percentage']);
    if (sharedSummary != null) {
      used += pickNum(sharedSummary, ['usedValue', 'used_value']) ?? 0;
      total += pickNum(sharedSummary, ['limitValue', 'limit_value']) ?? 0;
      percent = total > 0 ? (used / total) * 100 : 0;
    }
    if (percent == null) {
      percent = total > 0 ? (used / total) * 100 : 0;
    }
    let resets = 0;
    const resetRaw = firstOfObj(root, ['nextResetAt', 'next_reset_at']);
    if (typeof resetRaw === 'number') {
      const n = resetRaw as number;
      resets = n > 10000000000 ? n : n * 1000;
    } else if (typeof resetRaw === 'string') {
      resets = isoMs(resetRaw as string);
    }
    const snap = UsageSnapshot.success(makeWindow(Math.max(0, Math.min(100, percent)), resets, true), null, null);
    const rows: ProviderDetailRow[] = [
      { label: '已用 / 总量', value: `${Math.round(used)} / ${Math.round(total)}` },
    ];
    const section: ProviderDetailSection = { title: 'Big Model Credits', rows: rows };
    snap.details = [section];
    return snap;
  }
}

function firstOfObj(o: Record<string, Json>, keys: string[]): Json {
  for (let i = 0; i < keys.length; i++) {
    const v = o[keys[i]];
    if (v != null) {
      return v;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Venice
// ---------------------------------------------------------------------------

class VeniceProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'venice',
    title: 'Venice',
    authKind: AuthKind.API_KEY,
    accentColor: '#E11D48',
    authHint: '粘贴 Venice API Key',
    authUrl: 'https://venice.ai/settings/api',
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
    const resp = await Http.get('https://api.venice.ai/api/v1/billing/balance', headers);
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    const root = asObj(resp.json());
    if (root == null) {
      return UsageSnapshot.failure('响应解析失败');
    }
    const balances = asObj(root['balances']);
    if (balances == null) {
      return UsageSnapshot.failure('响应缺少余额');
    }
    const usd = pickNum(balances, ['usd']) ?? 0;
    const diem = pickNum(balances, ['diem']) ?? 0;
    const snap = UsageSnapshot.success(null, null, null);
    snap.providerCost = {
      remaining: usd, used: 0, currency: 'USD',
      displayText: Format.money(usd, 'USD'),
    };
    const rows: ProviderDetailRow[] = [
      { label: 'USD 余额', value: Format.money(usd, 'USD') },
      { label: 'Diem 余额', value: `${diem}` },
    ];
    const section: ProviderDetailSection = { title: '余额明细', rows: rows };
    snap.details = [section];
    return snap;
  }
}

// ---------------------------------------------------------------------------
// Nous Research
// ---------------------------------------------------------------------------

class NousProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'nous',
    title: 'Nous Research',
    authKind: AuthKind.API_KEY,
    accentColor: '#8B5CF6',
    authHint: '粘贴 Nous Portal 访问令牌；可选第二栏填自定义 Portal 地址',
    authUrl: 'https://portal.nousresearch.com',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const token = setting.credential.trim();
    if (token.length === 0) {
      return UsageSnapshot.failure('未配置访问令牌');
    }
    const portalRaw = setting.credential2.trim();
    const portal = portalRaw.length > 0 ? portalRaw.replace(/\/+$/, '') : 'https://portal.nousresearch.com';
    const headers: Record<string, string> = {
      'authorization': `Bearer ${token}`,
      'accept': 'application/json',
    };
    const resp = await Http.get(`${portal}/api/oauth/account`, headers);
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    const root = asObj(resp.json());
    if (root == null) {
      return UsageSnapshot.failure('响应解析失败');
    }
    const sub = asObj(root['subscription']);
    const remaining = pickNum(root, ['credits_remaining']) ??
      (sub != null ? pickNum(sub, ['credits_remaining']) : null) ?? 0;
    const monthly = sub != null ? pickNum(sub, ['monthly_credits']) : null;
    const rollover = sub != null ? pickNum(sub, ['rollover_credits']) : null;
    const purchased = pickNum(root, ['purchased_credits_remaining']) ?? 0;

    const snap = UsageSnapshot.success(null, null, null);
    snap.providerCost = {
      remaining: remaining, used: 0, currency: 'CREDITS',
      displayText: `${remaining} credits`,
    };
    const rows: ProviderDetailRow[] = [];
    if (monthly != null) {
      rows.push({ label: '月度额度', value: `${monthly}` });
    }
    if (rollover != null) {
      rows.push({ label: '滚存额度', value: `${rollover}` });
    }
    rows.push({ label: '已购额度', value: `${purchased}` });
    const section: ProviderDetailSection = { title: '额度构成', rows: rows };
    snap.details = [section];
    return snap;
  }
}

// ---------------------------------------------------------------------------
// Muse Code（Meta）
// ---------------------------------------------------------------------------

class MuseProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'muse',
    title: 'Muse Code',
    authKind: AuthKind.OAUTH_TOKEN,
    accentColor: '#0668E1',
    authHint: '粘贴 Muse 设备令牌（muse login 获取）',
    authUrl: 'https://dev.meta.ai',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const token = setting.credential.trim();
    if (token.length === 0) {
      return UsageSnapshot.failure('未配置设备令牌');
    }
    const headers: Record<string, string> = {
      'authorization': `Bearer ${token}`,
      'content-type': 'application/json',
      'x-api-version': '1.0.0',
      'user-agent': 'CodexBar',
    };
    const resp = await Http.post('https://api.meta.ai/muse-code/key', headers, '{}');
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    const root = asObj(resp.json());
    if (root == null) {
      return UsageSnapshot.failure('响应解析失败');
    }
    if (bool(root, 'require_payment')) {
      return UsageSnapshot.failure('需要先完成支付绑定（dev.meta.ai）');
    }
    if (!bool(root, 'is_subs_active')) {
      return UsageSnapshot.failure('没有有效的 Muse Code 订阅');
    }
    const usage = asObj(root['subs_usage']);
    const windowObj = usage != null ? asObj(usage['window']) : null;
    const weekly = usage != null ? asObj(usage['weekly']) : null;
    if (windowObj == null) {
      return UsageSnapshot.failure('响应缺少用量窗口');
    }
    const minutes = num(windowObj, 'window_duration_mins', 0);
    const percent = num(windowObj, 'used_percent', 0);
    const resetSec = optNum(windowObj, 'resets_at');
    const primary = makeWindow(
      Math.max(0, Math.min(100, percent)),
      resetSec != null && resetSec > 0 ? resetSec * 1000 : 0,
      true
    );
    let secondary: RateWindow | null = null;
    if (weekly != null) {
      const wPercent = num(weekly, 'used_percent', 0);
      const wReset = optNum(weekly, 'resets_at');
      secondary = makeWindow(Math.max(0, Math.min(100, wPercent)), wReset != null && wReset > 0 ? wReset * 1000 : 0, true);
    }
    const snap = UsageSnapshot.success(primary, secondary, null);
    const rows: ProviderDetailRow[] = [
      { label: '窗口时长', value: `${Math.round(minutes / 60)} 小时` },
    ];
    const section: ProviderDetailSection = { title: '订阅', rows: rows };
    snap.details = [section];
    return snap;
  }
}

// ---------------------------------------------------------------------------
// Deepgram
// ---------------------------------------------------------------------------

class DeepgramProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'deepgram',
    title: 'Deepgram',
    authKind: AuthKind.API_KEY,
    accentColor: '#13EF93',
    authHint: '粘贴 Deepgram API Key',
    authUrl: 'https://console.deepgram.com/project/keys',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const key = setting.credential.trim();
    if (key.length === 0) {
      return UsageSnapshot.failure('未配置 API Key');
    }
    const headers: Record<string, string> = {
      'authorization': `Token ${key}`,
      'accept': 'application/json',
    };
    const base = 'https://api.deepgram.com/v1';
    const projResp = await Http.get(`${base}/projects`, headers);
    if (!projResp.ok) {
      return UsageSnapshot.failure(projResp.errorText());
    }
    const projRoot = asObj(projResp.json());
    const projects = projRoot != null ? asArray(projRoot['projects']) : null;
    if (projects == null || projects.length === 0) {
      return UsageSnapshot.failure('未找到项目');
    }
    const first = asObj(projects[0]);
    const projectId = first != null ? str(first, 'project_id') : '';
    if (projectId.length === 0) {
      return UsageSnapshot.failure('响应解析失败');
    }
    const usageResp = await Http.get(`${base}/projects/${projectId}/usage/breakdown`, headers);
    if (!usageResp.ok) {
      return UsageSnapshot.failure(usageResp.errorText());
    }
    const usageRoot = asObj(usageResp.json());
    if (usageRoot == null) {
      return UsageSnapshot.failure('响应解析失败');
    }
    const hours = num(usageRoot, 'hours', 0);
    const totalHours = num(usageRoot, 'totalHours', 0);
    const requests = num(usageRoot, 'requests', 0);
    const tokensIn = num(usageRoot, 'tokensIn', 0);
    const tokensOut = num(usageRoot, 'tokensOut', 0);

    const snap = UsageSnapshot.success(null, null, null);
    const rows: ProviderDetailRow[] = [
      { label: '音频时长', value: `${hours.toFixed(1)} 小时 / 配额 ${totalHours.toFixed(1)}` },
      { label: '请求数', value: `${Math.round(requests)}` },
      { label: '输入 Token', value: Format.compact(tokensIn) },
      { label: '输出 Token', value: Format.compact(tokensOut) },
    ];
    const section: ProviderDetailSection = { title: '本月用量', rows: rows };
    snap.details = [section];
    if (totalHours > 0) {
      snap.primary = makeWindow(Math.min(100, (hours / totalHours) * 100), 0, true);
    }
    return snap;
  }
}

// ---------------------------------------------------------------------------
// ClinePass
// ---------------------------------------------------------------------------

class ClinePassProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'clinepass',
    title: 'ClinePass',
    authKind: AuthKind.API_KEY,
    accentColor: '#7C3AED',
    authHint: '粘贴 ClinePass API Key',
    authUrl: 'https://app.cline.bot',
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
    const resp = await Http.get('https://api.cline.bot/api/v1/users/me/plan/usage-limits', headers);
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    const root = asObj(resp.json());
    if (root == null || !bool(root, 'success')) {
      return UsageSnapshot.failure('响应解析失败');
    }
    const data = asObj(root['data']);
    const limits = data != null ? asArray(data['limits']) : null;
    if (limits == null) {
      return UsageSnapshot.failure('响应缺少限额');
    }
    let primary: RateWindow | null = null;
    let secondary: RateWindow | null = null;
    const extras: NamedRateWindow[] = [];
    for (let i = 0; i < limits.length; i++) {
      const l = asObj(limits[i]);
      if (l == null) {
        continue;
      }
      const type = str(l, 'type');
      let minutes = 0;
      let title = '';
      if (type === 'five_hour') {
        minutes = 300;
        title = '5 小时窗口';
      } else if (type === 'weekly') {
        minutes = 10080;
        title = '每周窗口';
      } else if (type === 'monthly') {
        minutes = 43200;
        title = '月度窗口';
      }
      if (minutes === 0) {
        continue;
      }
      const percent = num(l, 'percentUsed', 0);
      const resetSec = optNum(l, 'resetsAt');
      const w = makeWindow(Math.max(0, Math.min(100, percent)), resetSec != null && resetSec > 0 ? resetSec * 1000 : 0, true);
      if (type === 'five_hour' && primary == null) {
        primary = w;
      } else if (type === 'weekly' && secondary == null) {
        secondary = w;
      } else {
        extras.push({ id: type, title: title, window: w });
      }
    }
    const snap = UsageSnapshot.success(primary, secondary, null);
    snap.extraRateWindows = extras;
    return snap;
  }
}

// ---------------------------------------------------------------------------
// Crof
// ---------------------------------------------------------------------------

class CrofProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'crof',
    title: 'Crof',
    authKind: AuthKind.API_KEY,
    accentColor: '#059669',
    authHint: '粘贴 Crof API Key',
    authUrl: 'https://crof.ai/dashboard',
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
    const resp = await Http.get('https://crof.ai/usage_api/', headers);
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    const root = asObj(resp.json());
    if (root == null) {
      return UsageSnapshot.failure('响应解析失败');
    }
    const credits = num(root, 'credits', 0);
    const snap = UsageSnapshot.success(null, null, null);
    snap.providerCost = {
      remaining: Math.max(0, credits), used: 0, currency: 'CREDITS',
      displayText: `${Math.max(0, credits)} credits`,
    };
    const rows: ProviderDetailRow[] = [];
    const requestsPlan = optNum(root, 'requests_plan');
    const usable = optNum(root, 'usable_requests');
    if (requestsPlan != null) {
      rows.push({ label: '计划请求数', value: `${Math.round(requestsPlan)}` });
    }
    if (usable != null) {
      rows.push({ label: '可用请求', value: `${Math.round(usable)}` });
    }
    if (rows.length > 0) {
      const section: ProviderDetailSection = { title: '用量', rows: rows };
      snap.details = [section];
    }
    return snap;
  }
}

// ---------------------------------------------------------------------------
// Synthetic
// ---------------------------------------------------------------------------

class SyntheticProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'synthetic',
    title: 'Synthetic',
    authKind: AuthKind.API_KEY,
    accentColor: '#DC2626',
    authHint: '粘贴 Synthetic API Key',
    authUrl: 'https://api.synthetic.new',
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
    const resp = await Http.get('https://api.synthetic.new/v2/quotas', headers);
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    let root = asObj(resp.json());
    const parsed = resp.json();
    if (root == null && asArray(parsed) != null) {
      // 数组形态包装为 {quotas: [...]}
      const arr = asArray(parsed);
      if (arr != null) {
        const wrapped: Record<string, Json> = { 'quotas': arr };
        root = wrapped;
      }
    }
    if (root == null) {
      return UsageSnapshot.failure('响应解析失败');
    }
    const quotas = asArray(root['quotas']) ?? asArray(root['data']);
    const extras: NamedRateWindow[] = [];
    if (quotas != null) {
      for (let i = 0; i < quotas.length && extras.length < 5; i++) {
        const q = asObj(quotas[i]);
        if (q == null) {
          continue;
        }
        const label = pickStr(q, ['name', 'label', 'type', 'period', 'scope', 'title', 'id']) ?? `配额 ${i + 1}`;
        let percent = pickNum(q, ['percentUsed', 'usedPercent', 'usagePercent', 'usage_percent', 'used_percent', 'percent_used', 'percent']);
        if (percent == null) {
          const remain = pickNum(q, ['percentRemaining', 'remainingPercent', 'remaining_percent', 'percent_remaining']);
          if (remain != null) {
            percent = 100 - remain;
          }
        }
        if (percent == null) {
          const used = pickNum(q, ['used', 'usage', 'usedMessages', 'used_messages']);
          const limit = pickNum(q, ['limit', 'maxRequests', 'max_requests', 'quota', 'max', 'total', 'capacity', 'allowance']);
          if (used != null && limit != null && limit > 0) {
            percent = (used / limit) * 100;
          }
        }
        if (percent == null) {
          continue;
        }
        let resets = 0;
        const resetStr = pickStr(q, ['resetAt', 'reset_at', 'resetsAt', 'resets_at']);
        if (resetStr != null) {
          resets = isoMs(resetStr);
        } else {
          const resetNum = pickNum(q, ['resetAt', 'reset_at', 'resetsAt', 'resets_at']);
          if (resetNum != null && resetNum > 1e9) {
            resets = resetNum > 1e12 ? resetNum : resetNum * 1000;
          }
        }
        extras.push({ id: `syn_${i}`, title: label, window: makeWindow(Math.max(0, Math.min(100, percent)), resets, true) });
      }
    }
    if (extras.length === 0) {
      return UsageSnapshot.failure('未识别到配额数据');
    }
    const snap = UsageSnapshot.success(extras[0].window, null, null);
    snap.extraRateWindows = extras.slice(1);
    return snap;
  }
}

// ---------------------------------------------------------------------------
// ClawRouter
// ---------------------------------------------------------------------------

class ClawRouterProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'clawrouter',
    title: 'ClawRouter',
    authKind: AuthKind.SESSION,
    accentColor: '#D946EF',
    authHint: '粘贴 clawrouter.openclaw.ai 的会话 Cookie',
    authUrl: 'https://clawrouter.openclaw.ai/dashboard/access',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const cookie = setting.credential.trim();
    if (cookie.length === 0) {
      return UsageSnapshot.failure('未配置会话 Cookie');
    }
    const headers: Record<string, string> = {
      'cookie': cookie,
      'accept': 'application/json',
    };
    const resp = await Http.get('https://clawrouter.openclaw.ai/usage', headers);
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    const root = asObj(resp.json());
    if (root == null) {
      return UsageSnapshot.failure('响应解析失败');
    }
    const budget = asObj(root['budget']);
    const usage = asObj(root['usage']);
    const summary = usage != null ? asObj(usage['summary']) : null;
    if (budget == null || summary == null) {
      return UsageSnapshot.failure('响应缺少预算/用量');
    }
    const limitMicros = optNum(budget, 'limitMicros');
    const spentMicros = optNum(budget, 'spentMicros');
    const remainingMicros = optNum(budget, 'remainingMicros');
    const limit = limitMicros != null ? limitMicros / 1000000 : 0;
    const spent = spentMicros != null ? spentMicros / 1000000 : 0;
    const remaining = remainingMicros != null ? remainingMicros / 1000000 : 0;

    const snap = UsageSnapshot.success(null, null, null);
    if (limit > 0) {
      snap.primary = makeWindow(Math.min(100, (spent / limit) * 100), 0, true);
    }
    snap.providerCost = {
      remaining: remaining, used: spent, currency: 'USD',
      displayText: Format.money(remaining, 'USD'),
    };
    const rows: ProviderDetailRow[] = [
      { label: '预算上限', value: Format.money(limit, 'USD') },
      { label: '已消费', value: Format.money(spent, 'USD') },
      { label: '请求数', value: `${Math.round(num(summary, 'requestCount', 0))}` },
      { label: '输入 Token', value: Format.compact(num(summary, 'inputTokens', 0)) },
      { label: '输出 Token', value: Format.compact(num(summary, 'outputTokens', 0)) },
    ];
    const section: ProviderDetailSection = { title: '预算与用量', rows: rows };
    snap.details = [section];
    return snap;
  }
}

export function createXaiProvider(): UsageProvider {
  return new XaiProvider();
}

export function createQoderProvider(): UsageProvider {
  return new QoderProvider();
}

export function createVeniceProvider(): UsageProvider {
  return new VeniceProvider();
}

export function createNousProvider(): UsageProvider {
  return new NousProvider();
}

export function createMuseProvider(): UsageProvider {
  return new MuseProvider();
}

export function createDeepgramProvider(): UsageProvider {
  return new DeepgramProvider();
}

export function createClinePassProvider(): UsageProvider {
  return new ClinePassProvider();
}

export function createCrofProvider(): UsageProvider {
  return new CrofProvider();
}

export function createSyntheticProvider(): UsageProvider {
  return new SyntheticProvider();
}

export function createClawRouterProvider(): UsageProvider {
  return new ClawRouterProvider();
}

// ---------------------------------------------------------------------------
// LiteLLM（自托管）
// ---------------------------------------------------------------------------

class LiteLLMProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'litellm',
    title: 'LiteLLM',
    authKind: AuthKind.API_KEY,
    accentColor: '#0F766E',
    authHint: '第二栏填 LiteLLM 服务器地址；首栏填虚拟密钥',
    authUrl: 'https://docs.litellm.ai',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const key = setting.credential.trim();
    const base = setting.credential2.trim().replace(/\/+$/, '');
    if (key.length === 0 || base.length === 0) {
      return UsageSnapshot.failure('需要服务器地址与虚拟密钥');
    }
    const headers: Record<string, string> = {
      'authorization': `Bearer ${key}`,
      'accept': 'application/json',
    };
    const resp = await Http.get(`${base}/key/info`, headers);
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    const root = asObj(resp.json());
    const info = root != null ? asObj(root['info']) : null;
    if (info == null) {
      return UsageSnapshot.failure('响应解析失败');
    }
    const spend = num(info, 'spend', 0);
    const maxBudget = optNum(info, 'max_budget');
    const resetAt = optStr(info, 'budget_reset_at');
    let primary: RateWindow | null = null;
    if (maxBudget != null && maxBudget > 0) {
      primary = makeWindow(Math.min(100, (spend / maxBudget) * 100), isoMs(resetAt), true);
    }
    const snap = UsageSnapshot.success(primary, null, null);
    const rows: ProviderDetailRow[] = [
      { label: '已消费', value: Format.money(spend, 'USD') },
    ];
    if (maxBudget != null) {
      rows.push({ label: '预算上限', value: Format.money(maxBudget, 'USD') });
    }
    const section: ProviderDetailSection = { title: '预算', rows: rows };
    snap.details = [section];
    return snap;
  }
}

// ---------------------------------------------------------------------------
// LLM Proxy（自托管）
// ---------------------------------------------------------------------------

class LLMProxyProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'llmproxy',
    title: 'LLM Proxy',
    authKind: AuthKind.API_KEY,
    accentColor: '#475569',
    authHint: '第二栏填 LLM Proxy 服务器地址；首栏填 API Key',
    authUrl: 'https://github.com/LLMProxy',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const key = setting.credential.trim();
    const base = setting.credential2.trim().replace(/\/+$/, '');
    if (key.length === 0 || base.length === 0) {
      return UsageSnapshot.failure('需要服务器地址与 API Key');
    }
    const headers: Record<string, string> = {
      'authorization': `Bearer ${key}`,
      'accept': 'application/json',
    };
    const resp = await Http.get(`${base}/v1/quota-stats`, headers);
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    const root = asObj(resp.json());
    const groups = root != null ? asArray(root['quota_groups']) : null;
    if (groups == null || groups.length === 0) {
      return UsageSnapshot.failure('未返回配额组');
    }
    let primary: RateWindow | null = null;
    let secondary: RateWindow | null = null;
    const extras: NamedRateWindow[] = [];
    for (let i = 0; i < groups.length && i < 5; i++) {
      const g = asObj(groups[i]);
      if (g == null) {
        continue;
      }
      const remaining = optNum(g, 'remaining_percent');
      const name = str(g, 'name', `配额组 ${i + 1}`);
      if (remaining == null) {
        continue;
      }
      let resets = 0;
      const resetRaw = optStr(g, 'reset_time');
      if (resetRaw != null) {
        resets = isoMs(resetRaw);
      } else {
        const resetNum = optNum(g, 'reset_time');
        if (resetNum != null && resetNum > 1e9) {
          resets = resetNum > 1e12 ? resetNum : resetNum * 1000;
        }
      }
      const w = makeWindow(Math.max(0, Math.min(100, 100 - remaining)), resets, true);
      if (primary == null) {
        primary = w;
      } else if (secondary == null) {
        secondary = w;
      } else {
        extras.push({ id: `g_${i}`, title: name, window: w });
      }
    }
    if (primary == null) {
      return UsageSnapshot.failure('未识别到配额窗口');
    }
    const snap = UsageSnapshot.success(primary, secondary, null);
    snap.extraRateWindows = extras;
    return snap;
  }
}

export function createLiteLLMProvider(): UsageProvider {
  return new LiteLLMProvider();
}

export function createLLMProxyProvider(): UsageProvider {
  return new LLMProxyProvider();
}
