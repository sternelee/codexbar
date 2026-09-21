/**
 * CodexBar Mobile — 设置持久化
 * 对应 macOS 版的 resolved config（~/.config/codexbar/config.json），
 * 移动端改用 @ohos.data.preferences 存储：服务商开关 + 凭证 + 刷新时间。
 */

import preferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';
import { ProviderSetting } from '../model/Models';

const STORE_NAME = 'codexbar_settings';
const PREFIX = 'p_';
const KEY_PREFIX = 'k_';

export class Settings {
  private static prefs: preferences.Preferences | null = null;

  /** 在 EntryAbility.onCreate 中调用一次 */
  static init(ctx: common.Context): void {
    if (Settings.prefs != null) {
      return;
    }
    try {
      Settings.prefs = preferences.getPreferencesSync(ctx, { name: STORE_NAME });
    } catch (e) {
      Settings.prefs = null;
    }
  }

  private static getP(): preferences.Preferences | null {
    return Settings.prefs;
  }

  static getString(key: string, dflt: string): string {
    const p = Settings.getP();
    if (p == null) {
      return dflt;
    }
    return p.getSync(key, dflt) as string;
  }

  static setString(key: string, value: string): void {
    const p = Settings.getP();
    if (p == null) {
      return;
    }
    p.putSync(key, value);
    p.flush();
  }

  static getNumber(key: string, dflt: number): number {
    const p = Settings.getP();
    if (p == null) {
      return dflt;
    }
    return p.getSync(key, dflt) as number;
  }

  static setNumber(key: string, value: number): void {
    const p = Settings.getP();
    if (p == null) {
      return;
    }
    p.putSync(key, value);
    p.flush();
  }

  /** 读取某服务商配置 */
  static provider(providerId: string): ProviderSetting {
    const enabledRaw = Settings.getString(`${PREFIX}${providerId}`, '');
    const cred = Settings.getString(`${KEY_PREFIX}${providerId}_c1`, '');
    const cred2 = Settings.getString(`${KEY_PREFIX}${providerId}_c2`, '');
    const s: ProviderSetting = {
      enabled: enabledRaw === '1' || (enabledRaw === '' && cred.length > 0),
      credential: cred,
      credential2: cred2,
    };
    return s;
  }

  /** 保存某服务商配置 */
  static saveProvider(providerId: string, setting: ProviderSetting): void {
    Settings.setString(`${PREFIX}${providerId}`, setting.enabled ? '1' : '0');
    Settings.setString(`${KEY_PREFIX}${providerId}_c1`, setting.credential);
    Settings.setString(`${KEY_PREFIX}${providerId}_c2`, setting.credential2);
  }

  /** 上次成功刷新时间（毫秒） */
  static lastSuccess(providerId: string): number {
    return Settings.getNumber(`t_${providerId}`, 0);
  }

  static setLastSuccess(providerId: string, ms: number): void {
    Settings.setNumber(`t_${providerId}`, ms);
  }

  /** 上次快照缓存（JSON 文本），冷启动时展示旧数据 */
  static cache(providerId: string): string {
    return Settings.getString(`cache_${providerId}`, '');
  }

  static setCache(providerId: string, jsonText: string): void {
    Settings.setString(`cache_${providerId}`, jsonText);
  }
}
