/**
 * CodexBar Mobile — 设置持久化
 * 对应 macOS 版的 resolved config（~/.config/codexbar/config.json），
 * 移动端改用 @ohos.data.preferences 存储：服务商开关 + 凭证 + 刷新时间。
 */

import preferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';
import { defaultReminder, HistoryDay, ProviderAccount, ProviderSetting, ReminderConfig } from '../model/Models';

// ---------------- 账号列表纯函数（本地单元测试覆盖） ----------------

/** 解析账号列表 JSON；损坏输入返回空数组 */
export function parseAccounts(text: string): ProviderAccount[] {
  if (text == null || text.length === 0) {
    return [];
  }
  try {
    const arr = JSON.parse(text) as ProviderAccount[];
    if (!Array.isArray(arr)) {
      return [];
    }
    const out: ProviderAccount[] = [];
    for (let i = 0; i < arr.length; i++) {
      const a = arr[i];
      if (a != null && typeof a.aid === 'string' && (a.aid as string).length > 0) {
        out.push({
          aid: a.aid as string,
          name: typeof a.name === 'string' ? a.name as string : '',
          credential: typeof a.credential === 'string' ? a.credential as string : '',
          credential2: typeof a.credential2 === 'string' ? a.credential2 as string : '',
          refreshToken: typeof a.refreshToken === 'string' ? a.refreshToken as string : '',
        });
      }
    }
    return out;
  } catch (e) {
    return [];
  }
}

export function accountsToJson(list: ProviderAccount[]): string {
  return JSON.stringify(list);
}

/** 取激活账号；aid 为空或不存在时返回 null */
export function pickAccount(list: ProviderAccount[], aid: string): ProviderAccount | null {
  if (aid == null || aid.length === 0) {
    return null;
  }
  for (let i = 0; i < list.length; i++) {
    if (list[i].aid === aid) {
      return list[i];
    }
  }
  return null;
}

/** 下一个自动账号名（"账号 N"，N = 现有数量 + 1） */
export function nextAccountName(list: ProviderAccount[]): string {
  return `账号 ${list.length + 1}`;
}

export interface AddAccountResult {
  list: ProviderAccount[];
  /** 实际生效（新建或去重命中）的账号 */
  account: ProviderAccount;
  /** true 表示凭证已存在，仅激活了既有账号 */
  deduped: boolean;
}

/** 生成不与现有列表冲突的账号 ID（同毫秒连续添加时追加随机后缀） */
export function makeAccountAid(now: number, list: ProviderAccount[]): string {
  let aid = `a${now}`;
  let salt = 0;
  while (true) {
    let exists = false;
    for (let i = 0; i < list.length; i++) {
      if (list[i].aid === aid) {
        exists = true;
        break;
      }
    }
    if (!exists) {
      return aid;
    }
    salt += 1;
    aid = `a${now}_${salt}_${Math.floor(Math.random() * 100000)}`;
  }
}

/** 向列表添加账号：同凭证去重（仅激活既有），新账号自动命名并置为最后 */
export function addAccountToList(
  list: ProviderAccount[],
  credential: string,
  credential2: string,
  refreshToken: string,
  now: number
): AddAccountResult {
  for (let i = 0; i < list.length; i++) {
    if (credential.length > 0 && list[i].credential === credential) {
      // 同凭证：刷新辅助字段并复用
      list[i].credential2 = credential2.length > 0 ? credential2 : list[i].credential2;
      list[i].refreshToken = refreshToken.length > 0 ? refreshToken : list[i].refreshToken;
      return { list: list, account: list[i], deduped: true };
    }
  }
  const fresh: ProviderAccount = {
    aid: makeAccountAid(now, list),
    name: nextAccountName(list),
    credential: credential,
    credential2: credential2,
    refreshToken: refreshToken,
  };
  const merged = list.concat([fresh]);
  return { list: merged, account: fresh, deduped: false };
}

/** 重命名账号（返回新列表；aid 不存在时原样返回） */
export function renameAccountInList(list: ProviderAccount[], aid: string, name: string): ProviderAccount[] {
  const out: ProviderAccount[] = [];
  for (let i = 0; i < list.length; i++) {
    if (list[i].aid === aid) {
      out.push({
        aid: list[i].aid,
        name: name,
        credential: list[i].credential,
        credential2: list[i].credential2,
        refreshToken: list[i].refreshToken,
      });
    } else {
      out.push(list[i]);
    }
  }
  return out;
}

/** 移除账号的结果：新列表与建议的新激活 ID（删的是激活账号时取第一个剩余，否则原激活） */
export interface RemoveAccountResult {
  list: ProviderAccount[];
  newActive: string;
}

export function removeAccountFromList(
  list: ProviderAccount[],
  aid: string,
  activeAid: string
): RemoveAccountResult {
  const rest: ProviderAccount[] = [];
  for (let i = 0; i < list.length; i++) {
    if (list[i].aid !== aid) {
      rest.push(list[i]);
    }
  }
  const newActive = activeAid === aid ? (rest.length > 0 ? rest[0].aid : '') : activeAid;
  const res: RemoveAccountResult = { list: rest, newActive: newActive };
  return res;
}

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

  /** 读取某服务商配置：激活账号优先，回退旧单凭证键 */
  static provider(providerId: string): ProviderSetting {
    const accounts = Settings.accounts(providerId);
    const active = pickAccount(accounts, Settings.activeAccountId(providerId));
    const enabledRaw = Settings.getString(`${PREFIX}${providerId}`, '');
    if (active != null) {
      const s: ProviderSetting = {
        enabled: enabledRaw === '1' || (enabledRaw === '' && active.credential.length > 0),
        credential: active.credential,
        credential2: active.credential2,
      };
      return s;
    }
    const cred = Settings.getString(`${KEY_PREFIX}${providerId}_c1`, '');
    const cred2 = Settings.getString(`${KEY_PREFIX}${providerId}_c2`, '');
    const s: ProviderSetting = {
      enabled: enabledRaw === '1' || (enabledRaw === '' && cred.length > 0),
      credential: cred,
      credential2: cred2,
    };
    return s;
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

  /** 读取某服务商的提醒配置；缺失或损坏时返回默认值 */
  static reminder(providerId: string): ReminderConfig {
    const raw = Settings.getString(`r_${providerId}`, '');
    if (raw.length === 0) {
      return defaultReminder();
    }
    try {
      const parsed = JSON.parse(raw) as ReminderConfig;
      if (typeof parsed.enabled !== 'boolean') {
        return defaultReminder();
      }
      const dflt = defaultReminder();
      return {
        enabled: parsed.enabled,
        usageThreshold: typeof parsed.usageThreshold === 'number' ? parsed.usageThreshold : dflt.usageThreshold,
        resetLeadMinutes: typeof parsed.resetLeadMinutes === 'number' ? parsed.resetLeadMinutes : dflt.resetLeadMinutes,
      };
    } catch (e) {
      return defaultReminder();
    }
  }

  static saveReminder(providerId: string, config: ReminderConfig): void {
    Settings.setString(`r_${providerId}`, JSON.stringify(config));
  }

  /** 最近一次已提醒的去重键（kind: 'usage' | 'reset'），用于同一周期只提醒一次 */
  static reminderFiredKey(providerId: string, kind: string): string {
    return Settings.getString(`f_${kind}_${providerId}`, '');
  }

  static setReminderFiredKey(providerId: string, kind: string, key: string): void {
    Settings.setString(`f_${kind}_${providerId}`, key);
  }

  /** OAuth refresh token（Codex）：激活账号优先，回退旧键 */
  static oauthRefreshToken(providerId: string): string {
    const accounts = Settings.accounts(providerId);
    const active = pickAccount(accounts, Settings.activeAccountId(providerId));
    if (active != null) {
      return active.refreshToken;
    }
    return Settings.getString(`rt_${providerId}`, '');
  }

  static setOauthRefreshToken(providerId: string, token: string): void {
    const accounts = Settings.accounts(providerId);
    const activeAid = Settings.activeAccountId(providerId);
    const active = pickAccount(accounts, activeAid);
    if (active != null) {
      active.refreshToken = token;
      Settings.saveAccounts(providerId, accounts);
      return;
    }
    Settings.setString(`rt_${providerId}`, token);
  }

  /** 登录后写入令牌：有账号体系时更新激活账号，否则写旧键 */
  static applyRefreshedTokens(providerId: string, accessToken: string, refreshToken: string): void {
    const accounts = Settings.accounts(providerId);
    const activeAid = Settings.activeAccountId(providerId);
    const active = pickAccount(accounts, activeAid);
    if (active != null) {
      active.credential = accessToken;
      if (refreshToken.length > 0) {
        active.refreshToken = refreshToken;
      }
      Settings.saveAccounts(providerId, accounts);
      return;
    }
    Settings.setString(`${KEY_PREFIX}${providerId}_c1`, accessToken);
    if (refreshToken.length > 0) {
      Settings.setString(`rt_${providerId}`, refreshToken);
    }
  }

  /** 手工编辑凭证：有账号体系时写入激活账号，否则走旧键 */
  static saveProvider(providerId: string, setting: ProviderSetting): void {
    const accounts = Settings.accounts(providerId);
    const active = pickAccount(accounts, Settings.activeAccountId(providerId));
    if (active != null) {
      active.credential = setting.credential;
      active.credential2 = setting.credential2;
      Settings.saveAccounts(providerId, accounts);
      Settings.setString(`${PREFIX}${providerId}`, setting.enabled ? '1' : '0');
      return;
    }
    Settings.setString(`${PREFIX}${providerId}`, setting.enabled ? '1' : '0');
    Settings.setString(`${KEY_PREFIX}${providerId}_c1`, setting.credential);
    Settings.setString(`${KEY_PREFIX}${providerId}_c2`, setting.credential2);
  }

  // ---------------- 多账号（Claude/Codex 会话型） ----------------

  static accounts(providerId: string): ProviderAccount[] {
    return parseAccounts(Settings.getString(`acc_${providerId}`, ''));
  }

  static saveAccounts(providerId: string, list: ProviderAccount[]): void {
    Settings.setString(`acc_${providerId}`, accountsToJson(list));
  }

  static activeAccountId(providerId: string): string {
    return Settings.getString(`act_${providerId}`, '');
  }

  static setActiveAccountId(providerId: string, aid: string): void {
    Settings.setString(`act_${providerId}`, aid);
  }

  /** 登录结果入库：添加（或去重激活）账号并设为激活；返回生效账号与是否去重命中 */
  static addAccount(
    providerId: string,
    credential: string,
    credential2: string,
    refreshToken: string
  ): AddAccountResult {
    const list = Settings.accounts(providerId);
    const res = addAccountToList(list, credential, credential2, refreshToken, Date.now());
    Settings.saveAccounts(providerId, res.list);
    Settings.setActiveAccountId(providerId, res.account.aid);
    return res;
  }

  static removeAccount(providerId: string, aid: string): string {
    const list = Settings.accounts(providerId);
    const activeAid = Settings.activeAccountId(providerId);
    const res = removeAccountFromList(list, aid, activeAid);
    Settings.saveAccounts(providerId, res.list);
    Settings.setActiveAccountId(providerId, res.newActive);
    return res.newActive;
  }

  static renameAccount(providerId: string, aid: string, name: string): void {
    const list = Settings.accounts(providerId);
    Settings.saveAccounts(providerId, renameAccountInList(list, aid, name.trim()));
  }

  static accountCount(providerId: string): number {
    return Settings.accounts(providerId).length;
  }

  // ---------------- 桌面卡片（服务卡片）数据 ----------------

  /** 卡片数据 JSON（WidgetDataStore.update 写入，EntryFormAbility 读取） */
  static widgetData(): string {
    return Settings.getString('widget_data', '');
  }

  static setWidgetData(json: string): void {
    Settings.setString('widget_data', json);
  }

  /** 已添加卡片的 formId 列表（JSON 数组文本） */
  static formIds(): string[] {
    const raw = Settings.getString('widget_form_ids', '[]');
    try {
      const arr = JSON.parse(raw) as string[];
      if (!Array.isArray(arr)) {
        return [];
      }
      const out: string[] = [];
      for (let i = 0; i < arr.length; i++) {
        if (typeof arr[i] === 'string') {
          out.push(arr[i] as string);
        }
      }
      return out;
    } catch (e) {
      return [];
    }
  }

  static setFormIds(ids: string[]): void {
    Settings.setString('widget_form_ids', JSON.stringify(ids));
  }

  static addFormId(formId: string): void {
    if (formId.length === 0) {
      return;
    }
    const ids = Settings.formIds();
    if (ids.indexOf(formId) < 0) {
      ids.push(formId);
      Settings.setFormIds(ids);
    }
  }

  static removeFormId(formId: string): void {
    const ids = Settings.formIds();
    const next: string[] = [];
    for (let i = 0; i < ids.length; i++) {
      if (ids[i] !== formId) {
        next.push(ids[i]);
      }
    }
    Settings.setFormIds(next);
  }

  /** 清除凭证：激活账号与旧键、refresh token、启用标记一并清空（防回退链复活旧凭证） */
  static clearCredential(providerId: string): void {
    const accounts = Settings.accounts(providerId);
    const active = pickAccount(accounts, Settings.activeAccountId(providerId));
    if (active != null) {
      active.credential = '';
      active.credential2 = '';
      active.refreshToken = '';
      Settings.saveAccounts(providerId, accounts);
    }
    Settings.setString(`${PREFIX}${providerId}`, '0');
    Settings.setString(`${KEY_PREFIX}${providerId}_c1`, '');
    Settings.setString(`${KEY_PREFIX}${providerId}_c2`, '');
    Settings.setString(`rt_${providerId}`, '');
  }

  // ---------------- 用量历史（每日采样，统计页数据源） ----------------

  static history(providerId: string): HistoryDay[] {
    const raw = Settings.getString(`hist_${providerId}`, '[]');
    try {
      const arr = JSON.parse(raw) as HistoryDay[];
      if (!Array.isArray(arr)) {
        return [];
      }
      const out: HistoryDay[] = [];
      for (let i = 0; i < arr.length; i++) {
        const r = arr[i];
        if (r != null && typeof r.d === 'string' && typeof r.p === 'number' && typeof r.b === 'number') {
          out.push({ d: r.d as string, p: r.p as number, b: r.b as number });
        }
      }
      return out;
    } catch (e) {
      return [];
    }
  }

  static setHistory(providerId: string, records: HistoryDay[]): void {
    Settings.setString(`hist_${providerId}`, JSON.stringify(records));
  }
}
