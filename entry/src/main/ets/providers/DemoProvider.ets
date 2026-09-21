/**
 * 演示 Provider — 无需凭证，生成拟真快照
 * 用于 UI 演示与无网络场景验证。
 */

import {
  AuthKind,
  makeWindow,
  ProviderDescriptor,
  ProviderSetting,
  UsageSnapshot
} from '../model/Models';
import { UsageProvider } from './ProviderBase';
import { Format } from '../common/Format';

class DemoProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'demo',
    title: '演示模式',
    authKind: AuthKind.DEMO,
    accentColor: '#16D3B4',
    authHint: '无需凭证，展示拟真数据用于体验界面',
    authUrl: '',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const now = Date.now();
    const snap = UsageSnapshot.success(
      makeWindow(42, now + 3 * 3600 * 1000 + 12 * 60 * 1000, true),
      makeWindow(68, now + 4 * 86400 * 1000 + 7 * 3600 * 1000, true),
      makeWindow(25, now + 21 * 86400 * 1000, true)
    );
    snap.extraRateWindows = [
      { id: 'demo_opus', title: 'Opus 每周', window: makeWindow(81, now + 4 * 86400 * 1000, true) },
    ];
    snap.providerCost = {
      remaining: 212.4, used: 787.6, currency: 'USD',
      displayText: Format.money(212.4, 'USD'),
    };
    snap.identity = {
      accountEmail: 'demo@codexbar.app',
      accountOrganization: 'CodexBar Demo',
      loginMethod: '演示数据',
    };
    snap.details = [{
      title: '演示说明',
      rows: [
        { label: '数据', value: '本页为拟真演示数据' },
        { label: '用途', value: '体验仪表盘与倒计时交互' },
      ],
    }];
    return snap;
  }
}

export function createDemoProvider(): UsageProvider {
  return new DemoProvider();
}
