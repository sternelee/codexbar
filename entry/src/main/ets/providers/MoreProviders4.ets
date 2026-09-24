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
 * - CommandCode:GET api.commandcode.ai/internal/billing/{credits,subscriptions}（Cookie，对照 macOS）
 *               或 api.commandcode.ai/alpha/billing/{credits,subscriptions}（user_ API Key，对照官方 CLI）
 * - LongCat:    GET longcat.chat/api/...（Cookie，token lots）
 * - ZoomMate:   GET zoommate.zoom.us/ai-computer/api/v1/credits/status（Bearer/Cookie）
 * - Notion:     POST app.notion.com/api/v3/{getSpaces,getCreditRateLimitStatus}（Cookie token_v2）
 */

import { Http, HttpResult } from '../net/Http';
import { asArray, asObj, bool, Json, num, optNum, optStr, str } from '../net/Json';
import {
  AuthKind,
  makeWindow,
  NamedRateWindow,
  pct,
  ProviderCostSnapshot,
  ProviderDescriptor,
  ProviderDetailRow,
  ProviderDetailSection,
  ProviderChartPoint,
  makeChart,
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

/**
 * 词首大写（对照插件里的 title()）：下划线换成空格后把每个词的首字母大写。
 * NeuralWatt 的 plan / accounting_method / allowance.period 与 ElevenLabs 的 tier 都用它。
 */
export function titleCaseWords(value: string): string {
  const words = value.replace(/_/g, ' ').toLowerCase().split(' ');
  const out: string[] = [];
  for (let i = 0; i < words.length; i++) {
    const w = words[i];
    out.push(w.length === 0 ? w : `${w.charAt(0).toUpperCase()}${w.slice(1)}`);
  }
  return out.join(' ');
}

/** ElevenLabs 的一条席位泳道（对照插件 elevenlabs.js 的 voice-slots / professional-voices） */
export class ElevenLabsSlot {
  id: string = '';
  title: string = '';
  used: number | null = null;
  limit: number | null = null;
}

/** 席位泳道：分子分母都拿到且分母 > 0 才出泳道（其余情况源工程也不给泳道） */
export function elevenLabsSlotWindows(slots: ElevenLabsSlot[]): NamedRateWindow[] {
  const out: NamedRateWindow[] = [];
  for (let i = 0; i < slots.length; i++) {
    const s = slots[i];
    if (s.used != null && s.limit != null && s.limit > 0) {
      out.push({ id: s.id, title: s.title, window: makeWindow(pct(s.used, s.limit), 0) });
    }
  }
  return out;
}

/** 计划名（对照插件：tier 词首大写；status 不是 active 时拼在后面） */
export function elevenLabsLoginMethod(tier: string | null, status: string | null): string {
  const suffix = status != null && status.length > 0 && status.toLowerCase() !== 'active'
    ? ` · ${status}`
    : '';
  if (tier != null && tier.length > 0) {
    return `${titleCaseWords(tier)}${suffix}`;
  }
  return status != null ? status : '';
}

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
    // 主泳道：分母为 0 时报 0%（对照插件：character_limit > 0 ? pct : 0）
    const primary = makeWindow(
      limit > 0 ? pct(used, limit) : 0,
      resetSec != null && resetSec > 0 ? resetSec * 1000 : 0,
      true
    );
    const slots: ElevenLabsSlot[] = [];
    const voiceSlot = new ElevenLabsSlot();
    voiceSlot.id = 'voice-slots';
    voiceSlot.title = 'Voice slots';
    voiceSlot.used = optNum(root, 'voice_slots_used');
    voiceSlot.limit = optNum(root, 'voice_limit');
    slots.push(voiceSlot);
    const proSlot = new ElevenLabsSlot();
    proSlot.id = 'professional-voices';
    proSlot.title = 'Professional voices';
    proSlot.used = optNum(root, 'professional_voice_slots_used');
    proSlot.limit = optNum(root, 'professional_voice_limit');
    slots.push(proSlot);
    const slotsWindows = elevenLabsSlotWindows(slots);

    const snap = UsageSnapshot.success(primary, null, null);
    snap.extraRateWindows = slotsWindows;
    const tier = optStr(root, 'tier');
    snap.identity = {
      accountEmail: '', accountOrganization: '',
      loginMethod: elevenLabsLoginMethod(tier, optStr(root, 'status')),
    };
    const rows: ProviderDetailRow[] = [
      { label: '字符用量', value: `${Format.compact(used)} / ${Format.compact(limit)}` },
    ];
    if (tier != null) {
      rows.push({ label: '套餐', value: tier });
    }
    for (let i = 0; i < slots.length; i++) {
      const s = slots[i];
      if (s.used != null && s.limit != null && s.limit > 0) {
        rows.push({ label: s.title, value: `${s.used} / ${s.limit}` });
      }
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

/** NeuralWatt `/v1/quota` 的解析结果（对照插件 neuralwatt.js 的 balance / subscription / key.allowance） */
export class NeuralWattQuota {
  remainingUSD: number = 0;
  usedUSD: number = 0;
  totalUSD: number = 0;
  kwhIncluded: number = 0;
  kwhConsumed: number = 0;
  periodEndMs: number = 0;
  allowanceLimitUSD: number | null = null;
  allowanceSpentUSD: number | null = null;
  allowanceBlocked: boolean = false;
  allowancePeriod: string = '';
  plan: string = '';
  accountingMethod: string = '';
}

/** 非负数字（对照插件 nonnegative：只在有限且 >= 0 时算数） */
function nonneg(value: number | null): number | null {
  return value != null && isFinite(value) && value >= 0 ? value : null;
}

/** 正数（对照插件 positive） */
function positive(value: number | null): number | null {
  return value != null && isFinite(value) && value > 0 ? value : null;
}

export function neuralWattQuota(root: Record<string, Json>): NeuralWattQuota {
  const q = new NeuralWattQuota();
  const balance = asObj(root['balance']) ?? root;
  const subscription = asObj(root['subscription']);
  const keyObj = asObj(root['key']);
  const allowance = keyObj != null ? asObj(keyObj['allowance']) : asObj(root['allowance']);

  // 余额：remaining / used 互陀（对照插件）
  const rawRemaining = nonneg(getNum3(balance, ['credits_remaining_usd']));
  const rawUsed = nonneg(getNum3(balance, ['credits_used_usd']));
  const rawTotal = positive(getNum3(balance, ['total_credits_usd'])) ??
    (rawUsed != null && rawRemaining != null ? rawUsed + rawRemaining : null);
  q.totalUSD = rawTotal ?? 0;
  q.usedUSD = rawUsed ?? (rawTotal != null && rawRemaining != null ? Math.max(0, rawTotal - rawRemaining) : 0);
  q.remainingUSD = rawRemaining ?? (rawTotal != null && rawUsed != null ? Math.max(0, rawTotal - rawUsed) : 0);

  if (subscription != null) {
    const kwhUsed = nonneg(getNum3(subscription, ['kwh_used']));
    const kwhRemaining = nonneg(getNum3(subscription, ['kwh_remaining']));
    const included = positive(getNum3(subscription, ['kwh_included'])) ??
      (kwhUsed != null && kwhRemaining != null ? kwhUsed + kwhRemaining : null);
    q.kwhIncluded = included ?? 0;
    q.kwhConsumed = kwhUsed ?? (included != null && kwhRemaining != null ? Math.max(0, included - kwhRemaining) : 0);
    q.periodEndMs = isoMs3(optStr(subscription, 'current_period_end'));
    q.plan = optStr(subscription, 'plan') ?? '';
  }
  q.accountingMethod = str(balance, 'accounting_method', '');

  if (allowance != null) {
    q.allowanceLimitUSD = nonneg(getNum3(allowance, ['limit_usd']));
    q.allowanceSpentUSD = nonneg(getNum3(allowance, ['spent_usd']));
    q.allowanceBlocked = bool(allowance, 'blocked');
    q.allowancePeriod = optStr(allowance, 'period') ?? '';
  }
  return q;
}

/** NeuralWatt 的主泳道（订阅 kWh）与附加泳道（密钥限额） */
export class NeuralWattWindows {
  primary: RateWindow | null = null;
  extras: NamedRateWindow[] = [];
}

export function neuralWattWindows(q: NeuralWattQuota): NeuralWattWindows {
  const windows = new NeuralWattWindows();
  // 主泳道是订阅用电量（kWh），不是美元余额（对照插件 neuralwatt.js 的 primary）
  if (q.kwhIncluded > 0) {
    windows.primary = makeWindow(pct(q.kwhConsumed, q.kwhIncluded), q.periodEndMs);
  }
  // 密钥限额：被封锁时直接报 100%，否则要求 spent 与 limit 都在且 limit > 0（对照插件）
  let allowancePercent: number | null = null;
  if (q.allowanceBlocked) {
    allowancePercent = 100;
  } else if (q.allowanceSpentUSD != null && q.allowanceLimitUSD != null && q.allowanceLimitUSD > 0) {
    allowancePercent = pct(q.allowanceSpentUSD, q.allowanceLimitUSD);
  }
  if (allowancePercent != null) {
    const period = q.allowancePeriod.length > 0 ? q.allowancePeriod : 'allowance';
    windows.extras.push({
      id: 'key-allowance',
      title: `Key ${titleCaseWords(period)}`,
      window: makeWindow(allowancePercent, 0),
    });
  }
  return windows;
}

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
    // /v1/quota 的结构（对照插件 neuralwatt.js）：余额在 balance.*、订阅额度在 subscription.*、
    // 密钥限额在 key.allowance.*；root 上平铺的旧字段作为回退，兼容早期部署。
    const q = neuralWattQuota(root);
    const windows = neuralWattWindows(q);
    const snap = UsageSnapshot.success(windows.primary, null, null);
    snap.extraRateWindows = windows.extras;
    snap.providerCost = {
      remaining: q.remainingUSD, used: q.usedUSD, currency: 'USD',
      displayText: Format.money(q.remainingUSD, 'USD'),
      period: 'Neuralwatt prepaid balance',
    };
    snap.identity = {
      accountEmail: '', accountOrganization: '',
      loginMethod: q.plan.length > 0
        ? `${titleCaseWords(q.plan)} plan`
        : (q.accountingMethod.length > 0 ? titleCaseWords(q.accountingMethod) : ''),
    };
    const rows: ProviderDetailRow[] = [
      { label: '额度余量', value: Format.money(q.remainingUSD, 'USD') },
      { label: '已使用', value: Format.money(q.usedUSD, 'USD') },
    ];
    if (q.totalUSD > 0) {
      rows.push({ label: '总额度', value: Format.money(q.totalUSD, 'USD') });
    }
    if (q.kwhIncluded > 0) {
      rows.push({
        label: '订阅用电',
        value: `${q.kwhConsumed} / ${q.kwhIncluded} kWh`,
      });
    }
    if (q.allowanceLimitUSD != null && q.allowanceLimitUSD > 0) {
      rows.push({
        label: '密钥限额',
        value: `${Format.money(q.allowanceSpentUSD ?? 0, 'USD')} / ${Format.money(q.allowanceLimitUSD, 'USD')}`,
      });
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
        // 标签/取值对照 Swift Bobcoin usage 分组：
        // label = teamName（与 instanceName 不同时用 "instanceName · teamName"），
        // value = "used / limit Bobcoins"（无上限时 "used Bobcoins used"），副文本为套餐名。
        const instanceName = optStr(inst, 'instance_name') ?? optStr(inst, 'name') ?? instanceId;
        const tName = str(t, 'team_name', str(t, 'name', `团队 ${i + 1}`));
        const label = tName === instanceName ? tName : `${instanceName} · ${tName}`;
        rows.push({
          label: label,
          value: tLimit > 0
            ? `${Math.round(tUsed)} / ${Math.round(tLimit)} Bobcoins`
            : `${Math.round(tUsed)} Bobcoins used`,
          secondary: planName ?? undefined,
        });
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
      const section: ProviderDetailSection = { title: 'Bobcoin usage', rows: rows };
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

/** Sub2API 的泳道集合（对照插件 sub2api.js）：主泳道优先取订阅包、其次配额，另有 rate_limits 附加泳道 */
export class Sub2APIWindows {
  primary: RateWindow | null = null;
  secondary: RateWindow | null = null;
  tertiary: RateWindow | null = null;
  extras: NamedRateWindow[] = [];
}

/** rate_limits[].window 的分钟/标题映射（对照插件 sub2api.js） */
const SUB2API_MINUTES: string[] = ['5h', '1d', '7d'];
const SUB2API_TITLES: string[] = ['5 hour limit', 'Daily limit', '7 day limit'];

export function sub2APIWindows(root: Record<string, Json>): Sub2APIWindows {
  const windows = new Sub2APIWindows();
  const sub = asObj(root['subscription']);
  const quota = asObj(root['quota']);
  if (sub != null) {
    // 订阅包：日 / 周 / 月 三条泳道（只有 limit > 0 才出，否则该条为 null）
    windows.primary = sub2APILane(sub, 'daily_usage_usd', 'daily_limit_usd');
    windows.secondary = sub2APILane(sub, 'weekly_usage_usd', 'weekly_limit_usd');
    windows.tertiary = sub2APILane(sub, 'monthly_usage_usd', 'monthly_limit_usd');
  } else if (quota != null) {
    const used = num(quota, 'used', 0);
    const limit = optNum(quota, 'limit');
    if (limit != null && limit > 0) {
      windows.primary = makeWindow(pct(used, limit), 0);
    }
  }
  const rates = asArray(root['rate_limits']);
  if (rates != null) {
    for (let i = 0; i < rates.length; i++) {
      const rate = asObj(rates[i]);
      if (rate == null) {
        continue;
      }
      const key = optStr(rate, 'window');
      const limit = optNum(rate, 'limit');
      const used = optNum(rate, 'used');
      if (key == null || key.length === 0 || limit == null || used == null) {
        continue;
      }
      let title = `${key} limit`;
      for (let j = 0; j < SUB2API_MINUTES.length; j++) {
        if (SUB2API_MINUTES[j] === key.toLowerCase()) {
          title = SUB2API_TITLES[j];
          break;
        }
      }
      windows.extras.push({
        id: key,
        title: title,
        window: makeWindow(pct(used, limit), isoMs3(optStr(rate, 'reset_at'))),
      });
    }
  }
  return windows;
}

function sub2APILane(sub: Record<string, Json>, usedKey: string, limitKey: string): RateWindow | null {
  const limit = optNum(sub, limitKey);
  if (limit == null || limit <= 0) {
    return null;
  }
  return makeWindow(pct(num(sub, usedKey, 0), limit), 0);
}

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
    const windows = sub2APIWindows(root);
    const snap = UsageSnapshot.success(windows.primary, windows.secondary, windows.tertiary);
    snap.extraRateWindows = windows.extras;
    if (windows.primary != null) {
      // 主泳道标签（对照 Sub2APIProviderDescriptor.primaryLabel）：有订阅包（日/周/月）时叫 "Daily quota"
      snap.primaryLabel = windows.secondary != null ? 'Daily quota' : 'Quota';
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
      // 身份（对照插件：organization 与 loginMethod 都是 planName）
      snap.identity = { accountEmail: '', accountOrganization: planName, loginMethod: planName };
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
    const sections: ProviderDetailSection[] = [];
    if (rows.length > 0) {
      sections.push({ title: '订阅', rows: rows });
    }

    // Usage summary（对照插件 details：余额 + 今日/累计请求数、token 数（副文本为花费））
    const money = (value: number): string => unit.toUpperCase() === 'USD'
      ? Format.money(value, 'USD')
      : `${value.toFixed(2)} ${unit}`;
    const usageRows: ProviderDetailRow[] = [];
    if (balance != null) {
      usageRows.push({ label: 'Balance', value: money(balance) });
    }
    const usage = asObj(root['usage']);
    if (usage != null) {
      const groups: string[][] = [['Today', 'today'], ['All time', 'total']];
      for (let i = 0; i < groups.length; i++) {
        const totals = asObj(usage[groups[i][1]]);
        if (totals == null) {
          continue;
        }
        usageRows.push({ label: `${groups[i][0]} requests`, value: `${num(totals, 'requests', 0)}` });
        usageRows.push({
          label: `${groups[i][0]} tokens`,
          value: `${num(totals, 'total_tokens', 0)}`,
          secondary: money(num(totals, 'actual_cost', 0)),
        });
      }
    }
    if (usageRows.length > 0) {
      sections.push({ title: 'Usage summary', rows: usageRows });
    }
    if (sections.length > 0) {
      snap.details = sections;
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
    accentColor: '#38BDF8',
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
/** API Key（Provider API）侧的计费端点前缀，对照官方 CLI `usage` 与 pi 插件 */
const CC_ALPHA = 'https://api.commandcode.ai/alpha';
const CC_WEB = 'https://commandcode.ai';

/**
 * 对照 macOS CookieHeaderNormalizer.headerPatterns：用户往往整段粘贴 `Cookie: …` 头或
 * devtools 的 cURL 抓包，而不是裸的 `name=value`。直接把这坨文本塞进 Cookie 头，服务端解析
 * 出来的 Cookie 名会变成 `Cookie: __Secure-…`，better-auth 认不出 → 一律 401「凭证无效」。
 */
const CC_HEADER_PATTERNS: RegExp[] = [
  /-h\s*'cookie:\s*([^']+)'/i,
  /-h\s*"cookie:\s*([^"]+)"/i,
  /\bcookie:\s*'([^']+)'/i,
  /\bcookie:\s*"([^"]+)"/i,
  /\bcookie:\s*([^\r\n]+)/i,
  /(?:^|\s)(?:--cookie|-b)\s*'([^']+)'/i,
  /(?:^|\s)(?:--cookie|-b)\s*"([^"]+)"/i,
  /(?:^|\s)-b([^\s=]+=[^\s]+)/i,
  /(?:^|\s)(?:--cookie|-b)\s+([^\s]+)/i,
];

/** better-auth 在生产 / 开发下用过的会话 Cookie 名（对照 CommandCodeCookieHeader.supportedSessionCookieNames） */
const CC_SESSION_COOKIE_NAMES: string[] = [
  '__Secure-commandcode_prod_.session_token',
  'commandcode_prod_.session_token',
  '__Host-commandcode_prod_.session_token',
  '__Host-better-auth.session_token',
  '__Secure-better-auth.session_token',
  'better-auth.session_token',
];

/** 裸令牌默认按生产会话 Cookie 名补齐（对照 CommandCodeCookieHeader.override 的 bare token 分支） */
const CC_DEFAULT_SESSION_COOKIE = '__Secure-better-auth.session_token';

/** 去首尾成对引号 */
function ccStripQuotes(text: string): string {
  if (text.length < 2) {
    return text;
  }
  const head = text.charAt(0);
  const tail = text.charAt(text.length - 1);
  if ((head === '\'' && tail === '\'') || (head === '"' && tail === '"')) {
    return text.substring(1, text.length - 1);
  }
  return text;
}

/**
 * 规整用户粘贴的凭证：从 cURL / `Cookie:` 头里抽出 Cookie 串，再去引号
 * （对照 macOS CookieHeaderNormalizer.normalize）。
 */
export function commandCodeNormalize(raw: string): string {
  let value = raw == null ? '' : raw.trim();
  if (value.length === 0) {
    return '';
  }
  for (let i = 0; i < CC_HEADER_PATTERNS.length; i++) {
    const m = CC_HEADER_PATTERNS[i].exec(value);
    if (m != null && m.length > 1 && m[1] != null) {
      const captured = m[1].trim();
      if (captured.length > 0) {
        value = captured;
        break;
      }
    }
  }
  if (value.toLowerCase().startsWith('cookie:')) {
    value = value.substring('cookie:'.length).trim();
  }
  return ccStripQuotes(value).trim();
}

/**
 * 把粘贴内容组装成可用的 Cookie 头（对照 CommandCodeCookieHeader.override）。
 * 已知会话 Cookie 命中时只发那一条；都没有但确实像 `name=value` 串时整串照发；
 * 裸令牌（既无 `=` 也无 `;`）按生产会话 Cookie 名补齐 —— macOS 就是这么处理裸令牌的，
 * 旧实现把它当 API Key 发 `Authorization: Bearer`，服务端必然 401。
 */
export function commandCodeCookieHeader(raw: string): string {
  const text = commandCodeNormalize(raw);
  if (text.length === 0) {
    return '';
  }
  if (text.indexOf('=') < 0 && text.indexOf(';') < 0) {
    return `${CC_DEFAULT_SESSION_COOKIE}=${text}`;
  }
  const parts = text.split(';');
  const pairs: string[] = [];
  const names: string[] = [];
  for (let i = 0; i < parts.length; i++) {
    const part = parts[i].trim();
    const eq = part.indexOf('=');
    if (eq <= 0) {
      continue;
    }
    const name = part.substring(0, eq).trim();
    const value = part.substring(eq + 1).trim();
    if (name.length === 0 || value.length === 0) {
      continue;
    }
    pairs.push(`${name}=${value}`);
    names.push(name.toLowerCase());
  }
  for (let i = 0; i < CC_SESSION_COOKIE_NAMES.length; i++) {
    const idx = names.indexOf(CC_SESSION_COOKIE_NAMES[i].toLowerCase());
    if (idx >= 0) {
      return pairs[idx];
    }
  }
  return pairs.join('; ');
}

/**
 * 是否为官方 Provider API Key（形如 `user_xxx`，见官方 CLI 与 pi 插件的 COMMAND_CODE_API_KEY）。
 * 其余一律按网页会话凭证处理：裸串是会话令牌，含 `=` / `;` 是 Cookie 头。
 */
export function commandCodeIsApiKey(raw: string): boolean {
  const text = raw == null ? '' : raw.trim();
  if (text.length === 0 || text.indexOf('=') >= 0 || text.indexOf(';') >= 0) {
    return false;
  }
  return /^user_[\w.-]+$/.test(text);
}

/** 凭证请求头：网页会话走 Cookie，API Key 走 Authorization */
function ccHeaders(credential: string, apiKey: boolean): Record<string, string> {
  // 对照 macOS：浏览器 UA + Origin/Referer 为服务端必需校验头
  const h: Record<string, string> = {
    'accept': 'application/json, text/plain, */*',
    'accept-language': 'en-US,en;q=0.9',
    'user-agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36',
    'origin': CC_WEB,
    'referer': `${CC_WEB}/`,
  };
  if (apiKey) {
    h['authorization'] = `Bearer ${credential}`;
  } else {
    h['cookie'] = commandCodeCookieHeader(credential);
  }
  return h;
}

/** 计费端点换用 alpha 前缀重试的场合：凭证类型不对或路径不存在的可恢复错误 */
function ccShouldRetryAlpha(code: number): boolean {
  return code === 401 || code === 403 || code === 404;
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

/**
 * 套餐 → 月度额度总额（美元）的静态目录（对照 macOS CommandCodePlanCatalog.plans）。
 *
 * `/billing/credits` 只给出**剩余**的 monthlyCredits，总额只发布在定价页上，按 subscriptions
 * 返回的 planId 查表；没有它就无法算月度泳道的已用百分比。
 */
export interface CommandCodePlan {
  id: string;
  displayName: string;
  monthlyCreditsUSD: number;
}

export const COMMAND_CODE_PLANS: CommandCodePlan[] = [
  { id: 'individual-go', displayName: 'Go', monthlyCreditsUSD: 10 },
  { id: 'individual-goat', displayName: 'GOAT', monthlyCreditsUSD: 70 },
  { id: 'individual-pro', displayName: 'Pro', monthlyCreditsUSD: 30 },
  { id: 'individual-pro-v1', displayName: 'Pro', monthlyCreditsUSD: 80 },
  { id: 'individual-max', displayName: 'Max', monthlyCreditsUSD: 150 },
  { id: 'individual-ultra', displayName: 'Ultra', monthlyCreditsUSD: 300 },
];

/** planId → 套餐（大小写不敏感；未知套餐返回 null，对照 CommandCodePlanCatalog.plan(forID:)） */
export function commandCodePlanFor(planId: string | null): CommandCodePlan | null {
  if (planId == null || planId.length === 0) {
    return null;
  }
  const want = planId.toLowerCase();
  for (let i = 0; i < COMMAND_CODE_PLANS.length; i++) {
    if (COMMAND_CODE_PLANS[i].id === want) {
      return COMMAND_CODE_PLANS[i];
    }
  }
  return null;
}

/** 美元文案（对照 CommandCodeUsageSnapshot.formatUSD：< $100 保留两位，否则取整） */
export function commandCodeUSD(value: number): string {
  return value < 100 ? `$${value.toFixed(2)}` : `$${Math.round(value)}`;
}

/**
 * 月度泳道（对照 CommandCodeUsageSnapshot.makeMonthlyWindow）：总额取自套餐目录，
 * 已用 = 总额 − 剩余，截断在 [0, 总额]，重置时间用账期截止。
 *
 * `freeTierConfirmed` 只在订阅查询**显式成功且 data 为 null** 时为真；查询超时/失败、或返回了
 * 本目录不认识的 planId 时为假——这两种情况总额都不可知，宁可不出泳道，也不要报 0% 把已经花掉的
 * 付费额度显示成「未动用」。
 */
export function commandCodeMonthlyWindow(
  plan: CommandCodePlan | null,
  monthlyRemaining: number,
  purchased: number,
  periodEndMs: number,
  freeTierConfirmed: boolean
): RateWindow | null {
  if (plan != null && plan.monthlyCreditsUSD > 0) {
    const total = plan.monthlyCreditsUSD;
    const used = Math.max(0, Math.min(total, total - monthlyRemaining));
    return makeWindow(Math.max(0, Math.min(100, (used / total) * 100)), periodEndMs, true);
  }
  if (!freeTierConfirmed) {
    return null;
  }
  // 免费版：没有月度额度可消耗，只要还有可花费余额就报 0%
  if (monthlyRemaining > 0 || purchased > 0) {
    return makeWindow(0, periodEndMs, true);
  }
  return null;
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
    accentColor: '#A04DFD',
    authHint: '粘贴 commandcode.ai 的会话 Cookie（整段 Cookie 头 / cURL 抓包 / 裸令牌均可），或 user_ 开头的 API Key',
    authUrl: 'https://commandcode.ai/settings/billing',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const credential = setting.credential.trim();
    if (credential.length === 0) {
      return UsageSnapshot.failure('未配置会话 Cookie 或 API Key');
    }
    const apiKey = commandCodeIsApiKey(credential);
    const headers = ccHeaders(credential, apiKey);

    // credits（必需；结构对照 macOS parseCredits）
    // 网页会话（Cookie）走 macOS 用的 /internal/billing；API Key 走官方 CLI / pi 插件的
    // /alpha/billing，并在 401/403/404 时回退到 /internal（两种部署都见过的端点前缀）。
    let creditsBase = CC_API;
    let creditsResp: HttpResult;
    if (apiKey) {
      creditsBase = CC_ALPHA;
      creditsResp = await Http.get(`${CC_ALPHA}/billing/credits`, headers);
      if (!creditsResp.ok && ccShouldRetryAlpha(creditsResp.code)) {
        creditsBase = CC_API;
        creditsResp = await Http.get(`${CC_API}/internal/billing/credits`, headers);
      }
    } else {
      creditsResp = await Http.get(`${CC_API}/internal/billing/credits`, headers);
    }
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

    // subscriptions（失败不阻断主数据；但月度泳道的总额要从这里拿，所以必须先问）
    // 只有「显式成功且 data 为 null」才表示免费版，失败信封是短暂状态，不能当成免费版
    let subscriptionAnswered = false;
    let planId: string | null = null;
    let subStatus: string | null = null;
    let periodEnd = 0;
    const subResp = await Http.get(`${creditsBase}/billing/subscriptions`, headers);
    if (subResp.ok) {
      const sRoot = asObj(subResp.json());
      if (sRoot != null && sRoot['success'] === true) {
        subscriptionAnswered = true;
        const sData = asObj(sRoot['data']);
        if (sData != null) {
          planId = optStr(sData, 'planId');
          subStatus = optStr(sData, 'status');
          periodEnd = ccDateMs(sData['currentPeriodEnd']);
        }
      }
    }
    const plan = commandCodePlanFor(planId);
    // 只有「查询成功 + 明确没有订阅」才是已验证的免费版；回了个目录外 planId 不算
    const freeTier = subscriptionAnswered && (planId == null || planId.length === 0);

    const snap = UsageSnapshot.success(
      ccWindow(wl != null ? asObj(wl['fiveHour']) : null),
      ccWindow(wl != null ? asObj(wl['weekly']) : null),
      commandCodeMonthlyWindow(plan, monthly, purchased, periodEnd, freeTier)
    );
    const balance = monthly + purchased;
    snap.providerCost = {
      remaining: balance, used: 0, currency: 'CREDITS',
      displayText: `${Math.round(balance * 100) / 100} credits`,
    };

    const rows: ProviderDetailRow[] = [
      { label: '月度额度', value: `${monthly}` },
      { label: '已购额度', value: `${purchased}` },
      { label: '高级月度', value: `${premium}` },
      { label: '开源月度', value: `${opensource}` },
    ];
    if (plan != null) {
      // 总额来自套餐目录，credits 端点只给剩余（对照 CommandCodeUsageSnapshot.makeLoginMethod）
      const used = Math.max(0, Math.min(plan.monthlyCreditsUSD, plan.monthlyCreditsUSD - monthly));
      rows.push({ label: '计划', value: plan.displayName });
      rows.push({
        label: '月度已用',
        value: `${commandCodeUSD(used)} of ${commandCodeUSD(plan.monthlyCreditsUSD)}`,
      });
    } else if (planId != null && planId.length > 0) {
      // 目录外的 planId：总额不可知（对照 macOS unknownPlan，但保留 credits 主数据不报错）
      rows.push({ label: '计划', value: planId });
    } else if (subscriptionAnswered && subStatus == null) {
      rows.push({ label: '状态', value: '免费版' });
    }
    if (subStatus != null) {
      rows.push({ label: '状态', value: subStatus });
    }
    if (periodEnd > 0) {
      rows.push({ label: '账期截止', value: Format.dateTime(periodEnd) });
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
    accentColor: '#FFD100',
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

// ---------------------------------------------------------------------------
// ZoomMate（对照 ZoomMateUsageFetcher / ZoomMateCreditsHistoryFetcher）
// ---------------------------------------------------------------------------

/** 两个可互换的主机，任一退役不影响（源工程 withAPIHostFailover） */
const ZM_HOSTS = ['ai.zoom.us', 'zoommate.zoom.us'];
const ZM_STATUS_PATH = '/ai-computer/api/v1/credits/status';
const ZM_HISTORY_PATH = '/ai-computer/api/v1/credits/history';
const ZM_UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36';

/** 状态信封：data.credit_status → credit_status → credits → 根对象 */
export function zoomMateCreditStatus(json: Json): Record<string, Json> | null {
  const root = asObj(json);
  if (root == null) {
    return null;
  }
  const data = asObj(root['data']);
  if (data != null) {
    const inner = asObj(data['credit_status']);
    if (inner != null) {
      return inner;
    }
  }
  const direct = asObj(root['credit_status']);
  if (direct != null) {
    return direct;
  }
  const credits = asObj(root['credits']);
  if (credits != null) {
    return credits;
  }
  return root;
}

/**
 * credit_status → 主窗口（对照 ZoomMateModels.toUsageSnapshot D5 映射）：
 * 无限额或预算为 0 时用量记 0；重置点取 cycle_end_date（毫秒或 ISO）。
 */
export function zoomMateStatusWindow(value: Json): RateWindow | null {
  const status = asObj(value);
  if (status == null) {
    return null;
  }
  const unlimited = status['is_unlimited'] === true || status['isUnlimited'] === true;
  const cap = getNum3(status, ['budget_cap', 'budgetCap']) ?? 0;
  const used = getNum3(status, ['used_credit', 'usedCredit']) ?? 0;
  const percent = unlimited || cap <= 0 ? 0 : Math.min(100, Math.max(0, (used / cap) * 100));
  return makeWindow(percent, zoomMateResetMs(status), unlimited || cap <= 0 ? false : true);
}

/** 周期日期字段 → 毫秒（支持毫秒/秒时间戳与 ISO 字符串） */
function zmDateMs(raw: Json): number {
  if (typeof raw === 'number') {
    const n = raw as number;
    if (n > 1e12) {
      return n;
    }
    return n > 1e9 ? n * 1000 : 0;
  }
  if (typeof raw === 'string' && (raw as string).length > 0) {
    const parsed = Date.parse(raw as string);
    return isNaN(parsed) ? 0 : parsed;
  }
  return 0;
}

/** cycle_end_date → 毫秒（主窗口重置点） */
export function zoomMateResetMs(value: Json): number {
  const status = asObj(value);
  return status == null ? 0 : zmDateMs(get3(status, ['cycle_end_date', 'cycleEndDate']));
}

function zmDateKey(ms: number): string {
  const d = new Date(ms);
  const month = d.getMonth() + 1;
  const day = d.getDate();
  return `${d.getFullYear()}-${month < 10 ? '0' : ''}${month}-${day < 10 ? '0' : ''}${day}`;
}

/** ISO8601（秒级，对照源工程 .withInternetDateTime） */
function zmIso(ms: number): string {
  return new Date(ms).toISOString().replace(/\.\d{3}Z$/, 'Z');
}

/** 本地零点 */
function zmStartOfDay(ms: number): number {
  const d = new Date(ms);
  return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0, 0).getTime();
}

function zmCredits(value: number): string {
  return `${Math.round(value * 100) / 100}`;
}

/** credits/history 响应 → 记录数组（缺 data 信封时返回 null，对照源工程 parseFailed 不附带历史） */
export function zoomMateHistoryRecords(json: Json): Json[] | null {
  const root = asObj(json);
  const data = root != null ? asObj(root['data']) : null;
  if (data == null) {
    return null;
  }
  const records = asArray(data['records']);
  return records == null ? [] : records;
}

/**
 * 整页记录都早于给定时间点？（对照源工程的 allOlderThanWindow 防御性停页；
 * time 无法解析的记录按「不算旧」处理，避免误停）
 */
function zmPageAllOlderThan(records: Json[], startTime: number): boolean {
  if (records.length === 0) {
    return false;
  }
  for (let i = 0; i < records.length; i++) {
    const rec = asObj(records[i]);
    const timeStr = rec != null ? optStr(rec, 'time') : null;
    if (timeStr == null || timeStr.length === 0) {
      return false;
    }
    const ms = Date.parse(timeStr);
    if (isNaN(ms) || ms >= startTime) {
      return false;
    }
  }
  return true;
}

/**
 * 多页记录 → 本地日聚合（对照 ZoomMateCreditsHistorySnapshot.dailyBreakdown）：
 * 跳过 is_deleted、cost 缺失或为负、time 无法解析的记录；窗口为「今天往前 29 天」的本地零点起。
 */
export function zoomMateDailyBreakdown(records: Json[], now: number): ProviderChartPoint[] {
  const from = zmStartOfDay(now) - 29 * 86400000;
  const totals: Map<string, number> = new Map<string, number>();
  for (let i = 0; i < records.length; i++) {
    const rec = asObj(records[i]);
    if (rec == null || rec['is_deleted'] === true) {
      continue;
    }
    const cost = getNum3(rec, ['cost']);
    if (cost == null || cost < 0) {
      continue;
    }
    const timeStr = optStr(rec, 'time');
    if (timeStr == null || timeStr.length === 0) {
      continue;
    }
    const ms = Date.parse(timeStr);
    if (isNaN(ms) || ms < from) {
      continue;
    }
    const key = zmDateKey(ms);
    totals.set(key, (totals.get(key) ?? 0) + cost);
  }
  const keys = Array.from(totals.keys());
  keys.sort();
  const out: ProviderChartPoint[] = [];
  for (let i = 0; i < keys.length; i++) {
    out.push({ label: keys[i], value: totals.get(keys[i])! });
  }
  return out;
}

/** 记录 → Today / 30d credits 两行（对照 toUsageSnapshot：有历史就有这两行，哪怕都是 0） */
export function zoomMateHistoryRowsFrom(records: Json[], now: number): ProviderDetailRow[] {
  const breakdown = zoomMateDailyBreakdown(records, now);
  const todayKey = zmDateKey(now);
  let today = 0;
  let total = 0;
  for (let i = 0; i < breakdown.length; i++) {
    total += breakdown[i].value;
    if (breakdown[i].label === todayKey) {
      today = breakdown[i].value;
    }
  }
  return [
    { label: 'Today', value: zmCredits(today) },
    { label: '30d credits', value: zmCredits(total) },
  ];
}

/** credits/history 单页响应 → 明细行（测试与单页场景用） */
export function zoomMateHistoryRows(json: Json, now: number): ProviderDetailRow[] {
  const records = zoomMateHistoryRecords(json);
  return records == null ? [] : zoomMateHistoryRowsFrom(records, now);
}

/**
 * Pace 文案（对照 UsagePace.weekly 的 workDays: nil 分支 = 按周期线性推进，
 * 以及 ZoomMateUsageSnapshot.paceString 的档位阈值）：
 * |delta| ≤2 视为 on track，≤6 / ≤12 / 更大分别对应 slightly / normal / far。
 */
export function zoomMatePaceText(usedPercent: number, cycleMinutes: number, resetsAtMs: number, now: number): string {
  const duration = cycleMinutes * 60000;
  const timeUntilReset = resetsAtMs - now;
  if (duration <= 0 || timeUntilReset <= 0 || timeUntilReset > duration) {
    return '';
  }
  const elapsed = Math.min(Math.max(duration - timeUntilReset, 0), duration);
  const expected = Math.min(Math.max((elapsed / duration) * 100, 0), 100);
  const actual = Math.min(Math.max(usedPercent, 0), 100);
  // 周期刚开始就已有消耗：源工程此时放弃判定
  if (elapsed === 0 && actual > 0) {
    return '';
  }
  const delta = actual - expected;
  const abs = Math.abs(delta);
  if (abs <= 2) {
    return 'On track';
  }
  const percent = `${Math.round(abs)}%`;
  if (delta >= 0) {
    return `${percent} ahead of budget`;
  }
  return `${percent} behind budget`;
}

/**
 * Pace 明细行（对照 ZoomMateCreditStatus.pacingVerdict）：
 * 需要预算上限、非无限额、且周期起止时间可解析；周期长度即 UsagePace 的 windowMinutes。
 */
export function zoomMatePaceRow(status: Record<string, Json> | null, now: number): ProviderDetailRow | null {
  if (status == null) {
    return null;
  }
  const unlimited = status['is_unlimited'] === true || status['isUnlimited'] === true;
  const cap = getNum3(status, ['budget_cap', 'budgetCap']);
  if (unlimited || cap == null || cap <= 0) {
    return null;
  }
  const startMs = zmDateMs(get3(status, ['cycle_start_date', 'cycleStartDate']));
  const endMs = zmDateMs(get3(status, ['cycle_end_date', 'cycleEndDate']));
  if (startMs <= 0 || endMs <= startMs) {
    return null;
  }
  const cycleMinutes = Math.floor((endMs - startMs) / 60000);
  if (cycleMinutes <= 0) {
    return null;
  }
  const used = getNum3(status, ['used_credit', 'usedCredit']) ?? 0;
  const usedPercent = Math.min(100, Math.max(0, (used / cap) * 100));
  const text = zoomMatePaceText(usedPercent, cycleMinutes, endMs, now);
  return text.length === 0 ? null : { label: 'Pace', value: text };
}

class ZoomMateProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'zoommate',
    title: 'ZoomMate',
    authKind: AuthKind.OAUTH_TOKEN,
    accentColor: '#0B5CFF',
    authHint: '粘贴 ai.zoom.us / zoommate.zoom.us 的会话令牌（Bearer）或整段 Cookie',
    authUrl: 'https://zoommate.zoom.us',
  };

  private headers(cred: string): Record<string, string> {
    const h: Record<string, string> = {
      'accept': 'application/json, text/plain, */*',
      'accept-language': 'en-US,en;q=0.9',
      'user-agent': ZM_UA,
    };
    // 三段式 JWT 视为 Bearer 令牌，否则按 Cookie 串处理
    if (cred.split('.').length === 3) {
      h['authorization'] = `Bearer ${cred}`;
    } else {
      h['cookie'] = cred;
    }
    return h;
  }

  /** credits/history 额外请求头（对照源工程 PageRequest 的 Sec-Fetch-* 与 Origin/Referer） */
  private historyHeaders(cred: string): Record<string, string> {
    const h = this.headers(cred);
    h['sec-fetch-dest'] = 'empty';
    h['sec-fetch-mode'] = 'cors';
    h['sec-fetch-site'] = 'same-site';
    h['origin'] = 'https://zoommate.zoom.us';
    h['referer'] = 'https://zoommate.zoom.us';
    return h;
  }

  /**
   * 拉取近 30 天账单记录（对照 ZoomMateCreditsHistoryFetcher.fetch）：
   * limit=50 逐页翻，直到 page*limit >= total、空页、整页都早于窗口起点或达到 20 页上限；
   * 任一页失败视为整个历史不可用（源工程的 pagination 循环同失败同处理）。
   */
  private async fetchHistory(host: string, cred: string, now: number): Promise<Json[] | null> {
    const limit = 50;
    const maxPages = 20;
    const startTime = now - 30 * 86400000;
    const headers = this.historyHeaders(cred);
    const all: Json[] = [];
    let total = Number.MAX_SAFE_INTEGER;
    let pages = 0;
    for (let page = 0; page * limit < total && page < maxPages; page++) {
      const url = `https://${host}${ZM_HISTORY_PATH}` +
        `?app_id=demo_app&limit=${limit}&page=${page}&sort_by=time&sort_order=desc` +
        `&start_time=${encodeURIComponent(zmIso(startTime))}` +
        `&end_time=${encodeURIComponent(zmIso(now))}`;
      const resp = await Http.get(url, headers);
      if (!resp.ok) {
        return null;
      }
      const records = zoomMateHistoryRecords(resp.json());
      if (records == null) {
        return null;
      }
      pages += 1;
      if (records.length === 0) {
        break;
      }
      for (let i = 0; i < records.length; i++) {
        all.push(records[i]);
      }
      const root = asObj(resp.json());
      const data = root != null ? asObj(root['data']) : null;
      total = data != null ? (getNum3(data, ['total']) ?? all.length) : all.length;
      // 整页都已早于窗口（按时间降序，后续页只会更旧）→ 停
      if (zmPageAllOlderThan(records, startTime)) {
        break;
      }
    }
    return pages > 0 ? all : null;
  }

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const cred = setting.credential.trim();
    if (cred.length === 0) {
      return UsageSnapshot.failure('未配置令牌');
    }
    const headers = this.headers(cred);

    // 主机降级：非鉴权失败（连不上 / 5xx）时换另一台
    let status: Record<string, Json> | null = null;
    let host = '';
    let lastError = '';
    for (let i = 0; i < ZM_HOSTS.length && status == null; i++) {
      const resp = await Http.get(`https://${ZM_HOSTS[i]}${ZM_STATUS_PATH}`, headers);
      if (resp.ok) {
        const parsed = zoomMateCreditStatus(resp.json());
        if (parsed != null) {
          status = parsed;
          host = ZM_HOSTS[i];
          break;
        }
        lastError = '响应解析失败';
        break;
      }
      lastError = resp.errorText();
      // 401/403：凭证问题，换主机也没用
      if (resp.code === 401 || resp.code === 403) {
        break;
      }
    }
    if (status == null) {
      return UsageSnapshot.failure(lastError.length > 0 ? lastError : '查询失败');
    }

    const snap = UsageSnapshot.success(zoomMateStatusWindow(status), null, null);
    snap.primaryLabel = 'Credits';

    // 额度明细（对照源工程：余额/透支/周期结束均由主窗口承载，
    // 明细只有 Credit history 一组：Today / 30d credits / Pace + Daily credits 柱状图）
    const now = Date.now();
    const historyRecords = await this.fetchHistory(host, cred, now);
    if (historyRecords != null) {
      const historyRows = zoomMateHistoryRowsFrom(historyRecords, now);
      const paceRow = zoomMatePaceRow(status, now);
      if (paceRow != null) {
        historyRows.push(paceRow);
      }
      const breakdown = zoomMateDailyBreakdown(historyRecords, now);
      const historySection: ProviderDetailSection = breakdown.length > 0
        ? { title: 'Credit history', rows: historyRows, chart: makeChart('Daily credits', 'credits', breakdown) }
        : { title: 'Credit history', rows: historyRows };
      snap.details = [historySection];
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
    accentColor: '#337EA9',
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
    // 两条泳道（对照 NotionUsageSnapshot.toUsageSnapshot）：滚动窗口 + 计费周期窗口
    const windows = notionWindows(statusRoot, Date.now());
    if (windows.primary == null && windows.secondary == null) {
      return UsageSnapshot.failure('该套餐不适用额度限制');
    }
    return UsageSnapshot.success(windows.primary, windows.secondary, null);
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

}

/** Notion 的两条泳道（对照 NotionUsageSnapshot.toUsageSnapshot） */
export class NotionWindows {
  /** 滚动窗口（rate_limit 的 value 比例，或源工程模型里的 window.used/limit） */
  primary: RateWindow | null = null;
  /** 计费周期窗口（billingPeriodWindow.used/limit，重置取 periodEndMs） */
  secondary: RateWindow | null = null;
}

/** 递归定位额度对象（原有容错逻辑：优先 rate_limit / rateLimit 且带 value） */
export function notionFindRateLimit(value: Json): Record<string, Json> | null {
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
    const found = notionFindRateLimit(o[keys[i]]);
    if (found != null) {
      return found;
    }
  }
  return null;
}

/** 递归定位计费周期窗口对象（billingPeriodWindow / billing_period_window） */
export function notionFindBillingPeriod(value: Json): Record<string, Json> | null {
  const o = asObj(value);
  if (o == null) {
    return null;
  }
  const direct = o['billingPeriodWindow'] ?? o['billing_period_window'];
  const directObj = direct != null ? asObj(direct) : null;
  if (directObj != null) {
    return directObj;
  }
  const keys = Object.keys(o);
  for (let i = 0; i < keys.length; i++) {
    const found = notionFindBillingPeriod(o[keys[i]]);
    if (found != null) {
      return found;
    }
  }
  return null;
}

/** 递归找滚动窗口的重置秒数（resetsInSeconds / resets_in_seconds） */
function notionFindResetsInSeconds(value: Json): number | null {
  const o = asObj(value);
  if (o == null) {
    return null;
  }
  const secs = optNum(o, 'resetsInSeconds') ?? optNum(o, 'resets_in_seconds');
  if (secs != null) {
    return secs;
  }
  const keys = Object.keys(o);
  for (let i = 0; i < keys.length; i++) {
    const found = notionFindResetsInSeconds(o[keys[i]]);
    if (found != null) {
      return found;
    }
  }
  return null;
}

export function notionWindows(root: Json, now: number): NotionWindows {
  const windows = new NotionWindows();
  const rateLimit = notionFindRateLimit(root);
  if (rateLimit != null) {
    let percent: number | null = null;
    const value = optNum(rateLimit, 'value');
    if (value != null) {
      percent = value * 100;
    } else {
      // 源工程模型：window.used / window.limit
      const w = asObj(rateLimit['window']);
      const used = w != null ? optNum(w, 'used') : null;
      const limit = w != null ? optNum(w, 'limit') : null;
      if (used != null && limit != null && limit > 0) {
        percent = (used / limit) * 100;
      }
    }
    if (percent != null) {
      const secs = notionFindResetsInSeconds(rateLimit);
      const resetsAt = secs != null && secs > 0 ? now + secs * 1000 : 0;
      windows.primary = makeWindow(Math.max(0, Math.min(100, percent)), resetsAt, true);
    }
  }
  const billing = notionFindBillingPeriod(root);
  if (billing != null) {
    const used = optNum(billing, 'used');
    const limit = optNum(billing, 'limit');
    if (used != null && limit != null && limit > 0) {
      const endRaw = optNum(billing, 'periodEndMs') ?? optNum(billing, 'period_end_ms');
      const endMs = endRaw != null && endRaw > 0 ? (endRaw > 1e12 ? endRaw : endRaw * 1000) : 0;
      windows.secondary = makeWindow(Math.max(0, Math.min(100, (used / limit) * 100)), endMs, true);
    }
  }
  return windows;
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
