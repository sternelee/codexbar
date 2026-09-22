/**
 * 服务商第三批（对照 macOS 版逐家迁移）：
 * - MiniMax:  GET {api.minimaxi.com|api.minimax.io}/v1/token_plan/remains（Bearer，降级 coding_plan/remains）
 * - MiMo 小米: GET platform.xiaomimimo.com/api/v1/{balance,tokenPlan/detail,tokenPlan/usage}（Cookie）
 * - Mistral:  GET admin.mistral.ai/api/billing/credits（Cookie）
 * - Kilo Code: GET api.kilo.ai tRPC 批量（Bearer + 可选组织头）
 * - Poe:      GET api.poe.com/usage/current_balance（Bearer）
 * - T3Chat:   GET t3.chat/api/trpc/getCustomerData（Cookie，JSONL 递归查找）
 * - z.ai/GLM: GET {api.z.ai|open.bigmodel.cn}/api/monitor/usage/quota/limit（Bearer）
 */

import { Http } from '../net/Http';
import { asArray, asObj, bool, Json, num, optNum, optStr, str } from '../net/Json';
import {
  AuthKind,
  makeWindow,
  NamedRateWindow,
  ProviderChartPoint,
  ProviderCostSnapshot,
  ProviderDescriptor,
  ProviderDetailRow,
  ProviderDetailSection,
  makeChart,
  ProviderSetting,
  RateWindow,
  UsageSnapshot
} from '../model/Models';
import { UsageProvider } from './ProviderBase';
import { Format } from '../common/Format';

function isoToMs2(iso: string | null): number {
  if (iso == null || iso.length === 0) {
    return 0;
  }
  const parsed = Date.parse(iso);
  return isNaN(parsed) ? 0 : parsed;
}

function firstOf2(o: Record<string, Json>, keys: string[]): Json {
  for (let i = 0; i < keys.length; i++) {
    const v = o[keys[i]];
    if (v != null) {
      return v;
    }
  }
  return null;
}

function firstNum2(o: Record<string, Json>, keys: string[]): number | null {
  const v = firstOf2(o, keys);
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

function firstStr2(o: Record<string, Json>, keys: string[]): string | null {
  const v = firstOf2(o, keys);
  if (typeof v === 'string') {
    return v as string;
  }
  return null;
}

// ---------------------------------------------------------------------------
// MiniMax
// ---------------------------------------------------------------------------

/** 账单分页参数（对照 billingHistoryLimit = 100；上限防御分页失控） */
const MINIMAX_BILLING_LIMIT = 100;
const MINIMAX_BILLING_MAX_PAGES = 12;
/** 与控制台网页一致的 UA（账单接口对 UA 敏感） */
const MINIMAX_WEB_UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) ' +
  'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36';

/** 单条扣费记录（对照 MiniMaxBillingRecord，字段宽容解析为数字） */
export class MiniMaxBillingRecord {
  tokens: number = 0;
  /** 扣费金额（优先 consume_cash_after_voucher），null 表示未报告 */
  cash: number | null = null;
  createdAtMs: number = 0;
  ymd: string = '';
  consumeTime: string = '';
  method: string = '';
  model: string = '';
  /** result 优先，其次 status；空串表示未报告 */
  result: string = '';
}

/** 账单分页响应 */
class MiniMaxBillingPage {
  totalCount: number | null = null;
  records: MiniMaxBillingRecord[] = [];
}

/** 按天/模型/调用方式的汇总桶 */
class MiniMaxBillingBucket {
  tokens: number = 0;
  cash: number = 0;
  hasCash: boolean = false;
}

/** 明细条目（对照 MiniMaxBillingBreakdown） */
class MiniMaxBillingBreakdown {
  name: string = '';
  tokens: number = 0;
}

/** 聚合结果（对照 MiniMaxBillingSummary） */
export class MiniMaxBillingSummary {
  todayTokens: number = 0;
  last30DaysTokens: number = 0;
  todayCash: number | null = null;
  last30DaysCash: number | null = null;
  daily: MiniMaxBillingBreakdown[] = [];
  topMethods: MiniMaxBillingBreakdown[] = [];
  topModels: MiniMaxBillingBreakdown[] = [];
}

/** 金额文案（对照 cashString：固定两位小数，负值归零） */
export function minimaxCash(value: number): string {
  return Math.max(0, value).toFixed(2);
}

/** 数字字段宽容解析：数字或数字字符串，其余为 null */
function mmNum(o: Record<string, Json>, key: string): number | null {
  const n = optNum(o, key);
  if (n != null) {
    return n;
  }
  const s = optStr(o, key);
  if (s != null && s.trim().length > 0) {
    const parsed = parseFloat(s.trim());
    if (!isNaN(parsed)) {
      return parsed;
    }
  }
  return null;
}

/** result/status 任一字段的文本形态（数字/布尔也接受，对照 decodeOptionalScalarString） */
function mmScalarText(o: Record<string, Json>, key: string): string {
  const s = optStr(o, key);
  if (s != null) {
    return s.trim();
  }
  const n = optNum(o, key);
  if (n != null) {
    return `${n}`;
  }
  const v = o[key];
  if (typeof v === 'boolean') {
    return `${v}`;
  }
  return '';
}

/** 本地日键 YYYY-MM-DD（对照 dayString） */
function mmDayKey(ms: number): string {
  const d = new Date(ms);
  const m = d.getMonth() + 1;
  const day = d.getDate();
  return `${d.getFullYear()}-${m < 10 ? '0' : ''}${m}-${day < 10 ? '0' : ''}${day}`;
}

/** 记录时间：created_at（秒/毫秒） > ymd（本地零点） > consume_time（UTC） */
function mmRecordMs(rec: MiniMaxBillingRecord): number {
  if (rec.createdAtMs > 0) {
    return rec.createdAtMs;
  }
  if (rec.ymd.length > 0) {
    const text = rec.ymd.replace(/\//g, '-');
    let y = '';
    let m = '';
    let d = '';
    if (text.indexOf('-') > 0) {
      const parts = text.split('-');
      if (parts.length === 3) {
        y = parts[0];
        m = parts[1];
        d = parts[2];
      }
    } else if (text.length === 8) {
      y = text.substring(0, 4);
      m = text.substring(4, 6);
      d = text.substring(6, 8);
    }
    const parsed = new Date(parseInt(y, 10), parseInt(m, 10) - 1, parseInt(d, 10), 0, 0, 0, 0);
    if (!isNaN(parsed.getTime())) {
      return parsed.getTime();
    }
  }
  if (rec.consumeTime.length > 0) {
    // "yyyy-MM-dd HH:mm:ss" 按 UTC 解释（对照 parseDate 的 UTC 格式化器）
    const iso = rec.consumeTime.trim().replace(' ', 'T');
    const ms = Date.parse(iso.endsWith('Z') || iso.indexOf('+') > 0 ? iso : `${iso}Z`);
    if (!isNaN(ms)) {
      return ms;
    }
  }
  return 0;
}

/** 分页响应 → 记录列表（对照 decodePayload：base_resp.status_code 非 0 视为失败） */
export function minimaxBillingPage(json: Json): MiniMaxBillingPage | null {
  const root = asObj(json);
  if (root == null) {
    return null;
  }
  const baseResp = asObj(root['base_resp']);
  if (baseResp != null) {
    const code = optNum(baseResp, 'status_code');
    if (code != null && code !== 0) {
      return null;
    }
  }
  const raw = asArray(root['charge_records']);
  const page = new MiniMaxBillingPage();
  page.totalCount = optNum(root, 'total_cnt');
  if (raw == null) {
    return page;
  }
  for (let i = 0; i < raw.length; i++) {
    const o = asObj(raw[i]);
    if (o == null) {
      continue;
    }
    const rec = new MiniMaxBillingRecord();
    const consumeToken = mmNum(o, 'consume_token') ?? 0;
    const input = mmNum(o, 'consume_input_token') ?? 0;
    const output = mmNum(o, 'consume_output_token') ?? 0;
    rec.tokens = consumeToken > 0 ? consumeToken : Math.max(0, input + output);
    rec.cash = mmNum(o, 'consume_cash_after_voucher') ?? mmNum(o, 'consume_cash');
    const created = mmNum(o, 'created_at');
    if (created != null) {
      rec.createdAtMs = created > 1000000000000 ? created : created * 1000;
    }
    rec.ymd = optStr(o, 'ymd') ?? '';
    rec.consumeTime = optStr(o, 'consume_time') ?? '';
    rec.method = (optStr(o, 'method') ?? '').trim();
    rec.model = (optStr(o, 'model') ?? '').trim();
    const result = mmScalarText(o, 'result');
    rec.result = result.length > 0 ? result : mmScalarText(o, 'status');
    page.records.push(rec);
  }
  return page;
}

/** 本地零点（startOfDay） */
function mmStartOfDay(ms: number): number {
  const d = new Date(ms);
  return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0, 0).getTime();
}

/** 是否存在早于 30 天窗口的记录（对照 containsRecordBefore30DayWindow） */
export function minimaxHasRecordBeforeWindow(records: MiniMaxBillingRecord[], nowMs: number): boolean {
  const from = mmStartOfDay(nowMs) - 29 * 86400000;
  for (let i = 0; i < records.length; i++) {
    const ms = mmRecordMs(records[i]);
    if (ms > 0 && ms < from) {
      return true;
    }
  }
  return false;
}

/**
 * 账单聚合（对照 MiniMaxBillingHistoryParser.aggregate）：
 * 只统计 SUCCESS（或未报告结果）且在近 30 天内、不早于当前时刻的记录；
 * 按本地日、model、method 三个维度累加；Top model/method 取 token 数前三。
 */
export function minimaxAggregate(records: MiniMaxBillingRecord[], nowMs: number): MiniMaxBillingSummary {
  const from = mmStartOfDay(nowMs) - 29 * 86400000;
  const dayKeys: string[] = [];
  const byDay: Map<string, MiniMaxBillingBucket> = new Map<string, MiniMaxBillingBucket>();
  const byMethod: Map<string, MiniMaxBillingBucket> = new Map<string, MiniMaxBillingBucket>();
  const byModel: Map<string, MiniMaxBillingBucket> = new Map<string, MiniMaxBillingBucket>();
  for (let i = 0; i < records.length; i++) {
    const rec = records[i];
    if (rec.result.length > 0 && rec.result.toUpperCase() !== 'SUCCESS') {
      continue;
    }
    const ms = mmRecordMs(rec);
    if (ms <= 0 || ms < from || ms > nowMs) {
      continue;
    }
    const key = mmDayKey(ms);
    let day = byDay.get(key);
    if (day == null) {
      day = new MiniMaxBillingBucket();
      byDay.set(key, day);
      dayKeys.push(key);
    }
    day.tokens += rec.tokens;
    if (rec.cash != null) {
      day.cash += rec.cash;
      day.hasCash = true;
    }
    mmAddBucket(byMethod, rec.method, rec.tokens, rec.cash);
    mmAddBucket(byModel, rec.model, rec.tokens, rec.cash);
  }

  dayKeys.sort();
  const summary = new MiniMaxBillingSummary();
  for (let i = 0; i < dayKeys.length; i++) {
    const day = byDay.get(dayKeys[i])!;
    summary.daily.push({ name: dayKeys[i], tokens: day.tokens });
    summary.last30DaysTokens += day.tokens;
    if (day.hasCash) {
      summary.last30DaysCash = (summary.last30DaysCash ?? 0) + day.cash;
    }
  }
  const todayBucket = byDay.get(mmDayKey(nowMs));
  if (todayBucket != null) {
    summary.todayTokens = todayBucket.tokens;
    summary.todayCash = todayBucket.hasCash ? todayBucket.cash : null;
  }
  summary.topMethods = mmTopBreakdowns(byMethod);
  summary.topModels = mmTopBreakdowns(byModel);
  return summary;
}

function mmAddBucket(map: Map<string, MiniMaxBillingBucket>, name: string, tokens: number, cash: number | null): void {
  if (name.length === 0) {
    return;
  }
  let bucket = map.get(name);
  if (bucket == null) {
    bucket = new MiniMaxBillingBucket();
    map.set(name, bucket);
  }
  bucket.tokens += tokens;
  if (cash != null) {
    bucket.cash += cash;
    bucket.hasCash = true;
  }
}

/** 按 token 数降序取前三（同数按名称不区分大小写升序） */
function mmTopBreakdowns(map: Map<string, MiniMaxBillingBucket>): MiniMaxBillingBreakdown[] {
  const out: MiniMaxBillingBreakdown[] = [];
  const names = Array.from(map.keys());
  for (let i = 0; i < names.length; i++) {
    out.push({ name: names[i], tokens: map.get(names[i])!.tokens });
  }
  out.sort((a: MiniMaxBillingBreakdown, b: MiniMaxBillingBreakdown): number => {
    if (a.tokens === b.tokens) {
      const an = a.name.toLowerCase();
      const bn = b.name.toLowerCase();
      return an < bn ? -1 : (an > bn ? 1 : 0);
    }
    return b.tokens - a.tokens;
  });
  return out.length > 3 ? out.slice(0, 3) : out;
}

class MiniMaxProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'minimax',
    title: 'MiniMax',
    authKind: AuthKind.API_KEY,
    accentColor: '#F5222D',
    authHint: '粘贴 MiniMax API Token（平台账户 API 密钥）；可选第二栏填平台会话 Cookie 以查看 Billing history',
    authUrl: 'https://platform.minimaxi.com',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const token = setting.credential.trim();
    if (token.length === 0) {
      return UsageSnapshot.failure('未配置 API Token');
    }
    const headers: Record<string, string> = {
      'authorization': `Bearer ${token}`,
      'accept': 'application/json',
      'mm-api-source': 'CodexBar',
    };
    const hosts = ['https://api.minimaxi.com', 'https://api.minimax.io'];
    const paths = ['/v1/token_plan/remains', '/v1/api/openplatform/coding_plan/remains'];
    let root: Record<string, Json> | null = null;
    let lastError = '';
    for (let h = 0; h < hosts.length && root == null; h++) {
      for (let p = 0; p < paths.length; p++) {
        const resp = await Http.get(`${hosts[h]}${paths[p]}`, headers);
        if (resp.ok) {
          const parsed = asObj(resp.json());
          const data = parsed != null ? asObj(parsed['data']) : null;
          root = data ?? parsed;
          if (root != null && (firstNum2(root, ['current_interval_total_count']) != null ||
            firstNum2(root, ['current_weekly_total_count']) != null)) {
            break;
          }
          root = null;
        } else {
          lastError = resp.errorText();
        }
      }
    }
    if (root == null) {
      return UsageSnapshot.failure(lastError.length > 0 ? lastError : '未获取到用量数据');
    }

    const intervalRemaining = firstNum2(root, ['current_interval_remaining_percent']);
    const intervalTotal = firstNum2(root, ['current_interval_total_count']);
    let intervalUsed = 0;
    if (intervalRemaining != null) {
      intervalUsed = 100 - intervalRemaining;
    }
    const weeklyRemaining = firstNum2(root, ['current_weekly_remaining_percent']);
    const weeklyTotal = firstNum2(root, ['current_weekly_total_count']);
    let weeklyUsed = 0;
    if (weeklyRemaining != null) {
      weeklyUsed = 100 - weeklyRemaining;
    }

    const primary = intervalRemaining != null
      ? makeWindow(Math.max(0, Math.min(100, intervalUsed)), isoToMs2(firstStr2(root, ['remains_time'])), true)
      : null;
    const secondary = weeklyRemaining != null
      ? makeWindow(Math.max(0, Math.min(100, weeklyUsed)), isoToMs2(firstStr2(root, ['weekly_end_time'])), true)
      : null;

    const rows: ProviderDetailRow[] = [];
    if (intervalTotal != null) {
      rows.push({ label: '周期总量', value: `${intervalTotal}` });
    }
    if (weeklyTotal != null) {
      rows.push({ label: '每周总量', value: `${weeklyTotal}` });
    }
    const snap = UsageSnapshot.success(primary, secondary, null);
    const sections: ProviderDetailSection[] = [];
    if (rows.length > 0) {
      sections.push({ title: '配额', rows: rows });
    }

    // Billing history（对照 Swift fetchBillingSummary）：需要网页会话 Cookie，尽力而为
    const cookie = setting.credential2.trim();
    if (cookie.length > 0) {
      const summary = await MiniMaxProvider.fetchBillingSummary(cookie);
      if (summary != null) {
        // Billing history 附「Daily tokens」柱状图（对照源工程 billing.daily → chart）
        const points: ProviderChartPoint[] = [];
        for (let i = 0; i < summary.daily.length; i++) {
          points.push({ label: summary.daily[i].name, value: summary.daily[i].tokens });
        }
        const billingSection: ProviderDetailSection = {
          title: 'Billing history',
          rows: MiniMaxProvider.billingRows(summary),
        };
        if (points.length > 0) {
          billingSection.chart = makeChart('Daily tokens', 'tokens', points);
        }
        sections.push(billingSection);
      }
    }
    if (sections.length > 0) {
      snap.details = sections;
    }
    return snap;
  }

  /**
   * 拉取账单记录并聚合（对照 MiniMaxBillingHistoryParser）：
   * 逐页 page=1..、limit=100、aggregate=false，遇到早于 30 天窗口的记录即停。
   */
  private static async fetchBillingSummary(cookie: string): Promise<MiniMaxBillingSummary | null> {
    const hosts = ['https://platform.minimaxi.com', 'https://platform.minimax.io'];
    const headers: Record<string, string> = {
      'cookie': cookie,
      'accept': 'application/json, text/plain, */*',
      'x-requested-with': 'XMLHttpRequest',
      'accept-language': 'en-US,en;q=0.9',
      'user-agent': MINIMAX_WEB_UA,
    };
    const now = Date.now();
    const records: MiniMaxBillingRecord[] = [];
    let totalCount: number | null = null;
    for (let h = 0; h < hosts.length; h++) {
      for (let page = 1; page <= MINIMAX_BILLING_MAX_PAGES; page++) {
        const url = `${hosts[h]}/account/amount?page=${page}&limit=${MINIMAX_BILLING_LIMIT}&aggregate=false`;
        const resp = await Http.get(url, headers);
        if (!resp.ok) {
          break;
        }
        const parsed = minimaxBillingPage(resp.json());
        if (parsed == null) {
          break;
        }
        totalCount = parsed.totalCount ?? totalCount;
        if (parsed.records.length === 0) {
          break;
        }
        for (let i = 0; i < parsed.records.length; i++) {
          records.push(parsed.records[i]);
        }
        if (minimaxHasRecordBeforeWindow(parsed.records, now)) {
          break;
        }
        if (totalCount != null && records.length >= totalCount) {
          break;
        }
      }
      if (records.length > 0) {
        break;
      }
    }
    if (records.length === 0) {
      return null;
    }
    return minimaxAggregate(records, now);
  }

  /** Billing history 明细行（对照 MiniMaxUsageSnapshot.detailSections 的 billing 分支） */
  private static billingRows(b: MiniMaxBillingSummary): ProviderDetailRow[] {
    const rows: ProviderDetailRow[] = [
      { label: 'Today tokens', value: `${b.todayTokens}` },
      { label: '30d tokens', value: `${b.last30DaysTokens}` },
      { label: 'Today cash', value: b.todayCash != null ? minimaxCash(b.todayCash) : '—' },
      { label: 'Models', value: `${b.topModels.length}` },
    ];
    if (b.topModels.length > 0) {
      rows.push({ label: 'Top model', value: b.topModels[0].name });
    }
    if (b.topMethods.length > 0) {
      rows.push({ label: 'Top method', value: b.topMethods[0].name });
    }
    if (b.last30DaysCash != null) {
      rows.push({ label: '30d cash', value: minimaxCash(b.last30DaysCash) });
    }
    return rows;
  }
}

// ---------------------------------------------------------------------------
// MiMo 小米
// ---------------------------------------------------------------------------

class MiMoProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'mimo',
    title: 'MiMo (小米)',
    authKind: AuthKind.SESSION,
    accentColor: '#FF6900',
    authHint: '粘贴 platform.xiaomimimo.com 的会话 Cookie',
    authUrl: 'https://platform.xiaomimimo.com',
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
    const base = 'https://platform.xiaomimimo.com/api/v1';

    const snap = UsageSnapshot.success(null, null, null);
    const balResp = await Http.get(`${base}/balance`, headers);
    if (!balResp.ok) {
      return UsageSnapshot.failure(balResp.errorText());
    }
    const balRoot = asObj(balResp.json());
    const balData = balRoot != null ? asObj(balRoot['data']) : null;
    if (balData == null) {
      return UsageSnapshot.failure('余额响应解析失败');
    }
    const balance = firstNum2(balData, ['balance']) ?? 0;
    const currency = str(balData, 'currency', 'CNY');
    snap.providerCost = {
      remaining: balance, used: 0, currency: currency,
      displayText: Format.money(balance, currency),
    };

    const rows: ProviderDetailRow[] = [];
    const cash = firstNum2(balData, ['cashBalance']);
    const gift = firstNum2(balData, ['giftBalance']);
    // Balance 行（对照 Swift balanceDetail："¥X (Paid: ¥Y / Granted: ¥Z)"）
    let balanceText = Format.money(balance, currency);
    if (cash != null && gift != null) {
      balanceText += ` (Paid: ${Format.money(cash, currency)} / Granted: ${Format.money(gift, currency)})`;
    }
    rows.push({ label: 'Balance', value: balanceText });

    const usageResp = await Http.get(`${base}/tokenPlan/usage`, headers);
    if (usageResp.ok) {
      const uRoot = asObj(usageResp.json());
      const uData = uRoot != null ? asObj(uRoot['data']) : null;
      const month = uData != null ? asObj(uData['monthUsage']) : null;
      const percent = month != null ? firstNum2(month, ['percent']) : null;
      if (percent != null) {
        snap.primary = makeWindow(Math.max(0, Math.min(100, percent)), 0, true);
      }
      const items = month != null ? asArray(month['items']) : null;
      if (items != null) {
        for (let i = 0; i < items.length && i < 4; i++) {
          const it = asObj(items[i]);
          if (it == null) {
            continue;
          }
          rows.push({ label: str(it, 'name', `项目${i + 1}`), value: `${Math.round(num(it, 'used', 0))} / ${Math.round(num(it, 'limit', 0))}` });
        }
      }
    }
    const detailResp = await Http.get(`${base}/tokenPlan/detail`, headers);
    if (detailResp.ok) {
      const dRoot = asObj(detailResp.json());
      const dData = dRoot != null ? asObj(dRoot['data']) : null;
      if (dData != null) {
        const planCode = optStr(dData, 'planCode');
        if (planCode != null && planCode.length > 0) {
          rows.push({ label: '套餐', value: planCode });
        }
      }
    }
    if (rows.length > 0) {
      const section: ProviderDetailSection = { title: 'Credits', rows: rows };
      snap.details = [section];
    }
    return snap;
  }
}

// ---------------------------------------------------------------------------
// Mistral
// ---------------------------------------------------------------------------

class MistralProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'mistral',
    title: 'Mistral',
    authKind: AuthKind.SESSION,
    accentColor: '#FA500F',
    authHint: '粘贴 admin.mistral.ai 的会话 Cookie',
    authUrl: 'https://admin.mistral.ai/organization/billing',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const cookie = setting.credential.trim();
    if (cookie.length === 0) {
      return UsageSnapshot.failure('未配置会话 Cookie');
    }
    const headers: Record<string, string> = {
      'cookie': cookie,
      'accept': '*/*',
      'referer': 'https://admin.mistral.ai/organization/billing',
      'origin': 'https://admin.mistral.ai',
    };
    const resp = await Http.get('https://admin.mistral.ai/api/billing/credits', headers);
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    const root = asObj(resp.json());
    if (root == null) {
      return UsageSnapshot.failure('响应解析失败');
    }
    const wallet = firstNum2(root, ['walletAmount', 'wallet_amount']) ?? 0;
    const notes = firstNum2(root, ['creditNotesAmount', 'credit_notes_amount']) ?? 0;
    const ongoing = firstNum2(root, ['ongoingUsageBalance', 'ongoing_usage_balance']) ?? 0;
    const currency = str(root, 'currency', 'EUR');
    const snap = UsageSnapshot.success(null, null, null);
    snap.providerCost = {
      remaining: wallet, used: 0, currency: currency,
      displayText: Format.money(wallet, currency),
    };
    const rows: ProviderDetailRow[] = [
      { label: '钱包余额', value: Format.money(wallet, currency) },
      { label: '信用额度', value: Format.money(notes, currency) },
      { label: '进行中消费', value: Format.money(ongoing, currency) },
    ];
    const section: ProviderDetailSection = { title: '余额明细', rows: rows };
    snap.details = [section];
    return snap;
  }
}

// ---------------------------------------------------------------------------
// Kilo Code
// ---------------------------------------------------------------------------

class KiloProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'kilo',
    title: 'Kilo Code',
    authKind: AuthKind.API_KEY,
    accentColor: '#0D9488',
    authHint: '粘贴 Kilo API Key；可选第二栏填组织 ID',
    authUrl: 'https://app.kilo.ai',
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
    const org = setting.credential2.trim();
    if (org.length > 0) {
      headers['x-kilocode-organizationid'] = org;
    }
    const input = encodeURIComponent('{"0":{"json":null},"1":{"json":null},"2":{"json":null}}');
    const url =
      'https://api.kilo.ai/user.getCreditBlocks,kiloPass.getState,user.getAutoTopUpPaymentMethod' +
      `?batch=1&input=${input}`;
    const resp = await Http.get(url, headers);
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    const entries = asArray(resp.json());
    if (entries == null || entries.length < 2) {
      return UsageSnapshot.failure('响应解析失败');
    }
    // 第 0 项：信用块；第 1 项：Kilo Pass 状态
    const jsonOf = (entry: Json): Record<string, Json> | null => {
      const e = asObj(entry);
      const result = e != null ? asObj(e['result']) : null;
      const data = result != null ? asObj(result['data']) : null;
      return data != null ? asObj(data['json']) : null;
    };

    const snap = UsageSnapshot.success(null, null, null);
    const rows: ProviderDetailRow[] = [];
    const pass = jsonOf(entries[1]);
    if (pass != null) {
      const used = firstNum2(pass, ['used', 'creditsUsed']);
      const total = firstNum2(pass, ['total', 'creditsTotal']);
      const remaining = firstNum2(pass, ['remaining', 'creditsRemaining', 'available']);
      if (used != null && total != null && total > 0) {
        snap.primary = makeWindow(Math.min(100, (used / total) * 100), 0, true);
      }
      if (total != null) {
        rows.push({ label: '总额度', value: `${Math.round(total)}` });
      }
      if (used != null) {
        rows.push({ label: '已使用', value: `${Math.round(used)}` });
      }
      if (remaining != null) {
        rows.push({ label: '剩余', value: `${Math.round(remaining)}` });
      }
    }
    const blocksJson = jsonOf(entries[0]);
    const blocks = blocksJson != null ? asArray(blocksJson['blocks']) : null;
    if (blocks != null) {
      for (let i = 0; i < blocks.length && i < 4; i++) {
        const b = asObj(blocks[i]);
        if (b == null) {
          continue;
        }
        const amount = firstNum2(b, ['amount', 'total']);
        const available = firstNum2(b, ['available', 'remaining']);
        if (amount != null) {
          const line = available != null ? `${Math.round(available)} / ${Math.round(amount)}` : `${Math.round(amount)}`;
          rows.push({ label: `信用块 #${i + 1}`, value: line });
        }
      }
    }
    if (snap.primary == null && rows.length === 0) {
      return UsageSnapshot.failure('未识别到额度数据');
    }
    if (rows.length > 0) {
      const section: ProviderDetailSection = { title: '额度明细', rows: rows };
      snap.details = [section];
    }
    return snap;
  }
}

// ---------------------------------------------------------------------------
// Poe
// ---------------------------------------------------------------------------

class PoeProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'poe',
    title: 'Poe',
    authKind: AuthKind.API_KEY,
    accentColor: '#5D5CDE',
    authHint: '粘贴 Poe API Key（poe.com/api/keys 页面创建）',
    authUrl: 'https://poe.com/api/keys',
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
    const resp = await Http.get('https://api.poe.com/usage/current_balance', headers);
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    const root = asObj(resp.json());
    if (root == null) {
      return UsageSnapshot.failure('响应解析失败');
    }
    const balance = firstNum2(root, ['current_point_balance']) ?? 0;
    const compact = (value: number): string => value >= 1000
      ? `${Math.round(value)}`
      : `${Math.round(value * 10) / 10}`;
    const snap = UsageSnapshot.success(null, null, null);
    snap.providerCost = {
      remaining: balance, used: 0, currency: 'POINTS',
      displayText: `${compact(balance)} points`,
    };
    snap.identity = {
      accountEmail: '', accountOrganization: '',
      loginMethod: `Balance: ${compact(balance)} points`,
    };

    // Points 分组（对照插件：余额 + 近 7/30 天汇总 + Top model + 使用构成 + 最近记录）
    const rows: ProviderDetailRow[] = [];
    rows.push({ label: 'Current balance', value: `${compact(balance)} points` });
    const entries = await this.pointsHistory(headers);
    if (entries.length > 0) {
      const nowMs = Date.now();
      const inWindow = (days: number): PoeEntry[] => entries.filter(
        (e: PoeEntry) => e.dateMs >= nowMs - days * 86400000);
      const today = this.summarize(entries.filter((e: PoeEntry) => {
        const d = new Date(e.dateMs);
        const n = new Date(nowMs);
        return d.getUTCFullYear() === n.getUTCFullYear() && d.getUTCMonth() === n.getUTCMonth() &&
          d.getUTCDate() === n.getUTCDate();
      }));
      rows.push(this.summaryRow('Today', today));
      rows.push(this.summaryRow('Last 7 days', this.summarize(inWindow(7))));
      rows.push(this.summaryRow('Last 30 days', this.summarize(entries)));
      const models: Map<string, number> = new Map<string, number>();
      const types: Map<string, number> = new Map<string, number>();
      for (let i = 0; i < entries.length; i++) {
        models.set(entries[i].model, (models.get(entries[i].model) ?? 0) + entries[i].points);
        types.set(entries[i].usageType, (types.get(entries[i].usageType) ?? 0) + entries[i].points);
      }
      const modelNames = Array.from(models.keys());
      if (modelNames.length > 0) {
        let top = modelNames[0];
        for (let i = 1; i < modelNames.length; i++) {
          const a = models.get(modelNames[i]) ?? 0;
          const b = models.get(top) ?? 0;
          if (a > b || (a === b && modelNames[i] < top)) {
            top = modelNames[i];
          }
        }
        rows.push({ label: 'Top model', value: top, secondary: `${compact(models.get(top) ?? 0)} points` });
      }
      const typeNames = Array.from(types.keys()).sort((a: string, b: string): number => {
        const av = types.get(a) ?? 0;
        const bv = types.get(b) ?? 0;
        if (av === bv) {
          return a < b ? -1 : (a > b ? 1 : 0);
        }
        return bv - av;
      });
      if (typeNames.length > 0) {
        const mix: string[] = [];
        const limit = typeNames.length > 2 ? 2 : typeNames.length;
        for (let i = 0; i < limit; i++) {
          mix.push(`${typeNames[i]}: ${compact(types.get(typeNames[i]) ?? 0)} points`);
        }
        rows.push({ label: 'Usage mix', value: mix.join(' · ') });
      }
    }
    snap.details = [{ title: 'Points', rows: rows }];
    return snap;
  }

  /** 近 30 天积分明细（最多 5 页，对照插件分页与截止时间） */
  private async pointsHistory(headers: Record<string, string>): Promise<PoeEntry[]> {
    const cutoff = Date.now() - 30 * 86400000;
    const out: PoeEntry[] = [];
    let cursor = '';
    for (let page = 0; page < 5; page++) {
      const query = cursor.length > 0
        ? `?limit=100&starting_after=${encodeURIComponent(cursor)}`
        : '?limit=100';
      const resp = await Http.get(`https://api.poe.com/usage/points_history${query}`, headers);
      if (!resp.ok) {
        break;
      }
      const root = asObj(resp.json());
      if (root == null) {
        break;
      }
      const list = asArray(root['data']) ?? asArray(root['items']) ?? asArray(root['results']);
      if (list == null || list.length === 0) {
        break;
      }
      let lastMs = 0;
      let lastQueryId = '';
      for (let i = 0; i < list.length; i++) {
        const row = asObj(list[i]);
        if (row == null) {
          continue;
        }
        const ts = firstOf2(row, ['creation_time', 'timestamp', 'created_at']);
        const dateMs = PoeProvider.entryMs(ts);
        if (dateMs > 0) {
          lastMs = dateMs;
        }
        if (dateMs === 0 || dateMs < cutoff) {
          continue;
        }
        const points = Math.max(0, firstNum2(row, ['cost_points', 'points', 'point_cost']) ?? 0);
        const model = firstStr2(row, ['bot_name']) ?? 'unknown';
        const usageType = firstStr2(row, ['usage_type']) ?? 'unknown';
        out.push({ dateMs: dateMs, points: points, model: model, usageType: usageType });
        lastQueryId = firstStr2(row, ['query_id']) ?? '';
      }
      const next = firstStr2(root, ['next_cursor']);
      if (next != null && next.length > 0) {
        cursor = next;
      } else if (root['has_more'] === true && lastQueryId.length > 0) {
        cursor = lastQueryId;
      } else {
        break;
      }
      if (lastMs > 0 && lastMs < cutoff) {
        break;
      }
    }
    return out;
  }

  /** 时间戳兼容秒/毫秒/字符串三种形态 */
  private static entryMs(value: Json): number {
    if (typeof value === 'number') {
      const n = value as number;
      return n > 100000000000000 ? n / 1000 : (n > 1000000000000 ? n : n * 1000);
    }
    if (typeof value === 'string' && (value as string).trim().length > 0) {
      const parsed = Date.parse(value as string);
      return isNaN(parsed) ? 0 : parsed;
    }
    return 0;
  }

  private summarize(entries: PoeEntry[]): PoeSummary {
    const s = new PoeSummary();
    s.requests = entries.length;
    for (let i = 0; i < entries.length; i++) {
      s.points += entries[i].points;
    }
    return s;
  }

  private summaryRow(label: string, summary: PoeSummary): ProviderDetailRow {
    return {
      label: label,
      value: `${(summary.points >= 1000 ? `${Math.round(summary.points)}` : `${Math.round(summary.points * 10) / 10}`)} points`,
      secondary: `${summary.requests} requests`,
    };
  }
}

/** Poe 积分明细条目 */
interface PoeEntry {
  dateMs: number;
  points: number;
  model: string;
  usageType: string;
}

/** Poe 汇总 */
class PoeSummary {
  points: number = 0;
  requests: number = 0;
}

// ---------------------------------------------------------------------------
// T3Chat
// ---------------------------------------------------------------------------

/** JSONL 中递归查找含用量字段的客户数据对象（对照 t3chat.js 的 find 函数） */
export function t3chatFindCustomerData(value: Json): Record<string, Json> | null {
  if (value == null || !(value instanceof Object)) {
    return null;
  }
  const o = asObj(value);
  if (o == null) {
    return null;
  }
  if (o['usageFourHourPercentage'] != null || o['usageMonthPercentage'] != null ||
    (o['subscription'] != null && o['usageBand'] != null)) {
    return o;
  }
  const keys = Object.keys(o);
  for (let i = 0; i < keys.length; i++) {
    const child = o[keys[i]];
    if (child instanceof Object) {
      const found = t3chatFindCustomerData(child);
      if (found != null) {
        return found;
      }
    }
  }
  return null;
}

class T3ChatProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 't3chat',
    title: 'T3 Chat',
    authKind: AuthKind.SESSION,
    accentColor: '#F56647',
    authHint: '粘贴 t3.chat 的会话 Cookie',
    authUrl: 'https://t3.chat',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const cookie = setting.credential.trim();
    if (cookie.length === 0) {
      return UsageSnapshot.failure('未配置会话 Cookie');
    }
    const input = encodeURIComponent('{"0":{"json":{"sessionId":null},"meta":{"values":{"sessionId":["undefined"]}}}}');
    const headers: Record<string, string> = {
      'cookie': cookie,
      'accept': '*/*',
      'referer': 'https://t3.chat/settings/customization',
      'trpc-accept': 'application/jsonl',
      'x-trpc-source': 'web-client',
      'x-trpc-batch': 'true',
    };
    const resp = await Http.get(`https://t3.chat/api/trpc/getCustomerData?batch=1&input=${input}`, headers);
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    let data: Record<string, Json> | null = null;
    const lines = resp.body.split('\n');
    for (let i = 0; i < lines.length && data == null; i++) {
      const line = lines[i].trim();
      if (line.length === 0) {
        continue;
      }
      const parsed = asObj(Json_parse(line));
      if (parsed != null) {
        data = t3chatFindCustomerData(parsed);
      }
    }
    if (data == null) {
      return UsageSnapshot.failure('响应中缺少客户数据');
    }

    const pct = (v: Json): number => {
      const n = typeof v === 'number' ? v as number : 0;
      return Math.max(0, Math.min(100, n));
    };
    const toMs = (v: Json): number => {
      const n = typeof v === 'number' ? v as number : 0;
      if (n <= 0) {
        return 0;
      }
      return n > 10000000000 ? n : n * 1000;
    };

    const fourHour = data['usageFourHourPercentage'];
    const month = data['usageMonthPercentage'] ?? data['usagePeriodPercentage'];
    const primary = fourHour != null
      ? makeWindow(pct(fourHour), toMs(data['usageFourHourNextResetAt'] ?? data['usageWindowNextResetAt']), true)
      : null;
    const secondary = month != null
      ? makeWindow(pct(month), toMs(data['billingNextResetAt']), true)
      : null;

    const snap = UsageSnapshot.success(primary, secondary, null);
    const rows: ProviderDetailRow[] = [];
    const sub = asObj(data['subscription']);
    const rawPlan = (sub != null ? optStr(sub, 'productName') : null) ?? optStr(data, 'subTier');
    if (rawPlan != null && rawPlan.length > 0) {
      rows.push({ label: '套餐', value: rawPlan });
    }
    const lifetime = optNum(data, 'lifetimeBalance');
    if (lifetime != null) {
      rows.push({ label: '历史消息余额', value: `${lifetime}` });
    }
    const band = optStr(data, 'usageBand');
    if (band != null && band.length > 0) {
      rows.push({ label: '用量档位', value: band });
    }
    if (rows.length > 0) {
      const section: ProviderDetailSection = { title: '订阅', rows: rows };
      snap.details = [section];
    }
    return snap;
  }
}

function Json_parse(text: string): Json {
  try {
    return JSON.parse(text) as Json;
  } catch (e) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// z.ai / GLM 智谱
// ---------------------------------------------------------------------------

/** 单位代码 → 分钟（对照 zai.js multipliers：1=天 3=小时 5=分钟 6=周） */
function zaiWindowMinutes(unit: number, number: number): number {
  const multipliers: Record<number, number> = { 1: 1440, 3: 60, 5: 1, 6: 10080 };
  const m = multipliers[unit];
  return m != null && number > 0 ? number * m : 0;
}

/** 单条 limit 的归一化指标（对照 zai.js parseLimit） */
class ZaiLimitFacts {
  type: string = '';
  percent: number = 0;
  usage: number | null = null;
  remaining: number | null = null;
  windowMinutes: number = 0;
}

function zaiLimitFacts(limit: Record<string, Json>): ZaiLimitFacts | null {
  const type = str(limit, 'type');
  if (type !== 'TOKENS_LIMIT' && type !== 'TIME_LIMIT' && type !== 'CREDIT_LIMIT') {
    return null;
  }
  const facts = new ZaiLimitFacts();
  facts.type = type;
  facts.percent = num(limit, 'percentage', 0);
  facts.usage = optNum(limit, 'usage');
  facts.remaining = optNum(limit, 'remaining');
  const current = optNum(limit, 'currentValue');
  if (facts.usage != null && facts.usage > 0) {
    let used = 0;
    if (facts.remaining != null) {
      used = Math.max(facts.usage - facts.remaining, current == null ? facts.usage - facts.remaining : current);
    } else if (current != null) {
      used = current;
    }
    facts.percent = Math.max(0, Math.min(100, (Math.max(0, Math.min(facts.usage, used)) / facts.usage) * 100));
  }
  facts.percent = Math.max(0, Math.min(100, facts.percent));
  facts.windowMinutes = zaiWindowMinutes(num(limit, 'unit', 0), num(limit, 'number', 0));
  return facts;
}

/** 明细行文案（对照 zai.js limitRow）："65% used" + "300 limit · 105 remaining" */
function zaiLimitRow(label: string, facts: ZaiLimitFacts): ProviderDetailRow {
  const parts: string[] = [];
  if (facts.usage != null) {
    parts.push(`${facts.usage} limit`);
  }
  if (facts.remaining != null) {
    parts.push(`${facts.remaining} remaining`);
  }
  const pct = facts.percent % 1 === 0 ? facts.percent.toFixed(0) : facts.percent.toFixed(1);
  return { label: label, value: `${pct}% used`, secondary: parts.length > 0 ? parts.join(' · ') : undefined };
}

/** 时段费率行（对照 zai.js quotaRateRow：高峰为 UTC 周一至周五 06:00-10:00） */
function zaiQuotaRateRow(nowMs: number): ProviderDetailRow {
  const now = new Date(nowMs);
  const day = now.getUTCDay();
  const hour = now.getUTCHours();
  const isPeak = day >= 1 && day <= 5 && hour >= 6 && hour < 10;
  let boundary = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate(), isPeak ? 10 : 6);
  if (!isPeak) {
    if (hour >= 6) {
      boundary += 86400000;
    }
    let bd = new Date(boundary);
    while (bd.getUTCDay() === 0 || bd.getUTCDay() === 6) {
      boundary += 86400000;
      bd = new Date(boundary);
    }
  }
  const secs = Math.max(0, Math.floor((boundary - nowMs) / 1000));
  const totalMinutes = Math.max(1, Math.ceil(secs / 60));
  const days = Math.floor(totalMinutes / 1440);
  const hours = Math.floor(totalMinutes / 60) % 24;
  const minutes = totalMinutes % 60;
  let countdown = `in ${totalMinutes}m`;
  if (days > 0) {
    countdown = hours > 0 ? `in ${days}d ${hours}h` : (minutes > 0 ? `in ${days}d ${minutes}m` : `in ${days}d`);
  } else if (hours > 0) {
    countdown = minutes > 0 ? `in ${hours}h ${minutes}m` : `in ${hours}h`;
  }
  return {
    label: 'Quota rate',
    value: isPeak ? 'Peak' : 'Off-peak',
    secondary: `${isPeak ? 'off-peak' : 'peak'} ${countdown}`,
  };
}

export function zaiLimitWindow(limit: Record<string, Json>): NamedRateWindow | null {
  const type = str(limit, 'type');
  if (type !== 'TOKENS_LIMIT' && type !== 'TIME_LIMIT' && type !== 'CREDIT_LIMIT') {
    return null;
  }
  const unit = num(limit, 'unit', 0);
  const number = num(limit, 'number', 0);
  let percent = num(limit, 'percentage', 0);
  const usage = optNum(limit, 'usage');
  const remaining = optNum(limit, 'remaining');
  const current = optNum(limit, 'currentValue');
  if (usage != null && usage > 0) {
    let used = 0;
    if (remaining != null) {
      used = Math.max(usage - remaining, current == null ? usage - remaining : current);
    } else if (current != null) {
      used = current;
    }
    percent = Math.max(0, Math.min(100, (used / usage) * 100));
  }
  percent = Math.max(0, Math.min(100, percent));
  const windowMinutes = zaiWindowMinutes(unit, number);
  const resetSec = optNum(limit, 'nextResetTime');
  const resets = resetSec != null && resetSec > 0 ? resetSec * 1000 : 0;

  let title: string;
  if (type === 'TIME_LIMIT') {
    const unitNames: Record<number, string> = { 1: '天', 3: '小时', 5: '分钟', 6: '周' };
    const name = unitNames[unit];
    title = number === 5 && unit === 5 ? '5 小时窗口' : name != null ? `${number} ${name}窗口` : '时间窗口';
  } else if (type === 'TOKENS_LIMIT') {
    title = 'Token 配额';
  } else {
    title = 'Credit 配额';
  }
  const rows: ProviderDetailRow[] = [];
  if (usage != null) {
    rows.push({ label: '限额', value: `${usage}` });
  }
  if (remaining != null) {
    rows.push({ label: '剩余', value: `${remaining}` });
  }
  const w = makeWindow(percent, resets, true);
  return { id: `zai_${type}_${unit}_${number}`, title: title, window: w };
}

class ZaiProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'zai',
    title: 'z.ai / GLM 智谱',
    authKind: AuthKind.API_KEY,
    accentColor: '#3859FF',
    authHint: '粘贴 z.ai 或 BigModel/GLM 的 API Key',
    authUrl: 'https://z.ai',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const key = setting.credential.trim();
    if (key.length === 0) {
      return UsageSnapshot.failure('未配置 API Key');
    }
    // 优先国际站 api.z.ai，401/403/404 时回退开放平台
    const hosts = ['https://api.z.ai', 'https://open.bigmodel.cn'];
    const headers: Record<string, string> = {
      'authorization': `Bearer ${key}`,
      'accept': 'application/json',
    };
    let root: Record<string, Json> | null = null;
    let lastError = '';
    for (let i = 0; i < hosts.length && root == null; i++) {
      const resp = await Http.get(`${hosts[i]}/api/monitor/usage/quota/limit`, headers);
      if (resp.ok) {
        const parsed = asObj(resp.json());
        if (parsed != null && bool(parsed, 'success') && num(parsed, 'code', 0) === 200) {
          const data = asObj(parsed['data']);
          const limits = data != null ? asArray(data['limits']) : null;
          if (limits != null) {
            root = parsed;
            break;
          }
        }
        lastError = '响应格式不符';
      } else {
        lastError = resp.errorText();
      }
    }
    if (root == null) {
      return UsageSnapshot.failure(lastError);
    }
    const data = asObj(root['data'])!;
    const limits = asArray(data['limits'])!;

    const windows: NamedRateWindow[] = [];
    for (let i = 0; i < limits.length && windows.length < 6; i++) {
      const l = asObj(limits[i]);
      if (l == null) {
        continue;
      }
      const w = zaiLimitWindow(l);
      if (w != null) {
        windows.push(w);
      }
    }
    // 主窗口：优先 5 小时（300 分钟）窗口
    let primary: RateWindow | null = null;
    let secondary: RateWindow | null = null;
    for (let i = 0; i < windows.length; i++) {
      const title = windows[i].title;
      if (primary == null && title === '5 小时窗口') {
        primary = windows[i].window;
        continue;
      }
      if (secondary == null && title.indexOf('周') >= 0) {
        secondary = windows[i].window;
      }
    }
    if (primary == null && windows.length > 0) {
      primary = windows[0].window;
    }
    const extras: NamedRateWindow[] = windows.filter(w => w.window !== primary && w.window !== secondary);

    const snap = UsageSnapshot.success(primary, secondary, null);
    snap.extraRateWindows = extras.slice(0, 4);
    snap.identity = { accountEmail: '', accountOrganization: '', loginMethod: 'API Key' };

    // Quota details 分组（对照 zai.js：token 配额 / 会话配额 / 时段费率 / MCP 配额）
    const detailRows: ProviderDetailRow[] = [];
    const tokenLimits: ZaiLimitFacts[] = [];
    const timeLimits: ZaiLimitFacts[] = [];
    for (let i = 0; i < limits.length; i++) {
      const l = asObj(limits[i]);
      if (l == null) {
        continue;
      }
      const facts = zaiLimitFacts(l);
      if (facts == null) {
        continue;
      }
      if (facts.type === 'TIME_LIMIT') {
        timeLimits.push(facts);
      } else {
        tokenLimits.push(facts);
      }
    }
    tokenLimits.sort((a: ZaiLimitFacts, b: ZaiLimitFacts): number => {
      const aw = a.windowMinutes > 0 ? a.windowMinutes : 999999;
      const bw = b.windowMinutes > 0 ? b.windowMinutes : 999999;
      return aw - bw;
    });
    const tokenLimit = tokenLimits.length > 0 ? tokenLimits[tokenLimits.length - 1] : null;
    const primaryLimit = tokenLimits.length > 0 ? tokenLimits[0] : (timeLimits.length > 0 ? timeLimits[timeLimits.length - 1] : null);
    const timeLimit = timeLimits.length > 0 ? timeLimits[timeLimits.length - 1] : null;
    if (tokenLimit != null) {
      detailRows.push(zaiLimitRow(tokenLimit.type === 'CREDIT_LIMIT' ? 'Credit quota' : 'Token quota', tokenLimit));
    }
    if (tokenLimits.length >= 2 && primaryLimit != null) {
      detailRows.push(zaiLimitRow(
        primaryLimit.type === 'CREDIT_LIMIT' ? 'Session credit quota' : 'Session token quota', primaryLimit));
    }
    const hasCreditLimit = [tokenLimit, primaryLimit].some(
      (item: ZaiLimitFacts | null) => item != null && item.type === 'CREDIT_LIMIT');
    if (hasCreditLimit) {
      detailRows.push(zaiQuotaRateRow(Date.now()));
    }
    if (timeLimit != null) {
      detailRows.push(zaiLimitRow('MCP quota', timeLimit));
    }
    if (detailRows.length > 0) {
      snap.details = [{ title: 'Quota details', rows: detailRows }];
    }
    return snap;
  }
}

export function createMiniMaxProvider(): UsageProvider {
  return new MiniMaxProvider();
}

export function createMiMoProvider(): UsageProvider {
  return new MiMoProvider();
}

export function createMistralProvider(): UsageProvider {
  return new MistralProvider();
}

export function createKiloProvider(): UsageProvider {
  return new KiloProvider();
}

export function createPoeProvider(): UsageProvider {
  return new PoeProvider();
}

export function createT3ChatProvider(): UsageProvider {
  return new T3ChatProvider();
}

export function createZaiProvider(): UsageProvider {
  return new ZaiProvider();
}
