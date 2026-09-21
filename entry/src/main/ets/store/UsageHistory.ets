/**
 * CodexBar Mobile — 用量历史采样与派生统计
 *
 * macOS 版的每日消费数据来自扫描本地 CLI 会话文件；移动端没有该条件，
 * 改为本地采样：每次刷新成功记录当日快照（主窗口用量 % + 余额），
 * 按天聚合保留最近 62 天，再派生出：
 *  - 每日用量增量（跨天主窗口百分比差；跨天突降视为窗口重置）
 *  - 每日消费（余额降幅估算；余额上升视为充值记 0）
 * 柱形图刻度逻辑对照 macOS UsageChartScale / CostHistoryChartMenuView。
 * 标注为采样估算，与源工程的精确统计有差异。
 */

import { HistoryDay, ProviderState } from '../model/Models';
import { Settings } from './Settings';

/** 柱形图单点 */
export interface ChartPoint {
  /** 日期键 */
  d: string;
  /** 短标签 M/D */
  label: string;
  /** 数值（用量百分点 或 货币额） */
  v: number;
}

const MAX_DAYS = 62;
/** 跨天降幅超过该值视为窗口重置/换账号，而非消费回落 */
const RESET_DROP_THRESHOLD = 30;

// ---------------- 日期工具（纯函数） ----------------

function pad(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

/** Unix 毫秒 → 本地日期键 YYYY-MM-DD */
export function localDateKey(now: number): string {
  const t = new Date(now);
  return `${t.getFullYear()}-${pad(t.getMonth() + 1)}-${pad(t.getDate())}`;
}

/** YYYY-MM-DD → M/D 短标签 */
export function dayLabel(key: string): string {
  const parts = key.split('-');
  if (parts.length !== 3) {
    return key;
  }
  return `${Number(parts[1])}/${Number(parts[2])}`;
}

/** 日期键减 N 天 */
export function dateKeyMinus(key: string, days: number): string {
  const parts = key.split('-');
  if (parts.length !== 3) {
    return key;
  }
  const t = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
  t.setDate(t.getDate() - days);
  return localDateKey(t.getTime());
}

// ---------------- 采样（写入） ----------------

/** 从快照取主窗口用量；无主窗口回退次/附加窗口 */
function primaryPercent(state: ProviderState): number | null {
  const snap = state.snapshot;
  if (snap == null || !snap.ok) {
    return null;
  }
  const win = snap.primary != null ? snap.primary
    : (snap.secondary != null ? snap.secondary
      : (snap.extraRateWindows.length > 0 ? snap.extraRateWindows[0].window : null));
  return win != null ? win.usedPercent : null;
}

/** 刷新成功后调用：按天聚合记录快照 */
export function recordSampleFor(state: ProviderState, now: number): void {
  const pct = primaryPercent(state);
  if (pct == null) {
    return;
  }
  const snap = state.snapshot;
  const balance = snap != null && snap.providerCost != null && isFinite(snap.providerCost.remaining)
    ? snap.providerCost.remaining : -1;
  const key = localDateKey(now);
  const records = Settings.history(state.descriptor.id);
  const last = records.length > 0 ? records[records.length - 1] : null;
  if (last != null && last.d === key) {
    last.p = pct;
    last.b = balance;
    Settings.setHistory(state.descriptor.id, records);
    return;
  }
  records.push({ d: key, p: pct, b: balance });
  while (records.length > MAX_DAYS) {
    records.shift();
  }
  Settings.setHistory(state.descriptor.id, records);
}

// ---------------- 派生（纯函数） ----------------

/** 每日用量增量（百分点）：跨天突降视为重置，取当日值；首日无前值跳过 */
export function usageDeltas(records: HistoryDay[]): ChartPoint[] {
  const out: ChartPoint[] = [];
  for (let i = 1; i < records.length; i++) {
    const prev = records[i - 1];
    const cur = records[i];
    let delta: number;
    if (prev.p - cur.p > RESET_DROP_THRESHOLD) {
      delta = cur.p;
    } else {
      delta = Math.max(0, cur.p - prev.p);
    }
    out.push({ d: cur.d, label: dayLabel(cur.d), v: Math.round(delta * 10) / 10 });
  }
  return out;
}

/** 每日消费（余额降幅）：余额缺失跳过当日；上升视为充值记 0 */
export function costDeltas(records: HistoryDay[]): ChartPoint[] {
  const out: ChartPoint[] = [];
  for (let i = 1; i < records.length; i++) {
    const prev = records[i - 1];
    const cur = records[i];
    if (prev.b < 0 || cur.b < 0) {
      continue;
    }
    const drop = Math.max(0, prev.b - cur.b);
    out.push({ d: cur.d, label: dayLabel(cur.d), v: Math.round(drop * 100) / 100 });
  }
  return out;
}

/** 近 N 天（含今天）合计；todayKey 为本地今天 */
export function sumLast(points: ChartPoint[], todayKey: string, days: number): number {
  const from = dateKeyMinus(todayKey, days - 1);
  let sum = 0;
  for (let i = 0; i < points.length; i++) {
    if (points[i].d >= from && points[i].d <= todayKey) {
      sum += points[i].v;
    }
  }
  return Math.round(sum * 100) / 100;
}

// ---------------- 图表刻度（对照 UsageChartScale / macOS 刻度策略） ----------------

/** 柱形图 Y 轴最大值（取有效值最大者） */
export function scaleMax(values: number[]): number {
  let max = 0;
  for (let i = 0; i < values.length; i++) {
    if (isFinite(values[i]) && values[i] > max) {
      max = values[i];
    }
  }
  return max;
}

/** 值 → 柱高占比 0..1 */
export function scaleFraction(value: number, max: number): number {
  if (max <= 0 || !isFinite(value) || value <= 0) {
    return 0;
  }
  return Math.min(value / max, 1);
}

/** Y 轴刻度：费用 < $1 时 [0,max]，否则 [0,中点,max]；无数据返回空 */
export function yAxisTicks(max: number, isCost: boolean): number[] {
  if (max <= 0) {
    return [];
  }
  if (isCost && max < 1.0) {
    return [0, max];
  }
  return max < 2 ? [0, max] : [0, max / 2, max];
}
