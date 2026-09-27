/**
 * CodexBar Mobile — 应用状态中心
 * 持有全部服务商的展示状态并编排刷新；UI 层通过 version 触发重建。
 */

import { applyWindowLabels, ProviderState, ProviderSetting, UsageSnapshot } from '../model/Models';
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

  /**
   * 构建初始状态：注册表 × 用户设置，并回放缓存快照。
   * 卡片（FormExtensionAbility）进程里传 false——短生命周期进程不需要常驻提醒循环。
   */
  load(startReminderLoop: boolean = true): void {
    const list: ProviderState[] = [];
    const providers = ProviderRegistry.all();
    for (let i = 0; i < providers.length; i++) {
      const p = providers[i];
      const setting: ProviderSetting = Settings.provider(p.descriptor.id);
      const state = new ProviderState(p.descriptor, setting);
      state.lastSuccessAt = Settings.lastSuccess(p.descriptor.id);
      const cached = Settings.cache(p.descriptor.id);
      if (cached.length > 0 && state.lastSuccessAt > 0) {
        // 逐字段补齐（旧版本缓存缺后加字段，直接 as 断言会让 UI 读到 undefined）
        const restored = UsageSnapshot.fromStored(cached);
        if (restored != null) {
          // 旧缓存没有窗口标签（或来自旧版无标签的构建）：按元数据再补一次
          applyWindowLabels(restored, p.descriptor.id);
        }
        state.snapshot = restored;
      }
      list.push(state);
    }
    this.states = list;
    this.bump();
    if (startReminderLoop) {
      Reminders.startLoop();
    }
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

  /**
   * 首页排序权重：已配置凭证的服务商排前面。
   * 2 = 已配置且启用；1 = 已配置但停用；0 = 未配置。
   * 同权重内保持注册表顺序（sort 稳定）。
   */
  static configuredRank(s: ProviderState): number {
    if (s.setting.credential.length === 0) {
      return 0;
    }
    return s.setting.enabled ? 2 : 1;
  }

  /** 首页展示顺序：已配置凭证的在前（组内保持注册表顺序） */
  orderedStates(): ProviderState[] {
    const list = this.states.slice();
    list.sort((a: ProviderState, b: ProviderState) => AppStore.configuredRank(b) - AppStore.configuredRank(a));
    return list;
  }

  /** 保存设置后调用；已启用且未加载过的立即刷新 */
  applySetting(providerId: string, setting: ProviderSetting): void {
    Settings.saveProvider(providerId, setting);
    const state = this.find(providerId);
    if (state != null) {
      // 以落盘结果为准：多账号 / 旧单凭证键两条读取规则都在 Settings.provider 里，
      // 这样本次查询用的凭证与之后 refreshAll / 冷启动读到的完全一致
      state.setting = Settings.provider(providerId);
      // 清除上一次的失败快照：保存/更换凭证后不应继续显示旧的错误信息，
      // 改为展示“查询中…”，由随后的刷新结果覆盖。
      if (state.snapshot != null && !state.snapshot.ok) {
        state.snapshot = null;
      }
      if (state.setting.enabled && state.setting.credential.length > 0) {
        // 强制重新查询：即使上一次查询仍在进行，也以刚保存的凭证为准
        this.refreshOne(providerId, true);
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
        this.refreshOne(providerId, true);
      } else {
        this.bump();
      }
    }
  }

  /** 清除凭证：停用服务商并清空本地凭证/缓存，详情页回到未配置状态 */
  clearCredential(providerId: string): void {
    Settings.clearCredential(providerId);
    Settings.setCache(providerId, '');
    Settings.setLastSuccess(providerId, 0);
    const state = this.find(providerId);
    if (state != null) {
      state.setting = Settings.provider(providerId);
      state.fetchGen += 1;
      state.snapshot = null;
      state.lastSuccessAt = 0;
    }
    this.bump();
  }

  /** 设置变更后重读存储（如登录页新增账号返回时） */
  reloadSetting(providerId: string): void {
    const state = this.find(providerId);
    if (state != null) {
      state.setting = Settings.provider(providerId);
    }
    this.bump();
  }

  /** force=true 时即使正在查询也重新发起（新凭证优先，旧结果按 gen 丢弃） */
  async refreshOne(providerId: string, force: boolean = false): Promise<void> {
    const state = this.find(providerId);
    if (state == null || (state.loading && !force)) {
      return;
    }
    const provider: UsageProvider | null = ProviderRegistry.byId(providerId);
    if (provider == null) {
      return;
    }
    state.fetchGen += 1;
    const gen = state.fetchGen;
    state.loading = true;
    this.bump();
    let snap: UsageSnapshot;
    try {
      snap = await provider.fetch(state.setting);
    } catch (e) {
      snap = UsageSnapshot.failure(e instanceof Error ? e.message : '查询失败');
    }
    // 查询期间凭证发生变更（清除/切换账号/重新保存）：丢弃过期结果，
    // 并保留 loading（由更新的那次查询负责收尾）
    if (gen !== state.fetchGen) {
      this.bump();
      return;
    }
    state.loading = false;
    // 窗口标签统一在此补齐：服务商显式设置的优先，其余取元数据表（Session/Weekly/Sonnet 等）
    applyWindowLabels(snap, providerId);
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

  /**
   * 设置页改动了「卡片显示哪些服务商」后立即重建数据：
   * 无需等服务商刷新，按当前状态即时重推（鸿蒙）/落盘（其余平台）。
   */
  syncWidgets(): void {
    this.updateWidgets();
  }

  /**
   * 刷新成功后更新桌面组件数据：
   * 鸿蒙走 Form Kit 即时推送，各端再把同一份 JSON 落到沙箱文件（原生组件读取）。
   */
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
    // Android/iOS 的原生桌面组件读不了 FormBindingData，另落一份文件到沙箱；
    // 动态导入 + try/catch：平台没有文件能力时静默跳过。
    const dir = WidgetDataStore.sandboxDir();
    if (dir.length > 0) {
      try {
        const fileMod = await import('./WidgetFile');
        fileMod.writeWidgetJson(dir, json);
      } catch (e) {
        // 忽略：鸿蒙有自己的推送通道，其余平台无桌面组件
      }
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
      if (s.setting.enabled && s.setting.credential.length > 0) {
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
