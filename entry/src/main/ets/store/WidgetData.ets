/**
 * CodexBar Mobile — 桌面卡片（服务卡片）数据层
 *
 * 应用每次刷新成功后，把启用服务商的用量摘要写成 JSON 存入 Preferences；
 * 卡片侧（EntryFormAbility）在添加/定时更新时读取该 JSON 渲染；
 * 应用在线时另经 FormPush（HarmonyOS 专属，动态加载）即时推送到已添加的卡片。
 *
 * buildWidgetItems 为纯函数（本地单元测试覆盖）。
 */

import { ProviderState, RateWindow, UsageSnapshot } from '../model/Models';
import { Theme } from '../common/Theme';
import { Format } from '../common/Format';
import { Settings } from './Settings';

/** 卡片单行数据（与 widget/pages 卡片页字段一一对应） */
export interface WidgetItem {
  /** 服务商名 */
  name: string;
  /** 已用百分比文本，如 "83%" */
  pct: string;
  /** 进度条宽度 0-100 */
  barPct: number;
  /**
   * 用量等级（ok / warn / danger / unknown）。
   * 卡片数据要经 FormBindingData 序列化成 JSON，塞不进资源引用，
   * 因此这里传等级、由卡片页映射到 `$r('app.color.bar_*')`，随系统深浅色自动换值。
   */
  level: string;
  /** 重置倒计时文本，如 "2小时后重置"；未知为空 */
  cd: string;
}

export interface WidgetData {
  /** 数据生成时间文本（"HH:mm 更新"） */
  updatedAt: string;
  /** 行数据（最多 4 条，按用量降序） */
  items: WidgetItem[];
}

const MAX_ITEMS = 4;

/**
 * 纯函数：从状态列表构建卡片行数据。
 * 只取快照成功的服务商，主窗口用量优先（否则第一个可用窗口），
 * 按用量降序，最多 MAX_ITEMS 条。
 */
export function buildWidgetItems(states: ProviderState[], now: number): WidgetItem[] {
  const rows: WidgetItem[] = [];
  for (let i = 0; i < states.length; i++) {
    const s = states[i];
    if (!s.setting.enabled || s.snapshot == null || !s.snapshot.ok) {
      continue;
    }
    const win: RateWindow | null = s.snapshot.primary != null ? s.snapshot.primary : firstWindow(s.snapshot);
    if (win == null) {
      continue;
    }
    const cd = win.resetsAt > now ? Format.resetIn(win.resetsAt - now) : '';
    const item: WidgetItem = {
      name: s.descriptor.title,
      pct: Format.percent(win.usedPercent),
      barPct: Math.max(0, Math.min(100, win.usedPercent)),
      level: Theme.barLevel(win.usedPercent, win.usageKnown),
      cd: cd,
    };
    rows.push(item);
  }
  rows.sort((a: WidgetItem, b: WidgetItem) => b.barPct - a.barPct);
  return rows.slice(0, MAX_ITEMS);
}

/** 主窗口缺失时取第一个可用窗口（次窗口 → 附加窗口） */
function firstWindow(snapshot: UsageSnapshot): RateWindow | null {
  if (snapshot.secondary != null) {
    return snapshot.secondary;
  }
  if (snapshot.extraRateWindows.length > 0) {
    return snapshot.extraRateWindows[0].window;
  }
  return null;
}

export class WidgetDataStore {
  /** 构建当前数据并写入 Preferences；返回 JSON 文本（失败返回空串） */
  static update(states: ProviderState[]): string {
    const data: WidgetData = {
      updatedAt: `${Format.clock(Date.now())} 更新`,
      items: buildWidgetItems(states, Date.now()),
    };
    const json = JSON.stringify(data);
    try {
      Settings.setWidgetData(json);
      return json;
    } catch (e) {
      return '';
    }
  }
}
