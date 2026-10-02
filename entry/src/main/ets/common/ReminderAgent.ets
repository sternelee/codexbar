/**
 * CodexBar Mobile — 系统代理提醒（后台代理提醒）封装
 *
 * 单独成模块的原因与 WantAgent 相同：@ohos.reminderAgentManager 在
 * Android/iOS（ArkUI-X）没有实现，静态引用会让调用方整个模块加载失败。
 * 调用方（Reminders）必须以动态 import 加载本文件隔离风险：鸿蒙上正常
 * 注册系统级定时提醒（应用被冻结/退出后由系统代理发布通知），其他平台
 * 动态 import 解析为空、静默降级回进程内提醒。
 */

import reminderAgentManager from '@ohos.reminderAgentManager';
import notificationManager from '@ohos.notificationManager';

/**
 * 当前平台是否提供代理提醒实现。
 * 跨端时模块可能 import 成功却解析为空，先探可用性再真实调用；
 * 动态 import 本身失败不能说明平台缺能力（开放处理，走静态调用路径）。
 */
export async function isReminderAgentSupported(): Promise<boolean> {
  try {
    const mod: ESObject = await import('@ohos.reminderAgentManager');
    if (mod == null) {
      return false;
    }
    const api: ESObject = mod.default != null ? mod.default : mod;
    return api != null && typeof api.publishReminder === 'function';
  } catch (e) {
    return true;
  }
}

/**
 * 注册一个日历型代理提醒（一次性，到点由系统发布通知，无需应用存活）。
 * 返回系统侧 reminderId（供取消）；被管控/未授权等任何失败都抛异常，
 * 由调用方降级为进程内提醒。
 */
export async function publishCalendarReminder(notificationId: number, fireAt: number,
  title: string, text: string): Promise<number> {
  if (!await isReminderAgentSupported()) {
    throw new Error('reminderAgent unsupported');
  }
  const d = new Date(fireAt);
  const two = (n: number): string => n < 10 ? `0${n}` : `${n}`;
  const request: reminderAgentManager.ReminderRequestCalendar = {
    reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
    dateTime: {
      year: d.getFullYear(),
      month: d.getMonth() + 1,
      day: d.getDate(),
      hour: d.getHours(),
      minute: d.getMinutes(),
      second: 0,
    },
    title: title,
    content: text,
    notificationId: notificationId,
    slotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
  };
  return await reminderAgentManager.publishReminder(request);
}

/** 取消一个已注册的代理提醒；失败静默（id 失效即可视为已消失） */
export async function cancelReminderById(id: number): Promise<void> {
  try {
    await reminderAgentManager.cancelReminder(id);
  } catch (e) {
    // 静默：取消失败不影响主流程
  }
}
