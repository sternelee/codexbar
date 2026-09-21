/**
 * 服务商第六批（审计点名修正，端点级对照源码）：
 * - HuggingFace: GET huggingface.co/api/settings/billing/usage-v2（Bearer，纳秒→美元）
 *                + /api/spaces/zero-gpu/quota（ZeroGPU 副窗口）
 * - Warp:        POST app.warp.dev/graphql/v2（API Key，GetRequestLimitInfo）
 * - OpenCode:    GET opencode.ai/_server?id={serverID}&args=[workspaceID]（Cookie，订阅 + PAYG 计费回退）
 * - OpenCodeGo:  同 _server 计费函数（Cookie）
 * - Groq:        POST api.stytchb2b.groq.com/sdk/v1/b2b/sessions/authenticate（Stytch 交换）
 *                → GET groq.com/platform/v1/organizations/{org}/activity
 */

import { util } from '@kit.ArkTS';
import { Http } from '../net/Http';
import { asArray, asObj, bool, Json, num, optNum, optStr, str } from '../net/Json';
import {
  AuthKind,
  makeWindow,
  ProviderCostSnapshot,
  ProviderDescriptor,
  ProviderDetailRow,
  ProviderDetailSection,
  ProviderSetting,
  RateWindow,
  UsageSnapshot
} from '../model/Models';
import { UsageProvider } from './ProviderBase';
import { Format } from '../common/Format';

// ---------------------------------------------------------------------------
// HuggingFace
// ---------------------------------------------------------------------------

class HuggingFaceProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'huggingface',
    title: 'HuggingFace',
    authKind: AuthKind.API_KEY,
    accentColor: '#FFD21E',
    authHint: '粘贴 HuggingFace Token（需 Billing 读权限）',
    authUrl: 'https://huggingface.co/settings/tokens',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const token = setting.credential.trim();
    if (token.length === 0) {
      return UsageSnapshot.failure('未配置 Token');
    }
    const headers: Record<string, string> = {
      'authorization': `Bearer ${token}`,
      'accept': 'application/json',
      'user-agent': 'CodexBar',
    };
    // 本月 1 日（UTC 秒）→ 现在
    const now = new Date();
    const start = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1) / 1000;
    const end = Math.floor(Date.now() / 1000);
    const resp = await Http.get(
      `https://huggingface.co/api/settings/billing/usage-v2?startDate=${start}&endDate=${end}`,
      headers
    );
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    const root = asObj(resp.json());
    const usage = root != null ? asObj(root['usage']) : null;
    const inference = usage != null ? asObj(usage['inferenceProviders']) : null;
    if (inference == null) {
      return UsageSnapshot.failure('响应缺少 inferenceProviders');
    }
    const gross = (optNum(inference, 'usedNanoUsd') ?? 0) / 1e9;
    const included = (optNum(inference, 'includedNanoUsd') ?? 0) / 1e9;
    const billable = Math.max(0, gross - included);
    const limit = (optNum(inference, 'limitNanoUsd') ?? 0) / 1e9;
    const requests = optNum(inference, 'numRequests');

    let primary: RateWindow | null = null;
    if (limit > 0) {
      primary = makeWindow(Math.min(100, (billable / limit) * 100), 0, true);
    }
    const snap = UsageSnapshot.success(primary, null, null);
    snap.providerCost = {
      remaining: Math.max(0, limit - billable), used: billable, currency: 'USD',
      displayText: Format.money(billable, 'USD'),
    };
    const rows: ProviderDetailRow[] = [
      { label: '本月消费', value: Format.money(gross, 'USD') },
      { label: '含额度抵扣', value: Format.money(included, 'USD') },
    ];
    if (limit > 0) {
      rows.push({ label: '上限', value: Format.money(limit, 'USD') });
    }
    if (requests != null) {
      rows.push({ label: '请求数', value: `${Math.round(requests)}` });
    }

    // ZeroGPU 副窗口（可选，失败不阻塞）
    const gpuResp = await Http.get('https://huggingface.co/api/spaces/zero-gpu/quota', headers);
    if (gpuResp.ok) {
      const gpu = asObj(gpuResp.json());
      const base = gpu != null ? optNum(gpu, 'base') : null;
      const current = gpu != null ? optNum(gpu, 'current') : null;
      if (gpu != null && base != null && current != null && base > 0) {
        const consumed = Math.max(0, base - current);
        let resets = 0;
        const rIso = optStr(gpu, 'resetsAt');
        if (rIso != null) {
          const parsed = Date.parse(rIso);
          if (!isNaN(parsed)) {
            resets = parsed;
          }
        }
        snap.secondary = makeWindow(Math.min(100, (consumed / base) * 100), resets, true);
        rows.push({ label: 'ZeroGPU 已用', value: `${Math.round(consumed / 60)} 分钟` });
        rows.push({ label: 'ZeroGPU 剩余', value: `${Math.round(current / 60)} 分钟` });
      }
    }
    const section: ProviderDetailSection = { title: '推理计费', rows: rows };
    snap.details = [section];
    return snap;
  }
}

// ---------------------------------------------------------------------------
// Warp
// ---------------------------------------------------------------------------

const WARP_QUERY = 'query GetRequestLimitInfo($requestContext: RequestContext!) { user(requestContext: $requestContext) { __typename ... on UserOutput { user { requestLimitInfo { isUnlimited nextRefreshTime requestLimit requestsUsedSinceLastRefresh } bonusGrants { requestCreditsGranted requestCreditsRemaining expiration } } } } }';

class WarpProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'warp',
    title: 'Warp',
    authKind: AuthKind.API_KEY,
    accentColor: '#FFFFFF',
    authHint: '粘贴 Warp API Key',
    authUrl: 'https://app.warp.dev/settings/credits',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const key = setting.credential.trim();
    if (key.length === 0) {
      return UsageSnapshot.failure('未配置 API Key');
    }
    const headers: Record<string, string> = {
      'authorization': `Bearer ${key}`,
      'content-type': 'application/json',
      'accept': 'application/json',
      'user-agent': 'Warp/1.0',
      'x-warp-client-id': 'warp-app',
      'x-warp-os-category': 'macOS',
      'x-warp-os-name': 'macOS',
      'x-warp-os-version': '15.0.0',
    };
    const body = '{"query":' + JSON.stringify(WARP_QUERY) +
      ',"variables":{"requestContext":{"clientContext":{},' +
      '"osContext":{"category":"macOS","name":"macOS","version":"15.0.0"}}},' +
      '"operationName":"GetRequestLimitInfo"}';
    const resp = await Http.post('https://app.warp.dev/graphql/v2', headers, body);
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    const root = asObj(resp.json());
    const data = root != null ? asObj(root['data']) : null;
    const user = data != null ? asObj(data['user']) : null;
    const inner = user != null ? asObj(user['user']) : null;
    const limitInfo = inner != null ? asObj(inner['requestLimitInfo']) : null;
    if (limitInfo == null) {
      const errors = root != null ? asArray(root['errors']) : null;
      return UsageSnapshot.failure(errors != null && errors.length > 0 ? 'GraphQL 错误' : '响应解析失败');
    }
    const unlimited = bool(limitInfo, 'isUnlimited');
    const requestLimit = num(limitInfo, 'requestLimit', 0);
    const used = num(limitInfo, 'requestsUsedSinceLastRefresh', 0);
    const resetIso = optStr(limitInfo, 'nextRefreshTime');
    let resets = 0;
    if (resetIso != null) {
      const parsed = Date.parse(resetIso);
      if (!isNaN(parsed)) {
        resets = parsed;
      }
    }
    let primary: RateWindow | null = null;
    if (unlimited) {
      primary = makeWindow(0, resets, true);
    } else if (requestLimit > 0) {
      primary = makeWindow(Math.min(100, (used / requestLimit) * 100), resets, true);
    }
    const snap = UsageSnapshot.success(primary, null, null);
    const rows: ProviderDetailRow[] = [
      { label: '本周期请求', value: `${Math.round(used)} / ${unlimited ? '∞' : Math.round(requestLimit)}` },
    ];
    const grants = inner != null ? asObj(inner['bonusGrants']) : null;
    if (grants != null) {
      const granted = optNum(grants, 'requestCreditsGranted');
      const remaining = optNum(grants, 'requestCreditsRemaining');
      if (remaining != null) {
        rows.push({ label: '赠额剩余', value: `${Math.round(remaining)}${granted != null ? ` / ${Math.round(granted)}` : ''}` });
      }
    }
    const section: ProviderDetailSection = { title: '请求额度', rows: rows };
    snap.details = [section];
    return snap;
  }
}

// ---------------------------------------------------------------------------
// OpenCode / OpenCodeGo（_server RPC，Cookie）
// ---------------------------------------------------------------------------

const OC_SUBSCRIPTION_SERVER = '7abeebee372f304e050aaaf92be863f4a86490e382f8c79db68fd94040d691b4';
const OC_BILLING_SERVER = 'c83b78a614689c38ebee981f9b39a8b377716db85c1fd7dbab604adc02d3313d';
const OC_WORKSPACES_SERVER = 'def39973159c7f0483d8793a822b8dbb10d067e12c65455fcb4608459ba0234f';

/** 递归查找第一个含 used/percent 形态字段的用量对象 */
function ocFindUsage(value: Json, depth: number): Record<string, Json> | null {
  if (depth > 6) {
    return null;
  }
  const o = asObj(value);
  if (o == null) {
    return null;
  }
  const percent = getPercent3(o);
  const cap = optNum(o, 'cap') ?? optNum(o, 'limit');
  const used = optNum(o, 'used') ?? optNum(o, 'consumed');
  if (percent != null || (used != null && cap != null && cap > 0)) {
    return o;
  }
  const keys = Object.keys(o);
  for (let i = 0; i < keys.length; i++) {
    const found = ocFindUsage(o[keys[i]], depth + 1);
    if (found != null) {
      return found;
    }
  }
  return null;
}

function getPercent3(o: Record<string, Json>): number | null {
  const v = optNum(o, 'percent_used') ?? optNum(o, 'used_percent') ?? optNum(o, 'percentage');
  if (v == null) {
    return null;
  }
  return v <= 1 ? v * 100 : v;
}

/** 从文本中提取第一个 32 位十六进制 workspace ID */
function ocExtractWorkspaceID(text: string): string | null {
  const matches = text.match(/[0-9a-f]{32}/g);
  if (matches != null && matches.length > 0) {
    return matches[0];
  }
  return null;
}

class OpenCodeBaseProvider implements UsageProvider {
  descriptor: ProviderDescriptor;
  private readonly payg: boolean;

  constructor(descriptor: ProviderDescriptor, payg: boolean) {
    this.descriptor = descriptor;
    this.payg = payg;
  }

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const cookie = setting.credential.trim();
    if (cookie.length === 0) {
      return UsageSnapshot.failure('未配置会话 Cookie');
    }
    const headers: Record<string, string> = {
      'cookie': cookie,
      'accept': 'application/json, text/plain, */*',
      'origin': 'https://opencode.ai',
    };

    // 工作区 ID：优先第二凭证，否则从 workspaces 函数提取
    let workspaceID = setting.credential2.trim();
    if (workspaceID.length === 0) {
      const wsResp = await Http.get(`https://opencode.ai/_server?id=${OC_WORKSPACES_SERVER}`, headers);
      if (wsResp.ok) {
        const extracted = ocExtractWorkspaceID(wsResp.body);
        if (extracted != null) {
          workspaceID = extracted;
        }
      }
    }
    if (workspaceID.length === 0) {
      return UsageSnapshot.failure('未能确定工作区 ID，可在设置第二栏手动填写');
    }

    const referer = `https://opencode.ai/workspace/${workspaceID}`;
    const wsHeaders: Record<string, string> = {
      'cookie': cookie,
      'accept': '*/*',
      'referer': referer,
      'origin': 'https://opencode.ai',
    };

    if (!this.payg) {
      // 订阅函数
      const subResp = await Http.get(
        `https://opencode.ai/_server?id=${OC_SUBSCRIPTION_SERVER}&args=${encodeURIComponent(`["${workspaceID}"]`)}`,
        wsHeaders
      );
      if (subResp.ok) {
        const root = asObj(subResp.json()) ?? ({} as Record<string, Json>);
        const usage = ocFindUsage(root, 0);
        if (usage != null) {
          return OpenCodeBaseProvider.snapshotFrom(usage, root);
        }
      }
    }

    // PAYG 计费回退（订阅失败或显式 PAYG 模式）
    const billResp = await Http.get(
      `https://opencode.ai/_server?id=${OC_BILLING_SERVER}&args=${encodeURIComponent(`["${workspaceID}"]`)}`,
      wsHeaders
    );
    if (billResp.ok) {
      const root = asObj(billResp.json()) ?? ({} as Record<string, Json>);
      const usage = ocFindUsage(root, 0);
      if (usage != null) {
        return OpenCodeBaseProvider.snapshotFrom(usage, root);
      }
    }
    return UsageSnapshot.failure('未解析到用量（订阅与计费函数均无数据）');
  }

  private static snapshotFrom(usage: Record<string, Json>, root: Record<string, Json>): UsageSnapshot {
    let percent = getPercent3(usage);
    const cap = optNum(usage, 'cap') ?? optNum(usage, 'limit');
    const used = optNum(usage, 'used') ?? optNum(usage, 'consumed');
    if (percent == null && used != null && cap != null && cap > 0) {
      percent = (used / cap) * 100;
    }
    if (percent == null) {
      return UsageSnapshot.failure('用量字段缺失');
    }
    let resets = 0;
    const renewIso = optStr(usage, 'renews_at') ?? optStr(usage, 'renewsAt') ?? optStr(root, 'renews_at');
    if (renewIso != null) {
      resets = isoMs5(renewIso);
    }
    const snap = UsageSnapshot.success(makeWindow(Math.max(0, Math.min(100, percent)), resets, true), null, null);
    const balance = optNum(usage, 'balance');
    if (balance != null) {
      snap.providerCost = {
        remaining: balance, used: 0, currency: 'USD',
        displayText: Format.money(balance, 'USD'),
      };
    }
    return snap;
  }
}

function isoMs5(iso: string | null): number {
  if (iso == null || iso.length === 0) {
    return 0;
  }
  const parsed = Date.parse(iso);
  return isNaN(parsed) ? 0 : parsed;
}

class OpenCodeProvider extends OpenCodeBaseProvider {
  constructor() {
    super({
      id: 'opencode',
      title: 'OpenCode',
      authKind: AuthKind.SESSION,
      accentColor: '#F4A261',
      authHint: '粘贴 opencode.ai 会话 Cookie；可选第二栏填工作区 ID',
      authUrl: 'https://opencode.ai/workspace',
    }, false);
  }
}

class OpenCodeGoProvider extends OpenCodeBaseProvider {
  constructor() {
    super({
      id: 'opencodego',
      title: 'OpenCode Go',
      authKind: AuthKind.SESSION,
      accentColor: '#E76F51',
      authHint: '粘贴 opencode.ai 会话 Cookie（Go 计划）',
      authUrl: 'https://opencode.ai/workspace',
    }, true);
  }
}

// ---------------------------------------------------------------------------
// Groq（Stytch 会话交换 + 活动 API）
// ---------------------------------------------------------------------------

class GroqProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'groq',
    title: 'Groq',
    authKind: AuthKind.SESSION,
    accentColor: '#F55036',
    authHint: '粘贴 groq.com 的 stytch_session Cookie；可选第二栏填组织 ID',
    authUrl: 'https://console.groq.com/settings/organization',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const cookie = setting.credential.trim();
    if (cookie.length === 0) {
      return UsageSnapshot.failure('未配置会话 Cookie');
    }
    // 从 Cookie 中取 stytch_session 值
    let sessionToken = cookie;
    const marker = 'stytch_session=';
    const idx = cookie.indexOf(marker);
    if (idx >= 0) {
      const rest = cookie.substring(idx + marker.length);
      const end = rest.indexOf(';');
      sessionToken = (end >= 0 ? rest.substring(0, end) : rest).trim();
    }
    if (sessionToken.length === 0) {
      return UsageSnapshot.failure('Cookie 中未找到 stytch_session');
    }

    // 1. Stytch 会话交换
    const publicToken = 'public-token-live-58df57a9-a1f5-4066-bc0c-2ff942db684f';
    const encoder = new util.TextEncoder();
    const bytes = encoder.encodeInto(`${publicToken}:${sessionToken}`);
    const basic = `Basic ${new util.Base64Helper().encodeToStringSync(bytes)}`;
    const authHeaders: Record<string, string> = {
      'authorization': basic,
      'content-type': 'application/json',
      'origin': 'https://groq.com',
    };
    const authResp = await Http.post(
      'https://api.stytchb2b.groq.com/sdk/v1/b2b/sessions/authenticate',
      authHeaders,
      JSON.stringify({ session_token: sessionToken, session_duration_minutes: 30 })
    );
    if (!authResp.ok) {
      return UsageSnapshot.failure('会话交换失败，Cookie 可能已过期');
    }
    const authRoot = asObj(authResp.json());
    const authData = authRoot != null ? asObj(authRoot['data']) : null;
    const jwt = authData != null ? optStr(authData, 'session_jwt') : null;
    if (jwt == null || jwt.length === 0) {
      return UsageSnapshot.failure('会话交换响应缺少 JWT');
    }

    // 2. 组织 ID：优先第二凭证，否则从组织列表取第一个
    let orgId = setting.credential2.trim();
    if (orgId.length === 0) {
      const orgHeaders: Record<string, string> = {
        'authorization': `Bearer ${jwt}`,
        'accept': 'application/json',
      };
      const orgResp = await Http.get('https://groq.com/platform/v1/organizations', orgHeaders);
      if (orgResp.ok) {
        const orgRoot = asObj(orgResp.json());
        const orgs = orgRoot != null ? asArray(orgRoot['data']) : null;
        if (orgs != null && orgs.length > 0) {
          const first = asObj(orgs[0]);
          if (first != null) {
            orgId = str(first, 'id', str(first, 'slug', ''));
          }
        }
      }
    }
    if (orgId.length === 0) {
      return UsageSnapshot.failure('未能确定组织 ID，可在设置第二栏手动填写');
    }

    // 3. 近 30 天活动
    const endSec = Math.floor(Date.now() / 1000);
    const startSec = endSec - 30 * 86400;
    const actHeaders: Record<string, string> = {
      'authorization': `Bearer ${jwt}`,
      'accept': 'application/json',
    };
    const actResp = await Http.get(
      `https://groq.com/platform/v1/organizations/${encodeURIComponent(orgId)}/activity` +
      `?start_date=${startSec}&end_date=${endSec}`,
      actHeaders
    );
    if (!actResp.ok) {
      return UsageSnapshot.failure(actResp.errorText());
    }
    const actRoot = asObj(actResp.json());
    const rows = actRoot != null ? asArray(actRoot['data']) : null;
    let requests = 0;
    let contextTokens = 0;
    let generatedTokens = 0;
    let orgName = '';
    if (rows != null) {
      for (let i = 0; i < rows.length; i++) {
        const r = asObj(rows[i]);
        if (r == null) {
          continue;
        }
        requests += num(r, 'num_requests', 0);
        contextTokens += num(r, 'n_context_tokens_total', 0);
        generatedTokens += num(r, 'n_generated_tokens_total', 0);
        if (orgName.length === 0) {
          orgName = str(r, 'organization_name', '');
        }
      }
    }
    const snap = UsageSnapshot.success(null, null, null);
    snap.identity = { accountEmail: '', accountOrganization: orgName, loginMethod: 'Console Cookie' };
    const detailRows: ProviderDetailRow[] = [
      { label: '近 30 天请求', value: `${requests}` },
      { label: '上下文 Token', value: Format.compact(contextTokens) },
      { label: '生成 Token', value: Format.compact(generatedTokens) },
    ];
    const section: ProviderDetailSection = { title: '活动用量', rows: detailRows };
    snap.details = [section];
    return snap;
  }
}

export function createHuggingFaceProvider(): UsageProvider {
  return new HuggingFaceProvider();
}

export function createWarpProvider(): UsageProvider {
  return new WarpProvider();
}

export function createOpenCodeProvider(): UsageProvider {
  return new OpenCodeProvider();
}

export function createOpenCodeGoProvider(): UsageProvider {
  return new OpenCodeGoProvider();
}

export function createGroqProvider(): UsageProvider {
  return new GroqProvider();
}
