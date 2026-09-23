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
import { asArray, asObj, Json, num, optNum, optStr, str } from '../net/Json';
import {
  AuthKind,
  makeWindow,
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
// DeepSeek 平台（by_api_key 仪表盘序列）
// ---------------------------------------------------------------------------

/** 用量类别（对照 DeepSeekUsageCategory） */
const DS_CACHE_HIT = 'PROMPT_CACHE_HIT_TOKEN';
const DS_CACHE_MISS = 'PROMPT_CACHE_MISS_TOKEN';
const DS_RESPONSE = 'RESPONSE_TOKEN';
const DS_REQUEST = 'REQUEST';

/** 单日用量 */
export class DeepSeekDailyRow {
  date: string = '';
  tokens: number = 0;
  cost: number | null = null;
  requests: number = 0;
}

/** 平台用量汇总（对照 DeepSeekUsageSummary） */
export class DeepSeekPlatformUsage {
  todayTokens: number = 0;
  periodTokens: number = 0;
  todayCost: number | null = null;
  /** 周期花费：by-key 路径是每日求和（永远有值，无数据时 0），月度回退路径可能为 null（显示 —） */
  periodCost: number | null = null;
  todayRequests: number = 0;
  periodRequests: number = 0;
  topModel: string = '';
  apiKeyCount: number = 0;
  currency: string = 'CNY';
  /** 统计周期（对照 DeepSeekUsagePeriod）：last30Days（by-key）或 currentMonth（月度回退） */
  period: string = 'last30Days';
  /** 近 30 天的每日序列（升序） */
  daily: DeepSeekDailyRow[] = [];
  /** 各模型花费（花费降序） */
  modelCosts: DeepSeekModelCostRow[] = [];
}

/** 单模型花费行 */
export class DeepSeekModelCostRow {
  model: string = '';
  cost: number = 0;
}

/** 数值文本：字符串/数字 → 去空白文本（其他类型记空串） */
function dsNumberText(value: Json): string {
  if (typeof value === 'number') {
    return `${value as number}`;
  }
  if (typeof value === 'string') {
    return (value as string).trim();
  }
  return '';
}

/**
 * 标量解析（对照 ByAPIKeyScalar + Double(text)）：必须是完整数字，
 * "0.25" ✓；"0.25abc" / 空串 / 非标量 → 0。
 */
function dsScalar(value: Json): number {
  const text = dsNumberText(value);
  if (text.length === 0 || !/^[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?$/.test(text)) {
    return 0;
  }
  const parsed = parseFloat(text);
  return isNaN(parsed) || !isFinite(parsed) ? 0 : parsed;
}

/** token 数量（对照 parseTokenAmount：Int64(text) 失败记 0，所以 "1.5" 也是 0） */
function dsTokens(value: Json): number {
  const text = dsNumberText(value);
  if (!/^[+-]?\d+$/.test(text)) {
    return 0;
  }
  const parsed = parseInt(text, 10);
  return isNaN(parsed) ? 0 : parsed;
}

/** 业务错误码 / 鉴权错误（对照 isAuthenticationError：40002 / 40003） */
function dsFailure(payload: Record<string, Json> | null): boolean {
  if (payload == null) {
    return true;
  }
  const code = optNum(payload, 'code');
  if (code != null && code !== 0) {
    return true;
  }
  const data = asObj(payload['data']);
  const bizCode = data != null ? optNum(data, 'biz_code') : null;
  return bizCode != null && bizCode !== 0;
}

/** 本地日键（对照 AggregationContext.dayString） */
function dsDayKey(ms: number): string {
  const d = new Date(ms);
  const m = d.getMonth() + 1;
  const day = d.getDate();
  return `${d.getFullYear()}-${m < 10 ? '0' : ''}${m}-${day < 10 ? '0' : ''}${day}`;
}

/** 金额文案（对照 cost 闭包：符号 + 4 位小数，负值归零） */
export function deepseekCostText(value: number, currency: string): string {
  const symbol = currency === 'CNY' ? '¥' : '$';
  return `${symbol}${Math.max(0, value).toFixed(4)}`;
}

/** 金额文案（无数据时为 "—"，对照 cost 闭包对 nil 的处理） */
function dsCostTextOrDash(value: number | null, currency: string): string {
  return value == null ? '—' : deepseekCostText(value, currency);
}

/** 千分位计数（对照 formatted()） */
export function deepseekCountText(value: number): string {
  const text = `${Math.round(value)}`;
  let out = '';
  let count = 0;
  for (let i = text.length - 1; i >= 0; i--) {
    out = text.charAt(i) + out;
    count += 1;
    if (count % 3 === 0 && i > 0 && text.charAt(i - 1) !== '-') {
      out = ',' + out;
    }
  }
  return out;
}

/**
 * by_api_key amount + cost 两组响应 → 近 30 天汇总（对照 DeepSeekUsageCostParser.parseByAPIKey）：
 * 桶时间需落在 [startSec, endSec)；花费优先取 USD 且有金额的币种块。
 */
export function deepseekPlatformUsage(
  amountJson: Json,
  costJson: Json,
  nowMs: number,
  startSec: number,
  endSec: number
): DeepSeekPlatformUsage | null {
  const amountRoot = asObj(amountJson);
  const costRoot = asObj(costJson);
  if (dsFailure(amountRoot) || dsFailure(costRoot)) {
    return null;
  }
  const amountData = amountRoot != null ? asObj(amountRoot['data']) : null;
  const amountBiz = amountData != null ? asObj(amountData['biz_data']) : null;
  if (amountBiz == null) {
    return null;
  }

  const dayTokens: Map<string, number> = new Map<string, number>();
  const dayRequests: Map<string, number> = new Map<string, number>();
  const modelTokens: Map<string, number> = new Map<string, number>();
  const apiKeys: Map<string, boolean> = new Map<string, boolean>();

  const amountSeries = asArray(amountBiz['series']);
  if (amountSeries != null) {
    for (let i = 0; i < amountSeries.length; i++) {
      const series = asObj(amountSeries[i]);
      if (series == null) {
        continue;
      }
      const keyId = dsApiKeyId(series['api_key']);
      if (keyId.length > 0) {
        apiKeys.set(keyId, true);
      }
      const model = optStr(series, 'model') ?? 'unknown';
      const buckets = asArray(series['buckets']);
      if (buckets == null) {
        continue;
      }
      for (let j = 0; j < buckets.length; j++) {
        const bucket = asObj(buckets[j]);
        if (bucket == null) {
          continue;
        }
        const time = optNum(bucket, 'time') ?? 0;
        if (time < startSec || time >= endSec) {
          continue;
        }
        const usage = asObj(bucket['usage']);
        if (usage == null) {
          continue;
        }
        const date = dsDayKey(time * 1000);
        const types = Object.keys(usage);
        for (let k = 0; k < types.length; k++) {
          const type = types[k].toUpperCase();
          const value = dsTokens(usage[types[k]]);
          if (type === DS_REQUEST) {
            dayRequests.set(date, (dayRequests.get(date) ?? 0) + value);
            continue;
          }
          if (type !== DS_CACHE_HIT && type !== DS_CACHE_MISS && type !== DS_RESPONSE) {
            continue;
          }
          dayTokens.set(date, (dayTokens.get(date) ?? 0) + value);
          modelTokens.set(model, (modelTokens.get(model) ?? 0) + value);
        }
      }
    }
  }

  // 花费：优先 USD 且有花费的块，其次有花费的块，再次 USD 块，最后首个块
  const costData = costRoot != null ? asObj(costRoot['data']) : null;
  const costBiz = costData != null ? asObj(costData['biz_data']) : null;
  const blocks = costBiz != null ? asArray(costBiz['data']) : null;
  const block = dsPreferredCostBlock(blocks);
  const currency = block != null ? (optStr(block, 'currency') ?? 'CNY').trim() : 'CNY';
  const dayCosts: Map<string, number> = new Map<string, number>();
  const modelCosts: Map<string, number> = new Map<string, number>();
  const modelCostBroken: Map<string, boolean> = new Map<string, boolean>();
  const costSeries = block != null ? asArray(block['series']) : null;
  if (costSeries != null) {
    for (let i = 0; i < costSeries.length; i++) {
      const series = asObj(costSeries[i]);
      if (series == null) {
        continue;
      }
      const keyId = dsApiKeyId(series['api_key']);
      if (keyId.length > 0) {
        apiKeys.set(keyId, true);
      }
      const model = optStr(series, 'model') ?? '';
      const buckets = asArray(series['buckets']);
      if (buckets == null) {
        if (model.length > 0) {
          modelCostBroken.set(model, true);
        }
        continue;
      }
      for (let j = 0; j < buckets.length; j++) {
        const bucket = asObj(buckets[j]);
        if (bucket == null) {
          continue;
        }
        const time = optNum(bucket, 'time') ?? 0;
        if (time < startSec || time >= endSec) {
          continue;
        }
        const amount = dsScalarValue(bucket['cost']);
        const date = dsDayKey(time * 1000);
        dayCosts.set(date, (dayCosts.get(date) ?? 0) + amount);
        if (model.length > 0) {
          modelCosts.set(model, (modelCosts.get(model) ?? 0) + amount);
        }
      }
    }
  }

  const usage = new DeepSeekPlatformUsage();
  usage.currency = currency.length > 0 ? currency : 'CNY';
  usage.apiKeyCount = apiKeys.size;
  usage.period = 'last30Days';
  usage.periodCost = 0;

  // 每日序列按日期升序（amount 与 cost 任一有值的日期都算）
  const dates: string[] = [];
  const seen: Map<string, boolean> = new Map<string, boolean>();
  const dayKeys = Array.from(dayTokens.keys()).concat(Array.from(dayCosts.keys()));
  for (let i = 0; i < dayKeys.length; i++) {
    if (seen.get(dayKeys[i]) !== true) {
      seen.set(dayKeys[i], true);
      dates.push(dayKeys[i]);
    }
  }
  dates.sort();
  for (let i = 0; i < dates.length; i++) {
    const row = new DeepSeekDailyRow();
    row.date = dates[i];
    row.tokens = dayTokens.get(dates[i]) ?? 0;
    row.requests = dayRequests.get(dates[i]) ?? 0;
    row.cost = dayCosts.has(dates[i]) ? dayCosts.get(dates[i])! : null;
    usage.daily.push(row);
    usage.periodTokens += row.tokens;
    usage.periodRequests += row.requests;
    if (row.cost != null) {
      usage.periodCost = (usage.periodCost ?? 0) + row.cost;
    }
  }

  const todayKey = dsDayKey(nowMs);
  for (let i = 0; i < usage.daily.length; i++) {
    if (usage.daily[i].date === todayKey) {
      usage.todayTokens = usage.daily[i].tokens;
      usage.todayRequests = usage.daily[i].requests;
      usage.todayCost = usage.daily[i].cost;
      break;
    }
  }

  // Top model：token 数最大，同数取名称字典序较小者
  let top = '';
  let topTokens = -1;
  const modelNames = Array.from(modelTokens.keys()).sort();
  for (let i = 0; i < modelNames.length; i++) {
    const value = modelTokens.get(modelNames[i]) ?? 0;
    if (value > topTokens) {
      top = modelNames[i];
      topTokens = value;
    }
  }
  usage.topModel = top;

  // 模型花费：花费降序，同额按名称升序；缺 buckets 的模型整体剔除
  const costRows: DeepSeekModelCostRow[] = [];
  const costNames = Array.from(modelCosts.keys());
  for (let i = 0; i < costNames.length; i++) {
    if (modelCostBroken.get(costNames[i]) === true) {
      continue;
    }
    const row = new DeepSeekModelCostRow();
    row.model = costNames[i];
    row.cost = modelCosts.get(costNames[i]) ?? 0;
    costRows.push(row);
  }
  costRows.sort((a: DeepSeekModelCostRow, b: DeepSeekModelCostRow): number => {
    if (a.cost === b.cost) {
      return a.model < b.model ? -1 : (a.model > b.model ? 1 : 0);
    }
    return b.cost - a.cost;
  });
  usage.modelCosts = costRows;
  return usage;
}

/** 标量取值：{ value: "0.25" } 或裸标量（对照 ByAPIKeyScalar） */
function dsScalarValue(value: Json): number {
  const o = asObj(value);
  return dsScalar(o != null ? (o['value'] ?? null) : value);
}

/** api_key 字段：字符串 id 或 { tracking_id, name } 对象（对照 ByAPIKeyIdentity） */
function dsApiKeyId(value: Json): string {
  if (typeof value === 'string') {
    return (value as string).trim();
  }
  const o = asObj(value);
  if (o == null) {
    return '';
  }
  const tracking = (optStr(o, 'tracking_id') ?? '').trim();
  if (tracking.length > 0) {
    return tracking;
  }
  const name = (optStr(o, 'name') ?? '').trim();
  return name.length > 0 ? name : 'unknown';
}

/** 币种块选择（对照 preferredCostBlock） */
function dsPreferredCostBlock(blocks: Json[] | null): Record<string, Json> | null {
  if (blocks == null || blocks.length === 0) {
    return null;
  }
  let usdWithSpend: Record<string, Json> | null = null;
  let anyWithSpend: Record<string, Json> | null = null;
  let usd: Record<string, Json> | null = null;
  let first: Record<string, Json> | null = null;
  for (let i = 0; i < blocks.length; i++) {
    const block = asObj(blocks[i]);
    if (block == null) {
      continue;
    }
    if (first == null) {
      first = block;
    }
    const isUsd = (optStr(block, 'currency') ?? '') === 'USD';
    if (isUsd && usd == null) {
      usd = block;
    }
    const spend = dsBlockSpend(block);
    if (spend > 0) {
      if (anyWithSpend == null) {
        anyWithSpend = block;
      }
      if (isUsd && usdWithSpend == null) {
        usdWithSpend = block;
      }
    }
  }
  if (usdWithSpend != null) {
    return usdWithSpend;
  }
  if (anyWithSpend != null) {
    return anyWithSpend;
  }
  if (usd != null) {
    return usd;
  }
  return first;
}

function dsBlockSpend(block: Record<string, Json>): number {
  const series = asArray(block['series']);
  if (series == null) {
    return 0;
  }
  let total = 0;
  for (let i = 0; i < series.length; i++) {
    const s = asObj(series[i]);
    const buckets = s != null ? asArray(s['buckets']) : null;
    if (buckets == null) {
      continue;
    }
    for (let j = 0; j < buckets.length; j++) {
      const b = asObj(buckets[j]);
      if (b == null) {
        continue;
      }
      total += dsScalarValue(b['cost']);
    }
  }
  return total;
}

/**
 * 平台用量 → 明细分组（对照 ClaudeAdminAPIUsageSnapshot 同级的 DeepSeek detailSections）：
 * Usage（今日/近 30 天花费与 token、请求数、API Key 数、Top model）+ Spend（各模型花费）。
 */
/**
 * 明细不可用时的提示分组（对照 macOS 菜单里的用量提示：
 * .notRequested → 需要平台会话；.webSessionRequired / .unavailable → 暂不可用）。
 */
function deepseekUsageHint(text: string): ProviderDetailSection {
  return {
    title: '用量明细',
    rows: [{ label: '平台用量', value: text }],
  };
}

/** 每日序列 → 图表点（token 用总 token 数） */
function dsTokenPoints(usage: DeepSeekPlatformUsage): ProviderChartPoint[] {
  const out: ProviderChartPoint[] = [];
  for (let i = 0; i < usage.daily.length; i++) {
    out.push({ label: usage.daily[i].date, value: usage.daily[i].tokens });
  }
  return out;
}

/**
 * 每日花费 → 图表点（对照源工程：cost 缺失或 <=0 记 0，只要有一天 > 0 才画图）。
 * 返回 null 表示不画图。
 */
function dsCostPoints(usage: DeepSeekPlatformUsage): ProviderChartPoint[] | null {
  const out: ProviderChartPoint[] = [];
  let any = false;
  for (let i = 0; i < usage.daily.length; i++) {
    const cost = usage.daily[i].cost;
    const value = cost != null && cost > 0 ? cost : 0;
    if (value > 0) {
      any = true;
    }
    out.push({ label: usage.daily[i].date, value: value });
  }
  return any ? out : null;
}

export function deepseekDetailSections(usage: DeepSeekPlatformUsage): ProviderDetailSection[] {
  const sections: ProviderDetailSection[] = [];
  const rows: ProviderDetailRow[] = [
    {
      label: 'Today',
      value: `${dsCostTextOrDash(usage.todayCost, usage.currency)} · ` +
        `${deepseekCountText(usage.todayTokens)} tokens`,
    },
    {
      // by-key 路径是近 30 天，月度回退路径是本月（对照 usage.period）
      label: usage.period === 'last30Days' ? 'Last 30 days' : 'This month',
      value: `${dsCostTextOrDash(usage.periodCost, usage.currency)} · ` +
        `${deepseekCountText(usage.periodTokens)} tokens`,
    },
    { label: 'Requests', value: `${usage.periodRequests}` },
  ];
  if (usage.apiKeyCount > 0) {
    rows.push({ label: 'API keys', value: `${usage.apiKeyCount}` });
  }
  if (usage.topModel.length > 0) {
    rows.push({ label: 'Top model', value: usage.topModel });
  }
  const usageSection: ProviderDetailSection = { title: 'Usage', rows: rows };
  const tokenPoints = dsTokenPoints(usage);
  if (tokenPoints.length > 0) {
    usageSection.chart = makeChart('Daily tokens', 'tokens', tokenPoints);
  }
  sections.push(usageSection);

  const spendRows: ProviderDetailRow[] = [];
  for (let i = 0; i < usage.modelCosts.length; i++) {
    spendRows.push({
      label: usage.modelCosts[i].model,
      value: deepseekCostText(usage.modelCosts[i].cost, usage.currency),
    });
  }
  const costPoints = dsCostPoints(usage);
  if (spendRows.length > 0 || costPoints != null) {
    const spend: ProviderDetailSection = { title: 'Spend', rows: spendRows };
    if (costPoints != null) {
      spend.chart = makeChart('Daily cost', usage.currency, costPoints);
    }
    sections.push(spend);
  }
  return sections;
}

// ---------------- DeepSeek 月度回退（账户级 usage/amount + usage/cost） ----------------

/** 日期文本（yyyy-MM-dd）→ 本地零点毫秒（对照 parseDate：格式不符返回 null） */
function dsParseDay(text: string): number | null {
  const trimmed = text.trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) {
    return null;
  }
  const parts = trimmed.split('-');
  const ms = new Date(
    parseInt(parts[0], 10), parseInt(parts[1], 10) - 1, parseInt(parts[2], 10), 0, 0, 0, 0).getTime();
  return isNaN(ms) ? null : ms;
}

/** 单日/整月的 token 与请求数累加器 */
class DsUsageTotals {
  tokens: number = 0;
  requests: number = 0;
}

/**
 * amount 条目累加（对照 aggregateDay / aggregateMonth 的 amount 分支）：
 * REQUEST 计请求数，三个 token 类别计 token，未知类别跳过。
 */
function dsAddAmountItems(items: Json[] | null, out: DsUsageTotals): void {
  if (items == null) {
    return;
  }
  for (let i = 0; i < items.length; i++) {
    const item = asObj(items[i]);
    if (item == null) {
      continue;
    }
    const type = (optStr(item, 'type') ?? '').toUpperCase();
    if (type !== DS_REQUEST && type !== DS_CACHE_HIT && type !== DS_CACHE_MISS && type !== DS_RESPONSE) {
      continue;
    }
    const amount = dsTokens(item['amount']);
    if (type === DS_REQUEST) {
      out.requests += amount;
    } else {
      out.tokens += amount;
    }
  }
}

/** 花费累加器：与源工程一致，只要出现过金额条目就算「有花费」（即便是 0） */
class DsCostTotal {
  total: number = 0;
  seen: boolean = false;
}

/** cost 条目累加（对照 aggregateDay / aggregateMonth 的 cost 分支：只算非 REQUEST 类别） */
function dsAddCostItems(items: Json[] | null, out: DsCostTotal): void {
  if (items == null) {
    return;
  }
  for (let i = 0; i < items.length; i++) {
    const item = asObj(items[i]);
    if (item == null) {
      continue;
    }
    const type = (optStr(item, 'type') ?? '').toUpperCase();
    if (type === DS_REQUEST || (type !== DS_CACHE_HIT && type !== DS_CACHE_MISS && type !== DS_RESPONSE)) {
      continue;
    }
    out.seen = true;
    out.total += dsScalar(item['amount']);
  }
}

/**
 * days[] → 日期 → 条目数组（对照 buildAmountMap / buildCostMap）：
 * 缺 date 的日、缺 model 的模型、usage 为空的模型整条跳过。
 */
function dsDayItemsMap(days: Json[] | null): Map<string, Json[]> {
  const out: Map<string, Json[]> = new Map<string, Json[]>();
  if (days == null) {
    return out;
  }
  for (let i = 0; i < days.length; i++) {
    const day = asObj(days[i]);
    if (day == null) {
      continue;
    }
    const date = optStr(day, 'date');
    if (date == null || date.length === 0) {
      continue;
    }
    const models = asArray(day['data']);
    if (models == null) {
      continue;
    }
    const items: Json[] = [];
    for (let j = 0; j < models.length; j++) {
      const modelUsage = asObj(models[j]);
      if (modelUsage == null || optStr(modelUsage, 'model') == null) {
        continue;
      }
      const list = asArray(modelUsage['usage']);
      if (list == null) {
        continue;
      }
      for (let k = 0; k < list.length; k++) {
        items.push(list[k]);
      }
    }
    if (items.length > 0) {
      out.set(date, items);
    }
  }
  return out;
}

/** Top model：token 数最大，同数取名称字典序较小者（对照 modelTokens.max 的比较器语义） */
function dsTopModel(modelTokens: Map<string, number>): string {
  let top = '';
  let topTokens = -1;
  const names = Array.from(modelTokens.keys()).sort();
  for (let i = 0; i < names.length; i++) {
    const value = modelTokens.get(names[i]) ?? 0;
    if (value > topTokens) {
      top = names[i];
      topTokens = value;
    }
  }
  return top;
}

/** 模型花费累加（对照 ModelCostTotals：一旦出现坏值，该模型整体丢弃） */
class DsModelCostTotals {
  private totals: Map<string, number> = new Map<string, number>();
  private unavailable: Map<string, boolean> = new Map<string, boolean>();

  add(amount: number | null, model: string | null): void {
    const name = model != null ? model.trim() : '';
    if (name.length === 0 || this.unavailable.get(name) === true) {
      return;
    }
    if (amount != null && isFinite(amount) && amount >= 0) {
      const total = (this.totals.get(name) ?? 0) + amount;
      if (isFinite(total)) {
        this.totals.set(name, total);
        return;
      }
    }
    this.unavailable.set(name, true);
    this.totals.delete(name);
  }

  /** 花费降序，同额按模型名升序 */
  values(): DeepSeekModelCostRow[] {
    const rows: DeepSeekModelCostRow[] = [];
    const names = Array.from(this.totals.keys());
    for (let i = 0; i < names.length; i++) {
      const row = new DeepSeekModelCostRow();
      row.model = names[i];
      row.cost = this.totals.get(names[i])!;
      rows.push(row);
    }
    rows.sort((a: DeepSeekModelCostRow, b: DeepSeekModelCostRow): number => {
      if (a.cost === b.cost) {
        return a.model < b.model ? -1 : (a.model > b.model ? 1 : 0);
      }
      return b.cost - a.cost;
    });
    return rows;
  }
}

/**
 * 账户级月度用量（对照 DeepSeekUsageCostParser.parse）：
 * amount 的 biz_data = { total[], days[] }；cost 的 biz_data 是币种数组，取首个块的 total/days/currency。
 * 与 by-key 路径的差异都对齐源工程：apiKeyCount = 0、日期按「本月」过滤、无花费时花费为 null（显示 —）。
 */
export function deepseekMonthlyUsage(
  amountJson: Json,
  costJson: Json,
  nowMs: number,
  monthStartMs: number
): DeepSeekPlatformUsage | null {
  const amountRoot = asObj(amountJson);
  const costRoot = asObj(costJson);
  if (dsFailure(amountRoot) || dsFailure(costRoot)) {
    return null;
  }
  const amountData = amountRoot != null ? asObj(amountRoot['data']) : null;
  const amountBiz = amountData != null ? asObj(amountData['biz_data']) : null;
  if (amountBiz == null) {
    // 对照 parseFailed("Missing amount biz_data")
    return null;
  }
  const costData = costRoot != null ? asObj(costRoot['data']) : null;
  const costBlocks = costData != null ? asArray(costData['biz_data']) : null;
  const costBlock = costBlocks != null && costBlocks.length > 0 ? asObj(costBlocks[0]) : null;
  let currency = 'CNY';
  if (costBlock != null) {
    const raw = optStr(costBlock, 'currency');
    if (raw != null && raw.trim().length > 0) {
      currency = raw.trim();
    }
  }

  const amountDayItems = dsDayItemsMap(asArray(amountBiz['days']));
  const costDayItems = costBlock != null ? dsDayItemsMap(asArray(costBlock['days'])) : new Map<string, Json[]>();

  // 两类日期取并集后升序（对照 allDates = amount ∪ cost）
  const allDates: string[] = [];
  const seen: Map<string, boolean> = new Map<string, boolean>();
  const dateKeys = Array.from(amountDayItems.keys()).concat(Array.from(costDayItems.keys()));
  for (let i = 0; i < dateKeys.length; i++) {
    if (seen.get(dateKeys[i]) !== true) {
      seen.set(dateKeys[i], true);
      allDates.push(dateKeys[i]);
    }
  }
  allDates.sort();

  const usage = new DeepSeekPlatformUsage();
  usage.currency = currency;
  usage.period = 'currentMonth';
  usage.periodCost = null;

  const todayLabel = dsDayKey(nowMs);
  let monthCost = 0;
  let hasMonthCost = false;
  for (let i = 0; i < allDates.length; i++) {
    const date = allDates[i];
    const ms = dsParseDay(date);
    // 只保留本月且不晚于当下的日期（对照 aggregateMonth / buildDailyUsages 的过滤）
    if (ms == null || ms < monthStartMs || ms > nowMs) {
      continue;
    }
    const totals = new DsUsageTotals();
    dsAddAmountItems(amountDayItems.get(date) ?? null, totals);
    const cost = new DsCostTotal();
    dsAddCostItems(costDayItems.get(date) ?? null, cost);

    const row = new DeepSeekDailyRow();
    row.date = date;
    row.tokens = totals.tokens;
    row.requests = totals.requests;
    row.cost = cost.seen ? cost.total : null;
    usage.daily.push(row);
    usage.periodTokens += row.tokens;
    usage.periodRequests += row.requests;
    if (row.cost != null) {
      hasMonthCost = true;
      monthCost += row.cost;
    }
  }
  usage.periodCost = hasMonthCost ? monthCost : null;

  for (let i = 0; i < usage.daily.length; i++) {
    if (usage.daily[i].date === todayLabel) {
      usage.todayTokens = usage.daily[i].tokens;
      usage.todayRequests = usage.daily[i].requests;
      usage.todayCost = usage.daily[i].cost;
      break;
    }
  }

  // Top model 与模型花费都来自 total 数组（对照 buildBreakdowns）
  const modelTokens: Map<string, number> = new Map<string, number>();
  const totalAmounts = asArray(amountBiz['total']);
  if (totalAmounts != null) {
    for (let i = 0; i < totalAmounts.length; i++) {
      const modelUsage = asObj(totalAmounts[i]);
      if (modelUsage == null) {
        continue;
      }
      const model = optStr(modelUsage, 'model');
      if (model == null) {
        continue;
      }
      const totals = new DsUsageTotals();
      dsAddAmountItems(asArray(modelUsage['usage']), totals);
      modelTokens.set(model, totals.tokens);
    }
  }
  usage.topModel = dsTopModel(modelTokens);

  // 模型花费：未知类别或缺金额 → 该模型整体不可用（对照 ModelCostTotals.add）
  const costTotals = new DsModelCostTotals();
  const totalCosts = costBlock != null ? asArray(costBlock['total']) : null;
  if (totalCosts != null) {
    for (let i = 0; i < totalCosts.length; i++) {
      const modelUsage = asObj(totalCosts[i]);
      if (modelUsage == null) {
        continue;
      }
      const model = optStr(modelUsage, 'model');
      if (model == null) {
        continue;
      }
      const items = asArray(modelUsage['usage']);
      if (items == null) {
        costTotals.add(null, model);
        continue;
      }
      for (let j = 0; j < items.length; j++) {
        const item = asObj(items[j]);
        if (item == null) {
          costTotals.add(null, model);
          continue;
        }
        const type = (optStr(item, 'type') ?? '').toUpperCase();
        if (type === DS_REQUEST) {
          continue;
        }
        if (type !== DS_CACHE_HIT && type !== DS_CACHE_MISS && type !== DS_RESPONSE) {
          costTotals.add(null, model);
          continue;
        }
        const text = dsNumberText(item['amount']);
        let amount: number | null = null;
        if (text.length > 0) {
          const parsed = parseFloat(text);
          if (!isNaN(parsed) && isFinite(parsed)) {
            amount = parsed;
          }
        }
        costTotals.add(amount, model);
      }
    }
  }
  usage.modelCosts = costTotals.values();
  return usage;
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

  /** 数字字段兼容字符串形态 */
  private static numField(o: Record<string, Json>, key: string): number | null {
    const n = optNum(o, key);
    if (n != null) {
      return n;
    }
    const s = optStr(o, key);
    if (s != null && s.length > 0) {
      const parsed = parseFloat(s);
      return isNaN(parsed) ? null : parsed;
    }
    return null;
  }

  private static usd(value: number): string {
    return `$${Math.max(0, value).toFixed(2)}`;
  }

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const key = setting.credential.trim();
    if (key.length === 0) {
      return UsageSnapshot.failure('未配置 API Key');
    }
    const headers = bearer(key);
    headers['x-title'] = 'CodexBar';

    // 1) 账户余额（/credits）：只有管理密钥能读，普通推理密钥返回 403
    const creditsResp = await Http.get('https://openrouter.ai/api/v1/credits', headers);
    let balance: number | null = null;
    let totalUsage: number | null = null;
    let totalCredits: number | null = null;
    let creditsIssue = '';
    if (creditsResp.ok) {
      const root = asObj(creditsResp.json());
      const data = root != null ? asObj(root['data']) : null;
      if (data != null) {
        totalCredits = OpenRouterProvider.numField(data, 'total_credits');
        totalUsage = OpenRouterProvider.numField(data, 'total_usage');
        if (totalCredits != null && totalUsage != null) {
          balance = Math.max(0, totalCredits - totalUsage);
        }
      }
      if (balance == null) {
        creditsIssue = '响应解析失败';
      }
    } else if (creditsResp.code === 401 || creditsResp.code === 403) {
      creditsIssue = '需要管理密钥（管理密钥才能读账户余额）';
    } else {
      creditsIssue = creditsResp.errorText();
    }

    // 2) API key 额度（/key）
    const keyResp = await Http.get('https://openrouter.ai/api/v1/key', headers);
    let keyData: Record<string, Json> | null = null;
    let keyIssue = '';
    if (keyResp.ok) {
      const root = asObj(keyResp.json());
      keyData = root != null ? asObj(root['data']) : null;
      if (keyData == null) {
        keyIssue = '响应解析失败';
      }
    } else {
      keyIssue = keyResp.errorText();
    }
    if (balance == null && keyData == null) {
      return UsageSnapshot.failure(creditsIssue.length > 0 ? creditsIssue : keyIssue);
    }

    const keyLimit = keyData != null ? OpenRouterProvider.numField(keyData, 'limit') : null;
    const keyUsage = keyData != null ? OpenRouterProvider.numField(keyData, 'usage') : null;
    const limitRemaining = keyData != null ? OpenRouterProvider.numField(keyData, 'limit_remaining') : null;
    const resetWindow = keyData != null ? optStr(keyData, 'limit_reset') : null;
    const windowKey = resetWindow === 'daily' ? 'usage_daily'
      : resetWindow === 'weekly' ? 'usage_weekly'
        : resetWindow === 'monthly' ? 'usage_monthly'
          : '';
    const windowUsage = keyData != null && windowKey.length > 0
      ? OpenRouterProvider.numField(keyData, windowKey)
      : null;

    // 配额口径：优先服务端 remaining，其次与 limit_reset 匹配的窗口用量，最后累计用量
    let quotaUsed: number | null = null;
    let keyRemaining: number | null = null;
    if (keyLimit != null && keyLimit > 0) {
      if (limitRemaining != null) {
        quotaUsed = keyLimit - Math.min(keyLimit, Math.max(0, limitRemaining));
      } else if (windowUsage != null) {
        quotaUsed = windowUsage;
      } else {
        quotaUsed = keyUsage;
      }
    }

    const snap = UsageSnapshot.success(
      keyLimit != null && keyLimit > 0 && quotaUsed != null && quotaUsed >= 0
        ? makeWindow(Math.max(0, Math.min(100, (quotaUsed / keyLimit) * 100)), 0, true)
        : null,
      null, null);
    if (keyLimit != null && keyLimit > 0 && quotaUsed != null) {
      keyRemaining = Math.max(0, keyLimit - quotaUsed);
    }

    const details: ProviderDetailSection[] = [];
    if (balance != null) {
      details.push({
        title: 'Credits',
        rows: [
          { label: 'Remaining', value: OpenRouterProvider.usd(balance) },
          { label: 'Used', value: OpenRouterProvider.usd(totalUsage ?? 0) },
          { label: 'Total added', value: OpenRouterProvider.usd(totalCredits ?? 0) },
        ],
      });
    } else {
      // 对照源工程：拿不到余额时仍保留 Credits 分组并写清原因，而不是整块消失
      details.push({
        title: 'Credits',
        rows: [{ label: 'Balance', value: '暂不可用', secondary: creditsIssue }],
      });
    }
    if (keyData != null) {
      const rows: ProviderDetailRow[] = [];
      if (keyLimit != null && keyLimit > 0) {
        rows.push({ label: 'API key limit', value: OpenRouterProvider.usd(keyLimit), secondary: '支出上限，非余额' });
        if (keyRemaining != null) {
          rows.push({ label: 'API key remaining', value: OpenRouterProvider.usd(keyRemaining) });
        }
        if (keyUsage != null) {
          rows.push({ label: 'API key used', value: OpenRouterProvider.usd(keyUsage) });
        }
      } else {
        rows.push({ label: 'API key limit', value: '未设置上限' });
      }
      if (resetWindow != null && resetWindow.length > 0) {
        rows.push({ label: 'Reset window', value: resetWindow });
      }
      const periods: string[][] = [['Today', 'usage_daily'], ['This week', 'usage_weekly'], ['This month', 'usage_monthly']];
      for (let i = 0; i < periods.length; i++) {
        const value = OpenRouterProvider.numField(keyData, periods[i][1]);
        if (value != null) {
          rows.push({ label: periods[i][0], value: OpenRouterProvider.usd(value) });
        }
      }
      details.push({ title: 'API key', rows: rows });
    } else {
      details.push({
        title: 'API key',
        rows: [{ label: 'API key limit', value: '暂不可用', secondary: keyIssue }],
      });
    }

    // 3) 近 30 个完整 UTC 日的活动聚合（管理密钥才有权限，失败不影响余额展示）
    const activity = await this.activitySummary(headers);
    if (activity != null) {
      details.push({
        title: 'Activity (last 30 completed UTC days)',
        rows: [
          { label: 'Tokens', value: `${activity.tokens}` },
          { label: 'Requests', value: `${activity.requests}` },
          { label: 'Models', value: `${activity.models}` },
        ],
      });
    }

    if (details.length > 0) {
      snap.details = details;
    }
    if (balance != null) {
      snap.identity = { accountEmail: '', accountOrganization: '', loginMethod: `Balance: ${OpenRouterProvider.usd(balance)}` };
    }

    // 费用卡（对照源工程 cost 构造规则：有额度上限的 key 不重复展示花费周期）
    const monthly = keyData != null ? OpenRouterProvider.numField(keyData, 'usage_monthly') : null;
    const cappedKey = keyLimit != null && keyLimit > 0;
    if (!cappedKey) {
      const costUsed = monthly ?? keyUsage ?? totalUsage;
      if (costUsed != null) {
        const period = monthly != null ? 'This month (API key)'
          : keyUsage != null ? 'Total key usage' : 'Total account usage';
        snap.providerCost = {
          remaining: balance != null ? balance : 0,
          used: Math.max(0, costUsed),
          currency: 'USD',
          displayText: OpenRouterProvider.usd(Math.max(0, costUsed)),
          period: period,
          limit: 0,
        };
        // 按量花费卡片另起一行余额（对照 payAsYouGoSpend 的 balanceLine）
        if (balance != null) {
          snap.providerCost.balanceText = OpenRouterProvider.usd(balance);
        }
      }
    }
    return snap;
  }

  /** 活动聚合：Tokens / Requests / 去重模型数（管理密钥才有数据） */
  private async activitySummary(headers: Record<string, string>): Promise<OpenRouterActivity | null> {
    const resp = await Http.get('https://openrouter.ai/api/v1/activity', headers);
    if (!resp.ok) {
      return null;
    }
    const root = asObj(resp.json());
    const rows = root != null ? asArray(root['data']) : null;
    if (rows == null) {
      return null;
    }
    const out = new OpenRouterActivity();
    const models: Map<string, boolean> = new Map<string, boolean>();
    for (let i = 0; i < rows.length; i++) {
      const row = asObj(rows[i]);
      if (row == null) {
        continue;
      }
      out.tokens += num(row, 'tokens_prompt', 0) + num(row, 'tokens_completion', 0);
      out.requests += num(row, 'requests', 0);
      const model = optStr(row, 'model');
      if (model != null && model.length > 0) {
        models.set(model, true);
      }
    }
    out.models = models.size;
    return out;
  }
}

/** 活动聚合结果（对照源工程 Activity 分组三行） */
class OpenRouterActivity {
  tokens: number = 0;
  requests: number = 0;
  models: number = 0;
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
    authHint: '粘贴 DeepSeek 开放平台 API Key（sk-… 开头）；用量明细需「网页登录」一次自动获取平台会话',
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
    const paid = Math.max(0, total - granted);
    const snap = UsageSnapshot.success(null, null, null);
    // 首页/详情页大号数字只放余额；macOS 的余额窗口原句（含 Paid/Granted）放在详情页说明行
    snap.providerCost = {
      remaining: total, used: 0, currency: currency,
      displayText: Format.money(total, currency),
      detailText: `${Format.money(total, currency)} (Paid: ${Format.money(paid, currency)} / ` +
        `Granted: ${Format.money(granted, currency)})`,
    };
    const sections: ProviderDetailSection[] = [{
      title: '余额构成',
      rows: [
        { label: '总额', value: Format.money(total, currency) },
        { label: '充值余额', value: Format.money(paid, currency) },
        { label: '赠送余额', value: Format.money(granted, currency) },
      ],
    }];
    if (total <= 0) {
      // 对照 macOS：余额为 0 时附上充值提示
      sections[0].rows.push({ label: '提示', value: '余额为 0，请在 platform.deepseek.com 充值' });
    }

    // 平台 Web 使用量（对照 DeepSeekUsageFetcher：平台会话令牌，尽力而为）
    const platformToken = setting.credential2.trim();
    // 对照 macOS：平台会话不由用户手填（requiresManualCookieSource = false），一律自动获取。
    // 没有会话时先用 API Key 试一次同一平台接口，能通就直接出明细；
    // 不通就按 macOS 的 .webSessionRequired 给提示 —— macOS 是靠读 Chrome 的 userToken
    // 自动拿到平台会话，鸿蒙端用应用内「网页登录」等价替代。
    const credentialForPlatform = platformToken.length > 0 ? platformToken : key;
    const usage = await this.fetchUsageSummary(credentialForPlatform, Date.now());
    if (usage == null) {
      sections.push(deepseekUsageHint(platformToken.length > 0
        ? '暂不可用（平台会话可能已过期，可重新「网页登录」）'
        : '点详情页「网页登录」自动获取平台会话后可见近 30 天用量与花费'));
    } else {
      const detail = deepseekDetailSections(usage);
      for (let i = 0; i < detail.length; i++) {
        sections.push(detail[i]);
      }
    }
    snap.details = sections;
    return snap;
  }

  /**
   * 用量汇总（对照 fetchUsageSummary）：先走 by_api_key 的近 30 天数据，
   * 任一步失败（含非鉴权失败）就回退到账户级本月数据，所以详情页总有行可看。
   */
  private async fetchUsageSummary(token: string, nowMs: number): Promise<DeepSeekPlatformUsage | null> {
    const byKey = await this.fetchPlatformUsage(token, nowMs);
    if (byKey != null) {
      return byKey;
    }
    return this.fetchMonthlyUsage(token, nowMs);
  }

  /**
   * by_api_key 仪表盘序列（对照 fetchUsageSummary 的 by-key 路径）：
   * amount + cost 两组数据按桶时间合并，窗口为近 30 天，tz 为本地时区偏移。
   */
  private async fetchPlatformUsage(token: string, nowMs: number): Promise<DeepSeekPlatformUsage | null> {
    const headers: Record<string, string> = {
      'authorization': `Bearer ${token}`,
      'accept': 'application/json',
      'x-client-platform': 'web',
    };
    const now = new Date(nowMs);
    const startMs = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0, 0).getTime()
      - 29 * 86400000;
    const endMs = new Date(
      now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0, 0).getTime() + 86400000;
    const tz = -now.getTimezoneOffset() * 60;
    const query = `start=${Math.floor(startMs / 1000)}&end=${Math.floor(endMs / 1000)}&tz=${tz}`;
    const amountResp = await Http.get(
      `https://platform.deepseek.com/api/v0/usage/by_api_key/amount?${query}`, headers);
    const costResp = await Http.get(
      `https://platform.deepseek.com/api/v0/usage/by_api_key/cost?${query}`, headers);
    if (!amountResp.ok || !costResp.ok) {
      return null;
    }
    return deepseekPlatformUsage(amountResp.json(), costResp.json(), nowMs, startMs / 1000, endMs / 1000);
  }

  /**
   * 账户级本月用量（对照 fetchAmount / fetchCost 的 month/year 参数）：
   * 每个请求都拿「amount + cost」两份数据，任一份失败就算本次明细不可用。
   */
  private async fetchMonthlyUsage(token: string, nowMs: number): Promise<DeepSeekPlatformUsage | null> {
    const headers: Record<string, string> = {
      'authorization': `Bearer ${token}`,
      'accept': 'application/json',
      'x-client-platform': 'web',
    };
    const now = new Date(nowMs);
    const monthStartMs = new Date(now.getFullYear(), now.getMonth(), 1, 0, 0, 0, 0).getTime();
    const query = `month=${now.getMonth() + 1}&year=${now.getFullYear()}`;
    const amountResp = await Http.get(
      `https://platform.deepseek.com/api/v0/usage/amount?${query}`, headers);
    const costResp = await Http.get(
      `https://platform.deepseek.com/api/v0/usage/cost?${query}`, headers);
    if (!amountResp.ok || !costResp.ok) {
      return null;
    }
    return deepseekMonthlyUsage(amountResp.json(), costResp.json(), nowMs, monthStartMs);
  }
}

// ---------------------------------------------------------------------------
// Kimi / Moonshot
// ---------------------------------------------------------------------------

/** Moonshot 区域端点选项 */
interface MoonshotRegionOption {
  base: string;
  currency: string;
  label: string;
}

class MoonshotProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'moonshot',
    title: 'Kimi (Moonshot)',
    authKind: AuthKind.API_KEY,
    accentColor: '#17C0AA',
    authHint: '粘贴 Moonshot 开放平台 API Key（中国区/国际区自动识别）',
    authUrl: 'https://platform.moonshot.cn/console/api-keys',
  };

  /** 余额字段兼容数字与字符串两种形态 */
  private static balanceNum(data: Record<string, Json>, key: string): number {
    const n = optNum(data, key);
    if (n != null) {
      return n;
    }
    const s = optStr(data, key);
    if (s != null && s.length > 0) {
      const parsed = parseFloat(s);
      if (!isNaN(parsed)) {
        return parsed;
      }
    }
    return 0;
  }

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const key = setting.credential.trim();
    if (key.length === 0) {
      return UsageSnapshot.failure('未配置 API Key');
    }
    // 双区域回退（对照 macOS MoonshotRegion）：key 属于哪个平台就哪个端点成功
    const regions: MoonshotRegionOption[] = [
      { base: 'https://api.moonshot.cn', currency: 'CNY', label: '中国区' },
      { base: 'https://api.moonshot.ai', currency: 'USD', label: '国际区' },
    ];
    let lastFail = '查询失败';
    for (let i = 0; i < regions.length; i++) {
      const resp = await Http.get(`${regions[i].base}/v1/users/me/balance`, bearer(key));
      if (!resp.ok) {
        lastFail = resp.errorText();
        continue;
      }
      const root = asObj(resp.json());
      const data = root != null ? asObj(root['data']) : null;
      const code = root != null ? optNum(root, 'code') : null;
      const ok = root != null && root['status'] === true && (code == null || code === 0);
      if (data == null || !ok) {
        lastFail = `Moonshot ${regions[i].label} 响应异常`;
        continue;
      }
      const currency = regions[i].currency;
      const available = MoonshotProvider.balanceNum(data, 'available_balance');
      const voucher = MoonshotProvider.balanceNum(data, 'voucher_balance');
      const cash = MoonshotProvider.balanceNum(data, 'cash_balance');
      const snap = UsageSnapshot.success(null, null, null);
      snap.providerCost = {
        remaining: available, used: 0, currency: currency,
        displayText: Format.money(available, currency),
      };
      snap.details = [{
        title: '余额构成',
        rows: [
          { label: '可用余额', value: Format.money(available, currency) },
          { label: '代金券', value: Format.money(voucher, currency) },
          { label: '现金余额', value: Format.money(cash, currency) },
        ],
      }];
      return snap;
    }
    return UsageSnapshot.failure(lastFail);
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

    let accessUntil = 0;
    if (subResp.ok) {
      const sub = asObj(subResp.json());
      if (sub != null) {
        const until = num(sub, 'access_until', 0);
        if (until > 0) {
          accessUntil = until * 1000;
        }
      }
    }
    let granted = 0;
    let used = 0;
    let available = 0;
    let resetsAt = accessUntil;
    if (grantResp.ok) {
      const g = asObj(grantResp.json());
      if (g != null) {
        granted = num(g, 'total_granted', 0);
        used = num(g, 'total_used', 0);
        available = num(g, 'total_available', 0);
        // 最近的未来过期时间作为重置点（对照源工程 grants.data[].expires_at）
        const grants = asObj(g['grants']);
        const data = grants != null ? asArray(grants['data']) : null;
        if (data != null) {
          let soonest = 0;
          for (let i = 0; i < data.length; i++) {
            const item = asObj(data[i]);
            if (item == null) {
              continue;
            }
            const exp = num(item, 'expires_at', 0) * 1000;
            if (exp > Date.now() && (soonest === 0 || exp < soonest)) {
              soonest = exp;
            }
          }
          if (soonest > 0) {
            resetsAt = soonest;
          }
        }
      }
    }

    // 配额口径与源工程 API credits 回退路径一致：以授予额度为分母
    let percent = 100;
    if (granted > 0) {
      percent = Math.min(100, (used / granted) * 100);
    } else if (available > 0) {
      percent = 0;
    }
    const primary = makeWindow(Math.max(0, percent), resetsAt, granted > 0 || available > 0);
    const snap = UsageSnapshot.success(primary, null, null);
    snap.providerCost = {
      remaining: available, used: used, currency: 'USD',
      displayText: Format.money(available, 'USD'),
      period: 'API credits',
      limit: Math.max(0, granted),
    };
    snap.details = [{
      title: 'API credits',
      rows: [
        { label: 'Available', value: Format.money(Math.max(0, available), 'USD') },
        { label: 'Used', value: Format.money(Math.max(0, used), 'USD') },
        { label: 'Granted', value: Format.money(Math.max(0, granted), 'USD') },
      ],
    }];
    snap.identity = {
      accountEmail: '',
      accountOrganization: '',
      loginMethod: `API balance: ${Format.money(Math.max(0, available), 'USD')}`,
    };
    return snap;
  }
}

// ---------------------------------------------------------------------------
// Anthropic Console（Admin API：月度用量与花费）
// ---------------------------------------------------------------------------

/** 单日聚合桶（对照 ClaudeAdminAPIUsageSnapshot.DailyBucket） */
class ClaudeAdminDay {
  day: string = '';
  startMs: number = 0;
  costUSD: number = 0;
  inputTokens: number = 0;
  cacheCreationTokens: number = 0;
  cacheReadTokens: number = 0;
  outputTokens: number = 0;
  /** 花费明细：名称 → 金额 */
  costItems: Map<string, number> = new Map<string, number>();
  /** 模型 → 总 token 数（仅用于取 Top model） */
  modelTokens: Map<string, number> = new Map<string, number>();
}

class AnthropicConsoleProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'anthropic-console',
    title: 'Anthropic 控制台',
    authKind: AuthKind.API_KEY,
    accentColor: '#D97757',
    authHint: '粘贴 Anthropic Admin API Key（需要组织管理员权限，sk-ant-admin…）',
    authUrl: 'https://console.anthropic.com/settings/keys',
  };

  /** 每日桶上限（对照 maxDailyBuckets = 31，覆盖近 30 天） */
  private static readonly MAX_DAYS = 31;

  /** UTC 日边界 RFC3339（源工程按 UTC 建桶） */
  private static dayStartMs(nowMs: number, offsetDays: number): number {
    const d = new Date(nowMs + offsetDays * 86400000);
    return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate());
  }

  private static rfc3339(ms: number): string {
    return new Date(ms).toISOString().replace(/\.\d{3}Z$/, 'Z');
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
      'user-agent': 'CodexBar/1.0',
    };
    const nowMs = Date.now();
    const startMs = AnthropicConsoleProvider.dayStartMs(nowMs, -(AnthropicConsoleProvider.MAX_DAYS - 1));
    const endMs = AnthropicConsoleProvider.dayStartMs(nowMs, 1);
    const range =
      `starting_at=${encodeURIComponent(AnthropicConsoleProvider.rfc3339(startMs))}` +
      `&ending_at=${encodeURIComponent(AnthropicConsoleProvider.rfc3339(endMs))}` +
      `&bucket_width=1d&limit=${AnthropicConsoleProvider.MAX_DAYS}`;

    // 1) 花费报告（group_by=description → 花费明细）
    const costResp = await Http.get(
      `https://api.anthropic.com/v1/organizations/cost_report?${range}&group_by%5B%5D=description`, headers);
    if (!costResp.ok) {
      return UsageSnapshot.failure(costResp.errorText());
    }
    // 2) 消息用量（group_by=model → Top model）
    const usageResp = await Http.get(
      `https://api.anthropic.com/v1/organizations/usage_report/messages?${range}&group_by%5B%5D=model`, headers);
    if (!usageResp.ok) {
      return UsageSnapshot.failure(usageResp.errorText());
    }

    const daily = this.aggregate(costResp.json(), usageResp.json(), nowMs);
    if (daily.length === 0) {
      return UsageSnapshot.failure('响应解析失败');
    }

    const total = this.summary(daily);
    const today = this.summary(this.since(daily, 0, nowMs));
    const seven = this.summary(this.since(daily, 6, nowMs));

    const rows: ProviderDetailRow[] = [
      { label: 'Today spend', value: Format.money(today.cost, 'USD') },
      { label: '7d spend', value: Format.money(seven.cost, 'USD') },
      { label: '30d spend', value: Format.money(total.cost, 'USD') },
      { label: 'Today tokens', value: `${today.tokens}` },
      { label: '30d tokens', value: `${total.tokens}` },
      { label: 'Cache read', value: `${total.cacheRead}` },
    ];
    const top = this.topModel(daily);
    if (top != null) {
      rows.push({ label: 'Top model', value: top });
    }

    const snap = UsageSnapshot.success(null, null, null);
    // Usage summary 附「Daily spend」柱状图（对照源工程 daily → chart 点序列）
    const spendPoints: ProviderChartPoint[] = [];
    for (let i = 0; i < daily.length; i++) {
      spendPoints.push({ label: daily[i].day, value: daily[i].costUSD });
    }
    snap.details = [{
      title: 'Usage summary',
      rows: rows,
      chart: makeChart('Daily spend', 'USD', spendPoints),
    }];

    // 花费明细（对照 topCostItems 前 20 条，按金额降序）
    const items = this.topCostItems(daily);
    if (items.length > 0) {
      const itemRows: ProviderDetailRow[] = [];
      const limit = items.length > 20 ? 20 : items.length;
      for (let i = 0; i < limit; i++) {
        itemRows.push({ label: items[i].name, value: Format.money(items[i].cost, 'USD') });
      }
      snap.details.push({ title: 'Cost items', rows: itemRows });
    }

    snap.providerCost = {
      remaining: 0,
      used: total.cost,
      currency: 'USD',
      displayText: Format.money(total.cost, 'USD'),
      period: 'Last 30 days',
      limit: 0,
    };
    snap.identity = { accountEmail: '', accountOrganization: 'Anthropic 组织', loginMethod: 'Admin API' };
    return snap;
  }

  /** 按 bucket starting_at 合并花费与用量（锚点取桶内的最早时间） */
  private aggregate(costJson: Json, usageJson: Json, nowMs: number): ClaudeAdminDay[] {
    const byStart: Map<string, ClaudeAdminDay> = new Map<string, ClaudeAdminDay>();
    const costRoot = asObj(costJson);
    const costBuckets = costRoot != null ? asArray(costRoot['data']) : null;
    if (costBuckets != null) {
      for (let i = 0; i < costBuckets.length; i++) {
        const bucket = asObj(costBuckets[i]);
        const start = bucket != null ? str(bucket, 'starting_at', '') : '';
        if (bucket == null || start.length === 0) {
          continue;
        }
        const day = AnthropicConsoleProvider.bucket(byStart, start);
        const results = asArray(bucket['results']);
        if (results == null) {
          continue;
        }
        for (let j = 0; j < results.length; j++) {
          const r = asObj(results[j]);
          if (r == null) {
            continue;
          }
          // amount 为最低货币单位的十进制字符串（分）
          const value = (parseFloat(str(r, 'amount', '0')) || 0) / 100;
          day.costUSD += value;
          const name = optStr(r, 'description') ?? optStr(r, 'cost_type') ?? 'Claude API';
          day.costItems.set(name, (day.costItems.get(name) ?? 0) + value);
        }
      }
    }
    const usageRoot = asObj(usageJson);
    const usageBuckets = usageRoot != null ? asArray(usageRoot['data']) : null;
    if (usageBuckets != null) {
      for (let i = 0; i < usageBuckets.length; i++) {
        const bucket = asObj(usageBuckets[i]);
        const start = bucket != null ? str(bucket, 'starting_at', '') : '';
        if (bucket == null || start.length === 0) {
          continue;
        }
        const day = AnthropicConsoleProvider.bucket(byStart, start);
        const results = asArray(bucket['results']);
        if (results == null) {
          continue;
        }
        for (let j = 0; j < results.length; j++) {
          const r = asObj(results[j]);
          if (r == null) {
            continue;
          }
          const cache = asObj(r['cache_creation']);
          const cacheCreation = cache == null
            ? 0
            : num(cache, 'ephemeral_1h_input_tokens', 0) + num(cache, 'ephemeral_5m_input_tokens', 0);
          const input = num(r, 'uncached_input_tokens', 0);
          const cacheRead = num(r, 'cache_read_input_tokens', 0);
          const output = num(r, 'output_tokens', 0);
          day.inputTokens += input;
          day.cacheCreationTokens += cacheCreation;
          day.cacheReadTokens += cacheRead;
          day.outputTokens += output;
          const model = optStr(r, 'model') ?? 'Claude API';
          day.modelTokens.set(model, (day.modelTokens.get(model) ?? 0) + input + cacheCreation + cacheRead + output);
        }
      }
    }
    const out: ClaudeAdminDay[] = [];
    const keys = Array.from(byStart.keys());
    for (let i = 0; i < keys.length; i++) {
      const day = byStart.get(keys[i])!;
      if (day.startMs <= nowMs) {
        out.push(day);
      }
    }
    out.sort((a: ClaudeAdminDay, b: ClaudeAdminDay) => a.startMs - b.startMs);
    return out;
  }

  private static bucket(map: Map<string, ClaudeAdminDay>, start: string): ClaudeAdminDay {
    const existing = map.get(start);
    if (existing != null) {
      return existing;
    }
    const parsed = Date.parse(start);
    const day = new ClaudeAdminDay();
    day.day = start.length >= 10 ? start.substring(0, 10) : start;
    day.startMs = isNaN(parsed) ? 0 : parsed;
    map.set(start, day);
    return day;
  }

  /** 取最近 n 天的桶（含今天） */
  private since(daily: ClaudeAdminDay[], backDays: number, nowMs: number): ClaudeAdminDay[] {
    const from = AnthropicConsoleProvider.dayStartMs(nowMs, -backDays);
    const out: ClaudeAdminDay[] = [];
    for (let i = 0; i < daily.length; i++) {
      if (daily[i].startMs >= from) {
        out.push(daily[i]);
      }
    }
    return out;
  }

  private summary(days: ClaudeAdminDay[]): ClaudeAdminTotals {
    const t = new ClaudeAdminTotals();
    for (let i = 0; i < days.length; i++) {
      t.cost += days[i].costUSD;
      t.tokens += days[i].inputTokens + days[i].cacheCreationTokens + days[i].cacheReadTokens + days[i].outputTokens;
      t.cacheRead += days[i].cacheReadTokens;
    }
    return t;
  }

  private topModel(daily: ClaudeAdminDay[]): string | null {
    const totals: Map<string, number> = new Map<string, number>();
    for (let i = 0; i < daily.length; i++) {
      const keys = Array.from(daily[i].modelTokens.keys());
      for (let j = 0; j < keys.length; j++) {
        totals.set(keys[j], (totals.get(keys[j]) ?? 0) + (daily[i].modelTokens.get(keys[j]) ?? 0));
      }
    }
    let best: string | null = null;
    let bestTokens = -1;
    const names = Array.from(totals.keys()).sort();
    for (let i = 0; i < names.length; i++) {
      const value = totals.get(names[i]) ?? 0;
      if (value > bestTokens) {
        best = names[i];
        bestTokens = value;
      }
    }
    return best;
  }

  private topCostItems(daily: ClaudeAdminDay[]): AnthropicCostItem[] {
    const totals: Map<string, number> = new Map<string, number>();
    for (let i = 0; i < daily.length; i++) {
      const keys = Array.from(daily[i].costItems.keys());
      for (let j = 0; j < keys.length; j++) {
        totals.set(keys[j], (totals.get(keys[j]) ?? 0) + (daily[i].costItems.get(keys[j]) ?? 0));
      }
    }
    const items: AnthropicCostItem[] = [];
    const names = Array.from(totals.keys());
    for (let i = 0; i < names.length; i++) {
      items.push({ name: names[i], cost: totals.get(names[i]) ?? 0 });
    }
    items.sort((a: AnthropicCostItem, b: AnthropicCostItem) => {
      if (a.cost === b.cost) {
        return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0);
      }
      return b.cost - a.cost;
    });
    return items;
  }
}

/** 单日汇总 */
class ClaudeAdminTotals {
  cost: number = 0;
  tokens: number = 0;
  cacheRead: number = 0;
}

/** 花费明细条目 */
interface AnthropicCostItem {
  name: string;
  cost: number;
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
