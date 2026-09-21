/**
 * CodexBar Mobile — 应用状态中心
 * 持有全部服务商的展示状态并编排刷新；UI 层通过 version 触发重建。
 */

import { AuthKind, ProviderState, ProviderSetting, UsageSnapshot } from '../model/Models';
import { ProviderRegistry } from '../providers/ProviderRegistry';
import { UsageProvider } from '../providers/ProviderBase';
import { Settings } from './Settings';
import { Reminders } from './Reminders';
import { WidgetDataStore } from './WidgetData';
import { recordSampleFor } from './UsageHistory';

export class AppStore {
  private static instance: AppStore | null = null;

  states: ProviderState[] = [];
  /** 每次状态变更 +1；UI 以 @State 持有并用于触发重建 */
  version: number = 0;
  /** 全局刷新中 */
  refreshing: boolean = false;

  static get(): AppStore {
    if (AppStore.instance == null) {
      AppStore.instance = new AppStore();
    }
    return AppStore.instance;
  }

  /** 构建初始状态：注册表 × 用户设置，并回放缓存快照 */
  load(): void {
    const list: ProviderState[] = [];
    const providers = ProviderRegistry.all();
    for (let i = 0; i < providers.length; i++) {
      const p = providers[i];
      const setting: ProviderSetting = Settings.provider(p.descriptor.id);
      const state = new ProviderState(p.descriptor, setting);
      state.lastSuccessAt = Settings.lastSuccess(p.descriptor.id);
      const cached = Settings.cache(p.descriptor.id);
      if (cached.length > 0 && state.lastSuccessAt > 0) {
        try {
          const parsed = JSON.parse(cached) as UsageSnapshot;
          state.snapshot = parsed;
        } catch (e) {
          state.snapshot = null;
        }
      }
      list.push(state);
    }
    this.states = list;
    this.bump();
    Reminders.startLoop();
  }

  bump(): void {
    this.version += 1;
  }

  find(providerId: string): ProviderState | null {
    for (let i = 0; i < this.states.length; i++) {
      if (this.states[i].descriptor.id === providerId) {
        return this.states[i];
      }
    }
    return null;
  }

  /** 保存设置后调用；已启用且未加载过的立即刷新 */
  applySetting(providerId: string, setting: ProviderSetting): void {
    Settings.saveProvider(providerId, setting);
    const state = this.find(providerId);
    if (state != null) {
      state.setting = setting;
      if (setting.enabled && setting.credential.length > 0) {
        this.refreshOne(providerId);
      } else {
        this.bump();
      }
    }
  }

  /** 切换激活账号：重读凭证并立即刷新该服务商 */
  switchAccount(providerId: string, aid: string): void {
    Settings.setActiveAccountId(providerId, aid);
    const state = this.find(providerId);
    if (state != null) {
      state.setting = Settings.provider(providerId);
      if (state.setting.credential.length > 0) {
        this.refreshOne(providerId);
      } else {
        this.bump();
      }
    }
  }

  /** 设置变更后重读存储（如登录页新增账号返回时） */
  reloadSetting(providerId: string): void {
    const state = this.find(providerId);
    if (state != null) {
      state.setting = Settings.provider(providerId);
    }
    this.bump();
  }

  async refreshOne(providerId: string): Promise<void> {
    const state = this.find(providerId);
    if (state == null || state.loading) {
      return;
    }
    const provider: UsageProvider | null = ProviderRegistry.byId(providerId);
    if (provider == null) {
      return;
    }
    state.loading = true;
    this.bump();
    let snap: UsageSnapshot;
    try {
      snap = await provider.fetch(state.setting);
    } catch (e) {
      snap = UsageSnapshot.failure(e instanceof Error ? e.message : '查询失败');
    }
    state.loading = false;
    state.snapshot = snap;
    if (snap.ok) {
      state.lastSuccessAt = Date.now();
      Settings.setLastSuccess(providerId, state.lastSuccessAt);
      Settings.setCache(providerId, JSON.stringify(snap));
      Reminders.checkState(state);
      try {
        recordSampleFor(state, state.lastSuccessAt);
      } catch (e) {
        // 历史采样失败不影响主流程
      }
      this.updateWidgets();
    }
    this.bump();
  }

  /** 刷新成功后更新桌面卡片数据；鸿蒙上动态加载 FormPush 即时推送（跨端导入失败自动跳过） */
  private async updateWidgets(): Promise<void> {
    const json = WidgetDataStore.update(this.states);
    if (json.length === 0) {
      return;
    }
    try {
      const mod = await import('../form/FormPush');
      await mod.FormPush.pushAll(json);
    } catch (e) {
      // 非鸿蒙平台（Android/iOS）无 Form Kit：跳过即时推送，
      // 数据已写入 Preferences，由卡片定时更新兜底
    }
  }

  /** 并发刷新全部已启用且已配置凭证的服务商 */
  async refreshAll(): Promise<void> {
    if (this.refreshing) {
      return;
    }
    this.refreshing = true;
    this.bump();
    const tasks: Promise<void>[] = [];
    for (let i = 0; i < this.states.length; i++) {
      const s = this.states[i];
      const needFetch = s.descriptor.authKind === AuthKind.DEMO ||
        (s.setting.enabled && s.setting.credential.length > 0);
      if (needFetch) {
        tasks.push(this.refreshOne(s.descriptor.id));
      }
    }
    await Promise.all(tasks);
    this.refreshing = false;
    this.bump();
  }

  /** 已启用服务商数量 */
  enabledCount(): number {
    let n = 0;
    for (let i = 0; i < this.states.length; i++) {
      if (this.states[i].setting.enabled) {
        n += 1;
      }
    }
    return n;
  }
}
