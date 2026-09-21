/**
 * Claude（Web 会话方式）用量查询
 *
 * 迁移自 macOS 版 Sources/CodexBarCore/Providers/Claude/ClaudeWeb/ClaudeWebAPIFetcher.swift：
 * 1. GET https://claude.ai/api/organizations           （Cookie: sessionKey=...）→ 取组织 uuid
 * 2. GET https://claude.ai/api/organizations/{uuid}/usage
 *    → five_hour / seven_day / seven_day_opus(.sonnet) 三个窗口（utilization 0-100 + resets_at ISO8601）
 */

import { Http } from '../net/Http';
import { asArray, asObj, Json, optNum, optStr, str } from '../net/Json';
import { makeWindow, ProviderDescriptor, ProviderSetting, RateWindow, UsageSnapshot, AuthKind } from '../model/Models';
import { UsageProvider, UrlUtil } from './ProviderBase';

class ClaudeWebProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'claude',
    title: 'Claude',
    authKind: AuthKind.SESSION,
    accentColor: '#D97757',
    authHint: '粘贴 claude.ai 的 sessionKey（浏览器 Cookie，sk-ant-sid01-… 开头）',
    authUrl: 'https://claude.ai/settings/billing',
  };

  private headers(sessionKey: string): Record<string, string> {
    const h: Record<string, string> = {
      'cookie': `sessionKey=${sessionKey}`,
      'accept': 'application/json',
      'user-agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36',
    };
    return h;
  }

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const key = setting.credential.trim();
    if (key.length === 0) {
      return UsageSnapshot.failure('未配置 sessionKey');
    }
    const headers = this.headers(key);

    // 第一步：组织列表
    const orgResp = await Http.get('https://claude.ai/api/organizations', headers);
    if (!orgResp.ok) {
      return UsageSnapshot.failure(orgResp.errorText());
    }
    const orgs = asArray(orgResp.json());
    if (orgs == null || orgs.length === 0) {
      return UsageSnapshot.failure('未找到组织，sessionKey 可能已失效');
    }
    let orgId = '';
    let orgName = '';
    let email = '';
    // 若填了第二凭证（组织 ID）则精确匹配
    const wanted = setting.credential2.trim();
    for (let i = 0; i < orgs.length; i++) {
      const o = asObj(orgs[i]);
      if (o == null) {
        continue;
      }
      const uuid = str(o, 'uuid');
      if (wanted.length > 0 && uuid !== wanted) {
        continue;
      }
      orgId = uuid;
      orgName = str(o, 'name');
      email = str(o, 'email');
      break;
    }
    if (orgId.length === 0 && wanted.length === 0) {
      const first = asObj(orgs[0]);
      if (first != null) {
        orgId = str(first, 'uuid');
        orgName = str(first, 'name');
        email = str(first, 'email');
      }
    }
    if (orgId.length === 0) {
      return UsageSnapshot.failure('无法解析组织信息');
    }

    // 第二步：用量
    const usageUrl = `https://claude.ai/api/organizations/${UrlUtil.encode(orgId)}/usage`;
    const usageResp = await Http.get(usageUrl, headers);
    if (!usageResp.ok) {
      return UsageSnapshot.failure(usageResp.errorText());
    }
    const root = asObj(usageResp.json());
    if (root == null) {
      return UsageSnapshot.failure('响应解析失败');
    }

    const session = ClaudeWebProvider.windowOf(root, 'five_hour');
    const weekly = ClaudeWebProvider.windowOf(root, 'seven_day');
    let opus = ClaudeWebProvider.windowOf(root, 'seven_day_sonnet');
    if (opus == null) {
      opus = ClaudeWebProvider.windowOf(root, 'seven_day_opus');
    }

    const snap = UsageSnapshot.success(session, weekly, opus);
    snap.identity = { accountEmail: email, accountOrganization: orgName, loginMethod: 'sessionKey' };
    return snap;
  }

  /** 解析 {"utilization": 0-100, "resets_at": ISO} 形状 */
  private static windowOf(root: Record<string, Json>, key: string): RateWindow | null {
    const o = asObj(root[key]);
    if (o == null) {
      return null;
    }
    const util = optNum(o, 'utilization');
    if (util == null) {
      return null;
    }
    const percent = Math.max(0, Math.min(100, util));
    let resets = 0;
    const iso = optStr(o, 'resets_at');
    if (iso != null && iso.length > 0) {
      const parsed = Date.parse(iso);
      if (!isNaN(parsed)) {
        resets = parsed;
      }
    }
    return makeWindow(percent, resets, true);
  }
}

export function createClaudeProvider(): UsageProvider {
  return new ClaudeWebProvider();
}
