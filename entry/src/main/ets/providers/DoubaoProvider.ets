/**
 * 服务商第八批：Doubao（豆包 · 火山方舟编码计划 / Agent 计划）
 *
 * 对照 macOS 版 Providers/Doubao/{DoubaoUsageFetcher,DoubaoVolcengineSigner}.swift 迁移。
 * 移动端两种凭证模式（桌面版的 arkcli 本地 CLI 模式在移动端不适用）：
 *
 * 1) AK/SK 签名模式（第二凭证填 Secret Access Key 时启用）
 *    POST https://open.volcengineapi.com/ 火山引擎 Top OpenAPI（Volcengine V4 签名）
 *      - Action=GetCodingPlanUsage → 编码计划 5h/每周/月 配额（Result.QuotaUsage[]）
 *      - Action=GetAFPUsage       → Agent 计划（AFP）5h/每周/月（Result.AFP*，尽力查询）
 * 2) Ark API Key 探测模式（仅填第一凭证时启用）
 *    POST ark.cn-beijing.volces.com/api/coding/v3/chat/completions，
 *    读取 x-ratelimit-{limit,remaining,reset}-requests 响应头（接受 200/429；
 *    "连续两次 200 且剩余 0" 判定请求限额头不可信，与源工程一致）。
 *
 * 展示映射与源工程一致：编码计划占主/次/第三窗口，其余计划（Agent 计划、编码团队、
 * Agent 团队）进附加窗口。移动端补充：当编码计划缺失（如仅开 Agent 计划）时，
 * 由后续计划补位主窗口，避免仪表盘卡片空白；被补位的窗口不再在附加窗口中重复。
 */

import { Http, HttpResult } from '../net/Http';
import { asArray, asObj, Json, num, optNum, str } from '../net/Json';
import {
  AuthKind,
  makeWindow,
  NamedRateWindow,
  ProviderDescriptor,
  ProviderDetailRow,
  ProviderSetting,
  RateWindow,
  UsageSnapshot
} from '../model/Models';
import { UsageProvider } from './ProviderBase';
import { Format } from '../common/Format';
import { signVolcRequest, VolcCredentials } from '../common/VolcSign';

const DOUBAO_CODING_PLAN_URL =
  'https://open.volcengineapi.com/?Action=GetCodingPlanUsage&Version=2024-01-01';
const DOUBAO_AGENT_PLAN_URL =
  'https://open.volcengineapi.com/?Action=GetAFPUsage&Version=2024-01-01';
const DOUBAO_ARK_URL = 'https://ark.cn-beijing.volces.com/api/coding/v3/chat/completions';
/** 签名区域（源工程 DoubaoSettingsReader.defaultRegion 同值） */
const DOUBAO_REGION = 'cn-beijing';
/** 空请求体 + 表单型 Content-Type：与源工程签名时的头保持一致 */
const VOLC_CONTENT_TYPE = 'application/x-www-form-urlencoded; charset=utf-8';
/** 探测模型，按可用概率排序（不同 Key 权限不同） */
const DOUBAO_PROBE_MODELS: string[] = [
  'doubao-seed-2.0-code',
  'doubao-1.5-pro-32k',
  'doubao-lite-32k',
];

const FIVE_HOUR_LEVELS: string[] = ['session', '5-hour', 'five_hour', '5h'];
const WEEKLY_LEVELS: string[] = ['weekly', 'week'];
const MONTHLY_LEVELS: string[] = ['monthly', 'month'];

/** 计划档位：prefix 拼接到配额 level 前缀，id/title 用于附加窗口 */
interface DoubaoPlanSpec {
  prefix: string;
  id: string;
  title: string;
}

const DOUBAO_PLANS: DoubaoPlanSpec[] = [
  { prefix: '', id: '', title: '' },
  { prefix: 'agent_', id: 'doubao-agent', title: 'Agent 计划' },
  { prefix: 'coding_team_', id: 'doubao-coding-team', title: '编码团队' },
  { prefix: 'agent_team_', id: 'doubao-agent-team', title: 'Agent 团队' },
];

// ---------------------------------------------------------------------------
// 解析（纯函数，本地单元测试覆盖）
// ---------------------------------------------------------------------------

/** 单条配额：level 已小写，resetAt 为 Unix 毫秒（未知 0） */
export interface DoubaoQuota {
  level: string;
  percent: number;
  resetAt: number;
}

export interface DoubaoPlanMeta {
  status: string;
  updatedAt: number;
}

function clampPercent(value: number): number {
  if (!(value > 0)) {
    return 0;
  }
  return Math.min(100, value);
}

/** 秒/毫秒自适应 → Unix 毫秒（<=0 或缺失返回 0） */
export function doubaoEpochMs(value: number | null): number {
  if (value == null || value <= 0) {
    return 0;
  }
  return value >= 1e12 ? value : value * 1000;
}

/** 解析 GetCodingPlanUsage：Result.{Status,UpdateTimestamp,QuotaUsage[].{Level,Percent,ResetTimestamp}} */
export function doubaoCodingPlanMeta(json: Json): DoubaoPlanMeta {
  const root = asObj(json);
  const result = root != null ? asObj(root['Result']) : null;
  const meta: DoubaoPlanMeta = {
    status: result != null ? str(result, 'Status', '').trim() : '',
    updatedAt: result != null ? doubaoEpochMs(optNum(result, 'UpdateTimestamp')) : 0,
  };
  return meta;
}

export function doubaoQuotasFromCodingPlan(json: Json): DoubaoQuota[] {
  const out: DoubaoQuota[] = [];
  const root = asObj(json);
  const result = root != null ? asObj(root['Result']) : null;
  const list = result != null ? asArray(result['QuotaUsage']) : null;
  if (list == null) {
    return out;
  }
  for (let i = 0; i < list.length; i++) {
    const q = asObj(list[i]);
    if (q == null) {
      continue;
    }
    const level = str(q, 'Level', '').trim().toLowerCase();
    if (level.length === 0) {
      continue;
    }
    out.push({
      level: level,
      percent: clampPercent(num(q, 'Percent', 0)),
      resetAt: doubaoEpochMs(optNum(q, 'ResetTimestamp')),
    });
  }
  return out;
}

/** 解析 GetAFPUsage：Result.{AFPFiveHour,AFPWeekly,AFPMonthly}.{Quota,Used,ResetTime} → agent_* 档位 */
export function doubaoQuotasFromAgentPlan(json: Json): DoubaoQuota[] {
  const out: DoubaoQuota[] = [];
  const root = asObj(json);
  const result = root != null ? asObj(root['Result']) : null;
  if (result == null) {
    return out;
  }
  const keys: string[] = ['AFPFiveHour', 'AFPWeekly', 'AFPMonthly'];
  const levels: string[] = ['agent_5h', 'agent_weekly', 'agent_monthly'];
  for (let i = 0; i < keys.length; i++) {
    const w = asObj(result[keys[i]]);
    if (w == null) {
      continue;
    }
    const quota = num(w, 'Quota', 0);
    if (!(quota > 0)) {
      continue;
    }
    const used = num(w, 'Used', 0);
    out.push({
      level: levels[i],
      percent: clampPercent((used / quota) * 100),
      resetAt: doubaoEpochMs(optNum(w, 'ResetTime')),
    });
  }
  return out;
}

/** 取首个命中给定档位名的窗口（按配额顺序，与源工程 first(where:) 一致） */
function windowForLevels(quotas: DoubaoQuota[], levels: string[], minutes: number): RateWindow | null {
  for (let i = 0; i < quotas.length; i++) {
    if (levels.indexOf(quotas[i].level) >= 0) {
      return makeWindow(quotas[i].percent, quotas[i].resetAt, true);
    }
  }
  return null;
}

function prefixedLevels(prefix: string, levels: string[]): string[] {
  if (prefix.length === 0) {
    return levels;
  }
  const out: string[] = [];
  for (let i = 0; i < levels.length; i++) {
    out.push(prefix + levels[i]);
  }
  return out;
}

interface DoubaoPlanWindows {
  id: string;
  title: string;
  session: RateWindow | null;
  weekly: RateWindow | null;
  monthly: RateWindow | null;
}

/**
 * 配额 → 展示快照（主/次/第三窗口 + 附加计划窗口）。
 * 每档窗口取第一个可用计划（编码计划优先）；被主/次/第三档占用的窗口不再重复进附加窗口。
 */
export function doubaoSignedSnapshot(quotas: DoubaoQuota[], meta: DoubaoPlanMeta): UsageSnapshot {
  const plans: DoubaoPlanWindows[] = [];
  for (let i = 0; i < DOUBAO_PLANS.length; i++) {
    const spec = DOUBAO_PLANS[i];
    plans.push({
      id: spec.id,
      title: spec.title,
      session: windowForLevels(quotas, prefixedLevels(spec.prefix, FIVE_HOUR_LEVELS), 5 * 60),
      weekly: windowForLevels(quotas, prefixedLevels(spec.prefix, WEEKLY_LEVELS), 7 * 24 * 60),
      monthly: windowForLevels(quotas, prefixedLevels(spec.prefix, MONTHLY_LEVELS), 30 * 24 * 60),
    });
  }

  const usedSession = new Array<boolean>(plans.length);
  const usedWeekly = new Array<boolean>(plans.length);
  const usedMonthly = new Array<boolean>(plans.length);
  for (let i = 0; i < plans.length; i++) {
    usedSession[i] = false;
    usedWeekly[i] = false;
    usedMonthly[i] = false;
  }

  let primary: RateWindow | null = null;
  let secondary: RateWindow | null = null;
  let tertiary: RateWindow | null = null;
  for (let i = 0; i < plans.length; i++) {
    if (primary == null && plans[i].session != null) {
      primary = plans[i].session;
      usedSession[i] = true;
    }
  }
  for (let i = 0; i < plans.length; i++) {
    if (secondary == null && plans[i].weekly != null) {
      secondary = plans[i].weekly;
      usedWeekly[i] = true;
    }
  }
  for (let i = 0; i < plans.length; i++) {
    if (tertiary == null && plans[i].monthly != null) {
      tertiary = plans[i].monthly;
      usedMonthly[i] = true;
    }
  }

  // 附加窗口只来自非编码计划（索引 0 为编码计划，与源工程一致）
  const extras: NamedRateWindow[] = [];
  for (let i = 1; i < plans.length; i++) {
    const plan = plans[i];
    if (plan.session != null && !usedSession[i]) {
      extras.push({ id: `${plan.id}-session`, title: `${plan.title} 5 小时`, window: plan.session });
    }
    if (plan.weekly != null && !usedWeekly[i]) {
      extras.push({ id: `${plan.id}-weekly`, title: `${plan.title} 每周`, window: plan.weekly });
    }
    if (plan.monthly != null && !usedMonthly[i]) {
      extras.push({ id: `${plan.id}-monthly`, title: `${plan.title} 月度`, window: plan.monthly });
    }
  }

  const snap = UsageSnapshot.success(primary, secondary, tertiary);
  snap.extraRateWindows = extras;
  if (meta.updatedAt > 0) {
    snap.updatedAt = meta.updatedAt;
  }
  const rows: ProviderDetailRow[] = [];
  if (meta.status.length > 0) {
    rows.push({ label: '状态', value: meta.status });
  }
  if (meta.updatedAt > 0) {
    rows.push({ label: '更新于', value: Format.ago(meta.updatedAt) });
  }
  if (rows.length > 0) {
    snap.details = [{ title: '计划', rows: rows }];
  }
  if (meta.status.length > 0) {
    snap.identity = { accountEmail: '', accountOrganization: '', loginMethod: meta.status };
  }
  return snap;
}

// ---------------------------------------------------------------------------
// Ark API Key 探测（响应头解析）
// ---------------------------------------------------------------------------

export interface DoubaoProbeResult {
  window: RateWindow | null;
  keyValid: boolean;
  limitsReliable: boolean;
  /** HTTP 200 且限额可靠但剩余为 0：需二次探测确认 */
  ambiguousZero: boolean;
}

export function doubaoProbeResult(
  window: RateWindow | null,
  keyValid: boolean,
  limitsReliable: boolean,
  ambiguousZero: boolean
): DoubaoProbeResult {
  return {
    window: window,
    keyValid: keyValid,
    limitsReliable: limitsReliable,
    ambiguousZero: ambiguousZero,
  };
}

function headerInt(headers: Record<string, string>, name: string): number | null {
  const raw = headers[name];
  if (raw == null) {
    return null;
  }
  const parsed = parseInt(raw.trim(), 10);
  return isNaN(parsed) ? null : parsed;
}

/** 解析 x-ratelimit-reset-requests：ISO8601 / "1m30s" 时长 / 纯秒数 */
export function doubaoParseResetHeader(value: string, now: number): number {
  const trimmed = value.trim();
  if (trimmed.length === 0) {
    return 0;
  }
  const iso = Date.parse(trimmed);
  if (!isNaN(iso)) {
    return iso;
  }
  let seconds = 0;
  const matches = trimmed.match(/(\d+)([dhms])/g);
  if (matches != null) {
    for (let i = 0; i < matches.length; i++) {
      const m = matches[i];
      const amount = parseInt(m.substring(0, m.length - 1), 10);
      const unit = m.charAt(m.length - 1);
      if (isNaN(amount)) {
        continue;
      }
      if (unit === 'd') {
        seconds += amount * 86400;
      } else if (unit === 'h') {
        seconds += amount * 3600;
      } else if (unit === 'm') {
        seconds += amount * 60;
      } else {
        seconds += amount;
      }
    }
  }
  if (seconds > 0) {
    return now + seconds * 1000;
  }
  const plain = parseFloat(trimmed);
  if (!isNaN(plain)) {
    return now + plain * 1000;
  }
  return 0;
}

export function doubaoParseProbe(
  code: number,
  headers: Record<string, string>,
  now: number
): DoubaoProbeResult {
  const remaining = headerInt(headers, 'x-ratelimit-remaining-requests');
  const limit = headerInt(headers, 'x-ratelimit-limit-requests');
  const resetRaw = headers['x-ratelimit-reset-requests'];
  const resetAt = resetRaw != null ? doubaoParseResetHeader(resetRaw, now) : 0;

  // 429 说明 Key 有效但被限流；且 429 只要带 limit 头即可判定请求桶耗尽
  const keyValid = code === 200 || code === 429;
  const limitsReliable = code === 429
    ? limit != null
    : (limit != null && remaining != null);

  let window: RateWindow | null = null;
  if (limit != null && limit > 0 && limitsReliable) {
    const rem = remaining != null ? remaining : 0;
    const used = Math.max(0, limit - rem);
    window = makeWindow(clampPercent((used / limit) * 100), resetAt, true);
  }
  const remValue = remaining != null ? remaining : 0;
  const ambiguousZero =
    code === 200 && limitsReliable && limit != null && limit > 0 && remValue === 0;
  return doubaoProbeResult(window, keyValid, limitsReliable, ambiguousZero);
}

/** 探测结果 → 快照：限额可靠才给主窗口；Key 有效但无限额时给出说明行 */
export function doubaoProbeSnapshot(r: DoubaoProbeResult): UsageSnapshot {
  if (r.window != null) {
    return UsageSnapshot.success(r.window, null, null);
  }
  if (r.keyValid) {
    const snap = UsageSnapshot.success(null, null, null);
    snap.details = [{
      title: '说明',
      rows: [{ label: '请求额度', value: 'API Key 有效，但响应未携带请求限额' }],
    }];
    return snap;
  }
  return UsageSnapshot.failure('Ark API Key 无效或已过期');
}

function compactText(text: string, maxLength: number = 200): string {
  const collapsed = text.split('\n').join(' ').trim();
  if (collapsed.length <= maxLength) {
    return collapsed;
  }
  return `${collapsed.substring(0, maxLength)}...`;
}

/** 火山引擎 Top OpenAPI 错误体：ResponseMetadata.Error.{Code,Message}（Ark 侧为 error.message） */
export function doubaoApiErrorText(resp: HttpResult): string {
  const root = asObj(resp.json());
  if (root == null) {
    return resp.errorText();
  }
  const meta = asObj(root['ResponseMetadata']);
  if (meta != null) {
    const err = asObj(meta['Error']);
    if (err != null) {
      const code = str(err, 'Code', '').trim();
      const message = str(err, 'Message', '').trim();
      if (code.length > 0 && message.length > 0) {
        return compactText(`${code}: ${message}`);
      }
      if (code.length > 0) {
        return compactText(code);
      }
      if (message.length > 0) {
        return compactText(message);
      }
    }
  }
  const nested = asObj(root['error']);
  if (nested != null) {
    const message = str(nested, 'message', '').trim();
    if (message.length > 0) {
      return compactText(message);
    }
  }
  const message = str(root, 'message', '').trim();
  if (message.length > 0) {
    return compactText(message);
  }
  return resp.errorText();
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

class DoubaoProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'doubao',
    title: '豆包 · 火山方舟',
    authKind: AuthKind.API_KEY,
    accentColor: '#3370FF',
    authHint: '火山方舟 AK/SK（AK… + Secret Access Key 填第二栏）；或直接粘贴 Ark API Key',
    authUrl: 'https://console.volcengine.com/ark/region:ark+cn-beijing/openManagement?advancedActiveKey=subscribe',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const cred1 = setting.credential.trim();
    const cred2 = setting.credential2.trim();
    if (cred1.length === 0) {
      return UsageSnapshot.failure('未配置凭证');
    }
    if (cred2.length > 0) {
      return DoubaoProvider.fetchSignedPlan(cred1, cred2);
    }
    if (cred1.toUpperCase().startsWith('AK')) {
      return UsageSnapshot.failure('Access Key ID 需与 Secret Access Key 一同填写');
    }
    return DoubaoProvider.fetchArkProbe(cred1);
  }

  /** 每个请求单独签名（签名覆盖查询串，Action 不同则签名不同） */
  private static signedHeaders(
    url: string,
    credentials: VolcCredentials,
    now: number
  ): Record<string, string> {
    const sig = signVolcRequest('POST', url, VOLC_CONTENT_TYPE, '', credentials, now);
    const headers: Record<string, string> = {};
    const keys = Object.keys(sig.headers);
    for (let i = 0; i < keys.length; i++) {
      headers[keys[i]] = sig.headers[keys[i]];
    }
    headers['accept'] = 'application/json';
    return headers;
  }

  private static async fetchSignedPlan(ak: string, sk: string): Promise<UsageSnapshot> {
    const credentials: VolcCredentials = {
      accessKeyId: ak,
      secretAccessKey: sk,
      region: DOUBAO_REGION,
    };
    const now = Date.now();

    const codingResp = await Http.post(
      DOUBAO_CODING_PLAN_URL,
      DoubaoProvider.signedHeaders(DOUBAO_CODING_PLAN_URL, credentials, now),
      ''
    );
    if (!codingResp.ok) {
      return UsageSnapshot.failure(doubaoApiErrorText(codingResp));
    }
    const codingJson = codingResp.json();
    const meta = doubaoCodingPlanMeta(codingJson);
    const quotas = doubaoQuotasFromCodingPlan(codingJson);

    // Agent 计划（AFP）为同级尽力查询：未开通（403/404）静默忽略
    const agentResp = await Http.post(
      DOUBAO_AGENT_PLAN_URL,
      DoubaoProvider.signedHeaders(DOUBAO_AGENT_PLAN_URL, credentials, now),
      ''
    );
    if (agentResp.ok) {
      const agentQuotas = doubaoQuotasFromAgentPlan(agentResp.json());
      for (let i = 0; i < agentQuotas.length; i++) {
        quotas.push(agentQuotas[i]);
      }
    }

    if (quotas.length === 0) {
      const suffix = meta.status.length > 0 ? `（状态：${meta.status}）` : '';
      return UsageSnapshot.failure(`未获取到编码 / Agent 计划额度${suffix}`);
    }
    return doubaoSignedSnapshot(quotas, meta);
  }

  private static probe(apiKey: string, model: string): Promise<HttpResult> {
    const body =
      `{"model":${JSON.stringify(model)},"max_tokens":1,` +
      `"messages":[{"role":"user","content":"hi"}]}`;
    const headers: Record<string, string> = {
      'content-type': 'application/json',
      'accept': 'application/json',
      'authorization': `Bearer ${apiKey}`,
    };
    return Http.post(DOUBAO_ARK_URL, headers, body);
  }

  private static async fetchArkProbe(apiKey: string): Promise<UsageSnapshot> {
    const now = Date.now();
    let lastError = '';
    for (let i = 0; i < DOUBAO_PROBE_MODELS.length; i++) {
      const model = DOUBAO_PROBE_MODELS[i];
      const first = await DoubaoProvider.probe(apiKey, model);
      if (first.code !== 200 && first.code !== 429) {
        lastError = doubaoApiErrorText(first);
        // 该 Key 对此模型无权限：换下一个模型
        if (first.code === 403 || first.code === 404) {
          continue;
        }
        return UsageSnapshot.failure(lastError);
      }
      let result = doubaoParseProbe(first.code, first.headers, now);
      if (result.ambiguousZero) {
        // 连续两次 200 + 剩余 0：请求限额头不可信（源工程同款判定）
        const second = await DoubaoProvider.probe(apiKey, model);
        const parsed = doubaoParseProbe(second.code, second.headers, now);
        if (second.code === 429) {
          result = parsed.limitsReliable ? parsed : result;
        } else {
          result = parsed.ambiguousZero
            ? doubaoProbeResult(null, parsed.keyValid, false, false)
            : parsed;
        }
      }
      return doubaoProbeSnapshot(result);
    }
    return UsageSnapshot.failure(lastError.length > 0 ? lastError : '所有探测模型均不可用');
  }
}

export function createDoubaoProvider(): UsageProvider {
  return new DoubaoProvider();
}
