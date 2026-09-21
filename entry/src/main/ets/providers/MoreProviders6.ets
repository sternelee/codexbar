/**
 * 服务商第七批（审计补漏）：
 * - Factory AI: GET api.factory.ai/api/billing/limits（Bearer fk- Key + x-factory-client）
 *               GET api.factory.ai/api/v1/analytics/tokens?startDate&endDate（近30天用量）
 * - Alibaba Coding Plan（百炼编码计划）：
 *   POST {region}/data/api.json?action=zeldaEasy.broadscope-bailian.codingPlan.queryCodingPlanInstanceInfoV2
 *        &product=broadscope-bailian&api=queryCodingPlanInstanceInfoV2&currentRegionId=...
 *   认证：Authorization Bearer + x-api-key + X-DashScope-API-Key（同一 API Key 三重携带）
 *   体：{"queryCodingPlanInstanceInfoRequest":{"commodityCode":"sfm_codingplan_public_intl|_cn"}}
 *   响应：递归查找 codingPlanQuotaInfo（per5Hour/perWeek/perBillMonth Used/TotalQuota + NextRefreshTime）
 */

import { Http } from '../net/Http';
import { asArray, asObj, Json, num, optNum, optStr, str } from '../net/Json';
import {
  AuthKind,
  makeWindow,
  NamedRateWindow,
  ProviderDescriptor,
  ProviderDetailRow,
  ProviderDetailSection,
  ProviderSetting,
  RateWindow,
  UsageSnapshot
} from '../model/Models';
import { UsageProvider } from './ProviderBase';
import { Format } from '../common/Format';

const ALIBABA_ACTION = 'zeldaEasy.broadscope-bailian.codingPlan.queryCodingPlanInstanceInfoV2';

interface AlibabaRegion {
  gateway: string;
  regionID: string;
  commodityCode: string;
  dashboard: string;
}

const ALIBABA_INTL: AlibabaRegion = {
  gateway: 'https://modelstudio.console.alibabacloud.com',
  regionID: 'ap-southeast-1',
  commodityCode: 'sfm_codingplan_public_intl',
  dashboard: 'https://modelstudio.console.alibabacloud.com/ap-southeast-1/?tab=coding-plan',
};

const ALIBABA_CN: AlibabaRegion = {
  gateway: 'https://bailian.console.aliyun.com',
  regionID: 'cn-beijing',
  commodityCode: 'sfm_codingplan_public_cn',
  dashboard: 'https://bailian.console.aliyun.com/cn-beijing/?tab=model',
};

/** 递归查找第一个包含任一 key 的字典（对照 Swift findFirstDictionary(matchingAnyKey:)） */
function findDictWithAnyKey(value: Json, keys: string[], depth: number): Record<string, Json> | null {
  if (depth > 8) {
    return null;
  }
  const o = asObj(value);
  if (o != null) {
    for (let i = 0; i < keys.length; i++) {
      if (o[keys[i]] != null) {
        return o;
      }
    }
    const objKeys = Object.keys(o);
    for (let i = 0; i < objKeys.length; i++) {
      const found = findDictWithAnyKey(o[objKeys[i]], keys, depth + 1);
      if (found != null) {
        return found;
      }
    }
    return null;
  }
  const arr = asArray(value);
  if (arr != null) {
    for (let i = 0; i < arr.length; i++) {
      const found = findDictWithAnyKey(arr[i], keys, depth + 1);
      if (found != null) {
        return found;
      }
    }
  }
  return null;
}

class AlibabaCodingPlanProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'alibaba-coding',
    title: '阿里云百炼编码计划',
    authKind: AuthKind.API_KEY,
    accentColor: '#FF6A00',
    authHint: '粘贴百炼/DashScope API Key（国际站或中国站均可）',
    authUrl: 'https://bailian.console.aliyun.com/cn-beijing/?tab=coding-plan',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const key = setting.credential.trim();
    if (key.length === 0) {
      return UsageSnapshot.failure('未配置 API Key');
    }
    // 第二凭证可指定站点：intl / cn（默认先国际站后中国站）
    const site = setting.credential2.trim().toLowerCase();
    const regions: AlibabaRegion[] =
      site === 'cn' ? [ALIBABA_CN, ALIBABA_INTL] :
        site === 'intl' ? [ALIBABA_INTL, ALIBABA_CN] :
          [ALIBABA_INTL, ALIBABA_CN];

    let quota: Record<string, Json> | null = null;
    let lastError = '';
    for (let r = 0; r < regions.length && quota == null; r++) {
      const region = regions[r];
      const url =
        `${region.gateway}/data/api.json?action=${ALIBABA_ACTION}` +
        `&product=broadscope-bailian&api=queryCodingPlanInstanceInfoV2&currentRegionId=${region.regionID}`;
      const headers: Record<string, string> = {
        'authorization': `Bearer ${key}`,
        'x-api-key': key,
        'x-dashscope-api-key': key,
        'content-type': 'application/json',
        'accept': 'application/json',
        'user-agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/126.0 Safari/537.36',
        'origin': region.gateway,
        'referer': region.dashboard,
      };
      const body =
        '{"queryCodingPlanInstanceInfoRequest":{"commodityCode":' +
        JSON.stringify(region.commodityCode) + '}}';
      const resp = await Http.post(url, headers, body);
      if (!resp.ok) {
        lastError = resp.errorText();
        continue;
      }
      quota = findDictWithAnyKey(resp.json(), [
        'per5HourUsedQuota', 'per5HourTotalQuota', 'perWeekUsedQuota',
        'perBillMonthUsedQuota', 'perBillMonthTotalQuota',
      ], 0);
    }
    if (quota == null) {
      return UsageSnapshot.failure(lastError.length > 0 ? lastError : '未获取到配额（Key 可能无效）');
    }

    const windowFrom = (usedKey: string, totalKey: string): RateWindow | null => {
      const used = optNum(quota, usedKey);
      const total = optNum(quota, totalKey);
      if (used == null || total == null || total <= 0) {
        return null;
      }
      return makeWindow(Math.min(100, (used / total) * 100), 0, true);
    };

    const fiveHour = windowFrom('per5HourUsedQuota', 'per5HourTotalQuota');
    const weekly = windowFrom('perWeekUsedQuota', 'perWeekTotalQuota');
    const monthly = windowFrom('perBillMonthUsedQuota', 'perBillMonthTotalQuota');

    // 数值/字符串双形态重置时间
    let resets = 0;
    const refreshNum = optNum(quota, 'per5HourQuotaNextRefreshTime');
    if (refreshNum != null && refreshNum > 1e9) {
      resets = refreshNum > 1e12 ? refreshNum : refreshNum * 1000;
    } else {
      const refreshIso = optStr(quota, 'per5HourQuotaNextRefreshTime');
      if (refreshIso != null) {
        const parsed = Date.parse(refreshIso);
        if (!isNaN(parsed)) {
          resets = parsed;
        }
      }
    }
    if (fiveHour != null && resets > 0) {
      fiveHour.resetsAt = resets;
    }

    const snap = UsageSnapshot.success(fiveHour ?? monthly, weekly ?? monthly, monthly);
    const rows: ProviderDetailRow[] = [];
    const planName = optStr(quota, 'planName') ?? optStr(quota, 'instanceName');
    if (planName != null) {
      rows.push({ label: '套餐', value: planName });
    }
    const instanceStatus = optStr(quota, 'instanceStatus');
    if (instanceStatus != null) {
      rows.push({ label: '实例状态', value: instanceStatus });
    }
    const expireTime = optStr(quota, 'expireTime');
    if (expireTime != null) {
      rows.push({ label: '到期时间', value: expireTime });
    }
    if (rows.length > 0) {
      const section: ProviderDetailSection = { title: '实例', rows: rows };
      snap.details = [section];
    }
    return snap;
  }
}

export function createAlibabaCodingPlanProvider(): UsageProvider {
  return new AlibabaCodingPlanProvider();
}

// ---------------------------------------------------------------------------
// Factory AI（API Key：billing/limits 限额 + analytics/tokens 近30天用量）
// ---------------------------------------------------------------------------

function factoryWindowMs(v: Json): number {
  if (typeof v === 'number') {
    return v > 1e12 ? v : v * 1000;
  }
  if (typeof v === 'string' && (v as string).length > 0) {
    const parsed = Date.parse(v as string);
    if (!isNaN(parsed)) {
      return parsed;
    }
  }
  return 0;
}

function factoryWindow(o: Record<string, Json> | null, now: number): RateWindow | null {
  if (o == null) {
    return null;
  }
  const pct = optNum(o, 'usedPercent');
  if (pct == null) {
    return null;
  }
  let reset = 0;
  const secs = optNum(o, 'secondsRemaining');
  if (secs != null && secs > 0) {
    reset = now + secs * 1000;
  } else {
    reset = factoryWindowMs(o['windowEnd']);
  }
  return makeWindow(Math.max(0, Math.min(100, pct)), reset, true);
}

class FactoryProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'factory',
    title: 'Factory AI',
    authKind: AuthKind.API_KEY,
    accentColor: '#E8833A',
    authHint: '粘贴 Factory API Key（fk-… 开头）',
    authUrl: 'https://factory.ai/account',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const key = setting.credential.trim();
    if (key.length === 0) {
      return UsageSnapshot.failure('未配置 API Key');
    }
    const headers: Record<string, string> = {
      'authorization': `Bearer ${key}`,
      'accept': 'application/json',
      'x-factory-client': 'web-app',
      'origin': 'https://app.factory.ai',
      'referer': 'https://app.factory.ai/',
    };

    const now = Date.now();
    const snap = UsageSnapshot.success(null, null, null);
    const sections: ProviderDetailSection[] = [];
    let limitsFail = '';
    let analyticsFail = '';

    // 1) 限额（5小时/每周/月度，standard 与 core 池）
    const limitsResp = await Http.get('https://api.factory.ai/api/billing/limits', headers);
    if (limitsResp.ok) {
      const root = asObj(limitsResp.json());
      const limits = root != null ? asObj(root['limits']) : null;
      const std = limits != null ? asObj(limits['standard']) : null;
      if (std != null) {
        snap.primary = factoryWindow(asObj(std['fiveHour']), now);
        snap.secondary = factoryWindow(asObj(std['weekly']), now);
        const monthly = factoryWindow(asObj(std['monthly']), now);
        const extra: NamedRateWindow[] = [];
        if (monthly != null) {
          extra.push({ id: 'factory_monthly', title: '月度', window: monthly });
        }
        const core = limits != null ? asObj(limits['core']) : null;
        if (core != null) {
          const c5 = factoryWindow(asObj(core['fiveHour']), now);
          const cw = factoryWindow(asObj(core['weekly']), now);
          if (c5 != null) {
            extra.push({ id: 'core_5h', title: 'Core 5小时', window: c5 });
          }
          if (cw != null) {
            extra.push({ id: 'core_weekly', title: 'Core 每周', window: cw });
          }
        }
        snap.extraRateWindows = extra;
      }
      const cents = root != null ? optNum(root, 'extraUsageBalanceCents') : null;
      if (cents != null && cents > 0) {
        snap.providerCost = {
          remaining: cents / 100, used: 0, currency: 'USD',
          displayText: Format.money(cents / 100, 'USD'),
        };
      }
    } else {
      limitsFail = limitsResp.errorText();
    }

    // 2) 近30天用量统计（analytics/tokens；数据仅到昨日 UTC）
    const end = new Date(now - 86400 * 1000);
    const start = new Date(now - 30 * 86400 * 1000);
    const dkey = (d: Date): string => {
      const p = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
      return `${d.getUTCFullYear()}-${p(d.getUTCMonth() + 1)}-${p(d.getUTCDate())}`;
    };
    const aResp = await Http.get(
      `https://api.factory.ai/api/v1/analytics/tokens?startDate=${dkey(start)}&endDate=${dkey(end)}&group_by=model`,
      headers
    );
    if (aResp.ok) {
      const root = asObj(aResp.json());
      const data = root != null ? asArray(root['data']) : null;
      if (data != null && data.length > 0) {
        let billable = 0;
        let input = 0;
        let output = 0;
        let lastDay = '';
        for (let i = 0; i < data.length; i++) {
          const day = asObj(data[i]);
          if (day == null) {
            continue;
          }
          billable += num(day, 'billable_tokens', 0);
          input += num(day, 'input_tokens', 0);
          output += num(day, 'output_tokens', 0);
          lastDay = str(day, 'date', lastDay);
        }
        const rows: ProviderDetailRow[] = [
          { label: '可计费 tokens', value: Format.compact(billable) },
          { label: '输入 / 输出', value: `${Format.compact(input)} / ${Format.compact(output)}` },
        ];
        if (lastDay.length > 0) {
          rows.push({ label: '统计截止', value: lastDay });
        }
        sections.push({ title: '近30天用量', rows: rows });
      }
    } else {
      analyticsFail = aResp.errorText();
    }

    if (snap.primary == null && sections.length === 0) {
      // 两个来源都失败：优先返回限额端的错误
      return UsageSnapshot.failure(limitsFail.length > 0 ? limitsFail : analyticsFail);
    }
    if (limitsFail.length > 0 && snap.primary == null) {
      sections.push({ title: '提示', rows: [{ label: '限额查询失败', value: limitsFail }] });
    }
    snap.details = sections;
    return snap;
  }
}

export function createFactoryProvider(): UsageProvider {
  return new FactoryProvider();
}
