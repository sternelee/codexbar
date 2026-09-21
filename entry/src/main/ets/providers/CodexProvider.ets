/**
 * Codex / ChatGPT（OAuth 访问令牌方式）用量查询
 *
 * 迁移自 macOS 版 Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthUsageFetcher.swift：
 * GET https://chatgpt.com/backend-api/wham/usage
 *   Authorization: Bearer <accessToken>   （可选 ChatGPT-Account-Id 头）
 * → { "rate_limit": { "primary_window": {used_percent, reset_at(unix秒), limit_window_seconds},
 *                      "secondary_window": {...} },
 *     "additional_rate_limits": [{limit_name, rate_limit:{...}}] }
 */

import { Http } from '../net/Http';
import { asArray, asObj, Json, num, optNum, str } from '../net/Json';
import { makeWindow, NamedRateWindow, ProviderDescriptor, ProviderSetting, RateWindow, UsageSnapshot, AuthKind } from '../model/Models';
import { UsageProvider } from './ProviderBase';

class CodexProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'codex',
    title: 'Codex (ChatGPT)',
    authKind: AuthKind.OAUTH_TOKEN,
    accentColor: '#10A37F',
    authHint: '粘贴 ChatGPT OAuth access token；可选第二栏填组织/账号 ID（ChatGPT-Account-Id）',
    authUrl: 'https://chatgpt.com/codex',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const token = setting.credential.trim();
    if (token.length === 0) {
      return UsageSnapshot.failure('未配置 access token');
    }
    const headers: Record<string, string> = {
      'authorization': `Bearer ${token}`,
      'accept': 'application/json',
      'user-agent': 'CodexBar',
    };
    const accountId = setting.credential2.trim();
    if (accountId.length > 0) {
      headers['chatgpt-account-id'] = accountId;
    }

    const resp = await Http.get('https://chatgpt.com/backend-api/wham/usage', headers);
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    const root = asObj(resp.json());
    if (root == null) {
      return UsageSnapshot.failure('响应解析失败');
    }

    // 根级或 rate_limit 节点
    let limitNode = asObj(root['rate_limit']);
    if (limitNode == null) {
      limitNode = root;
    }

    const primary = CodexProvider.windowOf(limitNode, 'primary_window', 5 * 3600);
    const secondary = CodexProvider.windowOf(limitNode, 'secondary_window', 7 * 86400);

    const extra: NamedRateWindow[] = [];
    const addls = asArray(root['additional_rate_limits']);
    if (addls != null) {
      for (let i = 0; i < addls.length && extra.length < 4; i++) {
        const item = asObj(addls[i]);
        if (item == null) {
          continue;
        }
        const name = str(item, 'limit_name', '附加限制');
        const rl = asObj(item['rate_limit']);
        if (rl == null) {
          continue;
        }
        const w = CodexProvider.windowOf(rl, 'primary_window', 0);
        if (w != null) {
          extra.push({ id: `addl_${i}`, title: name, window: w });
        }
      }
    }

    const snap = UsageSnapshot.success(primary, secondary, null);
    snap.extraRateWindows = extra;
    return snap;
  }

  /** used_percent / reset_at(unix 秒) / limit_window_seconds */
  private static windowOf(node: Record<string, Json>, key: string, fallbackSeconds: number): RateWindow | null {
    const o = asObj(node[key]);
    if (o == null) {
      return null;
    }
    const used = optNum(o, 'used_percent');
    if (used == null) {
      return null;
    }
    const resetSec = optNum(o, 'reset_at');
    const resets = resetSec != null && resetSec > 0 ? resetSec * 1000 : 0;
    return makeWindow(Math.max(0, Math.min(100, used)), resets, true);
  }
}

export function createCodexProvider(): UsageProvider {
  return new CodexProvider();
}
