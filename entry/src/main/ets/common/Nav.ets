/**
 * CodexBar Mobile — 路由导航辅助
 */

import { router, promptAction } from '@kit.ArkUI';

export class DetailRouteParam {
  id: string = '';
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

export class Nav {
  static toDetail(providerId: string): void {
    const p = new DetailRouteParam();
    p.id = providerId;
    router.pushUrl({ url: 'pages/ProviderDetail', params: p });
  }

  static toSettings(): void {
    router.pushUrl({ url: 'pages/SettingsPage' });
  }

  static toOAuthLogin(providerId: string): void {
    const p = new DetailRouteParam();
    p.id = providerId;
    router.pushUrl({ url: 'pages/OAuthLogin', params: p });
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
