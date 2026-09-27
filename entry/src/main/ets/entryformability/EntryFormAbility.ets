/**
 * CodexBar Mobile — 服务卡片 FormExtensionAbility
 *
 * 卡片添加/定时更新时读取应用写入的用量摘要（Preferences 中的
 * widget_data JSON）返回渲染数据；formId 持久化供应用侧即时推送。
 *
 * 卡片右下角「刷新」按钮：postCardAction(message) → onFormEvent，
 * 在卡片进程里复用 AppStore 只重查当前显示中的服务商并即时推送。
 */

import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Want } from '@kit.AbilityKit';
import { Settings } from '../store/Settings';
import { AppStore } from '../store/AppStore';
import { WidgetDataStore, widgetDisplayedIds } from '../store/WidgetData';
import { asObj, parseJson } from '../net/Json';

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
    hilog.info(DOMAIN, TAG, 'onFormEvent: %{public}s', message);
    Settings.init(this.context);
    let event = '';
    try {
      const parsed = asObj(parseJson(message));
      if (parsed != null) {
        const v = parsed['event'];
        if (typeof v === 'string') {
          event = v as string;
        }
      }
    } catch (e) {
      return;
    }
    if (event === 'refresh') {
      this.refreshDisplayed(formId);
    }
  }

  /**
   * 卡片「刷新」：只重查当前显示中的几家服务商（widgetDisplayedIds，
   * 与 buildWidgetItems 同一挑选逻辑），成功后由 AppStore.refreshOne
   * 内部的 updateWidgets 推送全部卡片。
   */
  private async refreshDisplayed(formId: string): Promise<void> {
    // 先把本卡片切到「刷新中」，避免点击后没有反馈
    try {
      const current = Settings.widgetData();
      if (current.length > 0) {
        const parsed = asObj(parseJson(current));
        if (parsed != null) {
          parsed['updatedAt'] = '刷新中…';
          const pending = formBindingData.createFormBindingData(JSON.stringify(parsed));
          formProvider.updateForm(formId, pending);
        }
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'push refreshing state failed');
    }

    const store = AppStore.get();
    // 卡片进程短生命周期：跳过常驻提醒循环
    store.load(false);
    const displayed = widgetDisplayedIds(store.states, WidgetDataStore.selectedIds());
    const targets: string[] = [];
    for (let i = 0; i < displayed.length; i++) {
      const s = store.find(displayed[i]);
      if (s != null && s.setting.enabled && s.setting.credential.length > 0) {
        targets.push(displayed[i]);
      }
    }
    if (targets.length === 0) {
      // 兜底：卡片暂无可渲染条目时刷新全部已配置凭证的服务商
      for (let i = 0; i < store.states.length; i++) {
        const s = store.states[i];
        if (s.setting.enabled && s.setting.credential.length > 0) {
          targets.push(s.descriptor.id);
        }
      }
    }
    hilog.info(DOMAIN, TAG, 'refresh targets: %{public}d', targets.length);
    const tasks: Promise<void>[] = [];
    for (let i = 0; i < targets.length; i++) {
      tasks.push(store.refreshOne(targets[i]));
    }
    await Promise.all(tasks);
    // 有成功的已推送过；这里兜底恢复本卡片时间戳（全部失败时不留「刷新中」）
    try {
      const json = Settings.widgetData();
      if (json.length > 0) {
        const data = formBindingData.createFormBindingData(json);
        formProvider.updateForm(formId, data);
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'final push failed');
    }
  }
}
