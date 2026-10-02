/**
 * CodexBar Mobile — 中英文显示切换
 *
 * L(zh, en) 按当前语言返回对应文案；语言持久化在 Settings（键 app_lang），
 * 未设置时默认中文。切换经 setAppLang 持久化，由设置页自行 bump 触发重渲染。
 *
 * 单测环境（preferences 不可用）getString 回退默认值，语言恒为 zh，
 * 既有断言中文文案的用例不受影响。
 */

import { Settings } from '../store/Settings';

export type AppLang = 'zh' | 'en';

const LANG_KEY = 'app_lang';

let cached: AppLang = 'zh';
let inited: boolean = false;

/** 当前显示语言（首次调用时从持久化读取） */
export function currentLang(): AppLang {
  if (!inited) {
    cached = Settings.getString(LANG_KEY, 'zh') === 'en' ? 'en' : 'zh';
    inited = true;
  }
  return cached;
}

/** 切换语言并持久化；调用方负责触发界面重渲染（AppStore.bump()） */
export function setAppLang(lang: AppLang): void {
  cached = lang;
  inited = true;
  Settings.setString(LANG_KEY, lang);
}

/** 双语文案取值：中文原文 + 英文译文 */
export function L(zh: string, en: string): string {
  return currentLang() === 'en' ? en : zh;
}
