/**
 * CodexBar Mobile — API Key 服务商（新增批次）：v0 / Amp / Azure OpenAI / Ollama / Copilot
 *
 * 逐家对照 macOS 版 Sources/CodexBarCore 迁移，只保留 API Key 查询路径：
 * - v0         ← Resources/Plugins/v0.js（Bearer V0_API_KEY，/user/billing + /rate-limits）
 * - Amp        ← Providers/Amp/AmpUsageFetcher.swift（POST ampcode.com/api/internal，Bearer AMP_API_KEY，
 *                解析 userDisplayBalanceInfo 的 displayText：Amp Free / Subscription / Individual credits）
 * - Azure OpenAI ← Providers/AzureOpenAI/AzureOpenAIUsageFetcher.swift（api-key 头 + 部署 chat/completions 校验）
 * - Ollama     ← Providers/Ollama/OllamaUsageFetcher.swift（OllamaAPIUsageFetcher：web_search 校验 + /api/tags）
 * - Copilot    ← Providers/Copilot/CopilotUsageFetcher.swift（GitHub token → api.github.com/copilot_internal/user）
 */

import { Http } from '../net/Http';
import { asObj, bool, Json, num, optNum, optStr, str } from '../net/Json';
import {
  AuthKind,
  extraValue,
  makeWindow,
  NamedRateWindow,
  ProviderDescriptor,
  ProviderDetailRow,
  ProviderDetailSection,
  ProviderSetting,
  RateWindow,
  rowProgress,
  UsageSnapshot
} from '../model/Models';
import { UsageProvider } from './ProviderBase';
import { Format } from '../common/Format';

// ---------------- 公共小工具 ----------------

/** 金额展示：12.5 → "$12.50" */
function usd(v: number): string {
  return `$${v.toFixed(2)}`;
}

/** 正则首匹配的第 index 个捕获组；无匹配返回 '' */
function group(text: string, pattern: string, index: number): string {
  const re = new RegExp(pattern, 'im');
  const m = re.exec(text);
  if (m == null || m.length <= index) {
    return '';
  }
  const g = m[index];
  return g == null ? '' : g;
}

/** 解析金额文本（去千分位）；失败返回 null */
function amount(text: string): number | null {
  if (text == null || text.length === 0) {
    return null;
  }
  const v = parseFloat(text.replace(/,/g, ''));
  return isNaN(v) ? null : v;
}

/** 解析 Unix 秒/毫秒（>= 1e12 视为毫秒）；<=0 返回 0 */
function unixToMs(value: number): number {
  if (value <= 0) {
    return 0;
  }
  return value >= 1000000000000 ? value : value * 1000;
}

/** ISO8601 或 yyyy-MM-dd → Unix 毫秒；失败返回 0 */
function parseDateText(raw: string): number {
  const text = raw.trim();
  if (text.length === 0) {
    return 0;
  }
  const iso = Date.parse(text);
  if (!isNaN(iso)) {
    return iso;
  }
  const m = new RegExp('^(\\d{4})-(\\d{2})-(\\d{2})$').exec(text);
  if (m == null) {
    return 0;
  }
  const ms = Date.UTC(parseInt(m[1], 10), parseInt(m[2], 10) - 1, parseInt(m[3], 10));
  return isNaN(ms) ? 0 : ms;
}

// ---------------- v0 ----------------

class V0Provider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'v0',
    title: 'v0',
    authKind: AuthKind.API_KEY,
    accentColor: '#111111',
    authHint: '粘贴 v0 Platform API Key（v0.app/settings/keys）',
    authUrl: 'https://v0.app/settings/keys',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const key = setting.credential.trim();
    if (key.length === 0) {
      return UsageSnapshot.failure('未配置 v0 API Key');
    }
    const scope = extraValue(setting.extraConfig, 'scope');
    const query = scope.length > 0 ? `?scope=${encodeURIComponent(scope)}` : '';
    const headers: Record<string, string> = {
      'authorization': `Bearer ${key}`,
      'accept': 'application/json',
    };

    const billingResp = await Http.get(`https://api.v0.dev/v1/user/billing${query}`, headers);
    if (!billingResp.ok) {
      return UsageSnapshot.failure(billingResp.errorText());
    }
    const billing = asObj(billingResp.json());
    if (billing == null) {
      return UsageSnapshot.failure('v0 计费响应解析失败');
    }
    const billingType = str(billing, 'billingType');
    if (billingType !== 'token' && billingType !== 'legacy') {
      return UsageSnapshot.failure('无法解析 v0 计费类型');
    }
    const data = asObj(billing['data']);
    if (data == null) {
      return UsageSnapshot.failure('v0 计费数据缺失');
    }

    let primary: RateWindow | null = null;
    let billingRemaining: number | null = null;
    let billingLimit = 0;
    let onDemandBalance: number | null = null;
    if (billingType === 'token') {
      const balance = asObj(data['balance']);
      const cycle = asObj(data['billingCycle']);
      const onDemand = asObj(data['onDemand']);
      const total = balance != null ? optNum(balance, 'total') : null;
      const remaining = balance != null ? optNum(balance, 'remaining') : null;
      if (total != null && remaining != null && total >= 0) {
        billingRemaining = remaining;
        billingLimit = total;
        primary = makeWindow(total > 0 ? Math.max(0, Math.min(100, ((total - remaining) / total) * 100)) : 0,
          cycle != null ? unixToMs(num(cycle, 'end')) : 0, true);
      }
      if (onDemand != null) {
        onDemandBalance = optNum(onDemand, 'balance');
      }
    } else {
      const limit = optNum(data, 'limit');
      const remaining = optNum(data, 'remaining');
      if (limit != null && remaining != null && limit >= 0) {
        billingRemaining = remaining;
        billingLimit = limit;
        primary = makeWindow(limit > 0 ? Math.max(0, Math.min(100, ((limit - remaining) / limit) * 100)) : 0,
          unixToMs(num(data, 'reset')), true);
      }
    }

    const rateResp = await Http.get(`https://api.v0.dev/v1/rate-limits${query}`, headers);
    let secondary: RateWindow | null = null;
    let rateRemaining: number | null = null;
    let rateLimit = 0;
    if (rateResp.ok) {
      const rate = asObj(rateResp.json());
      if (rate != null) {
        const limit = optNum(rate, 'limit');
        const remaining = optNum(rate, 'remaining');
        if (limit != null && limit >= 0) {
          rateLimit = limit;
          rateRemaining = remaining;
          secondary = remaining == null ? null :
            makeWindow(limit > 0 ? Math.max(0, Math.min(100, ((limit - remaining) / limit) * 100)) : 0,
              unixToMs(num(rate, 'reset')), true);
        }
      }
    }

    const snap = UsageSnapshot.success(primary, secondary, null);
    snap.primaryLabel = 'Billing';
    snap.secondaryLabel = 'Rate limit';
    const rows: ProviderDetailRow[] = [];
    rows.push({
      label: 'Billing remaining',
      value: billingRemaining == null ? '不可用' : billingRemaining.toFixed(2),
      secondary: billingRemaining == null ? `limit ${billingLimit.toFixed(2)}` : `of ${billingLimit.toFixed(2)}`,
    });
    if (onDemandBalance != null) {
      rows.push({ label: 'On-demand balance', value: onDemandBalance.toFixed(2) });
    }
    rows.push({
      label: 'Rate-limit remaining',
      value: rateRemaining == null ? '不可用' : rateRemaining.toFixed(2),
      secondary: rateRemaining == null ? `limit ${rateLimit.toFixed(2)}` : `of ${rateLimit.toFixed(2)}`,
    });
    rows.push({ label: 'Billing type', value: billingType });
    if (scope.length > 0) {
      rows.push({ label: 'Scope', value: scope.substring(0, 120) });
    }
    const section: ProviderDetailSection = { title: 'v0 API', rows: rows };
    snap.details = [section];
    snap.identity = { accountEmail: '', accountOrganization: '', loginMethod: 'API key' };
    return snap;
  }
}

// ---------------- Amp ----------------

/** Amp 内部 RPC 请求体（与 Swift 的 method/params 形态一致） */
class AmpRpcParams {
}

class AmpRpcRequest {
  method: string = 'userDisplayBalanceInfo';
  params: AmpRpcParams = new AmpRpcParams();
}

/** Amp displayText 解析结果 */
class AmpParsed {
  freeQuota: number = -1;
  freeUsed: number = 0;
  hourlyReplenishment: number = 0;
  freeResetDaily: boolean = false;
  individualCredits: number = -1;
  accountEmail: string = '';
  accountOrganization: string = '';
  plan: string = '';
  agentRemaining: number = -1;
  agentLimit: number = -1;
  otherUsedPercent: number = -1;
  orbUsedPercent: number = -1;
  /** Orb 剩余小时（对照 Swift SubscriptionUsage.orbHoursRemaining） */
  orbHoursRemaining: number = -1;
  resetsAt: number = 0;
  resetDescription: string = '';
  workspaceNames: string[] = [];
  workspaceRemaining: number[] = [];
}

class AmpProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'amp',
    title: 'Amp',
    authKind: AuthKind.API_KEY,
    accentColor: '#DC2626',
    authHint: '粘贴 Amp access token（ampcode.com 设置页的 AMP_API_KEY）',
    authUrl: 'https://ampcode.com/settings',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const token = setting.credential.trim();
    if (token.length === 0) {
      return UsageSnapshot.failure('未配置 Amp access token');
    }
    const resp = await Http.post(
      'https://ampcode.com/api/internal?userDisplayBalanceInfo',
      {
        'authorization': `Bearer ${token}`,
        'accept': 'application/json',
        'content-type': 'application/json',
      },
      JSON.stringify(new AmpRpcRequest())
    );
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    const root = asObj(resp.json());
    if (root == null) {
      return UsageSnapshot.failure('Amp 响应解析失败');
    }
    if (!bool(root, 'ok')) {
      const err = asObj(root['error']);
      const code = err != null ? str(err, 'code') : '';
      if (code === 'auth-required') {
        return UsageSnapshot.failure('Amp access token 无效或已过期');
      }
      const message = err != null ? str(err, 'message') : '';
      return UsageSnapshot.failure(message.length > 0 ? message : 'Amp 查询失败');
    }
    const result = asObj(root['result']);
    const displayText = result != null ? str(result, 'displayText') : '';
    if (displayText.length === 0) {
      return UsageSnapshot.failure('Amp 响应缺少用量文本');
    }
    return AmpProvider.build(displayText);
  }

  /** 对照 Swift AmpUsageParser.parse(displayText:) */
  private static build(raw: string): UsageSnapshot {
    const text = raw.replace(/\u001b\[[0-9;]*m/g, '').replace(/\*\*/g, '');
    const p = new AmpParsed();

    p.accountEmail = group(text, '^\\s*Signed in as\\s+([^\\s(]+)(?:\\s+\\(([^\\r\\n)]+)\\))?\\s*$', 1);
    p.accountOrganization = group(text, '^\\s*Signed in as\\s+([^\\s(]+)(?:\\s+\\(([^\\r\\n)]+)\\))?\\s*$', 2);

    const AMT = '([0-9][0-9,]*(?:\\.[0-9]+)?)';
    // Amp Free: $X / $Y remaining (replenishes +$Z/hour)
    const freePattern = '^\\s*Amp Free:\\s*\\$?' + AMT + '\\s*/\\s*\\$?' + AMT +
      '\\s+remaining(?:\\s*\\(replenishes\\s*\\+\\$?' + AMT + '\\s*/\\s*hour\\))?';
    const freeRemaining = amount(group(text, freePattern, 1));
    const freeQuota = amount(group(text, freePattern, 2));
    let hourlyReplenishment = 0;
    if (freeRemaining != null && freeQuota != null) {
      hourlyReplenishment = amount(group(text, freePattern, 3)) ?? 0;
      p.hourlyReplenishment = hourlyReplenishment;
      p.freeQuota = freeQuota;
      p.freeUsed = Math.max(0, freeQuota - freeRemaining);
    } else {
      // Amp Free: X% remaining (today) (resets daily)
      const pctPattern = '^\\s*Amp Free:\\s*' + AMT + '\\s*%\\s+remaining(?:\\s+today)?(?:\\s*(\\(resets\\s+daily\\)))?';
      const pct = amount(group(text, pctPattern, 1));
      if (pct != null) {
        const clamped = Math.min(100, Math.max(0, pct));
        p.freeQuota = 100;
        p.freeUsed = 100 - clamped;
        p.freeResetDaily = group(text, pctPattern, 2).length > 0;
      }
    }

    const credits = amount(group(text, '^\\s*Individual credits:\\s*\\$?' + AMT + '\\s+remaining', 1));
    if (credits != null) {
      p.individualCredits = credits;
    }

    const wsPattern = '^\\s*Workspace\\s+(.+?):\\s*\\$?' + AMT + '\\s+remaining';
    const wsRe = new RegExp(wsPattern, 'gim');
    let wsMatch = wsRe.exec(text);
    while (wsMatch != null) {
      const name = wsMatch[1].trim();
      const remaining = amount(wsMatch[2]);
      if (name.length > 0 && remaining != null) {
        p.workspaceNames.push(name);
        p.workspaceRemaining.push(remaining);
      }
      wsMatch = wsRe.exec(text);
    }

    // Subscription（Tier 形态：agent dollars 权威）
    const suffix = '\\s*' + AMT + '\\s*%\\s+other\\s+usage\\s+and\\s+' + AMT +
      '\\s*%\\s+orb\\s+usage\\s+remaining\\s*-\\s*resets\\s+upon\\s+renewal\\s+in\\s+' +
      '([0-9][0-9,]*)\\s+(days?|months?)(?:\\s+-\\s+https?://\\S+)?\\s*$';
    const tierPattern = '^\\s*Amp\\s+([^\\r\\n]+?)\\s+Tier:\\s*agent\\s+usage\\s+\\$' + AMT +
      '\\s+of\\s+\\$' + AMT + '\\s+remaining\\b([^\\r\\n]*?)resets\\s+upon\\s+renewal\\s+in\\s+' +
      '([0-9][0-9,]*)\\s+(days?|months?)\\b';
    const tierPlan = group(text, tierPattern, 1);
    const tierRemaining = amount(group(text, tierPattern, 2));
    const tierLimit = amount(group(text, tierPattern, 3));
    if (tierPlan.length > 0 && tierRemaining != null && tierLimit != null && tierLimit > 0) {
      const unit = group(text, tierPattern, 5);
      const renewalText = group(text, tierPattern, 4).replace(/,/g, '');
      const renewal = parseInt(renewalText, 10);
      p.plan = tierPlan;
      p.agentRemaining = tierRemaining;
      p.agentLimit = tierLimit;
      p.otherUsedPercent = Math.min(100, Math.max(0, ((tierLimit - tierRemaining) / tierLimit) * 100));
      const orbPattern = '\\borb\\s+usage\\s+' + AMT + 'h\\s+of\\s+' + AMT + 'h\\s+a1\\.small\\s+orb\\s+hours\\s+remaining\\b';
      const orbRemaining = amount(group(text, orbPattern, 1));
      const orbLimit = amount(group(text, orbPattern, 2));
      if (orbRemaining != null && orbLimit != null && orbLimit > 0) {
        p.orbUsedPercent = Math.min(100, Math.max(0, ((orbLimit - orbRemaining) / orbLimit) * 100));
        p.orbHoursRemaining = orbRemaining;
      }
      const base = Date.now();
      const d = new Date(base);
      if (unit.toLowerCase().startsWith('month')) {
        d.setMonth(d.getMonth() + (isNaN(renewal) ? 1 : renewal));
      } else {
        d.setDate(d.getDate() + (isNaN(renewal) ? 1 : renewal));
      }
      p.resetsAt = d.getTime();
      p.resetDescription = `renews in ${renewalText} ${unit.toLowerCase()}`;
    } else {
      // 旧版 Subscription 文本（百分比形态）
      const subPatterns: string[] = [
        '^\\s*Subscription\\s+(.+?):' + suffix,
        '^\\s*Amp\\s+(.+?)\\s+Subscription:' + suffix,
      ];
      for (let i = 0; i < subPatterns.length; i++) {
        const plan = group(text, subPatterns[i], 1);
        if (plan.length === 0) {
          continue;
        }
        const otherRemaining = amount(group(text, subPatterns[i], 2));
        const orbRemaining = amount(group(text, subPatterns[i], 3));
        const renewalText = group(text, subPatterns[i], 4).replace(/,/g, '');
        const unit = group(text, subPatterns[i], 5);
        if (otherRemaining == null || orbRemaining == null || renewalText.length === 0 || unit.length === 0) {
          continue;
        }
        const renewal = parseInt(renewalText, 10);
        p.plan = plan;
        p.otherUsedPercent = 100 - Math.min(100, Math.max(0, otherRemaining));
        p.orbUsedPercent = 100 - Math.min(100, Math.max(0, orbRemaining));
        const d = new Date(Date.now());
        if (unit.toLowerCase().startsWith('month')) {
          d.setMonth(d.getMonth() + (isNaN(renewal) ? 1 : renewal));
        } else {
          d.setDate(d.getDate() + (isNaN(renewal) ? 1 : renewal));
        }
        p.resetsAt = d.getTime();
        p.resetDescription = `renews in ${renewalText} ${unit.toLowerCase()}`;
        break;
      }
    }

    if (p.freeQuota < 0 && p.plan.length === 0 && p.individualCredits < 0 && p.workspaceNames.length === 0) {
      return UsageSnapshot.failure('无法解析 Amp 用量数据');
    }

    // 免费额度窗口
    let freeWindow: RateWindow | null = null;
    if (p.freeQuota > 0) {
      const percent = Math.min(100, (p.freeUsed / p.freeQuota) * 100);
      let resetsAt = 0;
      if (p.freeResetDaily) {
        resetsAt = AmpProvider.nextFreeTierReset(new Date());
      } else if (p.hourlyReplenishment > 0) {
        // 按补充速率推算回满时间（对应 Swift 的 used / hourlyReplenishment * 3600）
        resetsAt = Date.now() + Math.max(0, (p.freeUsed / p.hourlyReplenishment) * 3600 * 1000);
      }
      freeWindow = makeWindow(percent, resetsAt, true);
    }

    let primary: RateWindow | null = null;
    let secondary: RateWindow | null = null;
    if (p.plan.length > 0 && p.otherUsedPercent >= 0) {
      primary = makeWindow(p.otherUsedPercent, p.resetsAt, true);
      if (p.orbUsedPercent >= 0) {
        secondary = makeWindow(p.orbUsedPercent, p.resetsAt, true);
      }
    } else {
      primary = freeWindow;
      freeWindow = null;
    }

    const snap = UsageSnapshot.success(primary, secondary, null);
    snap.primaryLabel = p.agentRemaining >= 0 ? 'Agent usage' : (secondary != null ? 'Other usage' : 'Amp Free');
    snap.secondaryLabel = 'Orb usage';
    if (freeWindow != null) {
      const extra: NamedRateWindow = { id: 'amp-free', title: 'Amp Free', window: freeWindow };
      snap.extraRateWindows = [extra];
    }

    const sections: ProviderDetailSection[] = [];
    const allowanceRows: ProviderDetailRow[] = [];
    if (p.agentRemaining >= 0) {
      allowanceRows.push({ label: 'Agent', value: usd(p.agentRemaining) });
    }
    // Orb 小时（对照 Swift：不足 1 小时显示 "< 1h"，否则取整）
    if (p.orbHoursRemaining >= 0) {
      const hours = p.orbHoursRemaining > 0 && p.orbHoursRemaining < 1
        ? '< 1h'
        : `${Math.floor(p.orbHoursRemaining)}h`;
      allowanceRows.push({ label: 'Orb', value: hours, secondary: 'a1.small-equivalent hours' });
    }
    if (allowanceRows.length > 0) {
      sections.push({ title: 'Monthly allowances', rows: allowanceRows });
    }
    const creditRows: ProviderDetailRow[] = [];
    if (p.individualCredits >= 0) {
      creditRows.push({
        label: 'Individual',
        value: usd(p.individualCredits),
        secondary: 'For agent and orb usage',
      });
    }
    for (let i = 0; i < p.workspaceNames.length; i++) {
      creditRows.push({ label: `Workspace ${p.workspaceNames[i]}`, value: usd(p.workspaceRemaining[i]) });
    }
    if (creditRows.length > 0) {
      sections.push({ title: 'Credits', rows: creditRows });
    }
    snap.details = sections;
    snap.identity = {
      accountEmail: p.accountEmail,
      accountOrganization: p.accountOrganization,
      loginMethod: p.plan.length > 0 ? p.plan : (primary == null ? 'Amp' : 'Amp Free'),
    };
    return snap;
  }

  /** Amp Free「resets daily」：下一个美东 20:00（DST 近似：3-11 月 UTC-4，其余 UTC-5） */
  private static nextFreeTierReset(now: Date): number {
    const month = now.getUTCMonth() + 1;
    const offsetHours = month >= 3 && month <= 11 ? 4 : 5;
    const eastern = new Date(now.getTime() - offsetHours * 3600 * 1000);
    const target = new Date(eastern.getTime());
    target.setHours(20, 0, 0, 0);
    if (target.getTime() <= eastern.getTime()) {
      target.setDate(target.getDate() + 1);
    }
    return target.getTime() + offsetHours * 3600 * 1000;
  }
}

// ---------------- Azure OpenAI ----------------

/** 校验用 chat 消息体 */
class AzureChatMessage {
  role: string;
  content: string;

  constructor(role: string, content: string) {
    this.role = role;
    this.content = content;
  }
}

/** v1 新版接口请求体（model + max_completion_tokens） */
class AzureV1ChatBody {
  model: string;
  messages: AzureChatMessage[];
  max_completion_tokens: number;

  constructor(model: string, cap: number) {
    this.model = model;
    this.messages = [new AzureChatMessage('user', 'ping')];
    this.max_completion_tokens = cap;
  }
}

/** 旧版 deployments 接口请求体（max_tokens） */
class AzureLegacyChatBody {
  messages: AzureChatMessage[];
  max_tokens: number;

  constructor(maxTokens: number) {
    this.messages = [new AzureChatMessage('user', 'ping')];
    this.max_tokens = maxTokens;
  }
}

class AzureOpenAIProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'azure-openai',
    title: 'Azure OpenAI',
    authKind: AuthKind.API_KEY,
    accentColor: '#0078D4',
    authHint: '粘贴 Azure OpenAI API Key；Endpoint / Deployment 填在下方输入框',
    authUrl: 'https://portal.azure.com',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const apiKey = setting.credential.trim();
    const endpointRaw = extraValue(setting.extraConfig, 'endpoint').trim();
    const deployment = extraValue(setting.extraConfig, 'deployment').trim();
    let apiVersion = extraValue(setting.extraConfig, 'apiVersion').trim();
    if (apiKey.length === 0) {
      return UsageSnapshot.failure('未配置 Azure OpenAI API Key');
    }
    if (endpointRaw.length === 0) {
      return UsageSnapshot.failure('未配置 Azure 端点（Endpoint）');
    }
    if (deployment.length === 0) {
      return UsageSnapshot.failure('未配置 Deployment 名称');
    }
    if (!endpointRaw.startsWith('https://')) {
      return UsageSnapshot.failure('Azure 端点必须是 HTTPS 地址');
    }
    if (apiVersion.length === 0) {
      apiVersion = '2024-10-21';
    }
    const endpoint = endpointRaw.replace(/\/+$/, '');
    const url = AzureOpenAIProvider.completionsUrl(endpoint, deployment, apiVersion);
    const body = apiVersion.toLowerCase() === 'v1'
      ? JSON.stringify(new AzureV1ChatBody(deployment, 64))
      : JSON.stringify(new AzureLegacyChatBody(1));

    const resp = await Http.post(url, {
      'api-key': apiKey,
      'accept': 'application/json',
      'content-type': 'application/json',
    }, body);
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    const root = asObj(resp.json());
    const model = root != null ? str(root, 'model') : '';
    const host = AzureOpenAIProvider.hostOf(endpoint);
    const detail = model.length > 0 ? `Deployment: ${deployment} · Model: ${model}` : `Deployment: ${deployment}`;

    const snap = UsageSnapshot.success(makeWindow(0, 0, true), null, null);
    snap.primaryLabel = 'Deployment';
    const rows: ProviderDetailRow[] = [
      { label: 'Deployment', value: deployment },
      { label: 'Endpoint', value: host },
      { label: 'API 版本', value: apiVersion },
    ];
    if (model.length > 0) {
      rows.push({ label: 'Model', value: model });
    }
    rows.push({ label: '校验请求', value: detail });
    snap.details = [{ title: 'Azure OpenAI', rows: rows }];
    snap.identity = { accountEmail: '', accountOrganization: host, loginMethod: `Deployment: ${deployment}` };
    return snap;
  }

  /** v1 走 /openai/v1/chat/completions；否则 /openai/deployments/{name}/chat/completions?api-version= */
  private static completionsUrl(endpoint: string, deployment: string, apiVersion: string): string {
    if (apiVersion.toLowerCase() === 'v1') {
      return `${endpoint}/openai/v1/chat/completions`;
    }
    return `${endpoint}/openai/deployments/${encodeURIComponent(deployment)}` +
      `/chat/completions?api-version=${encodeURIComponent(apiVersion)}`;
  }

  private static hostOf(endpoint: string): string {
    const stripped = endpoint.replace(/^https?:\/\//, '');
    const slash = stripped.indexOf('/');
    return slash >= 0 ? stripped.substring(0, slash) : stripped;
  }
}

// ---------------- Ollama ----------------

class OllamaProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'ollama',
    title: 'Ollama',
    authKind: AuthKind.API_KEY,
    accentColor: '#111111',
    authHint: '粘贴 ollama.com 的 API Key（ollama.com/settings/keys）',
    authUrl: 'https://ollama.com/settings/keys',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const key = setting.credential.trim();
    if (key.length === 0) {
      return UsageSnapshot.failure('未配置 Ollama API Key');
    }
    const headers: Record<string, string> = {
      'authorization': `Bearer ${key}`,
      'accept': 'application/json',
      'user-agent': 'CodexBar/1.0',
    };
    // 校验 Key：web_search 空查询（200/400 视为有效）
    const probe = await Http.post('https://ollama.com/api/web_search', {
      'authorization': `Bearer ${key}`,
      'accept': 'application/json',
      'content-type': 'application/json',
      'user-agent': 'CodexBar/1.0',
    }, '{"query":""}');
    if (probe.code === 401 || probe.code === 403) {
      return UsageSnapshot.failure('Ollama API Key 无效或已撤销');
    }
    if (!probe.ok && probe.code !== 400) {
      return UsageSnapshot.failure(probe.errorText());
    }

    const resp = await Http.get('https://ollama.com/api/tags', headers);
    if (resp.code === 401 || resp.code === 403) {
      return UsageSnapshot.failure('Ollama API Key 无效或已撤销');
    }
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    const root = asObj(resp.json());
    const models = root != null ? root['models'] : null;
    let count = 0;
    if (models != null && models instanceof Array) {
      count = (models as Json[]).length;
    }
    const snap = UsageSnapshot.success(null, null, null);
    snap.primaryLabel = 'Models';
    snap.details = [{ title: 'Ollama Cloud', rows: [{ label: '模型数量', value: `${count}` }] }];
    snap.identity = { accountEmail: '', accountOrganization: '', loginMethod: 'API key' };
    return snap;
  }
}

// ---------------- Copilot ----------------

/**
 * 席位额度解析（对照 CopilotCreditEntitlementParser.parse）：
 * 必须是完整数字（与 Swift `Double(text)` 一致，"12abc" 不接受），且有限、大于 0，否则视为未配置。
 */
export function copilotSeatEntitlement(raw: string): number | undefined {
  const text = raw.trim();
  if (text.length === 0 || !/^[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?$/.test(text)) {
    return undefined;
  }
  const value = parseFloat(text);
  if (isNaN(value) || !isFinite(value) || value <= 0) {
    return undefined;
  }
  return value;
}

/**
 * Credits 分组的行（对照 CopilotUsageFetcher.makeCreditDetails）：
 * GitHub 不公开包含额度上限，分母由用户在设置里填；填了就把比例作为数据带上（行文案仍是原始数字），
 * 未填则只展示用量数字，不带进度条。
 */
export function copilotCreditRows(
  creditsUsed: number,
  seatEntitlement: number | undefined,
  resetsAt: number
): ProviderDetailRow[] {
  const usedText = Format.creditsNumber(creditsUsed);
  const row: ProviderDetailRow = { label: 'Credits used', value: usedText };
  if (seatEntitlement != null) {
    row.value = `${usedText} / ${Format.creditsNumber(seatEntitlement)}`;
    const progress = rowProgress(creditsUsed, seatEntitlement);
    if (progress != null) {
      row.progress = progress;
    }
  }
  if (resetsAt > 0) {
    row.secondary = Format.dateTime(resetsAt);
  }
  return [row];
}

/** Copilot 配额快照（对照 Swift CopilotUsageResponse.QuotaSnapshot） */
class CopilotQuota {
  percentRemaining: number = 0;
  hasPercent: boolean = false;
  unlimited: boolean = false;
  creditsUsed: number = -1;
  entitlementDecoded: boolean = false;
  entitlement: number = 0;
  remainingDecoded: boolean = false;
  remaining: number = 0;

  /** 无用量信号（token 计费 / Business 席位占位） */
  isPlaceholder(): boolean {
    if (this.unlimited) {
      return false;
    }
    if (this.entitlement === 0 && this.remaining === 0 && this.percentRemaining === 0 && !this.hasPercent) {
      return true;
    }
    return this.entitlementDecoded && this.remainingDecoded && this.entitlement === 0 && this.remaining === 0;
  }

  usedPercent(): number {
    return Math.max(0, 100 - this.percentRemaining);
  }
}

class CopilotProvider implements UsageProvider {
  descriptor: ProviderDescriptor = {
    id: 'copilot',
    title: 'Copilot',
    authKind: AuthKind.API_KEY,
    accentColor: '#A855F7',
    authHint: '粘贴 GitHub Personal Access Token（需 copilot 读权限）',
    authUrl: 'https://github.com/settings/tokens',
  };

  async fetch(setting: ProviderSetting): Promise<UsageSnapshot> {
    const token = setting.credential.trim();
    if (token.length === 0) {
      return UsageSnapshot.failure('未配置 GitHub Token');
    }
    const host = CopilotProvider.apiHost(extraValue(setting.extraConfig, 'enterpriseHost'));
    const resp = await Http.get(`https://${host}/copilot_internal/user`, {
      'authorization': `token ${token}`,
      'accept': 'application/json',
      'editor-version': 'vscode/1.96.2',
      'editor-plugin-version': 'copilot-chat/0.26.7',
      'user-agent': 'GitHubCopilotChat/0.26.7',
      'x-github-api-version': '2025-04-01',
    });
    if (resp.code === 401 || resp.code === 403) {
      return UsageSnapshot.failure('GitHub Token 无效或缺少 Copilot 权限');
    }
    if (!resp.ok) {
      return UsageSnapshot.failure(resp.errorText());
    }
    const root = asObj(resp.json());
    if (root == null) {
      return UsageSnapshot.failure('Copilot 响应解析失败');
    }

    const snapshots = asObj(root['quota_snapshots']);
    const premium = CopilotProvider.quotaOf(snapshots, 'premium_interactions');
    const chat = CopilotProvider.quotaOf(snapshots, 'chat');
    const resetsAt = parseDateText(str(root, 'quota_reset_date'));
    const tokenBased = bool(root, 'token_based_billing');
    const unlimited = (premium != null && premium.unlimited) || (chat != null && chat.unlimited);
    let creditsUsed = -1;
    if (premium != null && premium.creditsUsed >= 0) {
      creditsUsed = premium.creditsUsed;
    } else if (chat != null && chat.creditsUsed >= 0) {
      creditsUsed = chat.creditsUsed;
    }

    const premiumWindow = CopilotProvider.windowOf(premium, resetsAt);
    const chatWindow = CopilotProvider.windowOf(chat, resetsAt);
    let primary: RateWindow | null = null;
    let secondary: RateWindow | null = null;
    if (premiumWindow != null) {
      primary = premiumWindow;
      secondary = chatWindow;
    } else if (chatWindow != null) {
      secondary = chatWindow;
    } else if (!tokenBased && !unlimited) {
      return UsageSnapshot.failure('Copilot 配额数据不可用');
    }

    const snap = UsageSnapshot.success(primary, secondary, null);
    snap.primaryLabel = 'Premium';
    snap.secondaryLabel = 'Chat';
    // 用户可填的席位额度：GitHub 不提供包含额度上限（对照 macOS 的 seat credit entitlement 输入框）
    const entitlement = copilotSeatEntitlement(extraValue(setting.extraConfig, 'seatEntitlement'));
    if (creditsUsed >= 0 && (tokenBased || unlimited || creditsUsed > 0 || entitlement != null)) {
      snap.details = [{
        title: 'Credits',
        rows: copilotCreditRows(creditsUsed, entitlement, resetsAt),
      }];
    }
    const plan = str(root, 'copilot_plan', 'unknown');
    snap.identity = {
      accountEmail: '',
      accountOrganization: '',
      loginMethod: plan.length > 0 ? plan.charAt(0).toUpperCase() + plan.substring(1) : 'unknown',
    };
    return snap;
  }

  private static apiHost(enterpriseHost: string): string {
    const host = enterpriseHost.trim().replace(/^https?:\/\//, '').replace(/\/+$/, '');
    if (host.length === 0 || host === 'github.com') {
      return 'api.github.com';
    }
    return host.startsWith('api.') ? host : `api.${host}`;
  }

  private static quotaOf(snapshots: Record<string, Json> | null, key: string): CopilotQuota | null {
    if (snapshots == null) {
      return null;
    }
    const raw = asObj(snapshots[key]);
    if (raw == null) {
      return null;
    }
    const q = new CopilotQuota();
    const entitlement = optNum(raw, 'entitlement');
    const remaining = optNum(raw, 'remaining');
    q.entitlementDecoded = entitlement != null;
    q.remainingDecoded = remaining != null;
    q.entitlement = entitlement == null ? 0 : entitlement;
    q.remaining = remaining == null ? 0 : remaining;
    const credits = optNum(raw, 'credits_used');
    q.creditsUsed = credits == null ? -1 : credits;
    q.unlimited = bool(raw, 'unlimited');
    const percent = optNum(raw, 'percent_remaining');
    if (q.unlimited) {
      q.percentRemaining = 100;
      q.hasPercent = true;
    } else if (percent != null) {
      q.percentRemaining = percent;
      q.hasPercent = true;
    } else if (entitlement != null && entitlement > 0 && remaining != null) {
      q.percentRemaining = (remaining / entitlement) * 100;
      q.hasPercent = true;
    }
    return q;
  }

  private static windowOf(q: CopilotQuota | null, resetsAt: number): RateWindow | null {
    if (q == null || q.unlimited || q.isPlaceholder() || !q.hasPercent) {
      return null;
    }
    return makeWindow(q.usedPercent(), resetsAt, true);
  }
}

// ---------------- 工厂 ----------------

export function createV0Provider(): UsageProvider {
  return new V0Provider();
}

export function createAmpProvider(): UsageProvider {
  return new AmpProvider();
}

export function createAzureOpenAIProvider(): UsageProvider {
  return new AzureOpenAIProvider();
}

export function createOllamaProvider(): UsageProvider {
  return new OllamaProvider();
}

export function createCopilotProvider(): UsageProvider {
  return new CopilotProvider();
}
