/**
 * CodexBar Mobile — 核心数据模型
 *
 * 从 macOS 版 CodexBar (Swift) 的 UsageSnapshot / RateWindow / NamedRateWindow
 * (Sources/CodexBarCore/UsageFetcher.swift) 迁移而来，保留原字段语义，
 * 按移动端场景裁剪为可序列化的 ArkTS 接口。
 */

/** 单个用量窗口（如 5 小时会话窗 / 每周窗 / 每月窗） */
export interface RateWindow {
  /** 已用百分比 0-100；usageKnown=false 时可能为 0 占位 */
  usedPercent: number;
  /** 窗口重置时间（Unix 毫秒），未知为 0 */
  resetsAt: number;
  /** 用量是否已知（部分服务商会先给重置时间，再给用量） */
  usageKnown: boolean;
}

/** 带名称的附加窗口（对应 Swift NamedRateWindow） */
export interface NamedRateWindow {
  id: string;
  title: string;
  window: RateWindow;
}

/** 费用/余额快照（对应 Swift ProviderCostSnapshot） */
export interface ProviderCostSnapshot {
  /** 剩余额度/余额（服务商主币种）；对应 Swift ProviderCostSnapshot.balance */
  remaining: number;
  /** 已使用 */
  used: number;
  /** 货币单位，如 USD / CNY */
  currency: string;
  /** 展示文本，如 "$12.34"（首页卡片与详情页大号数字都用它，所以保持短小） */
  displayText: string;
  /** 详情页补充说明（可空；为空时详情页不加说明行）：
   *  例如 DeepSeek 的 macOS 原句 "¥12.00 (Paid: ¥10.00 / Granted: ¥2.00)" —— 首页只显示 displayText */
  detailText?: string;
  /** 费用周期文案（对应 Swift ProviderCostSnapshot.period，如 "Monthly cap" / "Extra usage"）：
   *  非空时详情页用它作为费用分组标题 */
  period?: string;
  /** 周期上限（对应 Swift ProviderCostSnapshot.limit；0 表示无上限概念） */
  limit?: number;
}

/** 账号身份信息（对应 Swift ProviderIdentitySnapshot） */
export interface ProviderIdentitySnapshot {
  accountEmail: string;
  accountOrganization: string;
  loginMethod: string;
}

/**
 * 行内进度条的数值（对应 Swift ProviderDetailSection.Row.Progress）。
 * 约定与源工程一致：`usedPercent` **不截断**（超额计划可以 > 100），截断由渲染端负责。
 */
export interface RowProgress {
  used: number;
  total: number;
}

/** 明细行 */
export interface ProviderDetailRow {
  label: string;
  value: string;
  /** 可选副文本（对应 macOS 版 ProviderDetailSection.Row.secondaryValue） */
  secondary?: string;
  /** 可选行内进度条（对应 Row.progress，只有分子分母都已知时才有） */
  progress?: RowProgress;
}

/**
 * 构造行进度（对照 Row.Progress.init）：两个数必须有限，分母必须 > 0，
 * 否则返回 undefined（源工程这里是 throws，调用方一律 try? 成 nil）。
 */
export function rowProgress(used: number, total: number): RowProgress | undefined {
  if (!isFinite(used) || !isFinite(total) || total <= 0) {
    return undefined;
  }
  return { used: used, total: total };
}

/** 行进度百分比（不截断，对照 Row.Progress.usedPercent） */
export function progressPercent(p: RowProgress): number {
  const value = (p.used / p.total) * 100;
  return isFinite(value) ? value : 0;
}

/** 图表数据点（对应 Swift ProviderDetailSection.Chart.Point） */
export interface ProviderChartPoint {
  label: string;
  value: number;
}

/**
 * 明细分组内的图表（对应 Swift ProviderDetailSection.Chart）：
 * kind 为 "bars"（默认）或 "line"，points 最多保留 120 条（与源工程上限一致）。
 */
export interface ProviderChart {
  kind: string;
  title?: string;
  unit?: string;
  points: ProviderChartPoint[];
}

/** 明细分组（对应 Swift ProviderDetailSection） */
export interface ProviderDetailSection {
  title: string;
  rows: ProviderDetailRow[];
  chart?: ProviderChart;
}

/** 图表点数上限（对照 ProviderDetailSection.maximumPointsPerChart） */
export const MAX_CHART_POINTS: number = 120;

/** 构造图表：裁到 120 点、丢掉 NaN/Infinity（对照 makeChart） */
export function makeChart(
  title: string,
  unit: string,
  points: ProviderChartPoint[],
  kind: string = 'bars'
): ProviderChart {
  const out: ProviderChartPoint[] = [];
  const limit = points.length > MAX_CHART_POINTS ? MAX_CHART_POINTS : points.length;
  for (let i = 0; i < limit; i++) {
    const p = points[i];
    if (!isNaN(p.value) && isFinite(p.value)) {
      out.push({ label: p.label, value: p.value });
    }
  }
  return { kind: kind, title: title, unit: unit, points: out };
}

/** 缓存 JSON 的宽松形态：旧版本写入的快照可能缺少后加的字段（如窗口展示名） */
interface StoredSnapshot {
  primary?: RateWindow | null;
  secondary?: RateWindow | null;
  tertiary?: RateWindow | null;
  primaryLabel?: string;
  secondaryLabel?: string;
  tertiaryLabel?: string;
  extraRateWindows?: NamedRateWindow[];
  providerCost?: ProviderCostSnapshot | null;
  details?: ProviderDetailSection[];
  identity?: ProviderIdentitySnapshot | null;
  updatedAt?: number;
  ok?: boolean;
  error?: string;
}

function storedText(value: string | undefined, dflt: string): string {
  return typeof value === 'string' ? value : dflt;
}

/**
 * 图表还原：旧缓存没有 chart 字段，或点序列损坏时按「无图表」处理。
 * UI 直接读 chart.points.length，缺字段会崩，所以缓存入口必须过滤。
 */
function storedChart(value: ProviderChart | undefined | null): ProviderChart | undefined {
  if (value == null || !Array.isArray(value.points)) {
    return undefined;
  }
  const points: ProviderChartPoint[] = [];
  for (let i = 0; i < value.points.length && points.length < MAX_CHART_POINTS; i++) {
    const p = value.points[i];
    if (p == null || typeof p.label !== 'string' || typeof p.value !== 'number') {
      continue;
    }
    if (!isNaN(p.value) && isFinite(p.value)) {
      points.push({ label: p.label, value: p.value });
    }
  }
  return {
    kind: value.kind === 'line' ? 'line' : 'bars',
    title: typeof value.title === 'string' ? value.title : '',
    unit: typeof value.unit === 'string' ? value.unit : '',
    points: points,
  };
}

/** 明细分组还原：逐字段校验，损坏的分组/行直接丢弃（避免 UI 读取 undefined） */
function storedDetails(value: ProviderDetailSection[] | undefined): ProviderDetailSection[] {
  if (value == null || !Array.isArray(value)) {
    return [];
  }
  const out: ProviderDetailSection[] = [];
  for (let i = 0; i < value.length; i++) {
    const sec = value[i];
    if (sec == null || typeof sec.title !== 'string' || sec.title.length === 0) {
      continue;
    }
    const rows: ProviderDetailRow[] = [];
    const rawRows = sec.rows;
    if (Array.isArray(rawRows)) {
      for (let j = 0; j < rawRows.length; j++) {
        const r = rawRows[j];
        if (r == null || typeof r.label !== 'string' || typeof r.value !== 'string') {
          continue;
        }
        const row: ProviderDetailRow = { label: r.label, value: r.value };
        if (typeof r.secondary === 'string') {
          row.secondary = r.secondary;
        }
        // 进度条：非法数值（分母 ≤0 / 非有限数）按无进度条处理
        const rawProgress = r.progress;
        if (rawProgress != null && typeof rawProgress.used === 'number' && typeof rawProgress.total === 'number') {
          const progress = rowProgress(rawProgress.used, rawProgress.total);
          if (progress != null) {
            row.progress = progress;
          }
        }
        rows.push(row);
      }
    }
    const chart = storedChart(sec.chart);
    if (rows.length === 0 && chart == null) {
      continue;
    }
    out.push(chart != null ? { title: sec.title, rows: rows, chart: chart } : { title: sec.title, rows: rows });
  }
  return out;
}

/** 还原单个窗口：字段缺失时按不可知处理（0% / 未重置/已重置） */
function storedWindow(w: RateWindow | null | undefined): RateWindow | null {
  if (w == null) {
    return null;
  }
  return makeWindow(
    typeof w.usedPercent === 'number' ? w.usedPercent : 0,
    typeof w.resetsAt === 'number' ? w.resetsAt : 0,
    w.usageKnown == null ? true : w.usageKnown
  );
}

/** 用量快照：一个服务商一次查询的完整结果 */
export class UsageSnapshot {
  primary: RateWindow | null = null;
  secondary: RateWindow | null = null;
  tertiary: RateWindow | null = null;
  /** 主/次/第三窗口的展示名（对应 macOS 版 ProviderMetadata 的 sessionLabel/weeklyLabel/opusLabel）；
   *  为空时 UI 回退到「会话 / 每周 / 第三窗口」 */
  primaryLabel: string = '';
  secondaryLabel: string = '';
  tertiaryLabel: string = '';
  extraRateWindows: NamedRateWindow[] = [];
  providerCost: ProviderCostSnapshot | null = null;
  details: ProviderDetailSection[] = [];
  identity: ProviderIdentitySnapshot | null = null;
  /** 快照生成时间（Unix 毫秒） */
  updatedAt: number = Date.now();
  /** 查询是否成功 */
  ok: boolean = true;
  /** 失败信息 */
  error: string = '';

  static success(
    primary: RateWindow | null,
    secondary: RateWindow | null,
    tertiary: RateWindow | null
  ): UsageSnapshot {
    const s = new UsageSnapshot();
    s.primary = primary;
    s.secondary = secondary;
    s.tertiary = tertiary;
    s.updatedAt = Date.now();
    s.ok = true;
    return s;
  }

  static failure(message: string): UsageSnapshot {
    const s = new UsageSnapshot();
    s.ok = false;
    s.error = message;
    s.updatedAt = Date.now();
    return s;
  }

  /**
   * 从持久化缓存还原快照。
   *
   * 直接 `JSON.parse(text) as UsageSnapshot` 得到的普通对象会丢掉类字段默认值：
   * 旧版本写入的缓存没有 primaryLabel 等后加字段，UI 读 `.length` 会直接崩溃，
   * 因此统一走这里逐字段补齐（缺失字段回落到类默认值）。
   */
  static fromStored(text: string): UsageSnapshot | null {
    let parsed: StoredSnapshot | null = null;
    try {
      parsed = JSON.parse(text) as StoredSnapshot;
    } catch (e) {
      return null;
    }
    if (parsed == null || typeof parsed !== 'object') {
      return null;
    }
    const s = new UsageSnapshot();
    s.primary = storedWindow(parsed.primary);
    s.secondary = storedWindow(parsed.secondary);
    s.tertiary = storedWindow(parsed.tertiary);
    s.primaryLabel = storedText(parsed.primaryLabel, '');
    s.secondaryLabel = storedText(parsed.secondaryLabel, '');
    s.tertiaryLabel = storedText(parsed.tertiaryLabel, '');
    s.extraRateWindows = parsed.extraRateWindows == null ? [] : parsed.extraRateWindows;
    s.providerCost = parsed.providerCost == null ? null : parsed.providerCost;
    s.details = storedDetails(parsed.details);
    s.identity = parsed.identity == null ? null : parsed.identity;
    s.updatedAt = typeof parsed.updatedAt === 'number' ? parsed.updatedAt : Date.now();
    // 旧缓存缺 ok 字段时按成功处理（失败快照没必要长期保留）
    s.ok = parsed.ok == null ? true : parsed.ok;
    s.error = storedText(parsed.error, '');
    return s;
  }
}

/** 服务商认证方式（API Key 与网页登录两条线并存） */
export enum AuthKind {
  /** Bearer API Key（用户在设置里粘贴 sk-xxx） */
  API_KEY = 0,
  /** Web 会话 Cookie（如 claude.ai sessionKey） */
  SESSION = 1,
  /** OAuth 访问令牌（如 ChatGPT backend-api access token） */
  OAUTH_TOKEN = 2,
  /** 演示模式，无需认证 */
  DEMO = 3,
}

/** 窗口语义，用于 UI 图标与排序 */
export enum WindowKind {
  SESSION = 'session',
  WEEKLY = 'weekly',
  MONTHLY = 'monthly',
  BALANCE = 'balance',
}

/** 服务商描述符（对应 Swift ProviderDescriptor） */
export interface ProviderDescriptor {
  /** 稳定 ID，如 "claude" "deepseek" */
  id: string;
  /** 展示名 */
  title: string;
  /** 认证方式 */
  authKind: AuthKind;
  /** 品牌强调色（ARGB Hex 字符串） */
  accentColor: string;
  /** 认证提示（设置页 placeholder / 说明） */
  authHint: string;
  /** 获取凭证的说明链接（可为空串） */
  authUrl: string;
}

/** 用户为某服务商保存的配置 */
export interface ProviderSetting {
  enabled: boolean;
  /** API Key / access token */
  credential: string;
  /**
   * 第二凭证（如组织 / 账号 ID / Secret Access Key）。
   * 也用于存放自动获取的网页会话（如 DeepSeek 平台会话）：这类值不由用户手填，
   * 因此不进 needsSecondCredential，界面上没有输入框。
   */
  credential2: string;
  /** 额外字段（JSON 对象文本，键见 extraFields(providerId)，如 Azure endpoint / Bedrock region） */
  extraConfig: string;
}

/** 服务商额外配置输入框（第 3 个及以后；现有两栏不够时使用） */
export interface ExtraField {
  /** extraConfig JSON 中的键 */
  key: string;
  /** 输入框提示 */
  hint: string;
}

/** 需要额外字段的服务商字段表；未列出的服务商返回空数组 */
export function extraFields(providerId: string): ExtraField[] {
  if (providerId === 'azure-openai') {
    return [
      { key: 'endpoint', hint: 'Endpoint（如 https://my-res.openai.azure.com）' },
      { key: 'deployment', hint: 'Deployment 名称' },
      { key: 'apiVersion', hint: 'API 版本，默认 2024-10-21；填 v1 走新版接口' },
    ];
  }
  if (providerId === 'bedrock') {
    return [
      { key: 'region', hint: 'AWS 区域，默认 us-east-1' },
      { key: 'sessionToken', hint: '可选：AWS_SESSION_TOKEN' },
      { key: 'budget', hint: '可选：月度预算（美元，用于展示预算进度）' },
    ];
  }
  if (providerId === 'v0') {
    return [{ key: 'scope', hint: '可选：项目 ID 或 slug' }];
  }
  if (providerId === 'copilot') {
    return [
      { key: 'enterpriseHost', hint: '可选：GitHub Enterprise 域名（默认 github.com）' },
      { key: 'seatEntitlement', hint: '可选：席位包含额度（分母，用于明细行的用量进度条）' },
    ];
  }
  return [];
}

/** 解析 extraConfig JSON；损坏或为空返回空对象 */
export function parseExtra(text: string): Record<string, string> {
  const out: Record<string, string> = {};
  if (text == null || text.length === 0) {
    return out;
  }
  try {
    const obj = JSON.parse(text) as Record<string, string>;
    if (obj == null) {
      return out;
    }
    const keys = Object.keys(obj);
    for (let i = 0; i < keys.length; i++) {
      const v = obj[keys[i]];
      if (typeof v === 'string') {
        out[keys[i]] = (v as string).trim();
      }
    }
  } catch (e) {
    return {};
  }
  return out;
}

/** 取 extraConfig 中某个键（缺省为空串） */
export function extraValue(text: string, key: string): string {
  const map = parseExtra(text);
  const v = map[key];
  return v == null ? '' : v;
}

/** 写 extraConfig 单个键（返回新 JSON 文本） */
export function setExtraValue(text: string, key: string, value: string): string {
  const map = parseExtra(text);
  map[key] = value;
  return JSON.stringify(map);
}

/** 单服务商的额度提醒配置（详情页"提醒设置"卡片） */
export interface ReminderConfig {
  /** 总开关 */
  enabled: boolean;
  /** 任一窗口用量达到该百分比时提醒；0 表示关闭用量提醒 */
  usageThreshold: number;
  /** 重置前多少分钟提醒；0 表示关闭恢复提醒 */
  resetLeadMinutes: number;
}

/** 服务商的一个账号（多账号切换，对应 macOS 版 Managed Accounts） */
export interface ProviderAccount {
  /** 账号 ID（登录时间戳生成，稳定） */
  aid: string;
  /** 显示名（自动编号"账号 N"） */
  name: string;
  /** API Key / sessionKey / access token */
  credential: string;
  /**
   * 第二凭证（如组织 / 账号 ID / Secret Access Key）。
   * 也用于存放自动获取的网页会话（如 DeepSeek 平台会话）：这类值不由用户手填，
   * 因此不进 needsSecondCredential，界面上没有输入框。
   */
  credential2: string;
  /** OAuth refresh token（Codex 等网页登录服务商，其余为空） */
  refreshToken: string;
  /** 额外字段（JSON 对象文本，见 extraFields） */
  extraConfig: string;
}

/** 用量历史的单日聚合记录（当日最后一条成功样本；移动端为刷新采样估算） */
export interface HistoryDay {
  /** 本地日期键 YYYY-MM-DD */
  d: string;
  /** 当日最后的主窗口用量 %（无主窗口取第一个可用窗口） */
  p: number;
  /** 当日最后的余额（providerCost.remaining），-1 表示不可得 */
  b: number;
}

/**
 * 是否默认启用（对照 macOS ProviderMetadata.defaultEnabled）。
 * 源工程里只有 Codex 声明了 defaultEnabled: true，其余均需用户自行开启。
 */
export function isDefaultEnabledProvider(providerId: string): boolean {
  return providerId === 'codex';
}

/**
 * 是否为菜单栏主选服务商（对照 macOS ProviderMetadata.isPrimaryProvider）。
 * 源工程：Claude 与 Codex。
 */
export function isPrimaryProvider(providerId: string): boolean {
  return providerId === 'claude' || providerId === 'codex';
}

/**
 * 窗口标签（对照 macOS ProviderMetadata 的 sessionLabel / weeklyLabel / opusLabel）。
 * 空串表示源工程未定义该窗口。
 */
export class WindowLabels {
  primary: string = '';
  secondary: string = '';
  tertiary: string = '';
}

/**
 * 服务商窗口标签表：逐条抄自源工程各 ProviderDescriptor 的 metadata。
 * 未登记的服务商返回全空（UI 回落「会话 / 每周 / 第三窗口」）。
 */
export function windowLabelsFor(providerId: string): WindowLabels {
  const l = new WindowLabels();
  if (providerId === 'claude') {
    l.primary = 'Session'; l.secondary = 'Weekly'; l.tertiary = 'Sonnet';
  } else if (providerId === 'codex') {
    l.primary = 'Session'; l.secondary = 'Weekly';
  } else if (providerId === 'openai') {
    l.primary = 'Spend'; l.secondary = 'Requests';
  } else if (providerId === 'openrouter') {
    l.primary = 'Credits'; l.secondary = 'Usage';
  } else if (providerId === 'deepseek') {
    l.primary = 'Balance'; l.secondary = 'Balance';
  } else if (providerId === 'moonshot') {
    l.primary = 'Balance'; l.secondary = 'Balance';
  } else if (providerId === 'kimi-coding') {
    l.primary = '7-day usage'; l.secondary = '5-hour usage';
  } else if (providerId === 'zenmux') {
    l.primary = '5-hour quota'; l.secondary = 'Weekly quota';
  } else if (providerId === 'manus') {
    l.primary = 'Monthly credits'; l.secondary = 'Daily refresh';
  } else if (providerId === 'deepinfra') {
    l.primary = 'Balance'; l.secondary = 'Balance';
  } else if (providerId === 'perplexity') {
    l.primary = 'Credits'; l.secondary = 'Bonus credits'; l.tertiary = 'Purchased';
  } else if (providerId === 'chutes') {
    l.primary = '4-hour quota'; l.secondary = 'Monthly quota';
  } else if (providerId === 'minimax') {
    l.primary = 'Prompts'; l.secondary = 'Window';
  } else if (providerId === 'mimo') {
    l.primary = 'Credits'; l.secondary = 'Window';
  } else if (providerId === 'mistral') {
    l.primary = 'Balance';
  } else if (providerId === 'kilo') {
    l.primary = 'Credits'; l.secondary = 'Kilo Pass';
  } else if (providerId === 'poe') {
    l.primary = 'Points'; l.secondary = 'Points';
  } else if (providerId === 't3chat') {
    l.primary = 'Base'; l.secondary = 'Overage';
  } else if (providerId === 'zai') {
    l.primary = '5-hour'; l.secondary = 'Weekly';
  } else if (providerId === 'xai') {
    l.primary = 'Spend'; l.secondary = 'Spend';
  } else if (providerId === 'qoder') {
    l.primary = 'Credits'; l.secondary = 'Balance';
  } else if (providerId === 'venice') {
    l.primary = 'Balance'; l.secondary = 'Balance';
  } else if (providerId === 'nous') {
    l.primary = 'Monthly credits'; l.secondary = 'Weekly';
  } else if (providerId === 'muse') {
    l.primary = '5 hours'; l.secondary = 'Weekly';
  } else if (providerId === 'deepgram') {
    l.primary = 'Requests'; l.secondary = 'Usage';
  } else if (providerId === 'clinepass') {
    l.primary = '5-hour'; l.secondary = 'Weekly'; l.tertiary = 'Monthly';
  } else if (providerId === 'synthetic') {
    l.primary = 'Five-hour quota'; l.secondary = 'Weekly tokens'; l.tertiary = 'Search hourly';
  } else if (providerId === 'clawrouter') {
    l.primary = 'Monthly budget'; l.secondary = 'Requests';
  } else if (providerId === 'litellm') {
    l.primary = 'Personal budget'; l.secondary = 'Team budget';
  } else if (providerId === 'llmproxy') {
    l.primary = 'Quota'; l.secondary = 'Requests';
  } else if (providerId === 'elevenlabs') {
    l.primary = 'Credits'; l.secondary = 'Voices';
  } else if (providerId === 'fireworks') {
    l.primary = 'Spend'; l.secondary = 'Spend';
  } else if (providerId === 'neuralwatt') {
    l.primary = 'Subscription'; l.secondary = 'Key allowance';
  } else if (providerId === 'ibmbob') {
    l.primary = 'Monthly Bobcoins'; l.secondary = 'Monthly Bobcoins';
  } else if (providerId === 'aiand') {
    l.primary = 'Spend'; l.secondary = 'Spend';
  } else if (providerId === 'codebuff') {
    l.primary = 'Credits'; l.secondary = 'Weekly';
  } else if (providerId === 'sub2api') {
    l.primary = 'Quota'; l.secondary = 'Weekly quota'; l.tertiary = 'Monthly quota';
  } else if (providerId === 'devin') {
    l.primary = 'Daily'; l.secondary = 'Weekly';
  } else if (providerId === 'abacus') {
    l.primary = 'Credits'; l.secondary = 'Weekly';
  } else if (providerId === 'commandcode') {
    l.primary = '5-hour'; l.secondary = 'Weekly'; l.tertiary = 'Monthly';
  } else if (providerId === 'longcat') {
    l.primary = 'Quota'; l.secondary = 'Fuel Pack';
  } else if (providerId === 'zoommate') {
    l.primary = 'Credits'; l.secondary = 'Credits';
  } else if (providerId === 'notion') {
    l.primary = 'Rolling'; l.secondary = 'Monthly';
  } else if (providerId === 'huggingface') {
    l.primary = 'Inference'; l.secondary = 'ZeroGPU';
  } else if (providerId === 'warp') {
    l.primary = 'Credits'; l.secondary = 'Add-on credits';
  } else if (providerId === 'opencode') {
    l.primary = '5-hour'; l.secondary = 'Weekly';
  } else if (providerId === 'opencodego') {
    l.primary = '5-hour'; l.secondary = 'Weekly'; l.tertiary = 'Monthly';
  } else if (providerId === 'groq') {
    l.primary = 'Requests'; l.secondary = 'Tokens';
  } else if (providerId === 'alibaba-coding') {
    l.primary = '5-hour'; l.secondary = 'Weekly'; l.tertiary = 'Monthly';
  } else if (providerId === 'factory') {
    l.primary = 'Standard'; l.secondary = 'Premium';
  } else if (providerId === 'doubao') {
    l.primary = '5-hour'; l.secondary = 'Weekly'; l.tertiary = 'Monthly';
  } else if (providerId === 'bedrock') {
    l.primary = 'Budget'; l.secondary = 'Cost';
  } else if (providerId === 'azure-openai') {
    l.primary = 'Status'; l.secondary = 'Deployment';
  } else if (providerId === 'ollama') {
    l.primary = 'Session'; l.secondary = 'Weekly';
  } else if (providerId === 'copilot') {
    l.primary = 'Premium'; l.secondary = 'Chat';
  } else if (providerId === 'v0') {
    l.primary = 'Billing'; l.secondary = 'Rate limit';
  }
  return l;
}

/**
 * 用元数据补齐快照里为空的窗口标签（服务商显式设置的标签优先，不被覆盖）。
 * 在所有快照落地处调用一次即可：缓存回放与刷新成功后。
 */
export function applyWindowLabels(snap: UsageSnapshot, providerId: string): void {
  const l = windowLabelsFor(providerId);
  if (snap.primary != null && snap.primaryLabel.length === 0) {
    snap.primaryLabel = l.primary;
  }
  if (snap.secondary != null && snap.secondaryLabel.length === 0) {
    snap.secondaryLabel = l.secondary;
  }
  if (snap.tertiary != null && snap.tertiaryLabel.length === 0) {
    snap.tertiaryLabel = l.tertiary;
  }
}

/**
 * 明细可见性策略（对照 macOS ProviderOptionalDetailsPresentation）。
 * 三家字段的语义与源工程一致：
 * - hidesAllWithoutOptionalUsage：关闭「可选用量明细」时整块隐藏全部明细分组
 * - hiddenTitlesWithoutOptionalUsage：关闭时只隐藏列出的分组
 * - costSummaryTitles：这些分组由费用卡承载（用量项选择器里不单独列出）
 */
export interface OptionalDetailsPolicy {
  hidesAllWithoutOptionalUsage: boolean;
  hiddenTitlesWithoutOptionalUsage: string[];
  costSummaryTitles: string[];
}

/** 明细可见性策略表（源工程只有这 8 家显式声明，其余全为默认空策略） */
export function optionalDetailsFor(providerId: string): OptionalDetailsPolicy {
  const p: OptionalDetailsPolicy = {
    hidesAllWithoutOptionalUsage: false,
    hiddenTitlesWithoutOptionalUsage: [],
    costSummaryTitles: [],
  };
  switch (providerId) {
    case 'anthropic-console':
      // ClaudeProviderDescriptor: costSummaryTitles ["Usage summary", "Cost items"]
      p.costSummaryTitles = ['Usage summary', 'Cost items'];
      break;
    case 'groq':
      // GroqProviderDescriptor: costSummaryTitles ["Usage summary"]
      p.costSummaryTitles = ['Usage summary'];
      break;
    case 'minimax':
      // MiniMaxProviderDescriptor: hiddenTitlesWithoutOptionalUsage/costSummaryTitles ["Billing history"]
      p.hiddenTitlesWithoutOptionalUsage = ['Billing history'];
      p.costSummaryTitles = ['Billing history'];
      break;
    case 'deepseek':
      // DeepSeekProviderDescriptor: hidesAll + costSummaryTitles ["Usage", "Spend"]
      p.hidesAllWithoutOptionalUsage = true;
      p.costSummaryTitles = ['Usage', 'Spend'];
      break;
    case 'xai':
      // XAIProviderDescriptor: costSummaryTitles ["Billing summary"]
      p.costSummaryTitles = ['Billing summary'];
      break;
    case 'openai':
      // OpenAIAPIProviderDescriptor: costSummaryTitles ["Usage summary"]
      p.costSummaryTitles = ['Usage summary'];
      break;
    case 'zai':
      // ZaiProviderDescriptor: costSummaryTitles ["Hourly tokens", "Daily tokens"]
      p.costSummaryTitles = ['Hourly tokens', 'Daily tokens'];
      break;
    default:
      break;
  }
  return p;
}

/**
 * 费用卡已展示时需要从明细里删掉的重复行（对照 ProviderCostPresentation.replacedDetailRows）。
 * 键为分组标题，值为要删除的行标签；费用卡不可见时返回空表。
 * - OpenRouter：余额行 / 本月 API key 花费 / 账户总用量
 * - TypeSafe（本工程未实现）：账单页花费行
 */
export function replacedDetailRowsFor(providerId: string, costVisible: boolean): Record<string, string[]> {
  const empty: Record<string, string[]> = {};
  if (!costVisible) {
    return empty;
  }
  const out: Record<string, string[]> = {};
  if (providerId === 'openrouter') {
    out['Credits'] = ['Remaining', 'Used'];
    out['API key'] = ['This month'];
  }
  return out;
}

/**
 * 按策略过滤明细分组（对照 macOS visibleProviderDetails 的两段 gating）：
 * 1. 费用卡可见时移除被费用卡承载的重复行
 * 2. 关闭「可选用量明细」时按策略隐藏整块 / 指定分组
 */
export function visibleDetails(
  providerId: string,
  details: ProviderDetailSection[],
  showOptional: boolean,
  costVisible: boolean
): ProviderDetailSection[] {
  const replaced = replacedDetailRowsFor(providerId, costVisible);
  const policy = optionalDetailsFor(providerId);
  const out: ProviderDetailSection[] = [];
  for (let i = 0; i < details.length; i++) {
    const sec = details[i];
    if (!showOptional) {
      if (policy.hidesAllWithoutOptionalUsage) {
        return [];
      }
      if (policy.hiddenTitlesWithoutOptionalUsage.indexOf(sec.title) >= 0) {
        continue;
      }
    }
    const drop = replaced[sec.title];
    if (drop == null || drop.length === 0) {
      out.push(sec);
      continue;
    }
    const rows: ProviderDetailRow[] = [];
    for (let j = 0; j < sec.rows.length; j++) {
      if (drop.indexOf(sec.rows[j].label) < 0) {
        rows.push(sec.rows[j]);
      }
    }
    // 行被费用卡吃掉后，分组可能只剩图表（对照源工程「rows 为空但 chart 非空仍保留」）
    if (rows.length === 0 && sec.chart == null) {
      continue;
    }
    out.push(sec.chart != null ? { title: sec.title, rows: rows, chart: sec.chart } : { title: sec.title, rows: rows });
  }
  return out;
}

/**
 * 需要第二凭证输入框的服务商（组织 / 账号 ID / Secret Access Key 等）。
 * 注意：DeepSeek 的平台会话虽然也放在 credential2，但对照 macOS 的
 * `DeepSeekProviderDescriptor`（requiresManualCookieSource = false）界面不提供手填入口，
 * 只由应用内「网页登录」自动抓取，所以这里不列它。
 */
export function needsSecondCredential(providerId: string): boolean {
  return providerId === 'codex' || providerId === 'kilo' ||
    providerId === 'xai' || providerId === 'litellm' || providerId === 'llmproxy' ||
    providerId === 'sub2api' || providerId === 'devin' || providerId === 'bedrock' ||
    providerId === 'clawrouter' || providerId === 'doubao' ||
    // 可选：网页会话 Cookie（对照 MiniMaxProviderDescriptor：requiresManualCookieSource = true）
    providerId === 'minimax';
}

/** 第二凭证输入框提示文案 */
export function secondCredentialHint(providerId: string): string {
  if (providerId === 'doubao') {
    return 'Secret Access Key（AK/SK 模式必填）';
  }
  if (providerId === 'bedrock') {
    return 'AWS Secret Access Key（与 Access Key ID 配对）';
  }
  if (providerId === 'clawrouter') {
    return '可选：自托管 Base URL（默认 https://clawrouter.openclaw.ai）';
  }
  if (providerId === 'minimax') {
    return '可选：platform.minimaxi.com 的会话 Cookie（用于 Billing history 明细）';
  }

  return '可选：组织 / 账号 ID';
}

/** ReminderConfig 默认值（配置缺省/解析失败时） */
export function defaultReminder(): ReminderConfig {
  return { enabled: false, usageThreshold: 90, resetLeadMinutes: 15 };
}

/** 一次刷新后某服务商的展示状态 */
export class ProviderState {
  descriptor: ProviderDescriptor;
  setting: ProviderSetting;
  snapshot: UsageSnapshot | null = null;
  loading: boolean = false;
  /** 上次成功刷新时间（Unix 毫秒），0 表示从未成功 */
  lastSuccessAt: number = 0;
  /** 查询代际：凭证变更（清除/换账号/重新保存）后 +1，进行中的过期结果按此丢弃 */
  fetchGen: number = 0;

  constructor(descriptor: ProviderDescriptor, setting: ProviderSetting) {
    this.descriptor = descriptor;
    this.setting = setting;
  }

  /** 聚合所有窗口，用于详情页；窗口名优先用快照自带的展示名 */
  allWindows(): NamedRateWindow[] {
    const list: NamedRateWindow[] = [];
    const snap = this.snapshot;
    if (snap == null) {
      return list;
    }
    if (snap.primary != null) {
      list.push({ id: 'primary', title: snap.primaryLabel.length > 0 ? snap.primaryLabel : '会话', window: snap.primary });
    }
    if (snap.secondary != null) {
      list.push({ id: 'secondary', title: snap.secondaryLabel.length > 0 ? snap.secondaryLabel : '每周', window: snap.secondary });
    }
    if (snap.tertiary != null) {
      list.push({ id: 'tertiary', title: snap.tertiaryLabel.length > 0 ? snap.tertiaryLabel : '第三窗口', window: snap.tertiary });
    }
    for (let i = 0; i < snap.extraRateWindows.length; i++) {
      list.push(snap.extraRateWindows[i]);
    }
    return list;
  }
}

/** 构造 RateWindow 的工具 */
export function makeWindow(usedPercent: number, resetsAtMs: number, usageKnown: boolean = true): RateWindow {
  return { usedPercent: usedPercent, resetsAt: resetsAtMs, usageKnown: usageKnown };
}
