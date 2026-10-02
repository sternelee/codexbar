/**
 * CodexBar Mobile — 额度提醒引擎
 *
 * 两类提醒（对照需求"额度快结束 / 准备恢复额度"）：
 *  - usage：任一用量窗口 ≥ 阈值（额度快结束）——无未来触发点，仅进程内提醒
 *  - reset：任一窗口即将重置（恢复额度），提前量可配
 *
 * evaluateReminder / nextResetSchedule 为纯函数（本地单元测试覆盖）；
 * Reminders 负责编排：
 *  - reset 类优先注册系统代理提醒（@ohos.reminderAgentManager），应用被
 *    冻结/退出后由系统在到点时代为发布通知；注册成功即写入去重键抑制
 *    进程内的同一周期提醒，避免双份通知。
 *  - 代理提醒不可用（跨端无实现 / 系统管控 / 未授权）时降级为进程内提醒：
 *    刷新成功后与 30 秒周期循环各检查一次，仅在应用存活期间有效。
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

/** 下一个待注册的重置提醒（系统代理提醒的调度描述） */
export interface ResetSchedule {
  /** 命中的窗口 id */
  windowId: string;
  /** 窗口重置时刻（毫秒） */
  resetsAt: number;
  /** 提醒触发时刻 = 重置时刻 - 提前量 */
  fireAt: number;
  /** 与进程内提醒一致的去重键：注册成功后写入 fired key 抑制进程内重复 */
  dedupeKey: string;
  title: string;
  text: string;
}

/** 毫秒时间戳 → "M-D HH:mm"（代理提醒文案在注册时静态生成，需自带时刻） */
export function scheduleText(windowTitle: string, resetsAt: number): string {
  const d = new Date(resetsAt);
  const two = (n: number): string => n < 10 ? `0${n}` : `${n}`;
  return `${windowTitle} 将于 ${d.getMonth() + 1}-${d.getDate()} ${two(d.getHours())}:${two(d.getMinutes())} 重置`;
}

/**
 * 纯函数：取当前数据里最近的未来重置点（不受提前量窗口约束——代理提醒
 * 需要在应用还活着时就提前注册，哪怕重置在几天后）。
 * 未开启 reset 提醒或没有未来重置点时返回 null。
 */
export function nextResetSchedule(s: ProviderState, cfg: ReminderConfig, now: number): ResetSchedule | null {
  if (!cfg.enabled || cfg.resetLeadMinutes <= 0) {
    return null;
  }
  const windows: NamedRateWindow[] = s.allWindows();
  let soonest: NamedRateWindow | null = null;
  for (let i = 0; i < windows.length; i++) {
    const w = windows[i];
    if (w.window.resetsAt > now && (soonest == null || w.window.resetsAt < soonest.window.resetsAt)) {
      soonest = w;
    }
  }
  if (soonest == null) {
    return null;
  }
  return {
    windowId: soonest.id,
    resetsAt: soonest.window.resetsAt,
    fireAt: soonest.window.resetsAt - cfg.resetLeadMinutes * 60000,
    dedupeKey: `r_${soonest.id}_${soonest.window.resetsAt}`,
    title: `${s.descriptor.title} 额度即将恢复`,
    text: scheduleText(soonest.title, soonest.window.resetsAt),
  };
}

export class Reminders {
  private static timerId: number = -1;
  /** 代理提醒注册中的服务商：防止 30 秒循环重入造成重复注册 */
  private static pending: Set<string> = new Set();

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
    // 用户显式操作：清掉代理提醒的失败标记，给系统权益/授权恢复后一次重试机会
    Settings.setAgentFailKey(providerId, '');
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
    const pid = s.descriptor.id;
    const cfg = Settings.reminder(pid);
    if (!cfg.enabled || s.snapshot == null || !s.snapshot.ok) {
      // 关闭提醒 / 无有效数据：清掉已注册的代理提醒（幂等，无注册则空操作）
      Reminders.cancelAgentReminder(pid);
      return;
    }
    const now = Date.now();

    // 1) reset 类：先尝试注册系统代理提醒（应用届时不存活也能到点提醒）。
    //    触发点已过/临近（≤1 分钟）的不注册，交给进程内路径即时提醒。
    const sched = nextResetSchedule(s, cfg, now);
    if (sched != null && sched.fireAt > now + 60000) {
      const key = `${sched.dedupeKey}_${cfg.resetLeadMinutes}`;
      if (Settings.agentScheduleKey(pid) !== key &&
        Settings.agentFailKey(pid) !== key &&
        !Reminders.pending.has(pid)) {
        Reminders.pending.add(pid);
        Reminders.scheduleAgentReminder(pid, key, sched)
          .then(() => {
            Reminders.pending.delete(pid);
          })
          .catch(() => {
            Reminders.pending.delete(pid);
          });
      }
    }

    // 2) 进程内提醒：usage 类主路径；reset 类在代理提醒注册成功后由
    //    fired key 挡掉（同一周期只保留系统通知一份），降级时放行
    const hit = evaluateReminder(s, cfg, now);
    if (hit == null) {
      return;
    }
    // 去重：同一窗口同一周期同一类提醒只发一条
    if (Settings.reminderFiredKey(pid, hit.kind) === hit.dedupeKey) {
      return;
    }
    Settings.setReminderFiredKey(pid, hit.kind, hit.dedupeKey);
    Notify.post(Notify.notifyId(pid, hit.kind), hit.title, hit.text);
  }

  /**
   * 注册系统代理提醒（动态 import 隔离跨端风险）。
   * 成功：记录 reminderId 与调度标识，并写入 fired key 抑制进程内同周期提醒；
   * 失败（跨端无实现 / 系统管控 / 未授权）：记失败标记，本周期降级为进程内提醒。
   */
  private static async scheduleAgentReminder(pid: string, key: string, sched: ResetSchedule): Promise<void> {
    await Reminders.cancelAgentReminder(pid);
    try {
      const mod: ESObject = await import('../common/ReminderAgent');
      if (mod == null) {
        throw new Error('reminder agent module unavailable');
      }
      const api: ESObject = mod;
      const id: number = await api.publishCalendarReminder(
        Notify.notifyId(pid, 'reset'), sched.fireAt, sched.title, sched.text);
      Settings.setAgentReminderId(pid, 'reset', id);
      Settings.setAgentScheduleKey(pid, key);
      Settings.setAgentFailKey(pid, '');
      // 系统通知为准：抑制进程内对同一周期的重复提醒
      Settings.setReminderFiredKey(pid, 'reset', sched.dedupeKey);
    } catch (e) {
      Settings.setAgentScheduleKey(pid, '');
      Settings.setAgentFailKey(pid, key);
    }
  }

  /** 取消已注册的代理提醒（幂等；fire-and-forget，不阻塞调用方） */
  private static async cancelAgentReminder(pid: string): Promise<void> {
    const id = Settings.agentReminderId(pid, 'reset');
    if (id < 0) {
      return;
    }
    Settings.setAgentReminderId(pid, 'reset', -1);
    Settings.setAgentScheduleKey(pid, '');
    try {
      const mod: ESObject = await import('../common/ReminderAgent');
      if (mod != null) {
        const api: ESObject = mod;
        await api.cancelReminderById(id);
      }
    } catch (e) {
      // 静默：id 已失效即可视为已消失
    }
  }
}
