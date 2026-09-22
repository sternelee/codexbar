/**
 * CodexBar Mobile — 本地通知封装
 * 基于 @ohos.notificationManager（ArkUI-X 三端插件：Android/iOS 由 SDK 注入
 * ace_notification_manager_android.jar / libnotificationmanager.xcframework）。
 * 未授权或不支持的平台上静默降级，不影响业务流程。
 */

import notificationManager from '@ohos.notificationManager';
import common from '@ohos.app.ability.common';

export class Notify {
  private static ctx: common.UIAbilityContext | null = null;

  /** 在 EntryAbility.onCreate 中调用一次 */
  static init(ctx: common.Context): void {
    Notify.ctx = ctx as common.UIAbilityContext;
  }

  /**
   * 构建“点击通知拉起应用”的 wantAgent。
   * 动态加载 common/WantAgent：鸿蒙可用；Android/iOS（ArkUI-X）上该模块
   * 会解析成空值，由 WantAgent 内部的可用性判断拦下并返回 null，
   * 通知依旧发出但点击不额外跳转。
   */
  private static async buildWantAgent(): Promise<Object | null> {
    const ctx = Notify.ctx;
    if (ctx == null) {
      return null;
    }
    try {
      const mod = await import('./WantAgent');
      return await mod.buildLaunchWantAgent(ctx.abilityInfo.bundleName, ctx.abilityInfo.name);
    } catch (e) {
      return null;
    }
  }

  /**
   * 请求通知授权（用户首次开启提醒时调用）。
   * 已授权直接返回 true；弹窗被拒或接口异常返回 false（不阻塞开启配置）。
   */
  static async ensurePermission(): Promise<boolean> {
    try {
      const on = await notificationManager.isNotificationEnabled();
      if (on) {
        return true;
      }
    } catch (e) {
      // 部分跨端实现未提供该查询，继续走授权流程
    }
    const ctx = Notify.ctx;
    if (ctx == null) {
      return false;
    }
    return new Promise<boolean>((resolve) => {
      try {
        notificationManager.requestEnableNotification(ctx, (err) => {
          if (err != null && err.code !== 0) {
            // 1600004：用户拒绝授权弹窗
            resolve(false);
            return;
          }
          resolve(true);
        });
      } catch (e) {
        resolve(false);
      }
    });
  }

  /** 发送一条本地通知；任何失败静默（未授权/跨端不支持）；点击通知拉起应用 */
  static async post(id: number, title: string, text: string): Promise<void> {
    try {
      const request: notificationManager.NotificationRequest = {
        id: id,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: title,
            text: text,
            additionalText: 'CodexBar'
          }
        }
      };
      const agent = await Notify.buildWantAgent();
      if (agent != null) {
        request.wantAgent = agent;
      }
      await notificationManager.publish(request);
    } catch (e) {
      // 静默：通知失败不影响查询主流程
    }
  }

  /** 稳定的通知编号：同一服务商同一类提醒覆盖上一条，不刷屏 */
  static notifyId(providerId: string, kind: string): number {
    let h = 0;
    for (let i = 0; i < providerId.length; i++) {
      h = (h * 31 + providerId.charCodeAt(i)) % 100000;
    }
    return h * 2 + (kind === 'reset' ? 1 : 0);
  }
}
