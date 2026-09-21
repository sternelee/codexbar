/**
 * CodexBar Mobile — 额度提醒引擎
 *
 * 两类提醒（对照需求"额度快结束 / 准备恢复额度"）：
 *  - usage：任一用量窗口 ≥ 阈值（额度快结束）
 *  - reset：任一窗口即将重置（恢复额度），提前量可配
 *
 * evaluateReminder 为纯函数（本地单元测试覆盖）；Reminders 负责编排：
 * 刷新成功后与 30 秒周期循环各检查一次，去重键保证同一周期同一条件只发一条。
 * 通知在应用进程存活期间有效（含前台与后台未被回收时）。
 */

import { NamedRateWindow, ProviderState, ReminderConfig } from '../model/Models';
import { Format } from '../common/Format';
import { Notify } from '../common/Notify';
import { Settings } from './Settings';
import { AppStore } from './AppStore';

/** 一次待提醒事件的描述 */
export interface ReminderHit {
  /** 'usage' 额度快用完 | 'reset' 即将恢复 */
  kind: string;
  /** 命中的窗口 id */
  windowId: string;
  /** 去重键：同一窗口同一周期只提醒一次（周期变化后可再次提醒） */
  dedupeKey: string;
  /** 通知标题 */
  title: string;
  /** 通知正文 */
  text: string;
}

/**
 * 纯函数：对某服务商的当前快照做提醒判定。
 * 两者同时命中时优先"即将恢复"（更 actionable；重置后用量窗口自然刷新）。
 * 无命中返回 null。
 */
export function evaluateReminder(s: ProviderState, cfg: ReminderConfig, now: number): ReminderHit | null {
  const windows: NamedRateWindow[] = s.allWindows();

  // 1) 即将恢复：窗口重置时间落在提前量内，取最近要重置的窗口
  if (cfg.resetLeadMinutes > 0) {
    let soonest: NamedRateWindow | null = null;
    for (let i = 0; i < windows.length; i++) {
      const w = windows[i];
      const until = w.window.resetsAt - now;
      if (w.window.resetsAt > now && until <= cfg.resetLeadMinutes * 60000) {
        if (soonest == null || w.window.resetsAt < soonest.window.resetsAt) {
          soonest = w;
        }
      }
    }
    if (soonest != null) {
      const mins = Math.max(1, Math.round((soonest.window.resetsAt - now) / 60000));
      return {
        kind: 'reset',
        windowId: soonest.id,
        dedupeKey: `r_${soonest.id}_${soonest.window.resetsAt}`,
        title: `${s.descriptor.title} 额度即将恢复`,
        text: `${soonest.title} 约 ${mins} 分钟后重置`,
      };
    }
  }

  // 2) 额度快结束：任一已知用量窗口达到阈值，取用量最高的窗口
  if (cfg.usageThreshold > 0) {
    let worst: NamedRateWindow | null = null;
    for (let i = 0; i < windows.length; i++) {
      const w = windows[i];
      if (!w.window.usageKnown || w.window.usedPercent < cfg.usageThreshold) {
        continue;
      }
      if (worst == null || w.window.usedPercent > worst.window.usedPercent) {
        worst = w;
      }
    }
    if (worst != null) {
      return {
        kind: 'usage',
        windowId: worst.id,
        dedupeKey: `u_${worst.id}_${worst.window.resetsAt}`,
        title: `${s.descriptor.title} 额度即将用尽`,
        text: `${worst.title} 已用 ${Format.percent(worst.window.usedPercent)}`,
      };
    }
  }

  return null;
}

export class Reminders {
  private static timerId: number = -1;

  /** AppStore.load() 时启动；幂等 */
  static startLoop(): void {
    if (Reminders.timerId >= 0) {
      return;
    }
    Reminders.timerId = setInterval(() => {
      Reminders.checkAll();
    }, 30000);
  }

  /** 详情页保存提醒配置后调用：立即按当前数据检查一次 */
  static applyConfig(providerId: string, config: ReminderConfig): void {
    Settings.saveReminder(providerId, config);
    const s = AppStore.get().find(providerId);
    if (s != null) {
      Reminders.checkState(s);
    }
    AppStore.get().bump();
  }

  /** 检查全部服务商（周期循环/全量刷新后） */
  static checkAll(): void {
    const states = AppStore.get().states;
    for (let i = 0; i < states.length; i++) {
      Reminders.checkState(states[i]);
    }
  }

  static checkState(s: ProviderState): void {
    const cfg = Settings.reminder(s.descriptor.id);
    if (!cfg.enabled || s.snapshot == null || !s.snapshot.ok) {
      return;
    }
    const hit = evaluateReminder(s, cfg, Date.now());
    if (hit == null) {
      return;
    }
    // 去重：同一窗口同一周期同一类提醒只发一条
    if (Settings.reminderFiredKey(s.descriptor.id, hit.kind) === hit.dedupeKey) {
      return;
    }
    Settings.setReminderFiredKey(s.descriptor.id, hit.kind, hit.dedupeKey);
    Notify.post(Notify.notifyId(s.descriptor.id, hit.kind), hit.title, hit.text);
  }
}
