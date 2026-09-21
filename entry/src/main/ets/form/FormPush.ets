/**
 * CodexBar Mobile — 卡片即时推送（HarmonyOS 专属）
 *
 * 本文件静态依赖 @kit.FormKit（formProvider），仅供鸿蒙运行时使用。
 * AppStore 通过动态 import 加载本模块并以 try/catch 兜底——在 Android/iOS
 * 上动态导入会失败并被跳过，不影响应用主流程。
 */

import { formBindingData, formProvider } from '@kit.FormKit';
import { Settings } from '../store/Settings';

export class FormPush {
  /** 把最新卡片数据推送到全部已添加的卡片；返回推送成功的数量 */
  static async pushAll(json: string): Promise<number> {
    if (json.length === 0) {
      return 0;
    }
    const ids = Settings.formIds();
    let okCount = 0;
    for (let i = 0; i < ids.length; i++) {
      try {
        const data = formBindingData.createFormBindingData(json);
        await formProvider.updateForm(ids[i], data);
        okCount += 1;
      } catch (e) {
        // 卡片可能已被移除：失败即从存储中剔除
        Settings.removeFormId(ids[i]);
      }
    }
    return okCount;
  }
}
