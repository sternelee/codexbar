/**
 * Codex / ChatGPT 用量查询（OAuth 访问令牌 + Personal Access Token 两条路径共存）
 *
 * 1. OAuth 路径（迁移自 CodexOAuth/CodexOAuthUsageFetcher.swift）：
 *    GET https://chatgpt.com/backend-api/wham/usage（Bearer + 可选 ChatGPT-Account-Id）
 *    401/403 时用存储的 refresh token 静默续期并重试一次
 * 2. PAT 路径（迁移自 CodexPAT/CodexPATUsageFetcher.swift）：
 *    GET https://auth.openai.com/api/accounts/v1/user-auth-credential/whoami
 *    → { chatgpt_account_id, chatgpt_plan_type, email }（身份取自令牌本身，
 *      避免沿用已失效的 ChatGPT-Account-Id 查询到错误账号），再带上账号 ID 查用量
 *
 * 两种令牌都是 Bearer，先用 OAuth 直连，失败再按 PAT 推导账号 ID 重试，
 * 因此用户既可以在设置页「网页登录」授权，也可以粘贴 PAT。
 * 认证头与 Codex CLI 一致：Authorization: Bearer、originator: codex_cli_rs、
 * User-Agent: codex_cli_rs (…)（对应 CodexCLIUserAgent.make）。
 */

import { Http, HttpResult } from '../net/Http';
import { asArray, asObj, Json, optNum, optStr, str } from '../net/Json';
import {
  AuthKind,
  makeWindow,
  NamedRateWindow,
  ProviderCostSnapshot,
  ProviderDescriptor,
  ProviderSetting,
  RateWindow,
  UsageSnapshot
} from '../model/Models';
import { UsageProvider } from './ProviderBase';
import { Settings } from '../store/Settings';
import { AppStore } from '../store/AppStore';
import { codexRefreshToken, CodexTokenSet } from '../common/OAuth';

const WHOAMI_URL = 'https://auth.openai.com/api/accounts/v1/user-auth-credential/whoami';
const USAGE_URL = 'https://chatgpt.com/backend-api/wham/usage';
const ORIGINATOR = 'codex_cli_rs';
const USER_AGENT = `${ORIGINATOR} (HarmonyOS; arm64)`;

/** whoami 结果 */
class CodexIdentity {
  accountId: string = '';
  email: string = '';
  planType: string = '';
}

class CodexProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'codex',
    title: 'Codex (ChatGPT)',
    authKind: AuthKind.OAUTH_TOKEN,
    accentColor: '#10A37F',
    authHint: '在设置页「网页登录」授权，或粘贴 ChatGPT OAuth access token / OpenAI Personal Access Token；可选第二栏填账号 ID',
    authUrl: 'https://chatgpt.com/codex',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    let token = setting.credential.trim();
    if (token.length === 0) {
      return UsageSnapshot.failure('未配置 access token / Personal Access Token');
    }
    const accountId = setting.credential2.trim();

    // 1. OAuth 路径：直接带令牌查询，过期则用 refresh token 静默续期后重试一次
    let whoami = new CodexIdentity();
    let resp = await CodexProvider.fetchUsage(token, accountId);
    if (resp.code === 401 || resp.code === 403) {
      const refreshed = await CodexProvider.tryRefresh();
      if (refreshed.error.length === 0) {
        token = refreshed.accessToken;
        CodexProvider.persistTokens(refreshed);
        resp = await CodexProvider.fetchUsage(token, accountId);
      }
    }

    // 2. OAuth 不成立：按 PAT 用 whoami 推导账号 ID 再试一次
    if (!resp.ok) {
      whoami = await CodexProvider.fetchWhoami(token);
      const derived = whoami.accountId.length > 0 ? whoami.accountId : accountId;
      resp = await CodexProvider.fetchUsage(token, derived);
    }

    if (!resp.ok) {
      if (resp.code === 401 || resp.code === 403) {
        return UsageSnapshot.failure('令牌无效、已过期或无权访问该账号');
      }
      return UsageSnapshot.failure(resp.errorText());
    }
    return CodexProvider.parseUsage(resp, whoami);
  }

  /** 尝试 refresh token 换新 access token；无存储或换发失败返回 error 非空 */
  private static async tryRefresh(): Promise<CodexTokenSet> {
    const rt = Settings.oauthRefreshToken('codex');
    if (rt.length === 0) {
      const none: CodexTokenSet = { accessToken: '', refreshToken: '', accountId: '', error: 'no_refresh_token' };
      return none;
    }
    return codexRefreshToken(rt);
  }

  /** 续期后的令牌写回存储（激活账号或旧键）与状态中心，下次查询/展示直接用新值 */
  private static persistTokens(set: CodexTokenSet): void {
    Settings.applyRefreshedTokens('codex', set.accessToken, set.refreshToken);
    const state = AppStore.get().find('codex');
    if (state != null) {
      state.setting.credential = set.accessToken;
    }
  }

  private static headers(token: string, accountId: string): Record<string, string> {
    const headers: Record<string, string> = {
      'authorization': `Bearer ${token}`,
      'accept': 'application/json',
      'originator': ORIGINATOR,
      'user-agent': USER_AGENT,
    };
    if (accountId.length > 0) {
      headers['chatgpt-account-id'] = accountId;
    }
    return headers;
  }

  /** 身份查询失败不阻断用量查询（Swift 端 whoami 失败会抛错，这里降级为无身份） */
  private static async fetchWhoami(token: string): Promise<CodexIdentity> {
    const id = new CodexIdentity();
    const resp = await Http.get(WHOAMI_URL, CodexProvider.headers(token, ''));
    if (!resp.ok) {
      return id;
    }
    const root = asObj(resp.json());
    if (root == null) {
      return id;
    }
    id.accountId = str(root, 'chatgpt_account_id');
    id.email = str(root, 'email');
    id.planType = str(root, 'chatgpt_plan_type');
    return id;
  }

  private static fetchUsage(token: string, accountId: string): Promise<HttpResult> {
    return Http.get(USAGE_URL, CodexProvider.headers(token, accountId));
  }

  private static parseUsage(resp: HttpResult, whoami: CodexIdentity): UsageSnapshot {
    const root = asObj(resp.json());
    if (root == null) {
      return UsageSnapshot.failure('响应解析失败');
    }

    let limitNode = asObj(root['rate_limit']);
    if (limitNode == null) {
      limitNode = root;
    }

    const primary = CodexProvider.windowOf(limitNode, 'primary_window');
    const secondary = CodexProvider.windowOf(limitNode, 'secondary_window');

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
        const w = CodexProvider.windowOf(rl, 'primary_window');
        if (w != null) {
          extra.push({ id: `addl_${i}`, title: name, window: w });
        }
      }
    }

    // 窗口标签对照 macOS CodexProviderDescriptor：sessionLabel "Session" / weeklyLabel "Weekly"
    const snap = UsageSnapshot.success(primary, secondary, null);
    snap.primaryLabel = 'Session';
    snap.secondaryLabel = 'Weekly';
    // Extra usage（对照 CodexExtraUsageCost：currencyCode "Credits"、period "Extra usage"）
    const cost = CodexProvider.extraUsageCost(root);
    if (cost != null) {
      snap.providerCost = cost;
    }
    snap.extraRateWindows = extra;
    const email = whoami.email;
    if (email.length > 0 || whoami.planType.length > 0) {
      snap.identity = {
        accountEmail: email,
        accountOrganization: '',
        loginMethod: whoami.planType.length > 0 ? `PAT · ${whoami.planType}` : 'PAT',
      };
    } else {
      // 网页登录（OAuth）令牌：身份信息由 OAuthLogin 页展示，这里只标注登录方式
      snap.identity = { accountEmail: '', accountOrganization: '', loginMethod: 'OAuth' };
    }
    return snap;
  }

  /**
   * wham/usage 的 credits 节点 → 费用卡（对照 CodexExtraUsageCost）：
   * 币种固定 "Credits"、period "Extra usage"；无上限与已用（used/limit 均 0）。
   * unlimited 或完全未报告余额时不展示。
   */
  private static extraUsageCost(root: Record<string, Json>): ProviderCostSnapshot | null {
    const credits = asObj(root['credits']);
    if (credits == null) {
      return null;
    }
    if (credits['unlimited'] === true) {
      return null;
    }
    const hasCredits = credits['has_credits'] === true;
    let balance = optNum(credits, 'balance');
    if (balance == null) {
      const text = optStr(credits, 'balance');
      if (text != null && text.length > 0) {
        const parsed = parseFloat(text);
        balance = isNaN(parsed) ? null : parsed;
      }
    }
    if (!hasCredits && balance == null) {
      return null;
    }
    const remaining = balance != null ? balance : 0;
    const cost: ProviderCostSnapshot = {
      remaining: remaining,
      used: 0,
      currency: 'Credits',
      displayText: `${Math.round(remaining * 100) / 100} Credits`,
      period: 'Extra usage',
      limit: 0,
    };
    return cost;
  }

  /** used_percent / reset_at(unix 秒) / limit_window_seconds */
  private static windowOf(node: Record<string, Json>, key: string): RateWindow | null {
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
