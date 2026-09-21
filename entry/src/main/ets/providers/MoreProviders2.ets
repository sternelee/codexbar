/**
 * 服务商第三批（对照 macOS 版逐家迁移）：
 * - MiniMax:  GET {api.minimaxi.com|api.minimax.io}/v1/token_plan/remains（Bearer，降级 coding_plan/remains）
 * - MiMo 小米: GET platform.xiaomimimo.com/api/v1/{balance,tokenPlan/detail,tokenPlan/usage}（Cookie）
 * - Mistral:  GET admin.mistral.ai/api/billing/credits（Cookie）
 * - Kilo Code: GET api.kilo.ai tRPC 批量（Bearer + 可选组织头）
 * - Poe:      GET api.poe.com/usage/current_balance（Bearer）
 * - T3Chat:   GET t3.chat/api/trpc/getCustomerData（Cookie，JSONL 递归查找）
 * - z.ai/GLM: GET {api.z.ai|open.bigmodel.cn}/api/monitor/usage/quota/limit（Bearer）
 */

import { Http } from '../net/Http';
import { asArray, asObj, bool, Json, num, optNum, optStr, str } from '../net/Json';
import {
  AuthKind,
  makeWindow,
  NamedRateWindow,
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

function isoToMs2(iso: string | null): number {
  if (iso == null || iso.length === 0) {
    return 0;
  }
  const parsed = Date.parse(iso);
  return isNaN(parsed) ? 0 : parsed;
}

function firstOf2(o: Record<string, Json>, keys: string[]): Json {
  for (let i = 0; i < keys.length; i++) {
    const v = o[keys[i]];
    if (v != null) {
      return v;
    }
  }
  return null;
}

function firstNum2(o: Record<string, Json>, keys: string[]): number | null {
  const v = firstOf2(o, keys);
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

function firstStr2(o: Record<string, Json>, keys: string[]): string | null {
  const v = firstOf2(o, keys);
  if (typeof v === 'string') {
    return v as string;
  }
  return null;
}

// ---------------------------------------------------------------------------
// MiniMax
// ---------------------------------------------------------------------------

class MiniMaxProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'minimax',
    title: 'MiniMax',
    authKind: AuthKind.API_KEY,
    accentColor: '#F5222D',
    authHint: '粘贴 MiniMax API Token（平台账户 API 密钥）',
    authUrl: 'https://platform.minimaxi.com',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const token = setting.credential.trim();
    if (token.length === 0) {
      return UsageSnapshot.failure('未配置 API Token');
    }
    const headers: Record<string, string> = {
      'authorization': `Bearer ${token}`,
      'accept': 'application/json',
      'mm-api-source': 'CodexBar',
    };
    const hosts = ['https://api.minimaxi.com', 'https://api.minimax.io'];
    const paths = ['/v1/token_plan/remains', '/v1/api/openplatform/coding_plan/remains'];
    let root: Record<string, Json> | null = null;
    let lastError = '';
    for (let h = 0; h < hosts.length && root == null; h++) {
      for (let p = 0; p < paths.length; p++) {
        const resp = await Http.get(`${hosts[h]}${paths[p]}`, headers);
        if (resp.ok) {
          const parsed = asObj(resp.json());
          const data = parsed != null ? asObj(parsed['data']) : null;
          root = data ?? parsed;
          if (root != null && (firstNum2(root, ['current_interval_total_count']) != null ||
            firstNum2(root, ['current_weekly_total_count']) != null)) {
            break;
          }
          root = null;
        } else {
          lastError = resp.errorText();
        }
      }
    }
    if (root == null) {
      return UsageSnapshot.failure(lastError.length > 0 ? lastError : '未获取到用量数据');
    }

    const intervalRemaining = firstNum2(root, ['current_interval_remaining_percent']);
    const intervalTotal = firstNum2(root, ['current_interval_total_count']);
    let intervalUsed = 0;
    if (intervalRemaining != null) {
      intervalUsed = 100 - intervalRemaining;
    }
    const weeklyRemaining = firstNum2(root, ['current_weekly_remaining_percent']);
    const weeklyTotal = firstNum2(root, ['current_weekly_total_count']);
    let weeklyUsed = 0;
    if (weeklyRemaining != null) {
      weeklyUsed = 100 - weeklyRemaining;
    }

    const primary = intervalRemaining != null
      ? makeWindow(Math.max(0, Math.min(100, intervalUsed)), isoToMs2(firstStr2(root, ['remains_time'])), true)
      : null;
    const secondary = weeklyRemaining != null
      ? makeWindow(Math.max(0, Math.min(100, weeklyUsed)), isoToMs2(firstStr2(root, ['weekly_end_time'])), true)
      : null;

    const rows: ProviderDetailRow[] = [];
    if (intervalTotal != null) {
      rows.push({ label: '周期总量', value: `${intervalTotal}` });
    }
    if (weeklyTotal != null) {
      rows.push({ label: '每周总量', value: `${weeklyTotal}` });
    }
    const snap = UsageSnapshot.success(primary, secondary, null);
    if (rows.length > 0) {
      const section: ProviderDetailSection = { title: '配额', rows: rows };
      snap.details = [section];
    }
    return snap;
  }
}

// ---------------------------------------------------------------------------
// MiMo 小米
// ---------------------------------------------------------------------------

class MiMoProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'mimo',
    title: 'MiMo (小米)',
    authKind: AuthKind.SESSION,
    accentColor: '#FF6900',
    authHint: '粘贴 platform.xiaomimimo.com 的会话 Cookie',
    authUrl: 'https://platform.xiaomimimo.com',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const cookie = setting.credential.trim();
    if (cookie.length === 0) {
      return UsageSnapshot.failure('未配置会话 Cookie');
    }
    const headers: Record<string, string> = {
      'cookie': cookie,
      'accept': 'application/json',
    };
    const base = 'https://platform.xiaomimimo.com/api/v1';

    const snap = UsageSnapshot.success(null, null, null);
    const balResp = await Http.get(`${base}/balance`, headers);
    if (!balResp.ok) {
      return UsageSnapshot.failure(balResp.errorText());
    }
    const balRoot = asObj(balResp.json());
    const balData = balRoot != null ? asObj(balRoot['data']) : null;
    if (balData == null) {
      return UsageSnapshot.failure('余额响应解析失败');
    }
    const balance = firstNum2(balData, ['balance']) ?? 0;
    const currency = str(balData, 'currency', 'CNY');
    snap.providerCost = {
      remaining: balance, used: 0, currency: currency,
      displayText: Format.money(balance, currency),
    };

    const rows: ProviderDetailRow[] = [];
    const cash = firstNum2(balData, ['cashBalance']);
    const gift = firstNum2(balData, ['giftBalance']);
    if (cash != null) {
      rows.push({ label: '现金余额', value: Format.money(cash, currency) });
    }
    if (gift != null) {
      rows.push({ label: '赠送余额', value: Format.money(gift, currency) });
    }

    const usageResp = await Http.get(`${base}/tokenPlan/usage`, headers);
    if (usageResp.ok) {
      const uRoot = asObj(usageResp.json());
      const uData = uRoot != null ? asObj(uRoot['data']) : null;
      const month = uData != null ? asObj(uData['monthUsage']) : null;
      const percent = month != null ? firstNum2(month, ['percent']) : null;
      if (percent != null) {
        snap.primary = makeWindow(Math.max(0, Math.min(100, percent)), 0, true);
      }
      const items = month != null ? asArray(month['items']) : null;
      if (items != null) {
        for (let i = 0; i < items.length && i < 4; i++) {
          const it = asObj(items[i]);
          if (it == null) {
            continue;
          }
          rows.push({ label: str(it, 'name', `项目${i + 1}`), value: `${Math.round(num(it, 'used', 0))} / ${Math.round(num(it, 'limit', 0))}` });
        }
      }
    }
    const detailResp = await Http.get(`${base}/tokenPlan/detail`, headers);
    if (detailResp.ok) {
      const dRoot = asObj(detailResp.json());
      const dData = dRoot != null ? asObj(dRoot['data']) : null;
      if (dData != null) {
        const planCode = optStr(dData, 'planCode');
        if (planCode != null && planCode.length > 0) {
          rows.push({ label: '套餐', value: planCode });
        }
      }
    }
    if (rows.length > 0) {
      const section: ProviderDetailSection = { title: '明细', rows: rows };
      snap.details = [section];
    }
    return snap;
  }
}

// ---------------------------------------------------------------------------
// Mistral
// ---------------------------------------------------------------------------

class MistralProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'mistral',
    title: 'Mistral',
    authKind: AuthKind.SESSION,
    accentColor: '#FA500F',
    authHint: '粘贴 admin.mistral.ai 的会话 Cookie',
    authUrl: 'https://admin.mistral.ai/organization/billing',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const cookie = setting.credential.trim();
    if (cookie.length === 0) {
      return UsageSnapshot.failure('未配置会话 Cookie');
    }
    const headers: Record<string, string> = {
      'cookie': cookie,
      'accept': '*/*',
      'referer': 'https://admin.mistral.ai/organization/billing',
      'origin': 'https://admin.mistral.ai',
    };
    const resp = await Http.get('https://admin.mistral.ai/api/billing/credits', headers);
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    const root = asObj(resp.json());
    if (root == null) {
      return UsageSnapshot.failure('响应解析失败');
    }
    const wallet = firstNum2(root, ['walletAmount', 'wallet_amount']) ?? 0;
    const notes = firstNum2(root, ['creditNotesAmount', 'credit_notes_amount']) ?? 0;
    const ongoing = firstNum2(root, ['ongoingUsageBalance', 'ongoing_usage_balance']) ?? 0;
    const currency = str(root, 'currency', 'EUR');
    const snap = UsageSnapshot.success(null, null, null);
    snap.providerCost = {
      remaining: wallet, used: 0, currency: currency,
      displayText: Format.money(wallet, currency),
    };
    const rows: ProviderDetailRow[] = [
      { label: '钱包余额', value: Format.money(wallet, currency) },
      { label: '信用额度', value: Format.money(notes, currency) },
      { label: '进行中消费', value: Format.money(ongoing, currency) },
    ];
    const section: ProviderDetailSection = { title: '余额明细', rows: rows };
    snap.details = [section];
    return snap;
  }
}

// ---------------------------------------------------------------------------
// Kilo Code
// ---------------------------------------------------------------------------

class KiloProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'kilo',
    title: 'Kilo Code',
    authKind: AuthKind.API_KEY,
    accentColor: '#0D9488',
    authHint: '粘贴 Kilo API Key；可选第二栏填组织 ID',
    authUrl: 'https://app.kilo.ai',
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
    const org = setting.credential2.trim();
    if (org.length > 0) {
      headers['x-kilocode-organizationid'] = org;
    }
    const input = encodeURIComponent('{"0":{"json":null},"1":{"json":null},"2":{"json":null}}');
    const url =
      'https://api.kilo.ai/user.getCreditBlocks,kiloPass.getState,user.getAutoTopUpPaymentMethod' +
      `?batch=1&input=${input}`;
    const resp = await Http.get(url, headers);
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    const entries = asArray(resp.json());
    if (entries == null || entries.length < 2) {
      return UsageSnapshot.failure('响应解析失败');
    }
    // 第 0 项：信用块；第 1 项：Kilo Pass 状态
    const jsonOf = (entry: Json): Record<string, Json> | null => {
      const e = asObj(entry);
      const result = e != null ? asObj(e['result']) : null;
      const data = result != null ? asObj(result['data']) : null;
      return data != null ? asObj(data['json']) : null;
    };

    const snap = UsageSnapshot.success(null, null, null);
    const rows: ProviderDetailRow[] = [];
    const pass = jsonOf(entries[1]);
    if (pass != null) {
      const used = firstNum2(pass, ['used', 'creditsUsed']);
      const total = firstNum2(pass, ['total', 'creditsTotal']);
      const remaining = firstNum2(pass, ['remaining', 'creditsRemaining', 'available']);
      if (used != null && total != null && total > 0) {
        snap.primary = makeWindow(Math.min(100, (used / total) * 100), 0, true);
      }
      if (total != null) {
        rows.push({ label: '总额度', value: `${Math.round(total)}` });
      }
      if (used != null) {
        rows.push({ label: '已使用', value: `${Math.round(used)}` });
      }
      if (remaining != null) {
        rows.push({ label: '剩余', value: `${Math.round(remaining)}` });
      }
    }
    const blocksJson = jsonOf(entries[0]);
    const blocks = blocksJson != null ? asArray(blocksJson['blocks']) : null;
    if (blocks != null) {
      for (let i = 0; i < blocks.length && i < 4; i++) {
        const b = asObj(blocks[i]);
        if (b == null) {
          continue;
        }
        const amount = firstNum2(b, ['amount', 'total']);
        const available = firstNum2(b, ['available', 'remaining']);
        if (amount != null) {
          const line = available != null ? `${Math.round(available)} / ${Math.round(amount)}` : `${Math.round(amount)}`;
          rows.push({ label: `信用块 #${i + 1}`, value: line });
        }
      }
    }
    if (snap.primary == null && rows.length === 0) {
      return UsageSnapshot.failure('未识别到额度数据');
    }
    if (rows.length > 0) {
      const section: ProviderDetailSection = { title: '额度明细', rows: rows };
      snap.details = [section];
    }
    return snap;
  }
}

// ---------------------------------------------------------------------------
// Poe
// ---------------------------------------------------------------------------

class PoeProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'poe',
    title: 'Poe',
    authKind: AuthKind.API_KEY,
    accentColor: '#5D5CDE',
    authHint: '粘贴 Poe API Key（poe.com/api/keys 页面创建）',
    authUrl: 'https://poe.com/api/keys',
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
    const resp = await Http.get('https://api.poe.com/usage/current_balance', headers);
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    const root = asObj(resp.json());
    if (root == null) {
      return UsageSnapshot.failure('响应解析失败');
    }
    const balance = firstNum2(root, ['current_point_balance']) ?? 0;
    const snap = UsageSnapshot.success(null, null, null);
    snap.providerCost = {
      remaining: balance, used: 0, currency: 'POINTS',
      displayText: `${balance >= 1000 ? Format.compact(balance) : `${balance}`} points`,
    };
    return snap;
  }
}

// ---------------------------------------------------------------------------
// T3Chat
// ---------------------------------------------------------------------------

/** JSONL 中递归查找含用量字段的客户数据对象（对照 t3chat.js 的 find 函数） */
export function t3chatFindCustomerData(value: Json): Record<string, Json> | null {
  if (value == null || !(value instanceof Object)) {
    return null;
  }
  const o = asObj(value);
  if (o == null) {
    return null;
  }
  if (o['usageFourHourPercentage'] != null || o['usageMonthPercentage'] != null ||
    (o['subscription'] != null && o['usageBand'] != null)) {
    return o;
  }
  const keys = Object.keys(o);
  for (let i = 0; i < keys.length; i++) {
    const child = o[keys[i]];
    if (child instanceof Object) {
      const found = t3chatFindCustomerData(child);
      if (found != null) {
        return found;
      }
    }
  }
  return null;
}

class T3ChatProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 't3chat',
    title: 'T3 Chat',
    authKind: AuthKind.SESSION,
    accentColor: '#10B981',
    authHint: '粘贴 t3.chat 的会话 Cookie',
    authUrl: 'https://t3.chat',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const cookie = setting.credential.trim();
    if (cookie.length === 0) {
      return UsageSnapshot.failure('未配置会话 Cookie');
    }
    const input = encodeURIComponent('{"0":{"json":{"sessionId":null},"meta":{"values":{"sessionId":["undefined"]}}}}');
    const headers: Record<string, string> = {
      'cookie': cookie,
      'accept': '*/*',
      'referer': 'https://t3.chat/settings/customization',
      'trpc-accept': 'application/jsonl',
      'x-trpc-source': 'web-client',
      'x-trpc-batch': 'true',
    };
    const resp = await Http.get(`https://t3.chat/api/trpc/getCustomerData?batch=1&input=${input}`, headers);
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    let data: Record<string, Json> | null = null;
    const lines = resp.body.split('\n');
    for (let i = 0; i < lines.length && data == null; i++) {
      const line = lines[i].trim();
      if (line.length === 0) {
        continue;
      }
      const parsed = asObj(Json_parse(line));
      if (parsed != null) {
        data = t3chatFindCustomerData(parsed);
      }
    }
    if (data == null) {
      return UsageSnapshot.failure('响应中缺少客户数据');
    }

    const pct = (v: Json): number => {
      const n = typeof v === 'number' ? v as number : 0;
      return Math.max(0, Math.min(100, n));
    };
    const toMs = (v: Json): number => {
      const n = typeof v === 'number' ? v as number : 0;
      if (n <= 0) {
        return 0;
      }
      return n > 10000000000 ? n : n * 1000;
    };

    const fourHour = data['usageFourHourPercentage'];
    const month = data['usageMonthPercentage'] ?? data['usagePeriodPercentage'];
    const primary = fourHour != null
      ? makeWindow(pct(fourHour), toMs(data['usageFourHourNextResetAt'] ?? data['usageWindowNextResetAt']), true)
      : null;
    const secondary = month != null
      ? makeWindow(pct(month), toMs(data['billingNextResetAt']), true)
      : null;

    const snap = UsageSnapshot.success(primary, secondary, null);
    const rows: ProviderDetailRow[] = [];
    const sub = asObj(data['subscription']);
    const rawPlan = (sub != null ? optStr(sub, 'productName') : null) ?? optStr(data, 'subTier');
    if (rawPlan != null && rawPlan.length > 0) {
      rows.push({ label: '套餐', value: rawPlan });
    }
    const lifetime = optNum(data, 'lifetimeBalance');
    if (lifetime != null) {
      rows.push({ label: '历史消息余额', value: `${lifetime}` });
    }
    const band = optStr(data, 'usageBand');
    if (band != null && band.length > 0) {
      rows.push({ label: '用量档位', value: band });
    }
    if (rows.length > 0) {
      const section: ProviderDetailSection = { title: '订阅', rows: rows };
      snap.details = [section];
    }
    return snap;
  }
}

function Json_parse(text: string): Json {
  try {
    return JSON.parse(text) as Json;
  } catch (e) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// z.ai / GLM 智谱
// ---------------------------------------------------------------------------

/** 单位代码 → 分钟（对照 zai.js multipliers：1=天 3=小时 5=分钟 6=周） */
function zaiWindowMinutes(unit: number, number: number): number {
  const multipliers: Record<number, number> = { 1: 1440, 3: 60, 5: 1, 6: 10080 };
  const m = multipliers[unit];
  return m != null && number > 0 ? number * m : 0;
}

export function zaiLimitWindow(limit: Record<string, Json>): NamedRateWindow | null {
  const type = str(limit, 'type');
  if (type !== 'TOKENS_LIMIT' && type !== 'TIME_LIMIT' && type !== 'CREDIT_LIMIT') {
    return null;
  }
  const unit = num(limit, 'unit', 0);
  const number = num(limit, 'number', 0);
  let percent = num(limit, 'percentage', 0);
  const usage = optNum(limit, 'usage');
  const remaining = optNum(limit, 'remaining');
  const current = optNum(limit, 'currentValue');
  if (usage != null && usage > 0) {
    let used = 0;
    if (remaining != null) {
      used = Math.max(usage - remaining, current == null ? usage - remaining : current);
    } else if (current != null) {
      used = current;
    }
    percent = Math.max(0, Math.min(100, (used / usage) * 100));
  }
  percent = Math.max(0, Math.min(100, percent));
  const windowMinutes = zaiWindowMinutes(unit, number);
  const resetSec = optNum(limit, 'nextResetTime');
  const resets = resetSec != null && resetSec > 0 ? resetSec * 1000 : 0;

  let title: string;
  if (type === 'TIME_LIMIT') {
    const unitNames: Record<number, string> = { 1: '天', 3: '小时', 5: '分钟', 6: '周' };
    const name = unitNames[unit];
    title = number === 5 && unit === 5 ? '5 小时窗口' : name != null ? `${number} ${name}窗口` : '时间窗口';
  } else if (type === 'TOKENS_LIMIT') {
    title = 'Token 配额';
  } else {
    title = 'Credit 配额';
  }
  const rows: ProviderDetailRow[] = [];
  if (usage != null) {
    rows.push({ label: '限额', value: `${usage}` });
  }
  if (remaining != null) {
    rows.push({ label: '剩余', value: `${remaining}` });
  }
  const w = makeWindow(percent, resets, true);
  return { id: `zai_${type}_${unit}_${number}`, title: title, window: w };
}

class ZaiProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'zai',
    title: 'z.ai / GLM 智谱',
    authKind: AuthKind.API_KEY,
    accentColor: '#3859FF',
    authHint: '粘贴 z.ai 或 BigModel/GLM 的 API Key',
    authUrl: 'https://z.ai',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const key = setting.credential.trim();
    if (key.length === 0) {
      return UsageSnapshot.failure('未配置 API Key');
    }
    // 优先国际站 api.z.ai，401/403/404 时回退开放平台
    const hosts = ['https://api.z.ai', 'https://open.bigmodel.cn'];
    const headers: Record<string, string> = {
      'authorization': `Bearer ${key}`,
      'accept': 'application/json',
    };
    let root: Record<string, Json> | null = null;
    let lastError = '';
    for (let i = 0; i < hosts.length && root == null; i++) {
      const resp = await Http.get(`${hosts[i]}/api/monitor/usage/quota/limit`, headers);
      if (resp.ok) {
        const parsed = asObj(resp.json());
        if (parsed != null && bool(parsed, 'success') && num(parsed, 'code', 0) === 200) {
          const data = asObj(parsed['data']);
          const limits = data != null ? asArray(data['limits']) : null;
          if (limits != null) {
            root = parsed;
            break;
          }
        }
        lastError = '响应格式不符';
      } else {
        lastError = resp.errorText();
      }
    }
    if (root == null) {
      return UsageSnapshot.failure(lastError);
    }
    const data = asObj(root['data'])!;
    const limits = asArray(data['limits'])!;

    const windows: NamedRateWindow[] = [];
    for (let i = 0; i < limits.length && windows.length < 6; i++) {
      const l = asObj(limits[i]);
      if (l == null) {
        continue;
      }
      const w = zaiLimitWindow(l);
      if (w != null) {
        windows.push(w);
      }
    }
    // 主窗口：优先 5 小时（300 分钟）窗口
    let primary: RateWindow | null = null;
    let secondary: RateWindow | null = null;
    for (let i = 0; i < windows.length; i++) {
      const title = windows[i].title;
      if (primary == null && title === '5 小时窗口') {
        primary = windows[i].window;
        continue;
      }
      if (secondary == null && title.indexOf('周') >= 0) {
        secondary = windows[i].window;
      }
    }
    if (primary == null && windows.length > 0) {
      primary = windows[0].window;
    }
    const extras: NamedRateWindow[] = windows.filter(w => w.window !== primary && w.window !== secondary);

    const snap = UsageSnapshot.success(primary, secondary, null);
    snap.extraRateWindows = extras.slice(0, 4);
    snap.identity = { accountEmail: '', accountOrganization: '', loginMethod: 'API Key' };
    return snap;
  }
}

export function createMiniMaxProvider(): UsageProvider {
  return new MiniMaxProvider();
}

export function createMiMoProvider(): UsageProvider {
  return new MiMoProvider();
}

export function createMistralProvider(): UsageProvider {
  return new MistralProvider();
}

export function createKiloProvider(): UsageProvider {
  return new KiloProvider();
}

export function createPoeProvider(): UsageProvider {
  return new PoeProvider();
}

export function createT3ChatProvider(): UsageProvider {
  return new T3ChatProvider();
}

export function createZaiProvider(): UsageProvider {
  return new ZaiProvider();
}
