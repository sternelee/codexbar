/**
 * Cursor —— 两种查询方式（凭证形态自动识别）
 *
 * A. 网页会话（oauth web；对照 macOS CursorStatusProbe.fetchWithCookieHeader）
 *    凭证：cursor.com 的 WorkosCursorSessionToken（可整段 Cookie，也可只填值）
 *    GET  https://cursor.com/api/usage-summary                  → 计划内用量 / 按量花费（必需）
 *    GET  https://cursor.com/api/auth/me                        → 邮箱 / sub（可选）
 *    GET  https://cursor.com/api/usage?user=<sub>               → 旧版「按请求数」计划配额（可选）
 *    POST https://cursor.com/api/dashboard/get-sand-usage-status → Grok Bot 附加窗口（可选）
 *
 * B. API Key（官方 Admin API；凭证以 crsr_ 开头）
 *    Basic 认证（用户名=Key、密码留空）
 *    GET  https://api.cursor.com/teams/members                  → 校验密钥 + 团队目录（必需）
 *    POST https://api.cursor.com/teams/spend                    → 成员花费 / 预算
 *    POST https://api.cursor.com/teams/daily-usage-data         → 近 30 天每日请求量（图表）
 *
 * 注：macOS 版只做网页会话（依赖 Safari/App 抓 Cookie）；本工程额外接上官方 API Key，
 * 便于无浏览器环境（安卓/iOS）查询团队花费与用量。
 */

import { util } from '@kit.ArkTS';
import { Http } from '../net/Http';
import { asArray, asObj, Json, optNum, optStr } from '../net/Json';
import {
  AuthKind,
  makeChart,
  makeWindow,
  NamedRateWindow,
  ProviderChartPoint,
  ProviderCostSnapshot,
  ProviderDescriptor,
  ProviderDetailRow,
  ProviderDetailSection,
  ProviderSetting,
  UsageSnapshot
} from '../model/Models';
import { UsageProvider } from './ProviderBase';
import { Format } from '../common/Format';

const CURSOR_WEB_BASE = 'https://cursor.com';
const CURSOR_API_BASE = 'https://api.cursor.com';
/** Grok Bot 附加窗口（对照 CursorSandUsageStatus.extraWindowID / extraWindowTitle） */
const GROK_BOT_ID = 'cursor-grok-bot';
const GROK_BOT_TITLE = 'Grok Bot';

/** 把用户粘贴的凭证规整成 Cookie 头（Accepted: 整段 Cookie / 只填值 / 带 Cookie: 前缀） */
function cursorCookieHeader(credential: string): string {
  let text = credential.trim();
  if (text.toLowerCase().startsWith('cookie:')) {
    text = text.substring(7).trim();
  }
  if (text.indexOf('WorkosCursorSessionToken=') >= 0) {
    return text;
  }
  return `WorkosCursorSessionToken=${text}`;
}

/** 是否为官方 Admin API Key（crsr_ 前缀） */
function isAdminKey(credential: string): boolean {
  return credential.trim().toLowerCase().startsWith('crsr_');
}

/** ISO8601 → Unix 毫秒；无法解析返回 0 */
function isoMs(value: string | null): number {
  if (value == null || value.length === 0) {
    return 0;
  }
  const t = Date.parse(value);
  return isNaN(t) ? 0 : t;
}

/** 百分比截断到 0-100（对照 UsagePercent.displayClamped） */
function clampPct(value: number | null): number | null {
  if (value == null || !isFinite(value)) {
    return null;
  }
  return Math.max(0, Math.min(100, value));
}

/** 分 → 美元（Cursor 的 used/limit 是「分」） */
function cents(value: number | null): number {
  return value == null ? 0 : value / 100;
}

/** 计划名（对照 CursorStatusSnapshot.formatMembershipType） */
export function cursorPlanName(membership: string | null): string {
  if (membership == null || membership.length === 0) {
    return 'Cursor';
  }
  const key = membership.toLowerCase();
  if (key === 'enterprise') {
    return 'Cursor Enterprise';
  }
  if (key === 'express') {
    return 'Cursor Start';
  }
  if (key === 'free') {
    return 'Cursor Free';
  }
  if (key === 'free_trial') {
    return 'Cursor Pro Trial';
  }
  if (key === 'hobby') {
    return 'Cursor Hobby';
  }
  if (key === 'pro' || key === 'pro_student') {
    return 'Cursor Pro';
  }
  if (key === 'pro_plus') {
    return 'Cursor Pro+';
  }
  if (key === 'team' || key === 'teams') {
    return 'Cursor Team';
  }
  if (key === 'business') {
    return 'Cursor Business';
  }
  if (key === 'ultra') {
    return 'Cursor Ultra';
  }
  return `Cursor ${membership}`;
}

/** 旧版「按请求数」计划配额（对照 CursorRequestUsage） */
export class CursorRequestQuota {
  used: number = 0;
  limit: number = 0;

  usedPercent(): number {
    return this.limit > 0 ? (this.used / this.limit) * 100 : 0;
  }
}

/** /api/usage-summary 的解析结果（对照 CursorUsageSummary + parseUsageSummary 的 cents 换算） */
export class CursorPlanSummary {
  /** 计划内用量（分） */
  planUsedCents: number | null = null;
  planLimitCents: number | null = null;
  autoPercent: number | null = null;
  apiPercent: number | null = null;
  totalPercent: number | null = null;
  /** individualUsage.overall（企业/团队成员个人上限，分） */
  overallUsedCents: number | null = null;
  overallLimitCents: number | null = null;
  /** teamUsage.pooled（共享团队池，分） */
  pooledUsedCents: number | null = null;
  pooledLimitCents: number | null = null;
  onDemandUsedCents: number = 0;
  onDemandLimitCents: number | null = null;
  billingCycleStart: string | null = null;
  billingCycleEnd: string | null = null;
  membershipType: string | null = null;
  limitType: string | null = null;

  /** 顶部大号百分比：优先服务端总百分比，其次 Auto/API 均值，再退到分/上限（对照 planPercentUsed） */
  headlinePercent(): number {
    const total = clampPct(this.totalPercent);
    if (total != null) {
      return total;
    }
    const auto = clampPct(this.autoPercent);
    const api = clampPct(this.apiPercent);
    if (auto != null && api != null) {
      return Math.max(0, Math.min(100, (auto + api) / 2));
    }
    if (api != null) {
      return api;
    }
    if (auto != null) {
      return auto;
    }
    if (this.planLimitCents != null && this.planLimitCents > 0) {
      return clampPct(((this.planUsedCents ?? 0) / this.planLimitCents) * 100) ?? 0;
    }
    if (this.overallLimitCents != null && this.overallLimitCents > 0) {
      return clampPct(((this.overallUsedCents ?? 0) / this.overallLimitCents) * 100) ?? 0;
    }
    if (this.pooledLimitCents != null && this.pooledLimitCents > 0) {
      return clampPct(((this.pooledUsedCents ?? 0) / this.pooledLimitCents) * 100) ?? 0;
    }
    return 0;
  }
}

/** 解析 /api/usage-summary（字段缺失一律按 0 / null 处理，不因单字段缺失去掉整块用量） */
export function cursorParseSummary(json: Json): CursorPlanSummary | null {
  const root = asObj(json);
  if (root == null) {
    return null;
  }
  const out = new CursorPlanSummary();
  out.billingCycleStart = optStr(root, 'billingCycleStart');
  out.billingCycleEnd = optStr(root, 'billingCycleEnd');
  out.membershipType = optStr(root, 'membershipType');
  out.limitType = optStr(root, 'limitType');

  const individual = asObj(root['individualUsage']);
  if (individual != null) {
    const plan = asObj(individual['plan']);
    if (plan != null) {
      out.planUsedCents = optNum(plan, 'used');
      out.planLimitCents = optNum(plan, 'limit');
      out.autoPercent = optNum(plan, 'autoPercentUsed');
      out.apiPercent = optNum(plan, 'apiPercentUsed');
      out.totalPercent = optNum(plan, 'totalPercentUsed');
    }
    const overall = asObj(individual['overall']);
    if (overall != null) {
      out.overallUsedCents = optNum(overall, 'used');
      out.overallLimitCents = optNum(overall, 'limit');
    }
    const onDemand = asObj(individual['onDemand']);
    if (onDemand != null) {
      out.onDemandUsedCents = optNum(onDemand, 'used') ?? 0;
      out.onDemandLimitCents = optNum(onDemand, 'limit');
    }
  }
  const team = asObj(root['teamUsage']);
  if (team != null) {
    const pooled = asObj(team['pooled']);
    if (pooled != null) {
      out.pooledUsedCents = optNum(pooled, 'used');
      out.pooledLimitCents = optNum(pooled, 'limit');
    }
  }
  return out;
}

/** 是否为团队/企业计划（对照 CursorUsageSummary.isTeamPlan） */
function cursorIsTeamPlan(s: CursorPlanSummary): boolean {
  const m = (s.membershipType ?? '').toLowerCase();
  if (m === 'enterprise' || m === 'business' || m === 'team' || m === 'teams') {
    return true;
  }
  return (s.limitType ?? '').toLowerCase() === 'team';
}

/** 解析 /api/usage?user=ID（旧版按请求数计划） */
export function cursorParseRequestQuota(json: Json): CursorRequestQuota | null {
  const root = asObj(json);
  if (root == null) {
    return null;
  }
  const gpt4 = asObj(root['gpt-4']);
  if (gpt4 == null) {
    return null;
  }
  const limit = optNum(gpt4, 'maxRequestUsage');
  if (limit == null || limit <= 0) {
    return null;
  }
  const quota = new CursorRequestQuota();
  quota.limit = limit;
  quota.used = optNum(gpt4, 'numRequestsTotal') ?? optNum(gpt4, 'numRequests') ?? 0;
  return quota;
}

/** Grok Bot 附加窗口（对照 CursorSandUsageStatus.extraRateWindow） */
export function cursorGrokBotWindow(json: Json, now: number): NamedRateWindow | null {
  const body = asObj(json);
  if (body == null) {
    return null;
  }
  const usagePercent = optNum(body, 'usagePercent');
  if (usagePercent == null) {
    return null;
  }
  const includedLimitZero = body['includedLimitZero'];
  const hasNonZeroLimit = body['hasNonZeroIncludedLimit'];
  const hasLimit = typeof includedLimitZero === 'boolean'
    ? !(includedLimitZero as boolean)
    : hasNonZeroLimit === true;
  const trialMs = isoMs(optStr(body, 'sandTrialExpiresAt'));
  const hasTrial = !hasLimit && trialMs > now;
  if (!hasLimit && !hasTrial) {
    return null;
  }
  const resetsAt = hasTrial ? 0 : isoMs(optStr(body, 'nextResetTimestampUtc'));
  const w = makeWindow(clampPct(usagePercent) ?? 0, resetsAt, true);
  return { id: GROK_BOT_ID, title: GROK_BOT_TITLE, window: w };
}

// ---------------------------------------------------------------------------
// API Key（官方 Admin API）
// ---------------------------------------------------------------------------

/** 团队成员花费行（对照 CursorTeamSpend.Member） */
export class CursorMemberSpend {
  email: string = '';
  emailLower: string = '';
  spendCents: number = 0;
  overallSpendCents: number = 0;
  monthlyLimitDollars: number | null = null;
  effectivePerUserLimitDollars: number | null = null;
}

/** 解析 POST /teams/spend 的 teamMemberSpend[] */
export function cursorParseMembers(json: Json): CursorMemberSpend[] {
  const out: CursorMemberSpend[] = [];
  const root = asObj(json);
  const rows = root != null ? asArray(root['teamMemberSpend']) : null;
  if (rows == null) {
    return out;
  }
  for (let i = 0; i < rows.length; i++) {
    const row = asObj(rows[i]);
    if (row == null) {
      continue;
    }
    const m = new CursorMemberSpend();
    m.email = optStr(row, 'email') ?? '';
    m.emailLower = m.email.toLowerCase();
    m.spendCents = optNum(row, 'spendCents') ?? 0;
    m.overallSpendCents = optNum(row, 'overallSpendCents') ?? m.spendCents;
    m.monthlyLimitDollars = optNum(row, 'monthlyLimitDollars');
    m.effectivePerUserLimitDollars = optNum(row, 'effectivePerUserLimitDollars');
    out.push(m);
  }
  return out;
}

/** 单日请求量（POST /teams/daily-usage-data 的 data[]，字段缺失记 0） */
export class CursorDailyUsage {
  date: string = '';
  includedReqs: number = 0;
  usageBasedReqs: number = 0;
  apiKeyReqs: number = 0;

  total(): number {
    return this.includedReqs + this.usageBasedReqs + this.apiKeyReqs;
  }
}

/** 解析 POST /teams/daily-usage-data（date 升序） */
export function cursorParseDailyUsage(json: Json): CursorDailyUsage[] {
  const out: CursorDailyUsage[] = [];
  const root = asObj(json);
  const rows = root != null ? asArray(root['data']) : null;
  if (rows == null) {
    return out;
  }
  for (let i = 0; i < rows.length; i++) {
    const row = asObj(rows[i]);
    if (row == null) {
      continue;
    }
    const d = new CursorDailyUsage();
    d.date = optStr(row, 'date') ?? '';
    if (d.date.length === 0) {
      continue;
    }
    d.includedReqs = optNum(row, 'subscriptionIncludedReqs') ?? 0;
    d.usageBasedReqs = optNum(row, 'usageBasedReqs') ?? 0;
    d.apiKeyReqs = optNum(row, 'apiKeyReqs') ?? 0;
    out.push(d);
  }
  out.sort((a: CursorDailyUsage, b: CursorDailyUsage) => a.date < b.date ? -1 : a.date > b.date ? 1 : 0);
  return out;
}

// ---------------------------------------------------------------------------

class CursorProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'cursor',
    title: 'Cursor',
    authKind: AuthKind.SESSION,
    accentColor: '#00BFA5',
    authHint: '粘贴 Cursor 网页会话 Cookie（WorkosCursorSessionToken=…），或官方 API Key（crsr_…）',
    authUrl: 'https://cursor.com/dashboard?tab=usage',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const credential = setting.credential.trim();
    if (credential.length === 0) {
      return UsageSnapshot.failure('未配置凭证');
    }
    if (isAdminKey(credential)) {
      return this.fetchWithAdminKey(credential);
    }
    return this.fetchWithSession(credential);
  }

  // -------------------------------------------------------------------------
  // A. 网页会话
  // -------------------------------------------------------------------------

  private async fetchWithSession(credential: string): Promise<UsageSnapshot> {
    const cookie = cursorCookieHeader(credential);
    const headers: Record<string, string> = {
      'cookie': cookie,
      'accept': 'application/json',
    };

    const summaryResp = await Http.get(`${CURSOR_WEB_BASE}/api/usage-summary`, headers);
    if (summaryResp.code === 401 || summaryResp.code === 403) {
      return UsageSnapshot.failure('凭证无效或已过期');
    }
    if (!summaryResp.ok) {
      return UsageSnapshot.failure(summaryResp.errorText());
    }
    const summary = cursorParseSummary(summaryResp.json());
    if (summary == null) {
      return UsageSnapshot.failure('响应解析失败');
    }

    // 可选项：账号信息 / 旧版请求配额 / Grok Bot 窗口（失败都不影响主数据）
    const meResp = await Http.get(`${CURSOR_WEB_BASE}/api/auth/me`, headers);
    const me = meResp.ok ? asObj(meResp.json()) : null;
    const email = me != null ? (optStr(me, 'email') ?? '') : '';
    const sub = me != null ? (optStr(me, 'sub') ?? '') : '';

    let requestQuota: CursorRequestQuota | null = null;
    if (sub.length > 0) {
      const usageResp = await Http.get(
        `${CURSOR_WEB_BASE}/api/usage?user=${encodeURIComponent(sub)}`, headers);
      if (usageResp.ok) {
        requestQuota = cursorParseRequestQuota(usageResp.json());
      }
    }

    const sandHeaders: Record<string, string> = {
      'cookie': cookie,
      'accept': 'application/json',
      'content-type': 'application/json',
      'origin': CURSOR_WEB_BASE,
      'referer': `${CURSOR_WEB_BASE}/dashboard`,
    };
    const sandResp = await Http.post(
      `${CURSOR_WEB_BASE}/api/dashboard/get-sand-usage-status`, sandHeaders, '{}');
    const grokBot = sandResp.ok ? cursorGrokBotWindow(sandResp.json(), Date.now()) : null;

    const resetsAt = isoMs(summary.billingCycleEnd);
    const snapshot = UsageSnapshot.success(null, null, null);

    if (requestQuota != null) {
      // 旧版按请求数计划：顶部是请求配额，且不展示 Auto/API 拆分与 Grok Bot
      snapshot.primary = makeWindow(requestQuota.usedPercent(), resetsAt, true);
      snapshot.primaryLabel = 'Total';
      snapshot.details = [{
        title: 'Usage',
        rows: [{ label: 'Request quota', value: `${requestQuota.used} / ${requestQuota.limit}` }],
      }];
    } else {
      snapshot.primary = makeWindow(summary.headlinePercent(), resetsAt, true);
      snapshot.primaryLabel = 'Total';
      const auto = cursorIsTeamPlan(summary) ? null : clampPct(summary.autoPercent);
      const api = cursorIsTeamPlan(summary) ? null : clampPct(summary.apiPercent);
      if (auto != null) {
        snapshot.secondary = makeWindow(auto, resetsAt, true);
        snapshot.secondaryLabel = 'Cursor';
      }
      if (api != null) {
        snapshot.tertiary = makeWindow(api, resetsAt, true);
        snapshot.tertiaryLabel = 'Third Party';
      }
      if (grokBot != null) {
        snapshot.extraRateWindows = [grokBot];
      }
      const cost = this.onDemandCost(summary);
      if (cost != null) {
        snapshot.providerCost = cost;
      }
      const plan = this.planSection(summary);
      if (plan != null) {
        snapshot.details = [plan];
      }
    }

    snapshot.identity = {
      accountEmail: email,
      accountOrganization: '',
      loginMethod: cursorPlanName(summary.membershipType),
    };
    return snapshot;
  }

  /** 按量花费快照（对照 toUsageSnapshot 的 providerCost：used / limit / period Monthly） */
  private onDemandCost(s: CursorPlanSummary): ProviderCostSnapshot | null {
    const used = cents(s.onDemandUsedCents);
    const limit = s.onDemandLimitCents == null ? 0 : cents(s.onDemandLimitCents);
    if (!(used > 0 || limit > 0)) {
      return null;
    }
    return {
      remaining: limit > 0 ? Math.max(0, limit - used) : 0,
      used: used,
      currency: 'USD',
      displayText: Format.money(used, 'USD'),
      period: 'Monthly',
      limit: limit,
    };
  }

  /** 计划用量分组（对照 CursorStatusSnapshot 的各字段） */
  private planSection(s: CursorPlanSummary): ProviderDetailSection | null {
    const rows: ProviderDetailRow[] = [];
    const planUsed = cents(s.planUsedCents);
    const planLimit = cents(s.planLimitCents);
    if (planLimit > 0 || planUsed > 0) {
      const row: ProviderDetailRow = {
        label: 'Included usage',
        value: `${Format.money(planUsed, 'USD')} / ${Format.money(planLimit, 'USD')}`,
      };
      if (planLimit > 0) {
        row.progress = { used: planUsed, total: planLimit };
      }
      rows.push(row);
    }
    if (s.overallLimitCents != null && s.overallLimitCents > 0) {
      const used = cents(s.overallUsedCents);
      const limit = cents(s.overallLimitCents);
      rows.push({
        label: 'Personal cap',
        value: `${Format.money(used, 'USD')} / ${Format.money(limit, 'USD')}`,
        progress: { used: used, total: limit },
      });
    }
    if (s.pooledLimitCents != null && s.pooledLimitCents > 0) {
      const used = cents(s.pooledUsedCents);
      const limit = cents(s.pooledLimitCents);
      rows.push({
        label: 'Team pool',
        value: `${Format.money(used, 'USD')} / ${Format.money(limit, 'USD')}`,
        progress: { used: used, total: limit },
      });
    }
    const auto = clampPct(s.autoPercent);
    if (auto != null) {
      rows.push({ label: 'Auto + Composer', value: `${Format.percent(auto)} 已用` });
    }
    const api = clampPct(s.apiPercent);
    if (api != null) {
      rows.push({ label: 'API (named models)', value: `${Format.percent(api)} 已用` });
    }
    if (s.onDemandUsedCents > 0 || (s.onDemandLimitCents ?? 0) > 0) {
      const used = cents(s.onDemandUsedCents);
      const limit = s.onDemandLimitCents == null ? 0 : cents(s.onDemandLimitCents);
      rows.push({
        label: 'On-demand',
        value: limit > 0
          ? `${Format.money(used, 'USD')} / ${Format.money(limit, 'USD')}`
          : Format.money(used, 'USD'),
      });
    }
    if (s.billingCycleEnd != null && s.billingCycleEnd.length > 0) {
      rows.push({ label: 'Cycle resets', value: s.billingCycleEnd });
    }
    if (rows.length === 0) {
      return null;
    }
    return { title: 'Plan', rows: rows };
  }

  // -------------------------------------------------------------------------
  // B. 官方 Admin API Key
  // -------------------------------------------------------------------------

  private static basicAuth(key: string): string {
    const encoder = new util.TextEncoder();
    const bytes = encoder.encodeInto(`${key}:`);
    return `Basic ${new util.Base64Helper().encodeToStringSync(bytes)}`;
  }

  private async fetchWithAdminKey(key: string): Promise<UsageSnapshot> {
    const headers: Record<string, string> = {
      'authorization': CursorProvider.basicAuth(key),
      'accept': 'application/json',
      'content-type': 'application/json',
    };

    // 1) 团队目录：既是密钥校验，也是成员数/身份来源
    const membersResp = await Http.get(`${CURSOR_API_BASE}/teams/members`, headers);
    if (membersResp.code === 401) {
      return UsageSnapshot.failure('API Key 无效');
    }
    if (membersResp.code === 403) {
      return UsageSnapshot.failure('API Key 权限不足（Admin API 需要团队管理权限）');
    }
    if (!membersResp.ok) {
      return UsageSnapshot.failure(membersResp.errorText());
    }
    const membersRoot = asObj(membersResp.json());
    const memberRows = membersRoot != null ? asArray(membersRoot['teamMembers']) : null;
    const memberCount = memberRows == null ? 0 : memberRows.length;

    // 2) 团队花费 / 预算
    const spendResp = await Http.post(
      `${CURSOR_API_BASE}/teams/spend`, headers, JSON.stringify({ page: 1, pageSize: 100 }));
    const spendMembers = spendResp.ok ? cursorParseMembers(spendResp.json()) : [];

    // 3) 近 30 天每日请求量（对照 Cursor 用量图表）
    const endMs = Date.now();
    const startMs = endMs - 29 * 86400000;
    const dailyResp = await Http.post(
      `${CURSOR_API_BASE}/teams/daily-usage-data`, headers,
      JSON.stringify({ startDate: startMs, endDate: endMs, page: 1, pageSize: 100 }));
    const daily = dailyResp.ok ? cursorParseDailyUsage(dailyResp.json()) : [];

    if (spendMembers.length === 0 && daily.length === 0) {
      return UsageSnapshot.failure(spendResp.ok ? '响应解析失败' : spendResp.errorText());
    }

    let spendCents = 0;
    let budgetDollars = 0;
    for (let i = 0; i < spendMembers.length; i++) {
      spendCents += spendMembers[i].overallSpendCents;
      // 明确为 0 的硬上限不回落（对照 CursorTeamSpend.Member.budget）
      const limit = spendMembers[i].effectivePerUserLimitDollars ?? spendMembers[i].monthlyLimitDollars;
      if (limit != null && limit > 0) {
        budgetDollars += limit;
      }
    }

    const snapshot = UsageSnapshot.success(null, null, null);
    if (budgetDollars > 0) {
      snapshot.primary = makeWindow(Math.min(100, (cents(spendCents) / budgetDollars) * 100), 0, true);
      // 团队预算也走主泳道（对照 CursorStatusProbe+UsageSummary：teamBudget 喂给 planPercentUsed），
      // 标签跟元数据表一致用 Total，预算金额在明细行里（Monthly budget）。
      snapshot.primaryLabel = 'Total';
    }

    const rows: ProviderDetailRow[] = [
      { label: 'Members', value: `${memberCount}` },
      { label: 'Month spend', value: Format.money(cents(spendCents), 'USD') },
    ];
    if (budgetDollars > 0) {
      rows.push({ label: 'Monthly budget', value: Format.money(budgetDollars, 'USD') });
    }
    snapshot.details = [{ title: 'Team', rows: rows }];

    if (daily.length > 0) {
      let includedReqs = 0;
      let usageBasedReqs = 0;
      let apiKeyReqs = 0;
      const points: ProviderChartPoint[] = [];
      for (let i = 0; i < daily.length; i++) {
        includedReqs += daily[i].includedReqs;
        usageBasedReqs += daily[i].usageBasedReqs;
        apiKeyReqs += daily[i].apiKeyReqs;
        points.push({ label: daily[i].date, value: daily[i].total() });
      }
      const usageRows: ProviderDetailRow[] = [
        { label: 'Requests', value: `${includedReqs + usageBasedReqs + apiKeyReqs}` },
        { label: 'Included', value: `${includedReqs}` },
        { label: 'Usage-based', value: `${usageBasedReqs}` },
        { label: 'API key', value: `${apiKeyReqs}` },
      ];
      snapshot.details.push({
        title: 'Daily usage (30 days)',
        rows: usageRows,
        chart: makeChart('Requests', '', points),
      });
    }

    snapshot.identity = {
      accountEmail: '',
      accountOrganization: 'Cursor Team',
      loginMethod: 'Admin API Key',
    };
    return snapshot;
  }
}

export function createCursorProvider(): UsageProvider {
  return new CursorProvider();
}
