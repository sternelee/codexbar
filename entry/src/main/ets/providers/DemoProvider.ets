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
    // 随时间缓慢漂移，让统计页的柱形图有真实变化
    const driftPct = (now / 600000) % 40;
    const snap = UsageSnapshot.success(
      makeWindow(35 + driftPct, now + 3 * 3600 * 1000 + 12 * 60 * 1000, true),
      makeWindow(55 + (driftPct / 2), now + 4 * 86400 * 1000 + 7 * 3600 * 1000, true),
      makeWindow(25, now + 21 * 86400 * 1000, true)
    );
    snap.extraRateWindows = [
      { id: 'demo_opus', title: 'Opus 每周', window: makeWindow(70 + (driftPct / 4), now + 4 * 86400 * 1000, true) },
    ];
    const remaining = Math.max(0, 212.4 - (now / 1800000) % 30);
    snap.providerCost = {
      remaining: Math.round(remaining * 100) / 100,
      used: 787.6, currency: 'USD',
      displayText: Format.money(Math.round(remaining * 100) / 100, 'USD'),
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
