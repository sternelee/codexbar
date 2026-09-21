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
  /** 剩余额度/余额（服务商主币种） */
  remaining: number;
  /** 已使用 */
  used: number;
  /** 货币单位，如 USD / CNY */
  currency: string;
  /** 展示文本，如 "$12.34" */
  displayText: string;
}

/** 账号身份信息（对应 Swift ProviderIdentitySnapshot） */
export interface ProviderIdentitySnapshot {
  accountEmail: string;
  accountOrganization: string;
  loginMethod: string;
}

/** 明细行 */
export interface ProviderDetailRow {
  label: string;
  value: string;
}

/** 明细分组（对应 Swift ProviderDetailSection） */
export interface ProviderDetailSection {
  title: string;
  rows: ProviderDetailRow[];
}

/** 用量快照：一个服务商一次查询的完整结果 */
export class UsageSnapshot {
  primary: RateWindow | null = null;
  secondary: RateWindow | null = null;
  tertiary: RateWindow | null = null;
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
}

/** 服务商认证方式 */
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
  /** API Key / sessionKey / access token */
  credential: string;
  /** 可选第二凭证（如 Codex accountId） */
  credential2: string;
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

/** 服务商的一个账号（多账号切换；Claude/Codex 等会话型服务商） */
export interface ProviderAccount {
  /** 账号 ID（登录时间戳生成，稳定） */
  aid: string;
  /** 显示名（自动编号"账号 N"） */
  name: string;
  /** API Key / sessionKey / access token */
  credential: string;
  /** 可选第二凭证（如 Codex 账号 ID） */
  credential2: string;
  /** OAuth refresh token（Codex 专用，其余为空） */
  refreshToken: string;
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

  constructor(descriptor: ProviderDescriptor, setting: ProviderSetting) {
    this.descriptor = descriptor;
    this.setting = setting;
  }

  /** 聚合所有窗口，用于详情页 */
  allWindows(): NamedRateWindow[] {
    const list: NamedRateWindow[] = [];
    const snap = this.snapshot;
    if (snap == null) {
      return list;
    }
    if (snap.primary != null) {
      list.push({ id: 'primary', title: '主窗口', window: snap.primary });
    }
    if (snap.secondary != null) {
      list.push({ id: 'secondary', title: '次窗口', window: snap.secondary });
    }
    if (snap.tertiary != null) {
      list.push({ id: 'tertiary', title: '第三窗口', window: snap.tertiary });
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
