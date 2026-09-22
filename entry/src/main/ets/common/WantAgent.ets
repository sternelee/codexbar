/**
 * CodexBar Mobile — 通知点击拉起应用的 wantAgent 构建器
 *
 * 单独成模块的原因：@ohos.app.ability.wantAgent 在 Android/iOS（ArkUI-X）
 * 没有可用实现，若在 Notify 中静态引用，会让整个 Notify 模块加载失败、
 * 连带提醒功能一起挂掉。这里由 Notify 动态 import 本文件来隔离风险：
 * 鸿蒙上正常构建 wantAgent，其他平台由 isWantAgentSupported() 判掉、静默降级。
 */

import wantAgent from '@ohos.app.ability.wantAgent';

/**
 * 当前平台是否真的提供了 wantAgent 实现。
 *
 * 跨端时 `@ohos.app.ability.wantAgent` 能 import 成功、却被解析成空值，
 * 直接取属性就抛 “Cannot read property getWantAgent of undefined”：异常虽然
 * 会被调用方 catch 住（通知照发、点击不跳转），启动日志里却会留一条无意义的
 * Throw error。所以先探一次可用性，再决定要不要真的调用。
 *
 * 探测只能走动态 import：ArkTS 禁止把命名空间当对象用（`arkts-no-ns-as-obj`），
 * 对 `wantAgent` 这个导入绑定做 `typeof` / `!= null` / 赋值都会被拦下，
 * 而 `await import(...)` 拿到的是普通值，可以安全地看它有没有 `default`。
 */
export async function isWantAgentSupported(): Promise<boolean> {
  try {
    const mod: ESObject = await import('@ohos.app.ability.wantAgent');
    if (mod == null) {
      return false;
    }
    // @ohos.* 的 d.ts 是 `export default wantAgent`，所以取 default；
    // 万一某平台只有具名导出，再回退到模块对象本身。
    const api: ESObject = mod.default != null ? mod.default : mod;
    return api != null && typeof api.getWantAgent === 'function';
  } catch (e) {
    // 动态 import 本身不被支持：这不能说明平台缺能力（鸿蒙上静态 import 必然可用），
    // 失败开放、继续走静态调用路径，否则会静默丢掉“点击通知跳回应用”。
    return true;
  }
}

/** 构建“点击通知启动指定 Ability”的 wantAgent；平台不支持时返回 null 由调用方降级 */
export async function buildLaunchWantAgent(bundleName: string, abilityName: string): Promise<Object | null> {
  if (!await isWantAgentSupported()) {
    return null;
  }
  try {
    return await wantAgent.getWantAgent({
      wants: [{
        bundleName: bundleName,
        abilityName: abilityName,
      }],
      operationType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
    });
  } catch (e) {
    return null;
  }
}
