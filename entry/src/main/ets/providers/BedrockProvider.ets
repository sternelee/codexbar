/**
 * 服务商第九批：AWS Bedrock（API Key / 静态凭证路径）
 *
 * 对照 macOS 版迁移：
 * - Sources/CodexBarCore/Providers/Bedrock/BedrockUsageStats.swift（Cost Explorer + 快照映射）
 * - Sources/CodexBarCore/Providers/Bedrock/BedrockCloudWatchUsage.swift（近 14 天 Claude 指标）
 * - Sources/CodexBarCore/Providers/Bedrock/BedrockAWSSigner.swift（SigV4，见 common/AwsSign.ets）
 * - Sources/CodexBar/Providers/Bedrock/BedrockProviderImplementation.swift（凭证与展示）
 *
 * 桌面版的 AWS Profile（aws CLI / SSO）模式在移动端不可用（需本地 aws 二进制），
 * 只迁移静态凭证路径：
 *   凭证 1 = AWS Access Key ID；凭证 2 = AWS Secret Access Key；
 *   额外字段 = region（默认 us-east-1）/ sessionToken（临时凭证）/ budget（月度预算，美元）
 *
 * 1) AWS Cost Explorer：POST https://ce.us-east-1.amazonaws.com/
 *    SigV4 service=ce，区域固定 us-east-1；X-Amz-Target: AWSInsightsIndexService.GetCostAndUsage，
 *    Granularity=MONTHLY、Metrics=[UnblendedCost]、GroupBy SERVICE →
 *    汇总本期（UTC 本月首日至明日，左闭右开）服务名含 "Bedrock" 的花费；
 *    DataUnavailableException（账号未启用计费数据）按 0 处理；NextPageToken 分页（带重复令牌/页数保护，
 *    与源工程一致）。
 * 2) AWS CloudWatch：POST https://monitoring.{region}.{分区后缀}/
 *    SigV4 service=monitoring；X-Amz-Target: GraniteServiceVersion20100801.GetMetricData，
 *    三条 SEARCH 表达式（{AWS/Bedrock,ModelId} 下模型名含 claude 的
 *    InputTokenCount / OutputTokenCount / Invocations，Sum 聚合、86400s 周期、回溯 14 天）→
 *    累加各指标 Values；该调用为尽力查询：失败（或 Messages 非空）只保留花费，不影响主结果。
 *
 * 展示映射（对照 BedrockUsageSnapshot.toUsageSnapshot()）：
 *   主窗口 = 月度预算使用率（未配置预算时无窗口，倒计时为下月首日 UTC）；
 *   费用卡 = 本月消费（USD）；明细 = 本月消费 / 月度预算 / 预算使用率 / 近 14 天 Claude
 *   输入·输出 tokens 与请求数 / 区域；身份行与源工程同构
 *   （Spend / Budget / Claude 14d tokens / Requests 拼接）。
 */

import { Http, HttpResult } from '../net/Http';
import { asArray, asObj, Json, optNum, parseJson, str } from '../net/Json';
import {
  AuthKind,
  extraValue,
  makeWindow,
  ProviderDescriptor,
  ProviderDetailRow,
  ProviderSetting,
  RateWindow,
  UsageSnapshot
} from '../model/Models';
import { UsageProvider } from './ProviderBase';
import { Format } from '../common/Format';
import { AwsCredentials, signAwsRequest } from '../common/AwsSign';

const CE_URL = 'https://ce.us-east-1.amazonaws.com/';
/** Cost Explorer 只有 us-east-1 端点（源工程固定 ceRegion = us-east-1） */
const CE_REGION = 'us-east-1';
const CE_TARGET = 'AWSInsightsIndexService.GetCostAndUsage';
const CE_CONTENT_TYPE = 'application/x-amz-json-1.1';
const CW_TARGET = 'GraniteServiceVersion20100801.GetMetricData';
const CW_CONTENT_TYPE = 'application/x-amz-json-1.0';
/** 仅计费（Cost Explorer）仍可用作 CloudWatch 端点的默认区域 */
const DEFAULT_REGION = 'us-east-1';
/** Claude 活动指标回溯天数（源工程 lookbackDays） */
const CW_LOOKBACK_DAYS = 14;
/** 分页上限（源工程 CloudWatch maxPages = 20） */
const MAX_PAGES = 20;

// ---------------------------------------------------------------------------
// 解析与端点（纯函数，本地单元测试覆盖）
// ---------------------------------------------------------------------------

export interface BedrockActivity {
  inputTokens: number;
  outputTokens: number;
  requestCount: number;
}

export interface BedrockMonthRange {
  start: string;
  end: string;
}

function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

/** Unix 毫秒 → yyyy-MM-dd（UTC） */
function utcDateKey(ms: number): string {
  const d = new Date(ms);
  return `${d.getUTCFullYear()}-${pad2(d.getUTCMonth() + 1)}-${pad2(d.getUTCDate())}`;
}

/** 计费查询区间：UTC 本月首日 → 明日（左闭右开，源工程 currentMonthRange） */
export function bedrockMonthRange(nowMs: number): BedrockMonthRange {
  const d = new Date(nowMs);
  const monthStart = Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1);
  const dayStart = Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate());
  return { start: utcDateKey(monthStart), end: utcDateKey(dayStart + 86400000) };
}

/** 预算窗口重置点：下月首日 00:00 UTC（源工程 endOfCurrentMonth） */
export function bedrockMonthEnd(nowMs: number): number {
  const d = new Date(nowMs);
  return Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 1);
}

/** CloudWatch 端点：区域格式非法返回空串（调用方跳过该查询） */
export function bedrockCloudWatchEndpoint(region: string): string {
  const pattern = new RegExp('^[a-z0-9]+(?:-[a-z0-9]+)+-[0-9]+$');
  if (pattern.exec(region) == null) {
    return '';
  }
  // 分区后缀与 AWS SDK 端点解析器公布的一致（源工程 endpoint(region:)）
  let suffix = 'amazonaws.com';
  if (region.startsWith('cn-')) {
    suffix = 'amazonaws.com.cn';
  } else if (region.startsWith('eusc-')) {
    suffix = 'amazonaws.eu';
  } else if (region.startsWith('us-iso-')) {
    suffix = 'c2s.ic.gov';
  } else if (region.startsWith('us-isob-')) {
    suffix = 'sc2s.sgov.gov';
  } else if (region.startsWith('eu-isoe-')) {
    suffix = 'cloud.adc-e.uk';
  } else if (region.startsWith('us-isof-')) {
    suffix = 'csp.hci.ic.gov';
  }
  return `https://monitoring.${region}.${suffix}`;
}

/** Cost Explorer 汇总：仅累加服务名含 "Bedrock" 的分组（UnblendedCost.Amount） */
export function bedrockTotalCost(json: Json): number {
  const root = asObj(json);
  const results = root != null ? asArray(root['ResultsByTime']) : null;
  if (results == null) {
    return 0;
  }
  let total = 0;
  for (let i = 0; i < results.length; i++) {
    const result = asObj(results[i]);
    const groups = result != null ? asArray(result['Groups']) : null;
    if (groups == null) {
      continue;
    }
    for (let g = 0; g < groups.length; g++) {
      const group = asObj(groups[g]);
      if (group == null) {
        continue;
      }
      const keys = asArray(group['Keys']);
      const first = keys != null && keys.length > 0 ? keys[0] : null;
      const serviceName = typeof first === 'string' ? first as string : '';
      if (serviceName.toLowerCase().indexOf('bedrock') < 0) {
        continue;
      }
      const metrics = asObj(group['Metrics']);
      const unblended = metrics != null ? asObj(metrics['UnblendedCost']) : null;
      const amount = unblended != null ? optNum(unblended, 'Amount') : null;
      if (amount != null && amount > 0) {
        total += amount;
      }
    }
  }
  return total;
}

/** 分页令牌（缺失/空串表示最后一页） */
export function bedrockNextPageToken(json: Json): string {
  const root = asObj(json);
  return root != null ? str(root, 'NextPageToken', '').trim() : '';
}

/** 账号未启用计费数据：HTTP 400 + DataUnavailableException（按 0 花费处理） */
export function bedrockDataUnavailable(code: number, body: string): boolean {
  if (code !== 400) {
    return false;
  }
  const root = asObj(parseJson(body));
  if (root == null) {
    return false;
  }
  const nested = asObj(root['Error']);
  const candidates: string[] = [
    str(root, '__type', ''),
    str(root, 'code', ''),
    str(root, 'Code', ''),
    nested != null ? str(nested, 'Code', '') : '',
  ];
  for (let i = 0; i < candidates.length; i++) {
    const raw = candidates[i].trim();
    if (raw.length === 0) {
      continue;
    }
    const parts = raw.split('#');
    if (parts[parts.length - 1] === 'DataUnavailableException') {
      return true;
    }
  }
  return false;
}

/** CloudWatch GetMetricData 结果 → Claude 活动；任一指标缺失/不完整/非数值返回 null */
export function bedrockClaudeActivity(json: Json): BedrockActivity | null {
  const root = asObj(json);
  if (root == null) {
    return null;
  }
  const messages = asArray(root['Messages']);
  if (messages != null && messages.length > 0) {
    return null;
  }
  const results = asArray(root['MetricDataResults']);
  if (results == null) {
    return null;
  }
  let input = 0;
  let output = 0;
  let requests = 0;
  for (let i = 0; i < results.length; i++) {
    const item = asObj(results[i]);
    if (item == null) {
      return null;
    }
    const id = str(item, 'Id', '');
    if (id !== 'inputTokens' && id !== 'outputTokens' && id !== 'requests') {
      return null;
    }
    if (str(item, 'StatusCode', '') !== 'Complete') {
      return null;
    }
    const values = asArray(item['Values']);
    if (values == null) {
      continue;
    }
    let sum = 0;
    for (let v = 0; v < values.length; v++) {
      const value = values[v];
      if (typeof value !== 'number') {
        return null;
      }
      const n = value as number;
      if (!(n >= 0) || !isFinite(n)) {
        return null;
      }
      sum += n;
    }
    if (id === 'inputTokens') {
      input += sum;
    } else if (id === 'outputTokens') {
      output += sum;
    } else {
      requests += sum;
    }
  }
  return {
    inputTokens: Math.round(input),
    outputTokens: Math.round(output),
    requestCount: Math.round(requests),
  };
}

/** 汇总 → 快照（对照 BedrockUsageSnapshot.toUsageSnapshot()） */
export function bedrockSnapshot(
  spend: number,
  budget: number,
  activity: BedrockActivity | null,
  region: string,
  now: number
): UsageSnapshot {
  const resetsAt = bedrockMonthEnd(now);
  const budgetPercent = budget > 0 ? Math.max(0, Math.min(100, (spend / budget) * 100)) : 0;
  const primary: RateWindow | null = budget > 0 ? makeWindow(budgetPercent, resetsAt, true) : null;

  const snap = UsageSnapshot.success(primary, null, null);
  // 泳道标签用元数据表里的 Budget（对照 BedrockProviderDescriptor.sessionLabel）；重置说明按月
  snap.providerCost = {
    remaining: budget > 0 ? Math.max(0, budget - spend) : 0,
    used: spend,
    currency: 'USD',
    displayText: Format.money(spend, 'USD'),
  };

  const rows: ProviderDetailRow[] = [
    { label: '本月消费', value: Format.money(spend, 'USD'), secondary: 'UnblendedCost（Bedrock）' },
  ];
  if (budget > 0) {
    rows.push({ label: '月度预算', value: Format.money(budget, 'USD') });
    rows.push({ label: '预算使用', value: Format.percent(budgetPercent) });
  }
  if (activity != null) {
    rows.push({ label: 'Claude 输入 tokens', value: Format.compact(activity.inputTokens) });
    rows.push({ label: 'Claude 输出 tokens', value: Format.compact(activity.outputTokens) });
    rows.push({ label: 'Claude 请求数', value: Format.compact(activity.requestCount) });
  }
  rows.push({ label: '区域', value: region });
  rows.push({ label: '统计区间', value: `${bedrockMonthRange(now).start} 起` });
  snap.details = [{ title: 'AWS Bedrock', rows: rows }];

  const loginParts: string[] = [`Spend: ${Format.money(spend, 'USD')}`];
  if (budget > 0) {
    loginParts.push(`Budget: ${Format.money(budget, 'USD')}`);
  }
  if (activity != null) {
    loginParts.push(`Claude 14d: ${Format.compact(activity.inputTokens + activity.outputTokens)} tokens`);
    loginParts.push(`Requests: ${Format.compact(activity.requestCount)}`);
  }
  snap.identity = {
    accountEmail: '',
    accountOrganization: region,
    loginMethod: loginParts.join(' · '),
  };
  return snap;
}

// ---------------------------------------------------------------------------
// 请求体
// ---------------------------------------------------------------------------

function ceBody(start: string, end: string, nextPageToken: string): string {
  const page = nextPageToken.length > 0
    ? `,"NextPageToken":${JSON.stringify(nextPageToken)}`
    : '';
  return '{"TimePeriod":{"Start":' + JSON.stringify(start) + ',"End":' + JSON.stringify(end) + '},' +
    '"Granularity":"MONTHLY","Metrics":["UnblendedCost"],' +
    '"GroupBy":[{"Type":"DIMENSION","Key":"SERVICE"}]' + page + '}';
}

function cwQuery(id: string, metricName: string): string {
  const expression =
    `SUM(SEARCH('{AWS/Bedrock,ModelId} MetricName="${metricName}" claude', 'Sum', 86400))`;
  return `{"Id":${JSON.stringify(id)},"Expression":${JSON.stringify(expression)},"ReturnData":true}`;
}

function cwBody(startMs: number, endMs: number, nextToken: string): string {
  const page = nextToken.length > 0 ? `,"NextToken":${JSON.stringify(nextToken)}` : '';
  return `{"StartTime":${Math.floor(startMs / 1000)},"EndTime":${Math.floor(endMs / 1000)},` +
    '"ScanBy":"TimestampAscending","MetricDataQueries":[' +
    cwQuery('inputTokens', 'InputTokenCount') + ',' +
    cwQuery('outputTokens', 'OutputTokenCount') + ',' +
    cwQuery('requests', 'Invocations') + ']' + page + '}';
}

/** AWS 错误体：优先展示服务端 message / Message，否则回退到本地化错误文案 */
function awsErrorText(resp: HttpResult): string {
  const root = asObj(resp.json());
  if (root != null) {
    const message = str(root, 'message', '').trim().length > 0
      ? str(root, 'message', '').trim()
      : str(root, 'Message', '').trim();
    if (message.length > 0) {
      return message.split('\n').join(' ').substring(0, 200);
    }
    const type = str(root, '__type', '').trim();
    if (type.length > 0) {
      const parts = type.split('#');
      return parts[parts.length - 1];
    }
  }
  return resp.errorText();
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

class BedrockProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'bedrock',
    title: 'AWS Bedrock',
    authKind: AuthKind.API_KEY,
    accentColor: '#FF9900',
    authHint: '第一栏填 AWS Access Key ID，第二栏填 Secret Access Key；Region / 预算填在下方输入框',
    authUrl: 'https://console.aws.amazon.com/iam/home#/security_credentials',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const accessKeyId = setting.credential.trim();
    const secretAccessKey = setting.credential2.trim();
    if (accessKeyId.length === 0) {
      return UsageSnapshot.failure('未配置 AWS Access Key ID');
    }
    if (secretAccessKey.length === 0) {
      return UsageSnapshot.failure('AWS Bedrock 需要 Access Key ID 与 Secret Access Key 一同填写');
    }

    const regionRaw = extraValue(setting.extraConfig, 'region').trim();
    const region = regionRaw.length > 0 ? regionRaw : DEFAULT_REGION;
    const sessionToken = extraValue(setting.extraConfig, 'sessionToken').trim();
    const budgetText = extraValue(setting.extraConfig, 'budget').trim();
    const budgetParsed = budgetText.length > 0 ? parseFloat(budgetText) : NaN;
    const budget = !isNaN(budgetParsed) && budgetParsed > 0 ? budgetParsed : 0;

    const credentials: AwsCredentials = {
      accessKeyId: accessKeyId,
      secretAccessKey: secretAccessKey,
      sessionToken: sessionToken,
    };
    const now = Date.now();

    const cost = await BedrockProvider.fetchMonthlyCost(credentials, now);
    if (cost.error.length > 0) {
      return UsageSnapshot.failure(cost.error);
    }
    // CloudWatch 为尽力查询：失败仅丢失 tokens / 请求数
    const activity = await BedrockProvider.fetchClaudeActivity(credentials, region, now);
    return bedrockSnapshot(cost.total, budget, activity, region, now);
  }

  /** Cost Explorer 本月花费（分页；未启用计费数据按 0） */
  private static async fetchMonthlyCost(
    credentials: AwsCredentials,
    now: number
  ): Promise<BedrockCostResult> {
    const range = bedrockMonthRange(now);
    const seen: string[] = [];
    let token = '';
    let total = 0;
    for (let page = 0; page < MAX_PAGES; page++) {
      const body = ceBody(range.start, range.end, token);
      const headers: Record<string, string> = {
        'content-type': CE_CONTENT_TYPE,
        'x-amz-target': CE_TARGET,
        'accept': 'application/json',
      };
      const sig = signAwsRequest(
        'POST', CE_URL, 'ce', CE_REGION, headers, body, credentials, now, true
      );
      const resp = await Http.post(CE_URL, sig.headers, body);
      if (!resp.ok) {
        if (bedrockDataUnavailable(resp.code, resp.body)) {
          return { total: 0, error: '' };
        }
        return { total: 0, error: `AWS Cost Explorer：${awsErrorText(resp)}` };
      }
      const json = resp.json();
      total += bedrockTotalCost(json);
      const next = bedrockNextPageToken(json);
      if (next.length === 0) {
        return { total: total, error: '' };
      }
      if (seen.indexOf(next) >= 0) {
        return { total: 0, error: 'AWS Cost Explorer 分页令牌重复' };
      }
      seen.push(next);
      token = next;
    }
    return { total: 0, error: 'AWS Cost Explorer 分页过多' };
  }

  /** CloudWatch 近 14 天 Claude 输入/输出 tokens 与请求数（失败返回 null） */
  private static async fetchClaudeActivity(
    credentials: AwsCredentials,
    region: string,
    now: number
  ): Promise<BedrockActivity | null> {
    const endpoint = bedrockCloudWatchEndpoint(region);
    if (endpoint.length === 0) {
      return null;
    }
    const startMs = now - CW_LOOKBACK_DAYS * 86400000;
    const seen: string[] = [];
    let token = '';
    let input = 0;
    let output = 0;
    let requests = 0;
    for (let page = 0; page < MAX_PAGES; page++) {
      const body = cwBody(startMs, now, token);
      const headers: Record<string, string> = {
        'content-type': CW_CONTENT_TYPE,
        'x-amz-target': CW_TARGET,
        'accept': 'application/json',
      };
      const sig = signAwsRequest(
        'POST', endpoint, 'monitoring', region, headers, body, credentials, now, true
      );
      const resp = await Http.post(endpoint, sig.headers, body);
      if (!resp.ok) {
        return null;
      }
      const json = resp.json();
      const activity = bedrockClaudeActivity(json);
      if (activity == null) {
        return null;
      }
      input += activity.inputTokens;
      output += activity.outputTokens;
      requests += activity.requestCount;
      const root = asObj(json);
      const next = root != null ? str(root, 'NextToken', '').trim() : '';
      if (next.length === 0) {
        return { inputTokens: input, outputTokens: output, requestCount: requests };
      }
      if (seen.indexOf(next) >= 0) {
        return null;
      }
      seen.push(next);
      token = next;
    }
    return null;
  }
}

/** Cost Explorer 查询结果（error 非空视为失败） */
class BedrockCostResult {
  total: number = 0;
  error: string = '';
}

export function createBedrockProvider(): UsageProvider {
  return new BedrockProvider();
}
