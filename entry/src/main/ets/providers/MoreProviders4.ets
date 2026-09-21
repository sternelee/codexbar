/**
 * 服务商第五批（对照 macOS 版 UsageFetcher 逐家迁移，覆盖审计点名的可行集）：
 * API-Key 类：
 * - ElevenLabs: GET api.elevenlabs.io/v1/user/subscription（xi-api-key）
 * - Fireworks:  GET /v1/accounts → /v1/accounts/{slug}/billing/summary（Bearer）
 * - NeuralWatt: GET api.neuralwatt.com/v1/quota（Bearer）
 * - IBMBob:     GET api.us-east.bob.ibm.com/admin/v1/profile + {region}/admin/v1/teams（Bearer|Apikey）
 * - AiAnd:      GET api.aiand.com/logs?range=30days（Bearer，分页汇总花费）
 * - Codebuff:   GET www.codebuff.com/api/v1/usage + /api/user/subscription（Bearer）
 * - Sub2API:    GET {base}?days=30&timezone=...（Bearer，自托管）
 * Cookie/令牌类：
 * - Devin:      GET app.devin.ai/api/{org}/billing/quota/usage（Bearer）
 * - Abacus:     GET apps.abacus.ai/api/_getBillingInfo（Cookie）
 * - CommandCode:GET api.commandcode.ai/internal/billing/{credits,subscriptions}（Cookie）
 * - LongCat:    GET longcat.chat/api/...（Cookie，token lots）
 * - ZoomMate:   GET zoommate.zoom.us/ai-computer/api/v1/credits/status（Bearer/Cookie）
 * - Notion:     POST app.notion.com/api/v3/{getSpaces,getCreditRateLimitStatus}（Cookie token_v2）
 */

import { Http, HttpResult } from '../net/Http';
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

function isoMs3(iso: string | null): number {
  if (iso == null || iso.length === 0) {
    return 0;
  }
  const parsed = Date.parse(iso);
  return isNaN(parsed) ? 0 : parsed;
}

function get3(o: Record<string, Json>, keys: string[]): Json {
  for (let i = 0; i < keys.length; i++) {
    const v = o[keys[i]];
    if (v != null) {
      return v;
    }
  }
  return null;
}

function getNum3(o: Record<string, Json>, keys: string[]): number | null {
  const v = get3(o, keys);
  if (typeof v === 'number') {
    return v as number;
  }
  if (typeof v === 'string') {
    const parsed = parseFloat(v as string);
    if (!isNaN(parsed)) {
      return parsed;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// ElevenLabs
// ---------------------------------------------------------------------------

class ElevenLabsProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'elevenlabs',
    title: 'ElevenLabs',
    authKind: AuthKind.API_KEY,
    accentColor: '#000000',
    authHint: '粘贴 ElevenLabs API Key',
    authUrl: 'https://elevenlabs.io/app/settings/api-keys',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const key = setting.credential.trim();
    if (key.length === 0) {
      return UsageSnapshot.failure('未配置 API Key');
    }
    const headers: Record<string, string> = { 'xi-api-key': key, 'accept': 'application/json' };
    const resp = await Http.get('https://api.elevenlabs.io/v1/user/subscription', headers);
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    const root = asObj(resp.json());
    if (root == null) {
      return UsageSnapshot.failure('响应解析失败');
    }
    const used = num(root, 'character_count', 0);
    const limit = num(root, 'character_limit', 0);
    const resetSec = optNum(root, 'next_character_count_reset_unix');
    let primary: RateWindow | null = null;
    if (limit > 0) {
      primary = makeWindow(Math.min(100, (used / limit) * 100), resetSec != null && resetSec > 0 ? resetSec * 1000 : 0, true);
    }
    const snap = UsageSnapshot.success(primary, null, null);
    const rows: ProviderDetailRow[] = [
      { label: '字符用量', value: `${Format.compact(used)} / ${Format.compact(limit)}` },
    ];
    const tier = optStr(root, 'tier');
    if (tier != null) {
      rows.push({ label: '套餐', value: tier });
    }
    const section: ProviderDetailSection = { title: '订阅', rows: rows };
    snap.details = [section];
    return snap;
  }
}

// ---------------------------------------------------------------------------
// Fireworks
// ---------------------------------------------------------------------------

class FireworksProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'fireworks',
    title: 'Fireworks',
    authKind: AuthKind.API_KEY,
    accentColor: '#FF5C00',
    authHint: '粘贴 Fireworks API Key',
    authUrl: 'https://app.fireworks.ai/settings/api-keys',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const key = setting.credential.trim();
    if (key.length === 0) {
      return UsageSnapshot.failure('未配置 API Key');
    }
    const headers: Record<string, string> = {
      'authorization': `Bearer ${key}`,
      'accept': 'application/json',
    };
    const accountsResp = await Http.get('https://api.fireworks.ai/v1/accounts', headers);
    if (!accountsResp.ok) {
      return UsageSnapshot.failure(accountsResp.errorText());
    }
    const accRoot = asObj(accountsResp.json());
    const accounts = accRoot != null ? asArray(accRoot['accounts']) : null;
    if (accounts == null || accounts.length === 0) {
      return UsageSnapshot.failure('未找到账户');
    }
    const first = asObj(accounts[0]);
    let slug = first != null ? str(first, 'name') : '';
    if (slug.length === 0) {
      return UsageSnapshot.failure('无法解析账户');
    }
    if (slug.indexOf('accounts/') === 0) {
      slug = slug.substring('accounts/'.length);
    }
    // 近 30 天计费汇总
    const end = new Date(Date.now());
    const startD = new Date(Date.now() - 30 * 86400 * 1000);
    const iso = (d: Date): string => d.toISOString();
    const summaryResp = await Http.get(
      `https://api.fireworks.ai/v1/accounts/${encodeURIComponent(slug)}/billing/summary` +
      `?startTime=${encodeURIComponent(iso(startD))}&endTime=${encodeURIComponent(iso(end))}`,
      headers
    );
    if (!summaryResp.ok) {
      return UsageSnapshot.failure(summaryResp.errorText());
    }
    const sumRoot = asObj(summaryResp.json());
    const lineItems = sumRoot != null ? asArray(sumRoot['lineItems']) : null;
    let total = 0;
    let currency = 'USD';
    if (lineItems != null) {
      for (let i = 0; i < lineItems.length; i++) {
        const item = asObj(lineItems[i]);
        if (item == null) {
          continue;
        }
        const cost = asObj(item['totalCost']);
        if (cost == null) {
          continue;
        }
        const units = optNum(cost, 'units') ?? 0;
        const nanos = optNum(cost, 'nanos') ?? 0;
        total += units + nanos / 1e9;
        const code = optStr(cost, 'currencyCode');
        if (code != null) {
          currency = code;
        }
      }
    }
    const snap = UsageSnapshot.success(null, null, null);
    snap.providerCost = {
      remaining: 0, used: total, currency: currency,
      displayText: Format.money(total, currency),
    };
    const rows: ProviderDetailRow[] = [
      { label: '账户', value: slug },
      { label: '近 30 天消费', value: Format.money(total, currency) },
    ];
    const section: ProviderDetailSection = { title: '计费', rows: rows };
    snap.details = [section];
    return snap;
  }
}

// ---------------------------------------------------------------------------
// NeuralWatt
// ---------------------------------------------------------------------------

class NeuralWattProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'neuralwatt',
    title: 'NeuralWatt',
    authKind: AuthKind.API_KEY,
    accentColor: '#3B82F6',
    authHint: '粘贴 NeuralWatt API Key',
    authUrl: 'https://portal.neuralwatt.com/dashboard',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const key = setting.credential.trim();
    if (key.length === 0) {
      return UsageSnapshot.failure('未配置 API Key');
    }
    const headers: Record<string, string> = {
      'authorization': `Bearer ${key}`,
      'accept': 'application/json',
    };
    const resp = await Http.get('https://api.neuralwatt.com/v1/quota', headers);
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    const root = asObj(resp.json());
    if (root == null) {
      return UsageSnapshot.failure('响应解析失败');
    }
    const remaining = getNum3(root, ['credits_remaining_usd']) ?? 0;
    const used = getNum3(root, ['credits_used_usd']) ?? 0;
    const allowance = getNum3(root, ['allowance']) ?? 0;
    let primary: RateWindow | null = null;
    if (allowance > 0) {
      primary = makeWindow(Math.min(100, (used / allowance) * 100), isoMs3(optStr(root, 'current_period_end')), true);
    }
    const snap = UsageSnapshot.success(primary, null, null);
    snap.providerCost = {
      remaining: remaining, used: used, currency: 'USD',
      displayText: Format.money(remaining, 'USD'),
    };
    const rows: ProviderDetailRow[] = [
      { label: '额度余量', value: Format.money(remaining, 'USD') },
      { label: '已使用', value: Format.money(used, 'USD') },
    ];
    if (allowance > 0) {
      rows.push({ label: '周期额度', value: Format.money(allowance, 'USD') });
    }
    const section: ProviderDetailSection = { title: '配额', rows: rows };
    snap.details = [section];
    return snap;
  }
}

// ---------------------------------------------------------------------------
// IBM Bob
// ---------------------------------------------------------------------------

class IBMBobProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'ibmbob',
    title: 'IBM Bob',
    authKind: AuthKind.API_KEY,
    accentColor: '#0F62FE',
    authHint: '粘贴 IBM Bob API Key（JWT 或 Apikey）',
    authUrl: 'https://bob.ibm.com',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const key = setting.credential.trim();
    if (key.length === 0) {
      return UsageSnapshot.failure('未配置 API Key');
    }
    const isJwt = key.split('.').length === 3;
    const headers: Record<string, string> = {
      'authorization': isJwt ? `Bearer ${key}` : `Apikey ${key}`,
      'accept': 'application/json',
    };
    const profileResp = await Http.get('https://api.us-east.bob.ibm.com/admin/v1/profile', headers);
    if (!profileResp.ok) {
      return UsageSnapshot.failure(profileResp.errorText());
    }
    const profile = asObj(profileResp.json());
    const instances = profile != null ? asArray(profile['instances']) : null;
    if (instances == null || instances.length === 0) {
      return UsageSnapshot.failure('未返回订阅实例');
    }
    const inst = asObj(instances[0]);
    if (inst == null) {
      return UsageSnapshot.failure('响应解析失败');
    }
    const regionDomain = str(inst, 'region_domain', 'https://api.us-east.bob.ibm.com');
    const instanceId = str(inst, 'instance_id');
    const planName = optStr(inst, 'plan_name');

    const teamsHeaders: Record<string, string> = {
      'authorization': isJwt ? `Bearer ${key}` : `Apikey ${key}`,
      'accept': 'application/json',
      'x-instance-id': instanceId,
    };
    const teamsResp = await Http.get(`${regionDomain}/admin/v1/teams`, teamsHeaders);
    if (!teamsResp.ok) {
      return UsageSnapshot.failure(teamsResp.errorText());
    }
    const teamsRoot = asObj(teamsResp.json());
    const teams = teamsRoot != null ? asArray(teamsRoot['teams']) : null;

    let used = 0;
    let limit = 0;
    let resets = 0;
    const rows: ProviderDetailRow[] = [];
    if (teams != null) {
      for (let i = 0; i < teams.length; i++) {
        const t = asObj(teams[i]);
        if (t == null) {
          continue;
        }
        const tUsed = getNum3(t, ['used_bobcoins', 'usage', 'used']) ?? 0;
        const tLimit = getNum3(t, ['budget_limit']) ?? 0;
        used += tUsed;
        if (tLimit > 0) {
          limit = tLimit;
        }
        const tName = str(t, 'name', `团队 ${i + 1}`);
        rows.push({ label: tName, value: `${Math.round(tUsed)}${tLimit > 0 ? ` / ${Math.round(tLimit)}` : ''} Bobcoins` });
        const refresh = optStr(t, 'refresh_at');
        if (refresh != null && resets === 0) {
          resets = isoMs3(refresh);
        }
      }
    }
    let primary: RateWindow | null = null;
    if (limit > 0) {
      primary = makeWindow(Math.min(100, (used / limit) * 100), resets, true);
    }
    const snap = UsageSnapshot.success(primary, null, null);
    if (planName != null) {
      snap.identity = { accountEmail: '', accountOrganization: planName, loginMethod: isJwt ? 'JWT' : 'Apikey' };
    }
    if (rows.length > 0) {
      const section: ProviderDetailSection = { title: 'Bobcoin 用量', rows: rows };
      snap.details = [section];
    }
    return snap;
  }
}

// ---------------------------------------------------------------------------
// Ai&
// ---------------------------------------------------------------------------

class AiAndProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'aiand',
    title: 'Ai&',
    authKind: AuthKind.API_KEY,
    accentColor: '#F59E0B',
    authHint: '粘贴 Ai& API Key',
    authUrl: 'https://console.aiand.com',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const key = setting.credential.trim();
    if (key.length === 0) {
      return UsageSnapshot.failure('未配置 API Key');
    }
    const headers: Record<string, string> = {
      'authorization': `Bearer ${key}`,
      'accept': 'application/json',
    };
    let after = '';
    let afterId = '';
    let total = 0;
    let currency = '';
    let complete = true;
    // 最多翻 5 页（每页 100 条），覆盖 30 天窗口
    for (let page = 0; page < 5; page++) {
      let url = 'https://api.aiand.com/logs?range=30days&limit=100';
      if (after.length > 0) {
        url += `&after=${encodeURIComponent(after)}`;
      }
      if (afterId.length > 0) {
        url += `&after_id=${encodeURIComponent(afterId)}`;
      }
      const resp = await Http.get(url, headers);
      if (!resp.ok) {
        return UsageSnapshot.failure(resp.errorText());
      }
      const root = asObj(resp.json());
      if (root == null) {
        return UsageSnapshot.failure('响应解析失败');
      }
      const data = asArray(root['data']);
      if (data != null) {
        for (let i = 0; i < data.length; i++) {
          const row = asObj(data[i]);
          if (row == null) {
            continue;
          }
          const costStr = optStr(row, 'cost');
          if (costStr == null) {
            continue;
          }
          const cost = parseFloat(costStr);
          if (!isNaN(cost)) {
            total += cost;
            const cur = str(row, 'currency', 'USD');
            if (currency.length === 0) {
              currency = cur;
            }
          }
        }
      }
      const hasMore = bool(root, 'has_more');
      const nextAfter = optStr(root, 'next_after');
      const nextAfterId = optStr(root, 'next_after_id');
      if (!hasMore || nextAfter == null) {
        break;
      }
      after = nextAfter;
      afterId = nextAfterId ?? '';
    }
    const snap = UsageSnapshot.success(null, null, null);
    snap.providerCost = {
      remaining: 0, used: total, currency: currency.length > 0 ? currency : 'USD',
      displayText: Format.money(total, currency.length > 0 ? currency : 'USD'),
    };
    const rows: ProviderDetailRow[] = [
      { label: '近 30 天消费', value: Format.money(total, currency.length > 0 ? currency : 'USD') },
    ];
    const section: ProviderDetailSection = { title: '消费', rows: rows };
    snap.details = [section];
    return snap;
  }
}

// ---------------------------------------------------------------------------
// Codebuff
// ---------------------------------------------------------------------------

class CodebuffProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'codebuff',
    title: 'Codebuff',
    authKind: AuthKind.API_KEY,
    accentColor: '#84CC16',
    authHint: '粘贴 Codebuff API Key',
    authUrl: 'https://www.codebuff.com',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const key = setting.credential.trim();
    if (key.length === 0) {
      return UsageSnapshot.failure('未配置 API Key');
    }
    const headers: Record<string, string> = {
      'authorization': `Bearer ${key}`,
      'accept': 'application/json',
    };
    const base = 'https://www.codebuff.com';
    const usageResp = await Http.get(`${base}/api/v1/usage`, headers);
    if (!usageResp.ok) {
      return UsageSnapshot.failure(usageResp.errorText());
    }
    const uRoot = asObj(usageResp.json());
    if (uRoot == null) {
      return UsageSnapshot.failure('响应解析失败');
    }
    const quota = asObj(uRoot['quota']) ?? uRoot;
    const used = getNum3(quota, ['used']) ?? 0;
    const total = getNum3(quota, ['limit', 'total']) ?? 0;
    const remaining = getNum3(quota, ['remaining']);
    const resetIso = optStr(quota, 'next_quota_reset');
    let primary: RateWindow | null = null;
    if (total > 0) {
      primary = makeWindow(Math.min(100, (used / total) * 100), isoMs3(resetIso), true);
    }
    const snap = UsageSnapshot.success(primary, null, null);
    const rows: ProviderDetailRow[] = [];
    const subResp = await Http.get(`${base}/api/user/subscription`, headers);
    if (subResp.ok) {
      const sRoot = asObj(subResp.json());
      const sData = sRoot != null ? (asObj(sRoot['subscription']) ?? sRoot) : null;
      if (sData != null) {
        const tier = optStr(sData, 'tier');
        const status = optStr(sData, 'status');
        if (tier != null) {
          rows.push({ label: '套餐', value: tier });
        }
        if (status != null) {
          rows.push({ label: '状态', value: status });
        }
      }
    }
    if (remaining != null) {
      rows.push({ label: '剩余', value: `${Math.round(remaining)}` });
    }
    if (rows.length > 0) {
      const section: ProviderDetailSection = { title: '订阅', rows: rows };
      snap.details = [section];
    }
    return snap;
  }
}

// ---------------------------------------------------------------------------
// Sub2API（自托管）
// ---------------------------------------------------------------------------

class Sub2ApiProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'sub2api',
    title: 'Sub2API',
    authKind: AuthKind.API_KEY,
    accentColor: '#0EA5E9',
    authHint: '第二栏填 Sub2API 服务地址；首栏填 API Key',
    authUrl: 'https://github.com/sub2api',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const key = setting.credential.trim();
    const base = setting.credential2.trim().replace(/\/+$/, '');
    if (key.length === 0 || base.length === 0) {
      return UsageSnapshot.failure('需要服务地址与 API Key');
    }
    const headers: Record<string, string> = {
      'authorization': `Bearer ${key}`,
      'accept': 'application/json',
    };
    const resp = await Http.get(`${base}?days=30&timezone=UTC`, headers);
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    const root = asObj(resp.json());
    if (root == null) {
      return UsageSnapshot.failure('响应解析失败');
    }
    if (root['isValid'] != null && !bool(root, 'isValid')) {
      return UsageSnapshot.failure('API Key 无效或未分配分组');
    }
    const unit = str(root, 'unit', 'USD');
    const snap = UsageSnapshot.success(null, null, null);
    const quota = asObj(root['quota']);
    if (quota != null) {
      const qUsed = num(quota, 'used', 0);
      const qLimit = optNum(quota, 'limit');
      if (qLimit != null && qLimit > 0) {
        snap.primary = makeWindow(Math.min(100, (qUsed / qLimit) * 100), 0, true);
      }
    }
    const balance = optNum(root, 'balance');
    if (balance != null) {
      snap.providerCost = {
        remaining: balance, used: 0, currency: unit,
        displayText: unit.toUpperCase() === 'USD' ? Format.money(balance, 'USD') : `${balance.toFixed(2)} ${unit}`,
      };
    }
    const sub = asObj(root['subscription']);
    const rows: ProviderDetailRow[] = [];
    const planName = optStr(root, 'planName');
    if (planName != null) {
      rows.push({ label: '套餐', value: planName });
    }
    if (sub != null) {
      const pairs: string[][] = [
        ['今日', 'daily_usage_usd', 'daily_limit_usd'],
        ['本周', 'weekly_usage_usd', 'weekly_limit_usd'],
        ['本月', 'monthly_usage_usd', 'monthly_limit_usd'],
      ];
      for (let i = 0; i < pairs.length; i++) {
        const u = optNum(sub, pairs[i][1]);
        const l = optNum(sub, pairs[i][2]);
        if (u != null) {
          const line = l != null ? `${u.toFixed(2)} / ${l.toFixed(2)}` : `${u.toFixed(2)}`;
          rows.push({ label: pairs[i][0], value: line });
        }
      }
      const expiresAt = optStr(sub, 'expires_at');
      if (expiresAt != null) {
        rows.push({ label: '到期', value: Format.dateTime(isoMs3(expiresAt)) });
      }
    }
    if (rows.length > 0) {
      const section: ProviderDetailSection = { title: '订阅', rows: rows };
      snap.details = [section];
    }
    return snap;
  }
}

// ---------------------------------------------------------------------------
// Devin
// ---------------------------------------------------------------------------

class DevinProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'devin',
    title: 'Devin',
    authKind: AuthKind.OAUTH_TOKEN,
    accentColor: '#6D28D9',
    authHint: '粘贴 Devin 会话 Bearer Token；可选第二栏填组织标识',
    authUrl: 'https://app.devin.ai',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const token = setting.credential.trim()
      .replace(/^authorization:/i, '')
      .replace(/^bearer /i, '')
      .trim();
    if (token.length === 0) {
      return UsageSnapshot.failure('未配置 Bearer Token');
    }
    const org = setting.credential2.trim();
    const headers: Record<string, string> = {
      'authorization': `Bearer ${token}`,
      'accept': 'application/json',
    };
    const candidates: string[] = [];
    if (org.length > 0) {
      candidates.push(`api/${org}/billing/quota/usage`);
      if (org.indexOf('org/') === 0) {
        candidates.push(`api/${org.substring(4)}/billing/quota/usage`);
      } else if (org.indexOf('organizations/') !== 0) {
        candidates.push(`api/org/${org}/billing/quota/usage`);
      }
    }
    let lastError = '未识别组织';
    for (let i = 0; i < candidates.length; i++) {
      const resp = await Http.get(`https://app.devin.ai/${candidates[i]}`, headers);
      if (resp.ok) {
        const root = asObj(resp.json());
        if (root == null) {
          continue;
        }
        return DevinProvider.parse(root, org);
      }
      lastError = resp.errorText();
    }
    return UsageSnapshot.failure(lastError);
  }

  private static parse(root: Record<string, Json>, org: string): UsageSnapshot {
    // 容错：窗口对象可能在根或 usage 节点
    let node = asObj(root['usage']) ?? root;
    const findWindow = (keys: string[]): RateWindow | null => {
      for (let i = 0; i < keys.length; i++) {
        const w = asObj(node[keys[i]]);
        if (w != null) {
          const percent = getNum3(w, ['used_percent', 'usedPercent', 'percent_used', 'percent']);
          if (percent != null) {
            let resets = 0;
            const rIso = optStr(w, 'resets_at');
            if (rIso != null) {
              resets = isoMs3(rIso);
            } else {
              const rNum = optNum(w, 'reset_at');
              if (rNum != null && rNum > 1e9) {
                resets = rNum > 1e12 ? rNum : rNum * 1000;
              }
            }
            return makeWindow(Math.max(0, Math.min(100, percent)), resets, true);
          }
        }
      }
      return null;
    };
    const primary = findWindow(['acurve', 'daily', 'five_hour']);
    const secondary = findWindow(['weekly', 'wcurve']);
    const snap = UsageSnapshot.success(primary, secondary, null);
    snap.identity = { accountEmail: '', accountOrganization: org, loginMethod: 'Bearer Token' };
    return snap;
  }
}

// ---------------------------------------------------------------------------
// Abacus
// ---------------------------------------------------------------------------

class AbacusProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'abacus',
    title: 'Abacus',
    authKind: AuthKind.SESSION,
    accentColor: '#7C3AED',
    authHint: '粘贴 apps.abacus.ai 的会话 Cookie',
    authUrl: 'https://apps.abacus.ai',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const cookie = setting.credential.trim();
    if (cookie.length === 0) {
      return UsageSnapshot.failure('未配置会话 Cookie');
    }
    const headers: Record<string, string> = {
      'cookie': cookie,
      'accept': 'application/json',
      'user-agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/126.0 Safari/537.36',
    };
    const resp = await Http.get('https://apps.abacus.ai/api/_getBillingInfo', headers);
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    const root = asObj(resp.json());
    if (root == null || !bool(root, 'success')) {
      return UsageSnapshot.failure('响应解析失败（Cookie 可能已失效）');
    }
    const result = asObj(root['result']);
    const usage = result != null ? asObj(result['usage']) : null;
    if (usage == null) {
      return UsageSnapshot.failure('响应缺少用量');
    }
    const used = getNum3(usage, ['computePointsLeft']) != null
      ? (getNum3(usage, ['totalComputePoints']) ?? 0) - (getNum3(usage, ['computePointsLeft']) ?? 0)
      : 0;
    const total = getNum3(usage, ['totalComputePoints']) ?? 0;
    const tier = optStr(usage, 'currentTier');
    const resets = isoMs3(optStr(usage, 'nextBillingDate'));
    let primary: RateWindow | null = null;
    if (total > 0) {
      primary = makeWindow(Math.min(100, (used / total) * 100), resets, true);
    }
    const snap = UsageSnapshot.success(primary, null, null);
    const rows: ProviderDetailRow[] = [
      { label: '算力点', value: `${Math.round(used)} / ${Math.round(total)}` },
    ];
    if (tier != null) {
      rows.push({ label: '套餐', value: tier });
    }
    const section: ProviderDetailSection = { title: '订阅', rows: rows };
    snap.details = [section];
    return snap;
  }
}

// ---------------------------------------------------------------------------
// CommandCode
// ---------------------------------------------------------------------------

const CC_API = 'https://api.commandcode.ai';
const CC_WEB = 'https://commandcode.ai';

function ccHeaders(credential: string): Record<string, string> {
  // 对照 macOS：浏览器 UA + Origin/Referer 为服务端必需校验头
  const h: Record<string, string> = {
    'accept': 'application/json, text/plain, */*',
    'accept-language': 'en-US,en;q=0.9',
    'user-agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36',
    'origin': CC_WEB,
    'referer': `${CC_WEB}/`,
  };
  if (credential.indexOf('=') >= 0) {
    h['cookie'] = credential;
  } else {
    // API Key 模式
    h['authorization'] = `Bearer ${credential}`;
  }
  return h;
}

/** 数值兼容数字/字符串（对照 macOS double(from:)） */
function ccNum(v: Json | null): number | null {
  if (typeof v === 'number') {
    return isFinite(v) ? v as number : null;
  }
  if (typeof v === 'string') {
    const t = (v as string).trim();
    if (t.length === 0) {
      return null;
    }
    const p = parseFloat(t);
    return isNaN(p) ? null : p;
  }
  return null;
}

/** 时间戳（秒/毫秒）或 ISO8601 → 毫秒 */
function ccDateMs(v: Json | null): number {
  if (typeof v === 'number') {
    const n = v as number;
    if (n > 1e12) {
      return n;
    }
    return n > 1e9 ? n * 1000 : 0;
  }
  if (typeof v === 'string' && (v as string).length > 0) {
    const p = Date.parse(v as string);
    return isNaN(p) ? 0 : p;
  }
  return 0;
}

function ccWindow(limit: Record<string, Json> | null): RateWindow | null {
  if (limit == null) {
    return null;
  }
  const cap = ccNum(limit['cap']);
  if (cap == null || cap <= 0) {
    return null;
  }
  const used = ccNum(limit['used']) ?? 0;
  return makeWindow(Math.max(0, Math.min(100, (used / cap) * 100)), ccDateMs(limit['resetAt']), true);
}

class CommandCodeProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'commandcode',
    title: 'Command Code',
    authKind: AuthKind.SESSION,
    accentColor: '#EA580C',
    authHint: '粘贴 commandcode.ai 的会话 Cookie，或 API Key',
    authUrl: 'https://commandcode.ai/settings/billing',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const credential = setting.credential.trim();
    if (credential.length === 0) {
      return UsageSnapshot.failure('未配置会话 Cookie 或 API Key');
    }
    const headers = ccHeaders(credential);

    // credits（必需；结构对照 macOS parseCredits）
    const creditsResp = await Http.get(`${CC_API}/internal/billing/credits`, headers);
    if (!creditsResp.ok) {
      return UsageSnapshot.failure(creditsResp.errorText());
    }
    const cRoot = asObj(creditsResp.json());
    if (cRoot == null) {
      return UsageSnapshot.failure('响应解析失败');
    }
    const credits = asObj(cRoot['credits']);
    if (credits == null) {
      return UsageSnapshot.failure('响应缺少 credits 字段');
    }
    const monthly = ccNum(credits['monthlyCredits']);
    if (monthly == null) {
      return UsageSnapshot.failure('响应缺少 monthlyCredits');
    }
    const purchased = ccNum(credits['purchasedCredits']) ?? 0;
    const premium = ccNum(credits['premiumMonthlyCredits']) ?? 0;
    const opensource = ccNum(credits['opensourceMonthlyCredits']) ?? 0;
    const wl = asObj(cRoot['windowLimits']) ?? asObj(credits['windowLimits']);

    const snap = UsageSnapshot.success(
      ccWindow(wl != null ? asObj(wl['fiveHour']) : null),
      ccWindow(wl != null ? asObj(wl['weekly']) : null),
      null
    );
    const balance = monthly + purchased;
    snap.providerCost = {
      remaining: balance, used: 0, currency: 'CREDITS',
      displayText: `${Math.round(balance * 100) / 100} credits`,
    };

    // subscriptions（增强信息，失败不阻断）
    const rows: ProviderDetailRow[] = [
      { label: '月度额度', value: `${monthly}` },
      { label: '已购额度', value: `${purchased}` },
      { label: '高级月度', value: `${premium}` },
      { label: '开源月度', value: `${opensource}` },
    ];
    const subResp = await Http.get(`${CC_API}/internal/billing/subscriptions`, headers);
    if (subResp.ok) {
      const sRoot = asObj(subResp.json());
      if (sRoot != null && sRoot['success'] === true) {
        const sData = asObj(sRoot['data']);
        if (sData != null) {
          const planId = optStr(sData, 'planId');
          if (planId != null && planId.length > 0) {
            rows.push({ label: '计划', value: planId });
          }
          const status = optStr(sData, 'status');
          if (status != null) {
            rows.push({ label: '状态', value: status });
          }
          const period = ccDateMs(sData['currentPeriodEnd']);
          if (period > 0) {
            rows.push({ label: '账期截止', value: Format.dateTime(period) });
          }
        } else {
          rows.push({ label: '状态', value: '免费版' });
        }
      }
    }
    snap.details = [{ title: '订阅', rows: rows }];
    return snap;
  }
}

// ---------------------------------------------------------------------------
// LongCat
// ---------------------------------------------------------------------------

class LongCatProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'longcat',
    title: 'LongCat',
    authKind: AuthKind.SESSION,
    accentColor: '#14B8A6',
    authHint: '粘贴 longcat.chat 平台的会话 Cookie',
    authUrl: 'https://longcat.chat/platform',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const cookie = setting.credential.trim();
    if (cookie.length === 0) {
      return UsageSnapshot.failure('未配置会话 Cookie');
    }
    const headers: Record<string, string> = {
      'cookie': cookie,
      'accept': 'application/json',
      'origin': 'https://longcat.chat',
    };
    const resp = await Http.get('https://longcat.chat/api/task_center/trial_quotas/api/list', headers);
    if (!resp.ok) {
      // 容错：部分账号走另一路径
      const alt = await Http.get('https://longcat.chat/api/platform/trial_quotas/api/list', headers);
      if (!alt.ok) {
        return UsageSnapshot.failure(resp.errorText());
      }
      return LongCatProvider.parse(alt);
    }
    return LongCatProvider.parse(resp);
  }

  private static parse(resp: HttpResult): UsageSnapshot {
    const root = asObj(resp.json());
    if (root == null || num(root, 'code', -1) !== 200) {
      return UsageSnapshot.failure('响应解析失败（Cookie 可能已失效）');
    }
    const data = asObj(root['data']);
    const list = data != null ? asArray(data['list']) : null;
    if (list == null || list.length === 0) {
      return UsageSnapshot.failure('未返回 token 额度');
    }
    let totalAvail = 0;
    let totalUsed = 0;
    const rows: ProviderDetailRow[] = [];
    let earliestExpire = 0;
    for (let i = 0; i < list.length; i++) {
      const lot = asObj(list[i]);
      if (lot == null) {
        continue;
      }
      const avail = num(lot, 'availableToken', 0);
      const consumed = num(lot, 'consumedToken', 0);
      totalAvail += avail;
      totalUsed += consumed;
      const expire = optStr(lot, 'expireTime');
      if (expire != null) {
        const ms = isoMs3(expire);
        if (ms > 0 && (earliestExpire === 0 || ms < earliestExpire)) {
          earliestExpire = ms;
        }
      }
      const name = str(lot, 'name', `份额 ${i + 1}`);
      if (i < 4) {
        rows.push({ label: name, value: `${Format.compact(avail)} 可用` });
      }
    }
    const totalAll = totalAvail + totalUsed;
    let primary: RateWindow | null = null;
    if (totalAll > 0) {
      primary = makeWindow(Math.min(100, (totalUsed / totalAll) * 100), earliestExpire, true);
    }
    const snap = UsageSnapshot.success(primary, null, null);
    const section: ProviderDetailSection = { title: 'Token 份额', rows: rows };
    snap.details = [section];
    return snap;
  }
}


// ---------------------------------------------------------------------------
// ZoomMate
// ---------------------------------------------------------------------------

class ZoomMateProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'zoommate',
    title: 'ZoomMate',
    authKind: AuthKind.OAUTH_TOKEN,
    accentColor: '#2D8CFF',
    authHint: '粘贴 zoommate.zoom.us 的会话令牌或 Cookie',
    authUrl: 'https://zoommate.zoom.us',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const cred = setting.credential.trim();
    if (cred.length === 0) {
      return UsageSnapshot.failure('未配置令牌');
    }
    const isJwt = cred.split('.').length === 3;
    const headers: Record<string, string> = {
      'accept': 'application/json',
    };
    if (isJwt) {
      headers['authorization'] = `Bearer ${cred}`;
    } else {
      headers['cookie'] = cred;
    }
    const resp = await Http.get('https://zoommate.zoom.us/ai-computer/api/v1/credits/status', headers);
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    const root = asObj(resp.json());
    if (root == null) {
      return UsageSnapshot.failure('响应解析失败');
    }
    const credits = asObj(root['credits']) ?? root;
    const today = asObj(credits['today']);
    const weekly = asObj(credits['weekly']);
    const windowFrom = (o: Record<string, Json> | null, label: string): RateWindow | null => {
      if (o == null) {
        return null;
      }
      const unlimited = bool(o, 'is_unlimited') || bool(o, 'isUnlimited');
      if (unlimited) {
        return makeWindow(0, 0, true);
      }
      const used = getNum3(o, ['used_credit', 'usedCredit', 'used']) ?? 0;
      const limit = getNum3(o, ['budget_cap', 'budgetCap', 'limit']) ?? 0;
      if (limit <= 0) {
        return null;
      }
      return makeWindow(Math.min(100, (used / limit) * 100), 0, true);
    };
    const snap = UsageSnapshot.success(windowFrom(today, '今日'), windowFrom(weekly, '每周'), null);
    const remaining = getNum3(credits, ['remaining_credit', 'remainingCredit']);
    const rows: ProviderDetailRow[] = [];
    if (remaining != null) {
      rows.push({ label: '剩余额度', value: `${remaining}` });
    }
    const cycleEnd = optStr(credits, 'cycle_end_date');
    if (cycleEnd != null) {
      rows.push({ label: '周期结束', value: cycleEnd });
    }
    if (rows.length > 0) {
      const section: ProviderDetailSection = { title: '额度', rows: rows };
      snap.details = [section];
    }
    return snap;
  }
}

// ---------------------------------------------------------------------------
// Notion
// ---------------------------------------------------------------------------

class NotionProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'notion',
    title: 'Notion AI',
    authKind: AuthKind.SESSION,
    accentColor: '#111111',
    authHint: '粘贴 app.notion.com 的 Cookie（需含 token_v2）',
    authUrl: 'https://www.notion.so/my-account',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const cookie = setting.credential.trim();
    if (cookie.indexOf('token_v2') < 0) {
      return UsageSnapshot.failure('Cookie 需包含 token_v2');
    }
    const headers: Record<string, string> = {
      'cookie': cookie,
      'accept': 'application/json',
      'content-type': 'application/json',
      'referer': 'https://www.notion.so/',
    };
    const spacesResp = await Http.post('https://app.notion.com/api/v3/getSpaces', headers, '{}');
    if (!spacesResp.ok) {
      return UsageSnapshot.failure(spacesResp.errorText());
    }
    const spacesRoot = asObj(spacesResp.json());
    // 递归找 space 节点取 id/name
    const spaceId = NotionProvider.findSpaceId(spacesRoot);
    if (spaceId == null || spaceId.length === 0) {
      return UsageSnapshot.failure('未找到工作区');
    }
    const statusResp = await Http.post(
      'https://app.notion.com/api/v3/getCreditRateLimitStatus',
      headers,
      JSON.stringify({ spaceId: spaceId })
    );
    if (!statusResp.ok) {
      return UsageSnapshot.failure(statusResp.errorText());
    }
    const statusRoot = asObj(statusResp.json());
    if (statusRoot == null) {
      return UsageSnapshot.failure('响应解析失败');
    }
    // 容错定位额度对象
    const rateLimit = NotionProvider.findRateLimit(statusRoot);
    if (rateLimit == null) {
      return UsageSnapshot.failure('该套餐不适用额度限制');
    }
    const percent = num(rateLimit, 'value', 0) * 100;
    const snap = UsageSnapshot.success(makeWindow(Math.max(0, Math.min(100, percent)), 0, true), null, null);
    return snap;
  }

  private static findSpaceId(value: Json): string | null {
    const o = asObj(value);
    if (o == null) {
      return null;
    }
    const id = optStr(o, 'id');
    const name = optStr(o, 'name');
    if (id != null && name != null && o['permission'] != null) {
      return id;
    }
    const keys = Object.keys(o);
    for (let i = 0; i < keys.length; i++) {
      const found = NotionProvider.findSpaceId(o[keys[i]]);
      if (found != null) {
        return found;
      }
    }
    return null;
  }

  private static findRateLimit(value: Json): Record<string, Json> | null {
    const o = asObj(value);
    if (o == null) {
      return null;
    }
    const rl = o['rate_limit'] ?? o['rateLimit'];
    const rlObj = rl != null ? asObj(rl) : null;
    if (rlObj != null && rlObj['value'] != null) {
      return rlObj;
    }
    const keys = Object.keys(o);
    for (let i = 0; i < keys.length; i++) {
      const found = NotionProvider.findRateLimit(o[keys[i]]);
      if (found != null) {
        return found;
      }
    }
    return null;
  }
}

export function createElevenLabsProvider(): UsageProvider {
  return new ElevenLabsProvider();
}

export function createFireworksProvider(): UsageProvider {
  return new FireworksProvider();
}

export function createNeuralWattProvider(): UsageProvider {
  return new NeuralWattProvider();
}

export function createIBMBobProvider(): UsageProvider {
  return new IBMBobProvider();
}

export function createAiAndProvider(): UsageProvider {
  return new AiAndProvider();
}

export function createCodebuffProvider(): UsageProvider {
  return new CodebuffProvider();
}

export function createSub2ApiProvider(): UsageProvider {
  return new Sub2ApiProvider();
}

export function createDevinProvider(): UsageProvider {
  return new DevinProvider();
}

export function createAbacusProvider(): UsageProvider {
  return new AbacusProvider();
}

export function createCommandCodeProvider(): UsageProvider {
  return new CommandCodeProvider();
}

export function createLongCatProvider(): UsageProvider {
  return new LongCatProvider();
}

export function createZoomMateProvider(): UsageProvider {
  return new ZoomMateProvider();
}

export function createNotionProvider(): UsageProvider {
  return new NotionProvider();
}
