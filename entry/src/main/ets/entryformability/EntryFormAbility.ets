/**
 * CodexBar Mobile — 服务卡片 FormExtensionAbility
 *
 * 卡片添加/定时更新时读取应用写入的用量摘要（Preferences 中的
 * widget_data JSON）返回渲染数据；formId 持久化供应用侧即时推送。
 */

import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Want } from '@kit.AbilityKit';
import { Settings } from '../store/Settings';

const DOMAIN = 0x0000;
const TAG = 'EntryFormAbility';
const FORM_IDENTITY_KEY = 'ohos.extra.param.key.form_identity';

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    hilog.info(DOMAIN, TAG, 'onAddForm');
    Settings.init(this.context);
    try {
      const params = want.parameters;
      const formId = params != null && params[FORM_IDENTITY_KEY] != null ? `${params[FORM_IDENTITY_KEY]}` : '';
      Settings.addFormId(formId);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'save formId failed');
    }
    return formBindingData.createFormBindingData(Settings.widgetData());
  }

  onUpdateForm(formId: string): void {
    // 定时更新：直接把存储的最新数据推给该卡片
    Settings.init(this.context);
    try {
      const data = formBindingData.createFormBindingData(Settings.widgetData());
      formProvider.updateForm(formId, data);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'updateForm failed');
    }
  }

  onRemoveForm(formId: string): void {
    Settings.init(this.context);
    Settings.removeFormId(formId);
  }

  onFormEvent(formId: string, message: string): void {
    hilog.info(DOMAIN, TAG, 'onFormEvent');
  }
}
