/**
 * CodexBar Mobile — 通知点击拉起应用的 wantAgent 构建器
 *
 * 单独成模块的原因：@ohos.app.ability.wantAgent 在 Android/iOS（ArkUI-X）
 * 没有对应实现，若在 Notify 中静态引用，会让整个 Notify 模块加载失败、
 * 连带提醒功能一起挂掉。这里由 Notify 动态 import 本文件来隔离风险：
 * 鸿蒙上正常构建 wantAgent，其他平台 import 失败时由调用方静默降级。
 */

import wantAgent from '@ohos.app.ability.wantAgent';

/** 构建“点击通知启动指定 Ability”的 wantAgent（缺模块时由调用方捕获） */
export function buildLaunchWantAgent(bundleName: string, abilityName: string): Promise<Object> {
  return wantAgent.getWantAgent({
    wants: [{
      bundleName: bundleName,
      abilityName: abilityName,
    }],
    operationType: wantAgent.OperationType.START_ABILITY,
    requestCode: 0,
    wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
  });
}
