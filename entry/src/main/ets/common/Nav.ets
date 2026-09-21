/**
 * CodexBar Mobile — 路由导航辅助
 */

import { router, promptAction } from '@kit.ArkUI';

export class DetailRouteParam {
  id: string = '';
  /** 可选：'add' 表示网页登录用于新增账号（多账号） */
  mode: string = '';
}

/**
 * 解析详情页路由参数。
 * 跨端（ArkUI-X）序列化后参数可能退化为普通对象，不能用 instanceof 判定，
 * 这里按属性读取，兼容类实例 / 普通对象 / 空值三种形态。
 */
export function parseDetailParam(raw: Object | null): string {
  if (raw == null) {
    return '';
  }
  const p = raw as DetailRouteParam;
  if (p.id != null && typeof p.id === 'string') {
    return p.id as string;
  }
  return '';
}

/** 解析路由附加模式（跨端序列化后退化为普通对象，按属性读取） */
export function parseDetailMode(raw: Object | null): string {
  if (raw == null) {
    return '';
  }
  const p = raw as DetailRouteParam;
  if (p.mode != null && typeof p.mode === 'string') {
    return p.mode as string;
  }
  return '';
}

export class Nav {
  static toDetail(providerId: string): void {
    const p = new DetailRouteParam();
    p.id = providerId;
    router.pushUrl({ url: 'pages/ProviderDetail', params: p });
  }

  static toSettings(): void {
    router.pushUrl({ url: 'pages/SettingsPage' });
  }

  static toOAuthLogin(providerId: string, addMode: boolean = false): void {
    const p = new DetailRouteParam();
    p.id = providerId;
    p.mode = addMode ? 'add' : '';
    router.pushUrl({ url: 'pages/OAuthLogin', params: p });
  }

  /** 统计页；providerId 可为空（进入后自选服务商） */
  static toStats(providerId: string = ''): void {
    const p = new DetailRouteParam();
    p.id = providerId;
    router.pushUrl({ url: 'pages/StatsPage', params: p });
  }

  static back(): void {
    router.back();
  }

  static detailParam(): string {
    return parseDetailParam(router.getParams() as Object | null);
  }

  static toast(message: string): void {
    promptAction.showToast({ message: message, duration: 1800 });
  }
}
