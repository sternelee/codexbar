/**
 * CodexBar Mobile — 桌面卡片（服务卡片）数据层
 *
 * 应用每次刷新成功后，把启用服务商的用量摘要写成 JSON 存入 Preferences；
 * 卡片显示哪些服务商可在设置页挑选（未挑选则按用量自动取前 N 家）；
 * 卡片侧（EntryFormAbility）在添加/定时更新时读取该 JSON 渲染；
 * 应用在线时另经 FormPush（HarmonyOS 专属，动态加载）即时推送到已添加的卡片。
 *
 * buildWidgetItems 为纯函数（本地单元测试覆盖）。
 */

import common from '@ohos.app.ability.common';
import { primaryDisplayWindow, ProviderState, RateWindow, UsageSnapshot } from '../model/Models';
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
  /** 行数据（最多 MAX_ITEMS 条；指定了服务商则按指定顺序，否则按用量降序） */
  items: WidgetItem[];
}

/**
 * 数据行上限。
 *
 * 鸿蒙服务卡片尺寸固定（2x2 取前 2 条、2x4 取前 4 条，由卡片页自行截断）；
 * 安卓原生组件可任意拉伸，行数按实例高度自适应（见 widget/WidgetUpdater.java），
 * 所以这里留足余量，多出来的行由各端按自己的容量截断。
 */
const MAX_ITEMS = 8;

/**
 * 解析用户在设置页挑选的桌面组件服务商 ID 列表（JSON 数组文本）。
 * 损坏输入一律返回空数组 = 自动模式（按用量取前 N）。
 */
export function parseWidgetSelection(text: string): string[] {
  if (text == null || text.length === 0) {
    return [];
  }
  try {
    const arr = JSON.parse(text) as string[];
    if (!Array.isArray(arr)) {
      return [];
    }
    const out: string[] = [];
    for (let i = 0; i < arr.length; i++) {
      const id = arr[i];
      // 去重 + 丢弃非字符串/空项，避免手改存储后出现空行
      if (typeof id === 'string' && (id as string).length > 0 && out.indexOf(id as string) < 0) {
        out.push(id as string);
      }
    }
    return out;
  } catch (e) {
    return [];
  }
}

/** 单个服务商的状态 → 卡片行数据；不可展示（未启用 / 快照失败 / 无窗口）时返回 null */
function itemFor(s: ProviderState, now: number): WidgetItem | null {
  if (!s.setting.enabled || s.snapshot == null || !s.snapshot.ok) {
    return null;
  }
  // 主泳道记录绑定泳道投影（更长泳道耗尽时按 100% + 闸门恢复时间展示），与 App 内卡片一致
  const win: RateWindow | null = s.snapshot.primary != null
    ? primaryDisplayWindow(s.descriptor.id, s.snapshot, now)
    : firstWindow(s.snapshot);
  if (win == null) {
    return null;
  }
  const cd = win.resetsAt > now ? Format.resetIn(win.resetsAt - now) : '';
  const item: WidgetItem = {
    name: s.descriptor.title,
    pct: Format.percent(win.usedPercent),
    barPct: Math.max(0, Math.min(100, win.usedPercent)),
    level: Theme.barLevel(win.usedPercent, win.usageKnown),
    cd: cd,
  };
  return item;
}

function stateById(states: ProviderState[], id: string): ProviderState | null {
  for (let i = 0; i < states.length; i++) {
    if (states[i].descriptor.id === id) {
      return states[i];
    }
  }
  return null;
}

/**
 * 纯函数：从状态列表构建卡片行数据。
 * 只取快照成功的服务商，主窗口用量优先（否则第一个可用窗口），最多 MAX_ITEMS 条。
 *
 * - `selected` 为空：自动模式，按用量降序取前 N 家；
 * - `selected` 非空：只取指定服务商，且按用户挑选的顺序排列。
 *
 * 各端再按自身容量截断：鸿蒙 2x2 / 2x4 卡取前 2 / 4 条，安卓组件按高度取若干条。
 */
export function buildWidgetItems(states: ProviderState[], now: number, selected: string[] = []): WidgetItem[] {
  const rows: WidgetItem[] = [];
  if (selected.length > 0) {
    for (let i = 0; i < selected.length && rows.length < MAX_ITEMS; i++) {
      const s = stateById(states, selected[i]);
      if (s == null) {
        continue;
      }
      const item = itemFor(s, now);
      if (item != null) {
        rows.push(item);
      }
    }
    return rows;
  }
  for (let i = 0; i < states.length; i++) {
    const item = itemFor(states[i], now);
    if (item != null) {
      rows.push(item);
    }
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
  /** 应用沙箱 files 目录（EntryAbility.onCreate 时记录，供跨端组件文件桥使用） */
  private static dir: string = '';

  /** 在 EntryAbility.onCreate 中调用一次；取不到目录时静默降级（仅影响原生组件） */
  static init(ctx: common.Context): void {
    try {
      WidgetDataStore.dir = ctx.filesDir;
    } catch (e) {
      WidgetDataStore.dir = '';
    }
  }

  /** 沙箱目录；为空表示尚未初始化 */
  static sandboxDir(): string {
    return WidgetDataStore.dir;
  }

  // ---------------- 卡片显示哪些服务商（设置页「桌面组件显示」） ----------------

  /** 用户挑选的服务商 ID（按卡片上的出现顺序）；空数组 = 自动模式 */
  static selectedIds(): string[] {
    return parseWidgetSelection(Settings.getString('widget_selection', ''));
  }

  static setSelectedIds(ids: string[]): void {
    Settings.setString('widget_selection', JSON.stringify(ids));
  }

  /** 构建当前数据并写入 Preferences；返回 JSON 文本（失败返回空串） */
  static update(states: ProviderState[]): string {
    const data: WidgetData = {
      updatedAt: `${Format.clock(Date.now())} 更新`,
      items: buildWidgetItems(states, Date.now(), WidgetDataStore.selectedIds()),
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
