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
    // 费用卡：预付额度（对照插件 cost.period = "Prepaid credits"）
    snap.providerCost = {
      remaining: balance, used: 0, currency: 'USD',
      displayText: Format.money(balance, 'USD'),
      period: 'Prepaid credits',
    };
    snap.identity = { accountEmail: '', accountOrganization: `Team ${team}`, loginMethod: 'Management API' };

    // 账单汇总（对照插件 details[0]）：预付余额 + 近 30 天花费（分析接口尽力查询）
    const spend = await this.last30DaysSpend(key, team);
    const rows: ProviderDetailRow[] = [
      { label: 'Prepaid balance', value: Format.money(balance, 'USD') },
    ];
    if (spend != null) {
      rows.push({
        label: spend.partial ? 'Last 30 days (partial)' : 'Last 30 days',
        value: Format.money(spend.total, 'USD'),
      });
    }
    snap.details = [{ title: 'Billing summary', rows: rows }];
    return snap;
  }

  /** 近 30 天每日 USD 花费（对照插件 POST {root}/usage 的 analyticsRequest） */
  private async last30DaysSpend(key: string, team: string): Promise<XaiSpend | null> {
    const nowMs = Date.now();
    const start = new Date(nowMs);
    start.setUTCDate(start.getUTCDate() - 29);
    start.setUTCHours(0, 0, 0, 0);
    const stamp = (d: Date): string => {
      const pad = (n: number): string => n.toString().padStart(2, '0');
      return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())} ` +
        `${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}:${pad(d.getUTCSeconds())}`;
    };
    const req: XaiAnalyticsRequest = {
      timeRange: { startTime: stamp(start), endTime: stamp(new Date(nowMs)), timezone: 'Etc/GMT' },
      timeUnit: 'TIME_UNIT_DAY',
      values: [{ name: 'usd', aggregation: 'AGGREGATION_SUM' }],
      groupBy: [],
      filters: [],
    };
    const body = JSON.stringify({ analyticsRequest: req } as XaiUsageBody);
    const headers: Record<string, string> = {
      'authorization': `Bearer ${key}`,
      'content-type': 'application/json',
      'accept': 'application/json',
    };
    const resp = await Http.post(
      `https://management-api.x.ai/v1/billing/teams/${encodeURIComponent(team)}/usage`, headers, body);
    if (!resp.ok) {
      return null;
    }
    const root = asObj(resp.json());
    const series = root != null ? asArray(root['timeSeries']) : null;
    if (series == null) {
      return null;
    }
    const out = new XaiSpend();
    for (let i = 0; i < series.length; i++) {
      const s = asObj(series[i]);
      const points = s != null ? asArray(s['dataPoints']) : null;
      if (points == null) {
        continue;
      }
      for (let j = 0; j < points.length; j++) {
        const p = asObj(points[j]);
        if (p == null) {
          continue;
        }
        const values = asArray(p['values']);
        const first = values != null && values.length > 0 ? values[0] : null;
        const value = typeof first === 'number' ? first as number : 0;
        if (value > 0) {
          out.total += value;
        }
      }
    }
    out.partial = root != null && root['limitReached'] === true;
    return out;
  }
}

/** xAI 近 30 天花费聚合（对照插件 daily 累加与 partial 标记） */
class XaiSpend {
  total: number = 0;
  partial: boolean = false;
}

/** xAI 分析接口请求体（对照插件 analyticsRequest） */
interface XaiTimeRange {
  startTime: string;
  endTime: string;
  timezone: string;
}

interface XaiAnalyticsValue {
  name: string;
  aggregation: string;
}

interface XaiAnalyticsRequest {
  timeRange: XaiTimeRange;
  timeUnit: string;
  values: XaiAnalyticsValue[];
  groupBy: string[];
  filters: string[];
}

interface XaiUsageBody {
  analyticsRequest: XaiAnalyticsRequest;
}

// ---------------------------------------------------------------------------
// Qoder
// ---------------------------------------------------------------------------

class QoderProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'qoder',
    title: 'Qoder',
    authKind: AuthKind.SESSION,
    accentColor: '#10B981',
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
    const usdValue = pickNum(balances, ['usd']);
    const diemValue = pickNum(balances, ['diem']);
    const usd = usdValue ?? 0;
    const diem = diemValue ?? 0;
    const allocation = pickNum(root, ['diemEpochAllocation']);
    const canConsume = bool(root, 'canConsume');
    const currency = (optStr(root, 'consumptionCurrency') ?? '').toUpperCase();

    // 主窗口口径逐条对照插件 venice.js（余额不可用 / USD 直接可用 / DIEM 时期配额 / 仅 DIEM / 无余额）
    let usedPercent = 100;
    if (!canConsume) {
      usedPercent = 100;
    } else if (currency === 'USD' && usdValue != null && usd > 0) {
      usedPercent = 0;
    } else if (currency !== 'USD' && diemValue != null && allocation != null && allocation > 0) {
      usedPercent = Math.max(0, Math.min(100, ((allocation - diem) / allocation) * 100));
    } else if ((currency === 'DIEM' && diemValue != null && diem > 0) ||
      (diemValue != null && diem > 0) || (usdValue != null && usd > 0)) {
      usedPercent = 0;
    }

    const snap = UsageSnapshot.success(makeWindow(usedPercent, 0, true), null, null);
    snap.primaryLabel = 'Balance';
    snap.providerCost = {
      remaining: usd, used: 0, currency: 'USD',
      displayText: Format.money(usd, 'USD'),
    };
    // 余额分组（源工程 API Key 路径只把余额写在窗口描述里，这里额外列出两项明细）
    const rows: ProviderDetailRow[] = [
      { label: 'USD balance', value: Format.money(usd, 'USD') },
      { label: 'Diem balance', value: `${diem}` },
    ];
    if (allocation != null) {
      rows.push({ label: 'Epoch allocation', value: `${allocation}` });
    }
    snap.details = [{ title: 'Credits', rows: rows }];
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
    const access = asObj(root['paid_service_access']);
    const remaining = pickNum(root, ['credits_remaining']) ??
      (sub != null ? pickNum(sub, ['credits_remaining']) : null) ??
      (access != null ? pickNum(access, ['subscription_credits_remaining']) : null);
    const monthly = sub != null ? pickNum(sub, ['monthly_credits']) : null;
    const rollover = sub != null ? pickNum(sub, ['rollover_credits']) : null;
    const purchased = pickNum(root, ['purchased_credits_remaining']) ??
      (access != null ? pickNum(access, ['purchased_credits_remaining']) : null);
    const total = access != null ? pickNum(access, ['total_usable_credits']) : null;
    if (remaining == null && monthly == null && rollover == null && purchased == null && total == null) {
      return UsageSnapshot.failure('未返回额度信息');
    }
    const renewable = sub != null ? optStr(sub, 'current_period_end') : null;

    const snap = UsageSnapshot.success(null, null, null);
    const balance = remaining ?? 0;
    snap.providerCost = {
      remaining: balance, used: 0, currency: 'CREDITS',
      displayText: `${balance} credits`,
    };

    // Subscription / Credits 两组（对照插件：订阅额度、月度授予、滚存、续期、充值、可用总额）
    const subscriptionRows: ProviderDetailRow[] = [];
    if (remaining != null) {
      const grant = monthly != null && monthly > 0 ? ` of ${monthly}` : '';
      subscriptionRows.push({
        label: 'Subscription credits',
        value: `${Math.max(0, remaining)}${grant} left`,
      });
    } else if (monthly != null) {
      subscriptionRows.push({ label: 'Monthly grant', value: `${monthly}` });
    }
    if (rollover != null && rollover > 0) {
      subscriptionRows.push({ label: 'Rollover credits', value: `${rollover}` });
    }
    if (renewable != null && renewable.length > 0) {
      const ms = Date.parse(renewable);
      subscriptionRows.push({ label: 'Renews', value: isNaN(ms) ? renewable : Format.dateTime(ms) });
    }
    const creditRows: ProviderDetailRow[] = [];
    if (purchased != null) {
      creditRows.push({ label: 'Top-up credits', value: `${purchased}` });
    }
    if (total != null) {
      creditRows.push({ label: 'Total usable', value: `${total}` });
    }
    const sections: ProviderDetailSection[] = [];
    if (subscriptionRows.length > 0) {
      sections.push({ title: 'Subscription', rows: subscriptionRows });
    }
    if (creditRows.length > 0) {
      sections.push({ title: 'Credits', rows: creditRows });
    }
    if (sections.length > 0) {
      snap.details = sections;
    }
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
    const plan = optStr(root, 'subs_tier_name');
    const email = optStr(root, 'user_email');
    const rows: ProviderDetailRow[] = [];
    if (plan != null && plan.length > 0) {
      rows.push({ label: 'Plan', value: plan });
    }

    const usage = asObj(root['subs_usage']);
    if (usage == null) {
      // 登录响应不含订阅用量时只给 Plan/Quota 两行（对照插件）
      rows.push({ label: 'Quota', value: 'Not included in this login response' });
      const snap = UsageSnapshot.success(null, null, null);
      snap.identity = {
        accountEmail: email ?? '', accountOrganization: '',
        loginMethod: plan != null && plan.length > 0 ? plan : 'Muse login',
      };
      snap.details = [{ title: 'Muse Code subscription', rows: rows }];
      return snap;
    }
    const windowObj = asObj(usage['window']);
    const weekly = asObj(usage['weekly']);
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
    rows.push({ label: '5 hours', value: `${Math.round(Math.max(0, Math.min(100, percent)))}%` });
    if (weekly != null) {
      rows.push({ label: 'Weekly', value: `${Math.round(Math.max(0, Math.min(100, num(weekly, 'used_percent', 0))))}%` });
    }
    const snap = UsageSnapshot.success(primary, secondary, null);
    snap.identity = {
      accountEmail: email ?? '', accountOrganization: '',
      loginMethod: plan != null && plan.length > 0 ? plan : 'Muse login',
    };
    snap.details = [{ title: 'Muse Code subscription', rows: rows }];
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

    // 逐项目累加用量分解（对照插件：遍历全部项目，取最早 start / 最晚 end）
    const totals = new DeepgramTotals();
    let firstProjectName = '';
    let start = '';
    let end = '';
    let anyOk = false;
    let lastError = '';
    for (let i = 0; i < projects.length; i++) {
      const project = asObj(projects[i]);
      const projectId = project != null ? str(project, 'project_id') : '';
      if (projectId.length === 0) {
        continue;
      }
      if (firstProjectName.length === 0) {
        firstProjectName = optStr(project!, 'name') ?? projectId;
      }
      const usageResp = await Http.get(
        `${base}/projects/${encodeURIComponent(projectId)}/usage/breakdown`, headers);
      if (!usageResp.ok) {
        lastError = usageResp.errorText();
        continue;
      }
      const payload = asObj(usageResp.json());
      if (payload == null) {
        continue;
      }
      anyOk = true;
      const pStart = optStr(payload, 'start');
      if (pStart != null && (start.length === 0 || pStart < start)) {
        start = pStart;
      }
      const pEnd = optStr(payload, 'end');
      if (pEnd != null && (end.length === 0 || pEnd > end)) {
        end = pEnd;
      }
      const rows = asArray(payload['results']);
      if (rows == null) {
        continue;
      }
      for (let j = 0; j < rows.length; j++) {
        const row = asObj(rows[j]);
        if (row == null) {
          continue;
        }
        totals.hours += num(row, 'hours', 0);
        totals.totalHours += num(row, 'total_hours', 0);
        totals.agentHours += num(row, 'agent_hours', 0);
        totals.tokensIn += num(row, 'tokens_in', 0);
        totals.tokensOut += num(row, 'tokens_out', 0);
        totals.tts += num(row, 'tts_characters', 0);
        totals.requests += num(row, 'requests', 0);
      }
    }
    if (!anyOk) {
      return UsageSnapshot.failure(lastError.length > 0 ? lastError : '未获取到用量数据');
    }

    const snap = UsageSnapshot.success(null, null, null);
    snap.identity = {
      accountEmail: '',
      accountOrganization: '',
      loginMethod: projects.length > 1 ? `${projects.length} projects` : `Project: ${firstProjectName}`,
    };

    // Usage summary 分组（对照插件深搜：请求数、音频时长、Agent 小时、Token、TTS 字符、区间）
    const decimal = (value: number): string => value === Math.floor(value) ? `${value}` : value.toFixed(1);
    const rows: ProviderDetailRow[] = [
      { label: 'Requests', value: `${Math.round(totals.requests)}` },
    ];
    if (totals.hours > 0 || totals.totalHours > 0) {
      rows.push({
        label: 'Audio',
        value: `${decimal(totals.hours)} hours`,
        secondary: `${decimal(totals.totalHours)} billable hours`,
      });
    }
    if (totals.agentHours > 0) {
      rows.push({ label: 'Agent hours', value: decimal(totals.agentHours) });
    }
    if (totals.tokensIn > 0 || totals.tokensOut > 0) {
      rows.push({ label: 'Tokens', value: `${Math.round(totals.tokensIn + totals.tokensOut)}` });
    }
    if (totals.tts > 0) {
      rows.push({ label: 'TTS characters', value: `${Math.round(totals.tts)}` });
    }
    if (start.length > 0 && end.length > 0) {
      rows.push({ label: 'Period', value: `${start} to ${end}` });
    }
    snap.details = [{ title: 'Usage summary', rows: rows }];
    return snap;
  }
}

/** Deepgram 多项目用量累加 */
class DeepgramTotals {
  hours: number = 0;
  totalHours: number = 0;
  agentHours: number = 0;
  tokensIn: number = 0;
  tokensOut: number = 0;
  tts: number = 0;
  requests: number = 0;
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
    let tertiary: RateWindow | null = null;
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
      // 泳道对照 macOS ClinePassProviderDescriptor：session=5-hour、weekly=Weekly、opus=Monthly
      if (type === 'five_hour' && primary == null) {
        primary = w;
      } else if (type === 'weekly' && secondary == null) {
        secondary = w;
      } else if (type === 'monthly' && tertiary == null) {
        tertiary = w;
      } else {
        extras.push({ id: type, title: title, window: w });
      }
    }
    const snap = UsageSnapshot.success(primary, secondary, tertiary);
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
    // 优先取插件（synthetic.js）定义的三个具名泳道：
    // primary=rollingFiveHourLimit、secondary=weeklyTokenLimit、tertiary=search.hourly
    const data = asObj(root['data']);
    const named: (Json | null)[] = [
      firstOfObj(root, ['rollingFiveHourLimit']) ?? (data != null ? firstOfObj(data, ['rollingFiveHourLimit']) : null),
      firstOfObj(root, ['weeklyTokenLimit']) ?? (data != null ? firstOfObj(data, ['weeklyTokenLimit']) : null),
      SyntheticProvider.searchHourly(root) ?? (data != null ? SyntheticProvider.searchHourly(data) : null),
    ];

    let primary: RateWindow | null = null;
    let secondary: RateWindow | null = null;
    let tertiary: RateWindow | null = null;
    const extras: NamedRateWindow[] = [];

    if (named[0] != null || named[1] != null || named[2] != null) {
      primary = syntheticQuotaWindow(named[0]);
      secondary = syntheticQuotaWindow(named[1]);
      tertiary = syntheticQuotaWindow(named[2]);
    } else {
      // 回退：扫描配额数组，前三个进主/次/三窗口，其余作附加窗口
      const parsed: RateWindow[] = [];
      const candidates: Json[] = [];
      const arrays: Json[] = [
        root['quotas'], root['quota'], root['limits'], root['usage'],
        root['entries'], root['subscription'],
      ];
      for (let i = 0; i < arrays.length; i++) {
        const arr = asArray(arrays[i]);
        if (arr != null && arr.length > 0) {
          for (let j = 0; j < arr.length; j++) {
            candidates.push(arr[j]);
          }
          break;
        }
      }
      if (candidates.length === 0 && data != null) {
        const nested = asArray(data['quotas']) ?? asArray(data['limits']) ?? asArray(data['usage']);
        if (nested != null) {
          for (let j = 0; j < nested.length; j++) {
            candidates.push(nested[j]);
          }
        }
      }
      for (let i = 0; i < candidates.length && parsed.length < 8; i++) {
        const w = syntheticQuotaWindow(candidates[i]);
        if (w != null) {
          parsed.push(w);
        }
      }
      if (parsed.length === 0) {
        return UsageSnapshot.failure('未识别到配额数据');
      }
      primary = parsed.length > 0 ? parsed[0] : null;
      secondary = parsed.length > 1 ? parsed[1] : null;
      tertiary = parsed.length > 2 ? parsed[2] : null;
      for (let i = 3; i < parsed.length; i++) {
        const q = asObj(candidates[i]);
        const title = q != null
          ? (pickStr(q, ['name', 'label', 'type', 'period', 'scope', 'title', 'id']) ?? `配额 ${i + 1}`)
          : `配额 ${i + 1}`;
        extras.push({ id: `syn_${i}`, title: title, window: parsed[i] });
      }
    }

    const snap = UsageSnapshot.success(primary, secondary, tertiary);
    snap.extraRateWindows = extras;
    // 套餐名（对照插件 planKeys → identity.loginMethod）
    const plan = pickStr(root, ['plan', 'planName', 'plan_name', 'subscription', 'subscriptionPlan', 'tier', 'package', 'packageName']);
    if (plan != null) {
      snap.identity = { accountEmail: '', accountOrganization: '', loginMethod: plan };
    }
    return snap;
  }

  /** 搜索小时配额位于 search.hourly（对照插件 slots[2]） */
  private static searchHourly(o: Record<string, Json>): Json | null {
    const search = asObj(o['search']);
    return search != null ? search['hourly'] : null;
  }
}

/** 单个配额 → 用量窗口（别名容错，对照插件 synthetic.js 的 parseQuota） */
export function syntheticQuotaWindow(value: Json | null): RateWindow | null {
  const q = asObj(value);
  if (q == null) {
    return null;
  }
  let percent = pickNum(q, ['percentUsed', 'usedPercent', 'usagePercent', 'usage_percent', 'used_percent', 'percent_used', 'percent']);
  if (percent == null) {
    const remain = pickNum(q, ['percentRemaining', 'remainingPercent', 'remaining_percent', 'percent_remaining']);
    if (remain != null) {
      percent = 100 - remain;
    }
  }
  if (percent == null) {
    const used = pickNum(q, ['used', 'usage', 'usedMessages', 'used_messages', 'requests', 'requestCount', 'request_count', 'consumed', 'spent']);
    const limit = pickNum(q, ['limit', 'messageLimit', 'message_limit', 'messages', 'maxRequests', 'max_requests', 'requestLimit', 'request_limit', 'quota', 'max', 'total', 'capacity', 'allowance']);
    if (used != null && limit != null && limit > 0) {
      percent = (used / limit) * 100;
    }
  }
  if (percent == null) {
    return null;
  }
  // 小数比率 → 百分点（对照插件 normalizedPercent）
  if (percent <= 1 && percent > 0) {
    percent = percent * 100;
  }
  let resets = 0;
  const resetStr = pickStr(q, ['resetAt', 'reset_at', 'resetsAt', 'resets_at', 'renewAt', 'renew_at', 'renewsAt', 'nextTickAt', 'periodEnd', 'expiresAt']);
  if (resetStr != null) {
    resets = isoMs(resetStr);
  } else {
    const resetNum = pickNum(q, ['resetAt', 'reset_at', 'resetsAt', 'resets_at', 'renewAt', 'periodEnd', 'expiresAt']);
    if (resetNum != null) {
      if (resetNum > 1e12) {
        resets = resetNum;
      } else if (resetNum > 1e9) {
        resets = resetNum * 1000;
      }
    }
  }
  return makeWindow(Math.max(0, Math.min(100, percent)), resets, true);
}

// ---------------------------------------------------------------------------
// ClawRouter
// ---------------------------------------------------------------------------

/**
 * 凭证判别：带 "=" 的串按会话 Cookie 处理，否则视为 policy API Key
 * （与 OpenCode Go 的同款双模式判别保持一致）。
 */
export function clawRouterIsApiKey(credential: string): boolean {
  const c = credential.trim();
  return c.length > 0 && c.indexOf('=') < 0;
}

/** Base URL：空值取默认站点，去尾斜杠（第二凭证栏可填自托管地址） */
export function clawRouterBaseURL(configured: string): string {
  const base = configured.trim();
  if (base.length === 0) {
    return 'https://clawrouter.openclaw.ai';
  }
  return base.endsWith('/') ? base.substring(0, base.length - 1) : base;
}

/** 对应的用量端点：API Key 走 /v1/usage，Cookie 走 /usage（对照插件 clawrouter.js） */
export function clawRouterUsageUrl(credential: string, configuredBase: string): string {
  const suffix = clawRouterIsApiKey(credential) ? '/v1/usage' : '/usage';
  return `${clawRouterBaseURL(configuredBase)}${suffix}`;
}

class ClawRouterProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'clawrouter',
    title: 'ClawRouter',
    authKind: AuthKind.SESSION,
    accentColor: '#596EF6',
    authHint: '粘贴 clawrouter.openclaw.ai 的会话 Cookie，或自托管 / 云端 policy API Key',
    authUrl: 'https://clawrouter.openclaw.ai/dashboard/access',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const cred = setting.credential.trim();
    if (cred.length === 0) {
      return UsageSnapshot.failure('未配置会话 Cookie 或 API Key');
    }
    const headers: Record<string, string> = { 'accept': 'application/json' };
    if (clawRouterIsApiKey(cred)) {
      headers['authorization'] = `Bearer ${cred}`;
      headers['user-agent'] = 'CodexBar';
    } else {
      headers['cookie'] = cred;
    }
    const resp = await Http.get(clawRouterUsageUrl(cred, setting.credential2), headers);
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

    const configured = budget['configured'] === true;
    const ledger = optStr(budget, 'ledger') ?? '';
    const requestCount = Math.round(num(summary, 'requestCount', 0));
    const successCount = Math.round(num(summary, 'successCount', 0));
    const errorCount = Math.round(num(summary, 'errorCount', 0));
    const inputTokens = Math.round(num(summary, 'inputTokens', 0));
    const outputTokens = Math.round(num(summary, 'outputTokens', 0));
    const totalTokens = Math.round(num(summary, 'totalTokens', 0));
    // actualCostMicros 为可选字段，缺失按 0 处理
    const actualCostMicros = optNum(summary, 'actualCostMicros');
    const actualCost = actualCostMicros != null ? actualCostMicros / 1000000 : 0;

    const snap = UsageSnapshot.success(null, null, null);
    if (limit > 0) {
      snap.primary = makeWindow(Math.min(100, (spent / limit) * 100), 0, true);
    }
    snap.identity = {
      accountEmail: '',
      accountOrganization: `${this.providerCount(root)} routed providers`,
      loginMethod: configured ? 'Managed monthly budget' : 'Unmetered',
    };

    // Usage 分组（对照插件：请求数/成功失败、Token 数/输入输出、实际花费、预算账本）
    const rows: ProviderDetailRow[] = [
      {
        label: 'Requests',
        value: `${requestCount}`,
        secondary: `${successCount} succeeded · ${errorCount} failed`,
      },
      {
        label: 'Tokens',
        value: `${totalTokens}`,
        secondary: `${inputTokens} input · ${outputTokens} output`,
      },
      { label: 'Actual cost', value: `$${actualCost.toFixed(6)}` },
      { label: 'Budget ledger', value: ledger },
    ];
    const sections: ProviderDetailSection[] = [{ title: 'Usage', rows: rows }];

    // 预算行：有上限时补一行「已消费 / 上限」（对照插件 Monthly budget 行）
    if (limit > 0) {
      snap.providerCost = {
        remaining: remaining, used: spent, currency: 'USD',
        displayText: Format.money(remaining, 'USD'),
        period: 'This month',
        limit: limit,
      };
      rows.push({
        label: 'Monthly budget',
        value: `$${spent.toFixed(6)} / $${limit.toFixed(2)}`,
        secondary: remainingMicros != null ? `$${remaining.toFixed(6)} remaining` : undefined,
      });
    } else if (actualCost > 0) {
      snap.providerCost = {
        remaining: 0, used: actualCost, currency: 'USD',
        displayText: Format.money(actualCost, 'USD'),
        period: 'This month',
        limit: 0,
      };
    }

    // Routed providers 分组：前 20 家按花费降序
    const providerRows = this.routedProviderRows(root, 20);
    if (providerRows.length > 0) {
      sections.push({ title: 'Routed providers', rows: providerRows });
    }
    snap.details = sections;
    return snap;
  }

  /** usage.providers 条数（对照插件 identity.organization） */
  private providerCount(root: Record<string, Json>): number {
    const usage = asObj(root['usage']);
    const list = usage != null ? asArray(usage['providers']) : null;
    return list == null ? 0 : list.length;
  }

  /** 路由到各服务商的花费明细（对照插件：花费降序，取前 limit 条） */
  private routedProviderRows(root: Record<string, Json>, limit: number): ProviderDetailRow[] {
    const usage = asObj(root['usage']);
    const list = usage != null ? asArray(usage['providers']) : null;
    if (list == null) {
      return [];
    }
    const items: ClawRoutedProvider[] = [];
    for (let i = 0; i < list.length; i++) {
      const item = asObj(list[i]);
      if (item == null) {
        continue;
      }
      const name = optStr(item, 'provider');
      if (name == null || name.trim().length === 0) {
        continue;
      }
      const costMicros = optNum(item, 'actualCostMicros');
      items.push({
        name: name.trim(),
        requests: Math.round(num(item, 'requestCount', 0)),
        tokens: Math.round(num(item, 'totalTokens', 0)),
        cost: costMicros != null ? costMicros / 1000000 : 0,
      });
    }
    items.sort((a: ClawRoutedProvider, b: ClawRoutedProvider): number => {
      if (a.cost === b.cost) {
        if (a.requests === b.requests) {
          return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0);
        }
        return b.requests - a.requests;
      }
      return b.cost - a.cost;
    });
    const rows: ProviderDetailRow[] = [];
    const count = items.length > limit ? limit : items.length;
    for (let i = 0; i < count; i++) {
      rows.push({
        label: items[i].name,
        value: `${items[i].requests} requests`,
        secondary: `$${items[i].cost.toFixed(6)} · ${items[i].tokens} tokens`,
      });
    }
    return rows;
  }
}

/** 路由到的单个服务商花费 */
interface ClawRoutedProvider {
  name: string;
  requests: number;
  tokens: number;
  cost: number;
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
