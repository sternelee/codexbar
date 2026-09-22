import { describe, it, expect } from '@ohos/hypium';
import { Format } from '../main/ets/common/Format';
import { Theme } from '../main/ets/common/Theme';
import { parseJson, asObj, asArray, str, num, optNum, optStr, Json } from '../main/ets/net/Json';
import { makeWindow, UsageSnapshot, RateWindow, ProviderDescriptor, ProviderDetailSection, ProviderSetting,
  ProviderState, AuthKind, applyWindowLabels, defaultReminder, extraFields, extraValue,
  isDefaultEnabledProvider, isPrimaryProvider, makeChart, needsSecondCredential, optionalDetailsFor, parseExtra,
  progressPercent, replacedDetailRowsFor, rowProgress, setExtraValue, visibleDetails, windowLabelsFor
} from '../main/ets/model/Models';
import { parseDetailParam, DetailRouteParam } from '../main/ets/common/Nav';
import { chutesWindow } from '../main/ets/providers/MoreProviders';
import { deepseekCostText, deepseekCountText, deepseekDetailSections, deepseekMonthlyUsage,
  deepseekPlatformUsage } from '../main/ets/providers/ApiKeyProviders';
import { copilotCreditRows, copilotSeatEntitlement } from '../main/ets/providers/ApiKeyProviders2';
import {
  minimaxAggregate,
  minimaxBillingPage,
  minimaxCash,
  minimaxHasRecordBeforeWindow,
  MiniMaxBillingRecord,
  t3chatFindCustomerData,
  zaiLimitWindow
} from '../main/ets/providers/MoreProviders2';
import {
  zoomMateCreditStatus,
  zoomMateDailyBreakdown,
  zoomMateHistoryRecords,
  zoomMateHistoryRows,
  zoomMatePaceRow,
  zoomMatePaceText,
  zoomMateResetMs,
  zoomMateStatusWindow,
} from '../main/ets/providers/MoreProviders4';
import {
  claudeExtraUsageCost,
  claudeOverageSpendLimitCost,
  claudePrepaidBalanceCost,
} from '../main/ets/providers/ClaudeProvider';
import {
  clawRouterBaseURL,
  clawRouterIsApiKey,
  clawRouterUsageUrl,
  syntheticQuotaWindow,
} from '../main/ets/providers/MoreProviders3';
import { evaluateReminder, ReminderHit } from '../main/ets/store/Reminders';
import { Settings } from '../main/ets/store/Settings';
import {
  addAccountToList,
  nextAccountName,
  parseAccounts,
  pickAccount,
  removeAccountFromList,
  renameAccountInList,
} from '../main/ets/store/Settings';
import { buildWidgetItems } from '../main/ets/store/WidgetData';
import { HistoryDay, ProviderChartPoint } from '../main/ets/model/Models';
import { ChartPoint } from '../main/ets/store/UsageHistory';
import {
  costDeltas,
  dateKeyMinus,
  dayLabel,
  localDateKey,
  scaleFraction,
  scaleMax,
  sumLast,
  usageDeltas,
  yAxisTicks,
} from '../main/ets/store/UsageHistory';
import {
  base64UrlDecode,
  base64UrlEncode,
  hmacSha256Hex,
  sha256Base64Url,
  sha256Bytes,
  sha256Hex,
  utf8Bytes,
} from '../main/ets/common/Crypto';
import {
  signVolcRequest,
  volcCanonicalQuery,
  volcCanonicalUri,
  volcDateStamp,
  volcHostOf,
  volcPercentEncode,
  volcTimestamp,
  VolcCredentials,
} from '../main/ets/common/VolcSign';
import {
  codexAuthorizeUrl,
  decodeJwtPayload,
  extractChatgptAccountId,
  extractSessionKey,
  makePkce,
  parseCallbackUrl,
} from '../main/ets/common/OAuth';
import { AwsCredentials, signAwsRequest } from '../main/ets/common/AwsSign';
import {
  bedrockClaudeActivity,
  bedrockCloudWatchEndpoint,
  bedrockDataUnavailable,
  bedrockMonthEnd,
  bedrockMonthRange,
  bedrockNextPageToken,
  bedrockSnapshot,
  bedrockTotalCost,
} from '../main/ets/providers/BedrockProvider';
import {
  DoubaoPlanMeta,
  DoubaoQuota,
  doubaoCodingPlanMeta,
  doubaoEpochMs,
  doubaoParseProbe,
  doubaoParseResetHeader,
  doubaoQuotasFromAgentPlan,
  doubaoQuotasFromCodingPlan,
  doubaoSignedSnapshot,
} from '../main/ets/providers/DoubaoProvider';

/** 构造只带一个主窗口的服务商状态（提醒测试用） */
function stateWith(primary: RateWindow, title: string = '演示', enabled: boolean = true): ProviderState {
  const d: ProviderDescriptor = {
    id: 'demo', title: title, authKind: AuthKind.DEMO,
    accentColor: '#16D3B4', authHint: '', authUrl: ''
  };
  const s = new ProviderState(d, { enabled: enabled, credential: '', credential2: '', extraConfig: '' });
  s.snapshot = UsageSnapshot.success(primary, null, null);
  return s;
}

export default function logicUnitTest() {
  describe('logicUnitTest', () => {
    it('Format_percent', 0, () => {
      expect(Format.percent(85)).assertEqual('85%');
      expect(Format.percent(85.44)).assertEqual('85.4%');
      expect(Format.percent(0)).assertEqual('0%');
      expect(Format.percent(100)).assertEqual('100%');
    });

    it('Format_money', 0, () => {
      expect(Format.money(12.5, 'USD')).assertEqual('$12.50');
      expect(Format.money(110, 'CNY')).assertEqual('¥110.00');
      expect(Format.money(0, 'USD')).assertEqual('$0.00');
    });

    it('Format_countdown', 0, () => {
      expect(Format.countdown(-1)).assertEqual('已重置');
      expect(Format.countdown(0)).assertEqual('已重置');
      expect(Format.countdown(45 * 1000)).assertEqual('45秒');
      expect(Format.countdown(45 * 60 * 1000)).assertEqual('45分钟');
      expect(Format.countdown((3 * 3600 + 15 * 60) * 1000)).assertEqual('3小时15分');
      expect(Format.countdown((4 * 86400 + 7 * 3600) * 1000)).assertEqual('4天7小时');
    });

    it('Format_countdown_cap', 0, () => {
      // 超过 99 天：按绝对时间显示，避免"20713302天"这类异常输出
      const capped = Format.countdown(20713302 * 86400 * 1000 + 15 * 3600 * 1000);
      expect(capped.indexOf('重置于') >= 0).assertTrue();
      // 99 天内：保持相对时长
      expect(Format.countdown(30 * 86400 * 1000)).assertEqual('30天');
      // resetIn 统一文案：封顶时不叠"后重置"
      expect(Format.resetIn(30 * 86400 * 1000)).assertEqual('30天后重置');
      expect(Format.resetIn(45 * 60 * 1000)).assertEqual('45分钟后重置');
      expect(Format.resetIn(-1)).assertEqual('已重置');
      expect(Format.resetIn(20713302 * 86400 * 1000).indexOf('后重置') < 0).assertTrue();
    });

    it('Format_ago_compact', 0, () => {
      expect(Format.ago(0)).assertEqual('从未');
      expect(Format.ago(Date.now() - 30 * 1000)).assertEqual('刚刚');
      expect(Format.compact(999)).assertEqual('999');
      expect(Format.compact(12345)).assertEqual('12.3K');
      expect(Format.compact(1_500_000)).assertEqual('1.50M');
    });

    it('Theme_barColor_thresholds', 0, () => {
      expect(Theme.barColor(10, true)).assertEqual(Theme.accent);
      expect(Theme.barColor(75, true)).assertEqual(Theme.warn);
      expect(Theme.barColor(95, true)).assertEqual(Theme.danger);
      expect(Theme.barColor(95, false)).assertEqual('#3A3A44');
    });

    it('Json_helpers', 0, () => {
      const parsed = parseJson('{"name":"DeepSeek","total":"110.00","rate":42,"arr":[1,2],"nested":{"a":1}}');
      const o = asObj(parsed);
      expect(o != null).assertTrue();
      if (o != null) {
        expect(str(o, 'name')).assertEqual('DeepSeek');
        expect(str(o, 'missing', 'dflt')).assertEqual('dflt');
        expect(num(o, 'rate')).assertEqual(42);
        expect(num(o, 'total')).assertEqual(110);
        expect(optNum(o, 'missing')).assertEqual(null);
        const nested = asObj(o['nested']);
        expect(nested != null).assertTrue();
        const arr = asArray(o['arr']);
        expect(arr != null).assertTrue();
        if (arr != null) {
          expect(arr.length).assertEqual(2);
        }
      }
      expect(asObj(parseJson('bad json'))).assertEqual(null);
      expect(asObj(parseJson('[1,2]'))).assertEqual(null);
    });

    it('UsageSnapshot_lifecycle', 0, () => {
      const w: RateWindow = makeWindow(42, 123456, true);
      expect(w.usedPercent).assertEqual(42);
      expect(w.usageKnown).assertTrue();

      const ok = UsageSnapshot.success(w, null, null);
      expect(ok.ok).assertTrue();
      expect(ok.primary != null).assertTrue();
      expect(ok.error).assertEqual('');

      const fail = UsageSnapshot.failure('凭证无效');
      expect(fail.ok).assertFalse();
      expect(fail.error).assertEqual('凭证无效');
      expect(fail.primary).assertEqual(null);
    });

    it('Nav_parseDetailParam', 0, () => {
      // 类实例形态（鸿蒙原生路由）
      const typed = new DetailRouteParam();
      typed.id = 'claude';
      expect(parseDetailParam(typed)).assertEqual('claude');
      // 普通对象形态（ArkUI-X 跨端序列化后）
      const plain: DetailRouteParam = JSON.parse('{"id":"deepseek"}') as DetailRouteParam;
      expect(parseDetailParam(plain)).assertEqual('deepseek');
      // 异常形态
      expect(parseDetailParam(null)).assertEqual('');
      const empty: DetailRouteParam = JSON.parse('{}') as DetailRouteParam;
      expect(parseDetailParam(empty)).assertEqual('');
    });

    it('Chutes_alias_windows', 0, () => {
      // 滚动窗口：used/limit 推算百分比
      const rolling: Record<string, Object> =
        JSON.parse('{"used": 30, "limit": 100, "reset_at": "2026-09-21T12:00:00Z"}') as Record<string, Object>;
      const w1 = chutesWindow(rolling as Record<string, Object>, '4 小时窗口');
      expect(w1 != null).assertTrue();
      if (w1 != null) {
        expect(w1.usedPercent).assertEqual(30);
        expect(w1.resetsAt > 0).assertTrue();
      }
      // 月度窗口：percent_remaining 反推
      const monthly: Record<string, Object> = JSON.parse('{"percent_remaining": 80}') as Record<string, Object>;
      const w2 = chutesWindow(monthly as Record<string, Object>, '月度窗口');
      expect(w2 != null).assertTrue();
      if (w2 != null) {
        expect(w2.usedPercent).assertEqual(20);
      }
      // 无法得出百分比时返回 null
      const bad: Record<string, Object> = JSON.parse('{"foo": 1}') as Record<string, Object>;
      expect(chutesWindow(bad as Record<string, Object>, 'x')).assertEqual(null);
    });

    it('Zai_limit_window', 0, () => {
      // 5 小时 TIME_LIMIT：百分比 + 重置时间（unix 秒）
      const five: Record<string, Object> = JSON.parse(
        '{"type":"TIME_LIMIT","unit":5,"number":5,"percentage":42,"usage":1000,"remaining":580,"nextResetTime":1758000000}'
      ) as Record<string, Object>;
      const w = zaiLimitWindow(five);
      expect(w != null).assertTrue();
      if (w != null) {
        expect(w.title).assertEqual('5 小时窗口');
        expect(Math.round(w.window.usedPercent)).assertEqual(42);
        expect(w.window.resetsAt).assertEqual(1758000000000);
      }
      // Token 配额：unit=3(小时)、number=8
      const tokens: Record<string, Object> = JSON.parse(
        '{"type":"TOKENS_LIMIT","unit":3,"number":8,"percentage":10}'
      ) as Record<string, Object>;
      const w2 = zaiLimitWindow(tokens);
      expect(w2 != null).assertTrue();
      if (w2 != null) {
        expect(w2.title).assertEqual('Token 配额');
      }
      // 未知类型拒绝
      const bad: Record<string, Object> = JSON.parse('{"type":"OTHER","unit":1,"number":1}') as Record<string, Object>;
      expect(zaiLimitWindow(bad)).assertEqual(null);
    });

    it('Reminder_usage_threshold', 0, () => {
      const cfg = defaultReminder();
      cfg.enabled = true;
      cfg.usageThreshold = 90;
      cfg.resetLeadMinutes = 0;
      const now = 1758000000000;
      // 达到阈值：命中用量提醒
      const s = stateWith(makeWindow(95, now + 3600000, true));
      const hit = evaluateReminder(s, cfg, now);
      expect(hit != null).assertTrue();
      if (hit != null) {
        expect(hit.kind).assertEqual('usage');
        expect(hit.windowId).assertEqual('primary');
        expect(hit.dedupeKey).assertEqual(`u_primary_${now + 3600000}`);
        expect(hit.title.indexOf('演示') >= 0).assertTrue();
        expect(hit.text.indexOf('95%') >= 0).assertTrue();
      }
      // 低于阈值：不提醒
      const s2 = stateWith(makeWindow(89, now + 3600000, true));
      expect(evaluateReminder(s2, cfg, now)).assertEqual(null);
      // 用量未知（usageKnown=false）：不提醒
      const s3 = stateWith(makeWindow(95, now + 3600000, false));
      expect(evaluateReminder(s3, cfg, now)).assertEqual(null);
      // 阈值为 0：关闭用量提醒
      cfg.usageThreshold = 0;
      const s4 = stateWith(makeWindow(100, now + 3600000, true));
      expect(evaluateReminder(s4, cfg, now)).assertEqual(null);
    });

    it('Reminder_reset_lead', 0, () => {
      const cfg = defaultReminder();
      cfg.enabled = true;
      cfg.usageThreshold = 0;
      cfg.resetLeadMinutes = 15;
      const now = 1758000000000;
      // 10 分钟后重置：命中恢复提醒
      const resetsAt = now + 10 * 60000;
      const s = stateWith(makeWindow(20, resetsAt, true));
      const hit = evaluateReminder(s, cfg, now);
      expect(hit != null).assertTrue();
      if (hit != null) {
        expect(hit.kind).assertEqual('reset');
        expect(hit.dedupeKey).assertEqual(`r_primary_${resetsAt}`);
        expect(hit.text.indexOf('10') >= 0).assertTrue();
      }
      // 1 小时后重置：超出提前量，不提醒
      const s2 = stateWith(makeWindow(20, now + 3600000, true));
      expect(evaluateReminder(s2, cfg, now)).assertEqual(null);
      // 重置时间已过：不提醒
      const s3 = stateWith(makeWindow(20, now - 60000, true));
      expect(evaluateReminder(s3, cfg, now)).assertEqual(null);
      // 重置时间未知（0）：不提醒
      const s4 = stateWith(makeWindow(20, 0, true));
      expect(evaluateReminder(s4, cfg, now)).assertEqual(null);
    });

    it('Reminder_reset_priority_and_dedupe', 0, () => {
      // 两个条件同时满足：优先"即将恢复"
      const cfg = defaultReminder();
      cfg.enabled = true;
      cfg.usageThreshold = 90;
      cfg.resetLeadMinutes = 15;
      const now = 1758000000000;
      const s = stateWith(makeWindow(95, now + 10 * 60000, true));
      const hit = evaluateReminder(s, cfg, now);
      expect(hit != null).assertTrue();
      if (hit != null) {
        expect(hit.kind).assertEqual('reset');
      }
      // 窗口周期推进后（重置时间变化），去重键随之变化
      const hit2 = evaluateReminder(stateWith(makeWindow(95, now + 7200000, true)), cfg, now);
      expect(hit2 != null).assertTrue();
      if (hit != null && hit2 != null) {
        expect(hit.dedupeKey === hit2.dedupeKey).assertFalse();
      }
    });

    it('Reminder_config_default', 0, () => {
      // 本地测试无 Preferences 上下文：读取返回默认值，保存静默不崩溃
      const dflt = defaultReminder();
      expect(dflt.enabled).assertFalse();
      expect(dflt.usageThreshold).assertEqual(90);
      expect(dflt.resetLeadMinutes).assertEqual(15);
      Settings.saveReminder('x', { enabled: true, usageThreshold: 80, resetLeadMinutes: 5 });
      const back = Settings.reminder('x');
      expect(back.enabled).assertEqual(dflt.enabled);
      // 损坏的 JSON 同样回退默认
      Settings.saveReminder('y', { enabled: true, usageThreshold: 80, resetLeadMinutes: 5 });
      expect(Settings.reminder('y').usageThreshold).assertEqual(dflt.usageThreshold);
      expect(Settings.reminderFiredKey('x', 'usage')).assertEqual('');
    });

    it('OAuth_sha256_base64url', 0, () => {
      // FIPS 180-4 测试向量
      const abc = sha256Bytes('abc');
      expect(abc.length).assertEqual(32);
      expect(abc[0]).assertEqual(0xba);
      expect(abc[1]).assertEqual(0x78);
      expect(abc[31]).assertEqual(0xad);
      // Base64URL（无填充）
      expect(sha256Base64Url('abc')).assertEqual('ungWv48Bz-pBQUDeXa4iI7ADYaOWF3qctBD_YfIAFa0');
      expect(sha256Base64Url('')).assertEqual('47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU');
      expect(sha256Base64Url('hello world')).assertEqual('uU0nuZNNPgilLlLX2n2r-sSE7-N6U4DukIj3rOLvzek');
      // 编解码回环（ASCII）
      const round = base64UrlDecode(base64UrlEncode([104, 105, 33]));
      expect(round).assertEqual('hi!');
    });

    it('OAuth_parse_callback_and_jwt', 0, () => {
      // 回调解析
      const cb = parseCallbackUrl('http://localhost:1455/auth/callback?code=abc123&state=xyz');
      expect(cb != null).assertTrue();
      if (cb != null) {
        expect(cb.code).assertEqual('abc123');
        expect(cb.state).assertEqual('xyz');
      }
      expect(parseCallbackUrl('http://localhost:1455/auth/callback')).assertEqual(null);
      expect(parseCallbackUrl('')).assertEqual(null);
      const enc = parseCallbackUrl('http://localhost:1455/auth/callback?code=a%2Fb&state=s');
      if (enc != null) {
        expect(enc.code).assertEqual('a/b');
      }

      // JWT payload（根声明）
      const jwt = `header.${'eyJjaGF0Z3B0X2FjY291bnRfaWQiOiJhY2NfMTIzIn0'}.sig`;
      expect(extractChatgptAccountId(jwt)).assertEqual('acc_123');
      // 嵌套 auth 声明
      const jwt2 = `header.${'eyJodHRwczovL2FwaS5vcGVuYWkuY29tL2F1dGgiOnsiY2hhdGdwdF9hY2NvdW50X2lkIjoiYWNjXzQ1NiJ9fQ'}.sig`;
      expect(extractChatgptAccountId(jwt2)).assertEqual('acc_456');
      // 非 JWT
      expect(extractChatgptAccountId('not-a-jwt')).assertEqual('');
      expect(decodeJwtPayload('a.b.c')).assertEqual(null);

      // Claude sessionKey 提取
      expect(extractSessionKey('sessionKey=sk-ant-sid01-abc; other=1')).assertEqual('sk-ant-sid01-abc');
      expect(extractSessionKey('other=1')).assertEqual('');
      expect(extractSessionKey('')).assertEqual('');
    });

    it('OAuth_pkce_and_authorize_url', 0, () => {
      const pkce = makePkce(1758000000000);
      expect(pkce.verifier.length >= 43).assertTrue();
      expect(pkce.verifier.length <= 128).assertTrue();
      expect(pkce.challenge).assertEqual(sha256Base64Url(pkce.verifier));
      expect(pkce.state.length > 0).assertTrue();
      // 不同 seed 生成不同 verifier（随机性）
      const other = makePkce(1758000000001);
      expect(other.verifier === pkce.verifier).assertFalse();

      const url = codexAuthorizeUrl(pkce);
      expect(url.startsWith('https://auth.openai.com/oauth/authorize?')).assertTrue();
      expect(url.indexOf('client_id=app_EMoamEEZ73f0CkXaXp7hrann') >= 0).assertTrue();
      expect(url.indexOf('response_type=code') >= 0).assertTrue();
      expect(url.indexOf('code_challenge_method=S256') >= 0).assertTrue();
      expect(url.indexOf('redirect_uri=http%3A%2F%2Flocalhost%3A1455%2Fauth%2Fcallback') >= 0).assertTrue();
      expect(url.indexOf(`state=${pkce.state}`) >= 0).assertTrue();
    });

    it('Crypto_extra_config_helpers', 0, () => {
      // extraConfig 解析/写入（Azure endpoint、Bedrock region 等额外字段）
      const empty = parseExtra('');
      expect(Object.keys(empty).length).assertEqual(0);
      expect(extraValue('', 'endpoint')).assertEqual('');
      const one = setExtraValue('', 'endpoint', ' https://my-res.openai.azure.com ');
      expect(extraValue(one, 'endpoint')).assertEqual('https://my-res.openai.azure.com');
      const two = setExtraValue(one, 'deployment', 'gpt-4o');
      expect(extraValue(two, 'deployment')).assertEqual('gpt-4o');
      expect(extraValue(two, 'endpoint')).assertEqual('https://my-res.openai.azure.com');
      // 损坏 JSON 回退空对象
      expect(extraValue('{bad json', 'endpoint')).assertEqual('');
      // 字段表
      expect(extraFields('azure-openai').length).assertEqual(3);
      expect(extraFields('bedrock')[0].key).assertEqual('region');
      expect(extraFields('deepseek').length).assertEqual(0);
      expect(needsSecondCredential('bedrock')).assertTrue();
      expect(needsSecondCredential('azure-openai')).assertFalse();
      // DeepSeek 平台会话不由用户手填（对照 macOS requiresManualCookieSource = false），
      // MiniMax 的 Cookie 则对齐 macOS 保留手填框（requiresManualCookieSource = true）
      expect(needsSecondCredential('deepseek')).assertFalse();
      expect(needsSecondCredential('minimax')).assertTrue();
    });

    it('Accounts_parse_roundtrip', 0, () => {
      const json = '[{"aid":"a1","name":"账号 1","credential":"sk-1","credential2":"org1","extraConfig":"{\\"region\\":\\"us-east-1\\"}"},' +
        '{"aid":"a2","name":"账号 2","credential":"sk-2","credential2":"","extraConfig":""}]';
      const list = parseAccounts(json);
      expect(list.length).assertEqual(2);
      expect(list[0].aid).assertEqual('a1');
      expect(list[0].name).assertEqual('账号 1');
      expect(list[0].credential).assertEqual('sk-1');
      expect(list[0].credential2).assertEqual('org1');
      expect(extraValue(list[0].extraConfig, 'region')).assertEqual('us-east-1');
      // 激活查找
      expect(pickAccount(list, 'a2') != null).assertTrue();
      if (pickAccount(list, 'a2') != null) {
        expect(pickAccount(list, 'a2')!.credential).assertEqual('sk-2');
      }
      expect(pickAccount(list, '')).assertEqual(null);
      expect(pickAccount(list, 'missing')).assertEqual(null);
      // 损坏输入
      expect(parseAccounts('').length).assertEqual(0);
      expect(parseAccounts('not json').length).assertEqual(0);
      expect(parseAccounts('[1,2,3]').length).assertEqual(0);
      expect(parseAccounts('[{"name":"缺 aid"}]').length).assertEqual(0);
    });

const EXTRA_REGION_JSON = `{"region":"ap-1"}`;

    it('Accounts_add_dedupe_remove', 0, () => {
      expect(nextAccountName([])).assertEqual('账号 1');
      // 新增
      const r1 = addAccountToList([], 'cred-1', '', '', '', 1000);
      expect(r1.deduped).assertFalse();
      expect(r1.list.length).assertEqual(1);
      expect(r1.account.name).assertEqual('账号 1');
      expect(r1.account.aid).assertEqual('a1000');
      // 同凭证去重：仅刷新辅助字段（refresh token / 额外字段）并复用
      const r2 = addAccountToList(r1.list, 'cred-1', 'org-x', 'rt-1', EXTRA_REGION_JSON, 2000);
      expect(r2.deduped).assertTrue();
      expect(r2.list.length).assertEqual(1);
      expect(r2.account.credential2).assertEqual('org-x');
      expect(r2.account.refreshToken).assertEqual('rt-1');
      expect(extraValue(r2.account.extraConfig, 'region')).assertEqual('ap-1');
      // 不同凭证：新增为 账号 2
      const r3 = addAccountToList(r2.list, 'cred-2', '', '', '', 3000);
      expect(r3.deduped).assertFalse();
      expect(r3.list.length).assertEqual(2);
      expect(r3.account.name).assertEqual('账号 2');
      // 删除激活账号 → 激活转移到第一个剩余
      const rm1 = removeAccountFromList(r3.list, 'a1000', 'a1000');
      expect(rm1.list.length).assertEqual(1);
      expect(rm1.newActive).assertEqual('a3000');
      // 删除非激活账号 → 激活不变
      const rm2 = removeAccountFromList(r3.list, 'a3000', 'a1000');
      expect(rm2.list.length).assertEqual(1);
      expect(rm2.newActive).assertEqual('a1000');
      // 删空
      const rm3 = removeAccountFromList([{ aid: 'a1', name: 'n', credential: 'c', credential2: '', refreshToken: '', extraConfig: '' }], 'a1', 'a1');
      expect(rm3.list.length).assertEqual(0);
      expect(rm3.newActive).assertEqual('');
      // 空凭证（待填账号）不去重：连续添加各自成账号
      const e1 = addAccountToList([], '', '', '', '', 1000);
      const e2 = addAccountToList(e1.list, '', '', '', '', 2000);
      expect(e1.deduped).assertFalse();
      expect(e2.deduped).assertFalse();
      expect(e2.list.length).assertEqual(2);
      expect(e2.account.name).assertEqual('账号 2');
      // 同毫秒连续添加：aid 必须唯一
      const s1 = addAccountToList([], 'x1', '', '', '', 5000);
      const s2 = addAccountToList(s1.list, 'x2', '', '', '', 5000);
      expect(s1.account.aid === s2.account.aid).assertFalse();
      const s3 = addAccountToList(s2.list, 'x3', '', '', '', 5000);
      expect(s3.account.aid === s1.account.aid).assertFalse();
      expect(s3.account.aid === s2.account.aid).assertFalse();
      expect(s3.list.length).assertEqual(3);
    });

    it('Accounts_rename', 0, () => {
      const list = parseAccounts(
        '[{"aid":"a1","name":"账号 1","credential":"c1","credential2":"","extraConfig":""},' +
        '{"aid":"a2","name":"账号 2","credential":"c2","credential2":"","extraConfig":""}]');
      // 重命名只改目标账号名称，其余字段不变
      const renamed = renameAccountInList(list, 'a2', '工作号');
      expect(renamed.length).assertEqual(2);
      expect(renamed[1].name).assertEqual('工作号');
      expect(renamed[1].credential).assertEqual('c2');
      expect(renamed[1].aid).assertEqual('a2');
      expect(renamed[0].name).assertEqual('账号 1');
      // 不存在的 aid：原样返回
      const same = renameAccountInList(list, 'zz', 'x');
      expect(same.length).assertEqual(2);
      expect(same[0].name).assertEqual('账号 1');
      expect(same[1].name).assertEqual('账号 2');
    });

    it('WidgetData_build_items', 0, () => {
      const now = 1758000000000;
      const a = stateWith(makeWindow(42, now + 2 * 3600000, true), 'Alpha');
      const rows = buildWidgetItems([a], now);
      expect(rows.length).assertEqual(1);
      expect(rows[0].name).assertEqual('Alpha');
      expect(rows[0].pct).assertEqual('42%');
      expect(rows[0].barPct).assertEqual(42);
      expect(rows[0].color).assertEqual(Theme.accent);
      expect(rows[0].cd.indexOf('2小时') >= 0).assertTrue();
      // 过滤：未启用 / 失败快照 / 无窗口
      const off = stateWith(makeWindow(10, 0, true), 'Off', false);
      const fail = stateWith(makeWindow(10, 0, true), 'Fail');
      fail.snapshot = UsageSnapshot.failure('x');
      const empty = stateWith(makeWindow(10, 0, true), 'Empty');
      empty.snapshot = UsageSnapshot.success(null, null, null);
      const rows2 = buildWidgetItems([off, fail, empty, a], now);
      expect(rows2.length).assertEqual(1);
      // 按用量降序 + 上限 4 条
      const many: ProviderState[] = [];
      for (let i = 0; i < 6; i++) {
        many.push(stateWith(makeWindow(10 + i * 10, 0, true), `P${i}`));
      }
      const rows3 = buildWidgetItems(many, now);
      expect(rows3.length).assertEqual(4);
      expect(rows3[0].name).assertEqual('P5');
      expect(rows3[3].name).assertEqual('P2');
      // 无主窗口回退次窗口；usageKnown=false 灰色；重置已过无倒计时
      const b = stateWith(makeWindow(1, 0, true), 'B');
      b.snapshot = UsageSnapshot.success(null, makeWindow(55, now - 60000, false), null);
      const rows4 = buildWidgetItems([b], now);
      expect(rows4.length).assertEqual(1);
      expect(rows4[0].pct).assertEqual('55%');
      expect(rows4[0].color).assertEqual('#3A3A44');
      expect(rows4[0].cd).assertEqual('');
    });

    it('UsageHistory_date_and_deltas', 0, () => {
      // 日期键
      expect(localDateKey(new Date(2026, 8, 21, 15, 40).getTime())).assertEqual('2026-09-21');
      expect(dayLabel('2026-09-21')).assertEqual('9/21');
      expect(dateKeyMinus('2026-09-21', 6)).assertEqual('2026-09-15');
      // 跨月
      expect(dateKeyMinus('2026-09-03', 7)).assertEqual('2026-08-27');

      // 用量增量：正常差值 / 回落归零 / 跨天重置取当日值
      const recs: HistoryDay[] = [
        { d: '2026-09-19', p: 10, b: -1 },
        { d: '2026-09-20', p: 45, b: -1 },
        { d: '2026-09-21', p: 30, b: -1 },
        { d: '2026-09-22', p: 5, b: -1 },
        { d: '2026-09-23', p: 50, b: -1 },
      ];
      const u = usageDeltas(recs);
      expect(u.length).assertEqual(4);
      expect(u[0].v).assertEqual(35);
      expect(u[1].v).assertEqual(0);
      expect(u[2].v).assertEqual(0);
      expect(u[3].v).assertEqual(45);
      expect(u[3].label).assertEqual('9/23');

      // 消费：余额降幅；充值记 0；缺余额跳过
      const recs2: HistoryDay[] = [
        { d: '2026-09-19', p: 10, b: 100 },
        { d: '2026-09-20', p: 45, b: 97.5 },
        { d: '2026-09-21', p: 30, b: 102 },
        { d: '2026-09-22', p: 5, b: -1 },
        { d: '2026-09-23', p: 50, b: 99.2 },
      ];
      const c = costDeltas(recs2);
      expect(c.length).assertEqual(2);
      expect(c[0].v).assertEqual(2.5);
      expect(c[1].v).assertEqual(0);

      // 合计：近 N 天（含今天）
      const today = '2026-09-23';
      const pts: ChartPoint[] = [
        { d: '2026-09-15', label: '9/15', v: 5 },
        { d: '2026-09-17', label: '9/17', v: 3 },
        { d: '2026-09-23', label: '9/23', v: 4.5 },
      ];
      expect(sumLast(pts, today, 1)).assertEqual(4.5);
      expect(sumLast(pts, today, 7)).assertEqual(7.5);
      expect(sumLast(pts, today, 30)).assertEqual(12.5);
    });

    it('UsageHistory_scale_ticks', 0, () => {
      expect(scaleMax([1, 5, 3])).assertEqual(5);
      expect(scaleMax([-1, NaN])).assertEqual(0);
      expect(scaleFraction(2.5, 5)).assertEqual(0.5);
      expect(scaleFraction(9, 5)).assertEqual(1);
      expect(scaleFraction(0, 0)).assertEqual(0);
      // 费用 < $1：[0,max]；否则 [0, 中点, max]
      expect(yAxisTicks(0.75, true).length).assertEqual(2);
      const t = yAxisTicks(8, true);
      expect(t.length).assertEqual(3);
      expect(t[1]).assertEqual(4);
      expect(yAxisTicks(1.5, false).length).assertEqual(2);
      expect(yAxisTicks(2.5, false).length).assertEqual(3);
    });

    it('VolcSign_sha256_hmac', 0, () => {
      // FIPS 180-4 空串与 abc 向量
      expect(sha256Hex('')).assertEqual('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
      expect(sha256Hex('abc')).assertEqual('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      // RFC 4231 Test Case 2：key="Jefe"，data="what do ya want for nothing?"
      expect(hmacSha256Hex(utf8Bytes('Jefe'), 'what do ya want for nothing?'))
        .assertEqual('5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843');
      // RFC 4231 Test Case 1：20 字节 0x0b 密钥
      const zerosKey: number[] = [];
      for (let i = 0; i < 20; i++) {
        zerosKey.push(0x0b);
      }
      expect(hmacSha256Hex(zerosKey, 'Hi There'))
        .assertEqual('b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7');
      // 超过分组长度（64B）的密钥先做一次 SHA-256
      const longKey: number[] = [];
      for (let i = 0; i < 131; i++) {
        longKey.push(0xaa);
      }
      expect(hmacSha256Hex(longKey, 'Test Using Larger Than Block-Size Key - Hash Key First'))
        .assertEqual('60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54');
    });

    it('VolcSign_canonical_and_sign', 0, () => {
      const url = 'https://open.volcengineapi.com/?Action=GetCodingPlanUsage&Version=2024-01-01';
      expect(volcHostOf(url)).assertEqual('open.volcengineapi.com');
      expect(volcCanonicalUri(url)).assertEqual('/');
      expect(volcCanonicalQuery(url)).assertEqual('Action=GetCodingPlanUsage&Version=2024-01-01');
      // 查询串乱序输入 → 规范化后按 key 字典序
      expect(volcCanonicalQuery('https://x.test/?Version=2024-01-01&Action=GetAFPUsage'))
        .assertEqual('Action=GetAFPUsage&Version=2024-01-01');
      expect(volcCanonicalQuery('https://x.test/')).assertEqual('');
      expect(volcCanonicalUri('https://x.test/a/b')).assertEqual('/a/b');

      // UTC 时间戳
      const ms = Date.UTC(2026, 8, 21, 3, 4, 5);
      expect(volcTimestamp(ms)).assertEqual('20260921T030405Z');
      expect(volcDateStamp(ms)).assertEqual('20260921');

      // percent-encode：斜杠按需保留，其余大写十六进制
      expect(volcPercentEncode('a b/c', true)).assertEqual('a%20b%2Fc');
      expect(volcPercentEncode('a b/c', false)).assertEqual('a%20b/c');
      expect(volcPercentEncode('-_.~', true)).assertEqual('-_.~');

      const creds: VolcCredentials = {
        accessKeyId: 'AKLTtest', secretAccessKey: 'sk-test', region: 'cn-beijing',
      };
      const contentType = 'application/x-www-form-urlencoded; charset=utf-8';
      const sig = signVolcRequest('POST', url, contentType, '', creds, ms);
      expect(sig.headers['x-date']).assertEqual('20260921T030405Z');
      expect(sig.headers['x-content-sha256']).assertEqual(
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
      expect(sig.signature.length).assertEqual(64);
      expect(sig.headers['authorization'].indexOf(
        'Credential=AKLTtest/20260921/cn-beijing/ark/request') >= 0).assertTrue();
      expect(sig.headers['authorization'].indexOf(
        'SignedHeaders=content-type;host;x-content-sha256;x-date') >= 0).assertTrue();
      expect(sig.headers['authorization'].indexOf(`Signature=${sig.signature}`) >= 0).assertTrue();
      // 规范化请求的空行分隔与签名头顺序（与服务端重算一致）
      expect(sig.canonicalRequest.indexOf(
        'x-date:20260921T030405Z\n\ncontent-type;host;x-content-sha256;x-date\n') >= 0).assertTrue();
      expect(sig.stringToSign.indexOf('HMAC-SHA256\n20260921T030405Z\n') >= 0).assertTrue();
      // 相同输入 → 稳定签名；Action 变化 → 签名变化
      const again = signVolcRequest('POST', url, contentType, '', creds, ms);
      expect(again.signature).assertEqual(sig.signature);
      const afp = signVolcRequest('POST', 'https://open.volcengineapi.com/?Action=GetAFPUsage&Version=2024-01-01',
        contentType, '', creds, ms);
      expect(afp.signature === sig.signature).assertFalse();
    });

    it('Doubao_quota_parsing', 0, () => {
      // 秒 / 毫秒自适应与无效值
      expect(doubaoEpochMs(1758000000)).assertEqual(1758000000000);
      expect(doubaoEpochMs(1758000000000)).assertEqual(1758000000000);
      expect(doubaoEpochMs(0)).assertEqual(0);
      expect(doubaoEpochMs(-1)).assertEqual(0);
      expect(doubaoEpochMs(null)).assertEqual(0);

      // 编码计划：Level 统一小写、Percent 钳制到 [0,100]、ResetTimestamp 为秒
      const coding: Record<string, Object> = JSON.parse(
        '{"Result":{"Status":"Active","UpdateTimestamp":1758000000,"QuotaUsage":[' +
        '{"Level":"Session","Percent":42.5,"ResetTimestamp":1758003600},' +
        '{"Level":"weekly","Percent":150},' +
        '{"Level":"month","Percent":-3}]}}') as Record<string, Object>;
      const meta = doubaoCodingPlanMeta(coding);
      expect(meta.status).assertEqual('Active');
      expect(meta.updatedAt).assertEqual(1758000000000);
      const quotas = doubaoQuotasFromCodingPlan(coding);
      expect(quotas.length).assertEqual(3);
      expect(quotas[0].level).assertEqual('session');
      expect(quotas[0].percent).assertEqual(42.5);
      expect(quotas[0].resetAt).assertEqual(1758003600000);
      expect(quotas[1].percent).assertEqual(100);
      expect(quotas[2].percent).assertEqual(0);
      // 缺少 QuotaUsage（计划被回收）→ 空数组，不抛异常
      expect(doubaoQuotasFromCodingPlan(JSON.parse('{"Result":{"Status":"Expired"}}')).length)
        .assertEqual(0);
      expect(doubaoQuotasFromCodingPlan(null).length).assertEqual(0);

      // Agent 计划（AFP）：used/quota 推算百分比；quota<=0 跳过
      const agent: Record<string, Object> = JSON.parse(
        '{"Result":{"AFPFiveHour":{"Quota":100,"Used":25,"ResetTime":1758000000000},' +
        '"AFPWeekly":{"Quota":0,"Used":10},' +
        '"AFPMonthly":{"Quota":200,"Used":50}}}') as Record<string, Object>;
      const aq = doubaoQuotasFromAgentPlan(agent);
      expect(aq.length).assertEqual(2);
      expect(aq[0].level).assertEqual('agent_5h');
      expect(aq[0].percent).assertEqual(25);
      expect(aq[0].resetAt).assertEqual(1758000000000);
      expect(aq[1].level).assertEqual('agent_monthly');
      expect(aq[1].percent).assertEqual(25);
    });

    it('Doubao_signed_snapshot', 0, () => {
      const meta: DoubaoPlanMeta = { status: 'Active', updatedAt: 1758000000000 };
      const mixed: DoubaoQuota[] = [
        { level: 'session', percent: 42, resetAt: 1000 },
        { level: 'weekly', percent: 10, resetAt: 2000 },
        { level: 'monthly', percent: 5, resetAt: 3000 },
        { level: 'agent_5h', percent: 60, resetAt: 4000 },
        { level: 'agent_weekly', percent: 20, resetAt: 5000 },
      ];
      const snap = doubaoSignedSnapshot(mixed, meta);
      expect(snap.primary != null).assertTrue();
      expect(snap.primary!.usedPercent).assertEqual(42);
      expect(snap.primary!.resetsAt).assertEqual(1000);
      expect(snap.secondary!.usedPercent).assertEqual(10);
      expect(snap.tertiary!.usedPercent).assertEqual(5);
      // Agent 计划窗口未被主/次档占用 → 进附加窗口
      expect(snap.extraRateWindows.length).assertEqual(2);
      expect(snap.extraRateWindows[0].id).assertEqual('doubao-agent-session');
      expect(snap.extraRateWindows[0].title).assertEqual('Agent 计划 5 小时');
      expect(snap.extraRateWindows[1].id).assertEqual('doubao-agent-weekly');
      expect(snap.updatedAt).assertEqual(1758000000000);
      expect(snap.identity!.loginMethod).assertEqual('Active');

      // 仅 Agent 计划：补位主/次/第三窗口，且不在附加窗口重复展示
      const agentOnly: DoubaoQuota[] = [
        { level: 'agent_5h', percent: 60, resetAt: 4000 },
        { level: 'agent_weekly', percent: 20, resetAt: 5000 },
        { level: 'agent_monthly', percent: 8, resetAt: 6000 },
      ];
      const only = doubaoSignedSnapshot(agentOnly, meta);
      expect(only.primary!.usedPercent).assertEqual(60);
      expect(only.secondary!.usedPercent).assertEqual(20);
      expect(only.tertiary!.usedPercent).assertEqual(8);
      expect(only.extraRateWindows.length).assertEqual(0);

      // 团队计划：前缀隔离，不与个人计划串档
      const team: DoubaoQuota[] = [
        { level: 'session', percent: 42, resetAt: 1000 },
        { level: 'coding_team_session', percent: 90, resetAt: 9000 },
        { level: 'agent_team_monthly', percent: 33, resetAt: 8000 },
      ];
      const teamSnap = doubaoSignedSnapshot(team, meta);
      // 编码计划个人 session 占主窗口；coding_team_session 不串档
      expect(teamSnap.primary!.usedPercent).assertEqual(42);
      // 月度档缺失 → agent_team_monthly 补位第三窗口（不出现在附加窗口）
      expect(teamSnap.tertiary!.usedPercent).assertEqual(33);
      expect(teamSnap.extraRateWindows.length).assertEqual(1);
      expect(teamSnap.extraRateWindows[0].id).assertEqual('doubao-coding-team-session');
      expect(teamSnap.extraRateWindows[0].title).assertEqual('编码团队 5 小时');
      expect(teamSnap.extraRateWindows[0].window.usedPercent).assertEqual(90);
    });

    it('Doubao_probe_headers', 0, () => {
      const now = 1758000000000;
      // 200 + 完整限额头：按已用比例生成主窗口，重置时长按秒累加
      const full: Record<string, string> = {
        'x-ratelimit-limit-requests': '100',
        'x-ratelimit-remaining-requests': '30',
        'x-ratelimit-reset-requests': '2m30s',
      };
      const ok = doubaoParseProbe(200, full, now);
      expect(ok.window != null).assertTrue();
      expect(ok.window!.usedPercent).assertEqual(70);
      expect(ok.window!.resetsAt).assertEqual(now + 150000);
      expect(ok.window!.usageKnown).assertTrue();
      expect(ok.keyValid).assertTrue();
      expect(ok.limitsReliable).assertTrue();
      expect(ok.ambiguousZero).assertFalse();

      // 200 + 剩余 0：歧义态，需二次探测确认
      const zeroHeaders: Record<string, string> = {
        'x-ratelimit-limit-requests': '100',
        'x-ratelimit-remaining-requests': '0',
      };
      const zero = doubaoParseProbe(200, zeroHeaders, now);
      expect(zero.ambiguousZero).assertTrue();
      expect(zero.window!.usedPercent).assertEqual(100);

      // 429 且带 limit（无 remaining）：请求桶耗尽，可靠
      const limitedHeaders: Record<string, string> = { 'x-ratelimit-limit-requests': '100' };
      const limited = doubaoParseProbe(429, limitedHeaders, now);
      expect(limited.keyValid).assertTrue();
      expect(limited.limitsReliable).assertTrue();
      expect(limited.window!.usedPercent).assertEqual(100);
      expect(limited.ambiguousZero).assertFalse();
      // 429 且无 limit：限流原因不明，窗口不可得
      const bareThrottle = doubaoParseProbe(429, {}, now);
      expect(bareThrottle.keyValid).assertTrue();
      expect(bareThrottle.limitsReliable).assertFalse();
      expect(bareThrottle.window).assertEqual(null);

      // 200 但缺限额头：Key 有效、窗口不可得（不用 100% 冒充）
      const noHeaders = doubaoParseProbe(200, {}, now);
      expect(noHeaders.keyValid).assertTrue();
      expect(noHeaders.limitsReliable).assertFalse();
      expect(noHeaders.window).assertEqual(null);
      // 401：Key 无效
      expect(doubaoParseProbe(401, {}, now).keyValid).assertFalse();

      // 重置头解析：空串 / ISO8601 / 时长
      expect(doubaoParseResetHeader('', now)).assertEqual(0);
      expect(doubaoParseResetHeader('2026-09-21T03:04:05Z', now))
        .assertEqual(Date.UTC(2026, 8, 21, 3, 4, 5));
      expect(doubaoParseResetHeader('30s', now)).assertEqual(now + 30000);
      expect(doubaoParseResetHeader('1h', now)).assertEqual(now + 3600000);
    });

    it('AwsSign_sigv4_vector', 0, () => {
      // 期望值来自 botocore（AWS CLI 2.28.6 SigV4Auth）对同一个 Cost Explorer 请求的签名：
      //   POST https://ce.us-east-1.amazonaws.com/
      //   content-type: application/x-amz-json-1.1
      //   x-amz-target: AWSInsightsIndexService.GetCostAndUsage
      //   x-amz-date: 20260922T124909Z（区域 us-east-1 / 服务码 ce）
      const credentials: AwsCredentials = {
        accessKeyId: 'AKIDEXAMPLE',
        secretAccessKey: 'wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY',
        sessionToken: '',
      };
      const url = 'https://ce.us-east-1.amazonaws.com/';
      const body = '{"TimePeriod": {"Start": "2026-09-01", "End": "2026-09-23"}, ' +
        '"Granularity": "MONTHLY", "Metrics": ["UnblendedCost"]}';
      const headers: Record<string, string> = {
        'content-type': 'application/x-amz-json-1.1',
        'x-amz-target': 'AWSInsightsIndexService.GetCostAndUsage',
      };
      const timestamp = Date.UTC(2026, 8, 22, 12, 49, 9);
      const sig = signAwsRequest('POST', url, 'ce', 'us-east-1', headers, body,
        credentials, timestamp, false);
      expect(sig.signedHeaders).assertEqual('content-type;host;x-amz-date;x-amz-target');
      expect(sig.signature)
        .assertEqual('d41a028f3e64ad326f3cfc013666c80df6254d92c90924429437b5336e4d8892');
      expect(sig.headers['authorization']).assertEqual(
        'AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20260922/us-east-1/ce/aws4_request, ' +
        'SignedHeaders=content-type;host;x-amz-date;x-amz-target, ' +
        'Signature=d41a028f3e64ad326f3cfc013666c80df6254d92c90924429437b5336e4d8892');
      expect(sig.headers['x-amz-date']).assertEqual('20260922T124909Z');
      // Host 只参与签名，不由调用方下发（HTTP 客户端按 URL 生成）
      expect(sig.headers['host']).assertEqual(undefined);
      // 规范化请求逐行核对（对照 AWS SigV4 规范第 1 步：CanonicalHeaders 块后空行）
      const lines = sig.canonicalRequest.split('\n');
      expect(lines.length).assertEqual(10);
      expect(lines[0]).assertEqual('POST');
      expect(lines[1]).assertEqual('/');
      expect(lines[2]).assertEqual('');
      expect(lines[3]).assertEqual('content-type:application/x-amz-json-1.1');
      expect(lines[4]).assertEqual('host:ce.us-east-1.amazonaws.com');
      expect(lines[5]).assertEqual('x-amz-date:20260922T124909Z');
      expect(lines[6]).assertEqual('x-amz-target:AWSInsightsIndexService.GetCostAndUsage');
      expect(lines[7]).assertEqual('');
      expect(lines[8]).assertEqual('content-type;host;x-amz-date;x-amz-target');
      expect(lines[9]).assertEqual(sha256Hex(body));
      const expectToSign = 'AWS4-HMAC-SHA256\n20260922T124909Z\n' +
        '20260922/us-east-1/ce/aws4_request\n' + sha256Hex(sig.canonicalRequest);
      expect(sig.stringToSign === expectToSign).assertTrue();

      // 源工程形态：额外把 payload 哈希放进 x-amz-content-sha256 并计入签名头
      const withHash = signAwsRequest('POST', url, 'ce', 'us-east-1', headers, body,
        credentials, timestamp, true);
      expect(withHash.signedHeaders)
        .assertEqual('content-type;host;x-amz-content-sha256;x-amz-date;x-amz-target');
      expect(withHash.headers['x-amz-content-sha256']).assertEqual(sha256Hex(body));
      expect(withHash.signature).assertEqual(withHash.headers['authorization']
        .substring(withHash.headers['authorization'].lastIndexOf('Signature=') + 10));
      expect(withHash.signature === sig.signature).assertFalse();

      // 临时凭证：会话令牌必须计入签名头；头值空白折叠
      const temp = signAwsRequest('POST', url, 'ce', 'us-east-1',
        { 'content-type': 'application/x-amz-json-1.1  ' },
        body, { accessKeyId: 'AKIDEXAMPLE', secretAccessKey: 'secret', sessionToken: 'TOKEN-1' },
        timestamp, false);
      expect(temp.signedHeaders)
        .assertEqual('content-type;host;x-amz-date;x-amz-security-token');
      expect(temp.canonicalRequest.indexOf('content-type:application/x-amz-json-1.1\n') >= 0)
        .assertTrue();
      expect(temp.headers['x-amz-security-token']).assertEqual('TOKEN-1');
    });

    it('Bedrock_cost_and_activity', 0, () => {
      const now = Date.UTC(2026, 8, 22, 12, 0, 0);
      // 计费区间：UTC 本月首日 → 明日；预算窗口重置点 = 下月首日 UTC
      const range = bedrockMonthRange(now);
      expect(range.start).assertEqual('2026-09-01');
      expect(range.end).assertEqual('2026-09-23');
      expect(bedrockMonthEnd(now)).assertEqual(Date.UTC(2026, 9, 1));

      // CloudWatch 端点分区后缀
      expect(bedrockCloudWatchEndpoint('us-east-1'))
        .assertEqual('https://monitoring.us-east-1.amazonaws.com');
      expect(bedrockCloudWatchEndpoint('cn-north-1'))
        .assertEqual('https://monitoring.cn-north-1.amazonaws.com.cn');
      expect(bedrockCloudWatchEndpoint('eusc-de-east-1'))
        .assertEqual('https://monitoring.eusc-de-east-1.amazonaws.eu');
      expect(bedrockCloudWatchEndpoint('us-isob-east-1'))
        .assertEqual('https://monitoring.us-isob-east-1.sc2s.sgov.gov');
      expect(bedrockCloudWatchEndpoint('not-a-region')).assertEqual('');

      // Cost Explorer 汇总：只累加服务名含 Bedrock 的分组，空/负值忽略
      const costJson = parseJson('{"ResultsByTime":[' +
        '{"TimePeriod":{"Start":"2026-09-01"},"Groups":[' +
        '{"Keys":["Amazon Bedrock"],"Metrics":{"UnblendedCost":{"Amount":"12.34"}}},' +
        '{"Keys":["Amazon EC2"],"Metrics":{"UnblendedCost":{"Amount":"99"}}}]},' +
        '{"TimePeriod":{"Start":"2026-09-02"},"Groups":[' +
        '{"Keys":["Bedrock"],"Metrics":{"UnblendedCost":{"Amount":"1.66"}}},' +
        '{"Keys":["Bedrock"],"Metrics":{"UnblendedCost":{"Amount":"0"}}}]}],' +
        '"NextPageToken":"tok-2"}');
      expect(bedrockTotalCost(costJson)).assertEqual(14);
      expect(bedrockNextPageToken(costJson)).assertEqual('tok-2');
      expect(bedrockNextPageToken(parseJson('{}'))).assertEqual('');

      // 未启用计费数据（400 + DataUnavailableException）按 0 处理
      expect(bedrockDataUnavailable(400,
        '{"__type":"com.amazonaws.ce#DataUnavailableException","message":"no data"}'))
        .assertTrue();
      expect(bedrockDataUnavailable(400, '{"message":"bad request"}')).assertFalse();
      expect(bedrockDataUnavailable(500,
        '{"__type":"#DataUnavailableException"}')).assertFalse();

      // CloudWatch 指标：完整结果求和；Messages 非空 / Partial / 未知 Id 判为不可用
      const cwJson = parseJson('{"MetricDataResults":[' +
        '{"Id":"inputTokens","StatusCode":"Complete","Values":[100,50.5]},' +
        '{"Id":"outputTokens","StatusCode":"Complete","Values":[20]},' +
        '{"Id":"requests","StatusCode":"Complete","Values":[7,3]}]}');
      const activity = bedrockClaudeActivity(cwJson);
      expect(activity != null).assertTrue();
      expect(activity!.inputTokens).assertEqual(151);
      expect(activity!.outputTokens).assertEqual(20);
      expect(activity!.requestCount).assertEqual(10);
      expect(bedrockClaudeActivity(parseJson(
        '{"Messages":[{"Code":"InternalError"}],"MetricDataResults":[]}'))).assertEqual(null);
      expect(bedrockClaudeActivity(parseJson(
        '{"MetricDataResults":[{"Id":"inputTokens","StatusCode":"Partial","Values":[]}]}')))
        .assertEqual(null);
      expect(bedrockClaudeActivity(parseJson(
        '{"MetricDataResults":[{"Id":"cpu","StatusCode":"Complete","Values":[1]}]}')))
        .assertEqual(null);

      // 展示映射：有预算 → 主窗口按预算比例 + 本月首日→下月首日重置；无预算 → 无窗口
      const snap = bedrockSnapshot(20, 100, activity, 'us-east-1', now);
      expect(snap.primary!.usedPercent).assertEqual(20);
      expect(snap.primary!.resetsAt).assertEqual(Date.UTC(2026, 9, 1));
      expect(snap.providerCost!.used).assertEqual(20);
      expect(snap.providerCost!.remaining).assertEqual(80);
      expect(snap.providerCost!.displayText).assertEqual('$20.00');
      expect(snap.details[0].rows[0].label).assertEqual('本月消费');
      expect(snap.identity!.loginMethod.indexOf('Requests: 10') >= 0).assertTrue();
      const noBudget = bedrockSnapshot(7.5, 0, null, 'ap-northeast-1', now);
      expect(noBudget.primary).assertEqual(null);
      expect(noBudget.providerCost!.displayText).assertEqual('$7.50');
      expect(noBudget.identity!.loginMethod).assertEqual('Spend: $7.50');
    });

    it('Snapshot_from_stored_cache', 0, () => {
      // 旧版本缓存：没有 primaryLabel / extraRateWindows / details / ok
      // （曾导致首页 `primaryLabel.length` 读到 undefined 而闪退）
      const legacy = '{"primary":{"usedPercent":12.5,"resetsAt":1758000000000,' +
        '"usageKnown":true},"updatedAt":1758000000000}';
      const s = UsageSnapshot.fromStored(legacy);
      expect(s != null).assertTrue();
      expect(s!.primaryLabel).assertEqual('');
      expect(s!.secondaryLabel).assertEqual('');
      expect(s!.tertiaryLabel).assertEqual('');
      expect(s!.extraRateWindows.length).assertEqual(0);
      expect(s!.details.length).assertEqual(0);
      expect(s!.identity).assertEqual(null);
      expect(s!.providerCost).assertEqual(null);
      expect(s!.secondary).assertEqual(null);
      expect(s!.ok).assertTrue();
      expect(s!.primary!.usedPercent).assertEqual(12.5);
      expect(s!.updatedAt).assertEqual(1758000000000);

      // 更早的缓存：窗口缺 usageKnown 按已知处理
      const older = UsageSnapshot.fromStored('{"primary":{"usedPercent":0,"resetsAt":0}}');
      expect(older!.primary!.usageKnown).assertTrue();
      expect(older!.updatedAt > 0).assertTrue();

      // 非法缓存不抛异常
      expect(UsageSnapshot.fromStored('not json')).assertEqual(null);
      expect(UsageSnapshot.fromStored('null')).assertEqual(null);

      // 正常缓存：全部字段原样保留
      const fresh = new UsageSnapshot();
      fresh.primary = makeWindow(30, 1758000000000, true);
      fresh.primaryLabel = '5-hour';
      fresh.extraRateWindows = [{ id: 'x', title: 'X', window: makeWindow(1, 0, true) }];
      fresh.providerCost = {
        remaining: 5, used: 1, currency: 'USD', displayText: '$5.00',
        detailText: '$5.00 (Paid: $4.00 / Granted: $1.00)',
      };
      fresh.details = [{ title: 'T', rows: [{ label: 'L', value: 'V' }] }];
      fresh.identity = { accountEmail: 'a', accountOrganization: 'o', loginMethod: 'm' };
      const back = UsageSnapshot.fromStored(JSON.stringify(fresh));
      expect(back!.primaryLabel).assertEqual('5-hour');
      expect(back!.primary!.usedPercent).assertEqual(30);
      expect(back!.extraRateWindows.length).assertEqual(1);
      expect(back!.providerCost!.displayText).assertEqual('$5.00');
      // 余额说明行（首页不显示，详情页才显示）随缓存保留
      expect(back!.providerCost!.detailText).assertEqual('$5.00 (Paid: $4.00 / Granted: $1.00)');
      expect(back!.details[0].rows[0].label).assertEqual('L');
      expect(back!.identity!.loginMethod).assertEqual('m');
      expect(back!.secondary == null).assertTrue();
    });

    it('T3Chat_find_customer_data', 0, () => {
      const line = '{"0":{"result":{"data":{"json":{"subTier":"yearly","usageFourHourPercentage":55.5,' +
        '"usageFourHourNextResetAt":1758000000,"usageMonthPercentage":12,"billingNextResetAt":1760000000}}}}}';
      const found = t3chatFindCustomerData(JSON.parse(line) as Record<string, Object>);
      expect(found != null).assertTrue();
      if (found != null) {
        const fourHour = found['usageFourHourPercentage'];
        expect(fourHour != null).assertTrue();
        expect(JSON.stringify(found).indexOf('subTier') >= 0).assertTrue();
      }
      expect(t3chatFindCustomerData(null)).assertEqual(null);
    });

    it('ZoomMate_status_and_history', 0, () => {
      // 信封：data.credit_status 优先，其次 credit_status / credits / 根对象
      const wrapped = zoomMateCreditStatus(parseJson(
        '{"data":{"credit_status":{"budget_cap":100,"used_credit":25}}}'));
      expect(wrapped!['budget_cap']).assertEqual(100);
      const direct = zoomMateCreditStatus(parseJson('{"credit_status":{"budget_cap":7}}'));
      expect(direct!['budget_cap']).assertEqual(7);
      const legacy = zoomMateCreditStatus(parseJson('{"credits":{"budget_cap":9}}'));
      expect(legacy!['budget_cap']).assertEqual(9);
      expect(zoomMateCreditStatus(parseJson('{"budget_cap":3}'))!['budget_cap']).assertEqual(3);

      // 主窗口：used/budget_cap；无限额或预算为 0 时用量记 0（usageKnown=false）
      const win = zoomMateStatusWindow(
        parseJson('{"budget_cap":100,"used_credit":25,"cycle_end_date":1780000000000}'));
      expect(win!.usedPercent).assertEqual(25);
      expect(win!.resetsAt).assertEqual(1780000000000);
      expect(win!.usageKnown).assertTrue();
      const unlimited = zoomMateStatusWindow(parseJson('{"is_unlimited":true,"budget_cap":10,"used_credit":4}'));
      expect(unlimited!.usedPercent).assertEqual(0);
      expect(unlimited!.usageKnown).assertFalse();
      const noCap = zoomMateStatusWindow(parseJson('{"budget_cap":0,"used_credit":4}'));
      expect(noCap!.usedPercent).assertEqual(0);
      // 重置点：毫秒 / 秒 / ISO 三种形态
      expect(zoomMateResetMs(parseJson('{"cycle_end_date":1780000000000}'))).assertEqual(1780000000000);
      expect(zoomMateResetMs(parseJson('{"cycle_end_date":1780000000}'))).assertEqual(1780000000000);
      expect(zoomMateResetMs(parseJson('{"cycle_end_date":"2026-10-01T00:00:00Z"}')))
        .assertEqual(Date.UTC(2026, 9, 1));
      expect(zoomMateResetMs(parseJson('{}'))).assertEqual(0);

      // 历史行：跳过已删除 / 负花费 / 超出 30 天，Today 按本地日期合计
      const now = 1780000000000;
      const todayIso = new Date(now).toISOString();
      const oldIso = new Date(now - 40 * 86400000).toISOString();
      const rows = zoomMateHistoryRows(parseJson('{"data":{"records":[' +
        `{"cost":2.5,"time":"${todayIso}"},` +
        `{"cost":1.5,"time":"${todayIso}"},` +
        `{"cost":99,"time":"${oldIso}"},` +
        `{"cost":5,"time":"${todayIso}","is_deleted":true},` +
        `{"cost":-3,"time":"${todayIso}"}]}}`), now);
      expect(rows.length).assertEqual(2);
      expect(rows[0].label).assertEqual('Today');
      expect(rows[0].value).assertEqual('4');
      expect(rows[1].label).assertEqual('30d credits');
      expect(rows[1].value).assertEqual('4');
      // 缺 data 信封 = 解析失败（不附带历史）；data 存在但无记录 → 仍是两行 0
      expect(zoomMateHistoryRows(parseJson('{}'), now).length).assertEqual(0);
      const empty = zoomMateHistoryRows(parseJson('{"data":{}}'), now);
      expect(empty.length).assertEqual(2);
      expect(empty[0].value).assertEqual('0');

      // 每日聚合：只留当天（其它记录超窗/已删/负值都被剔除）
      const records = zoomMateHistoryRecords(parseJson('{"data":{"records":[' +
        `{"cost":2.5,"time":"${todayIso}"},` +
        `{"cost":1.5,"time":"${todayIso}"},` +
        `{"cost":99,"time":"${oldIso}"}]}}`));
      expect(records != null).assertTrue();
      const breakdown = zoomMateDailyBreakdown(records!, now);
      expect(breakdown.length).assertEqual(1);
      expect(breakdown[0].value).assertEqual(4);

      // Pace：按周期线性推进对比实际用量（|delta| ≤2 on track，>0 快于预算）
      const cycleStatus = (used: number): Record<string, Json> => parseJson('{' +
        `"budget_cap":100,"used_credit":${used},` +
        `"cycle_start_date":${now - 5 * 86400000},"cycle_end_date":${now + 5 * 86400000}}`) as Record<string, Json>;
      // 周期过半、只用了 25% → 落后 25%
      const behind = zoomMatePaceRow(cycleStatus(25), now);
      expect(behind != null).assertTrue();
      expect(behind!.label).assertEqual('Pace');
      expect(behind!.value).assertEqual('25% behind budget');
      // 52% ≈ 50% 期望值 → On track
      expect(zoomMatePaceRow(cycleStatus(52), now)!.value).assertEqual('On track');
      // 60% → 快 10%
      expect(zoomMatePaceRow(cycleStatus(60), now)!.value).assertEqual('10% ahead of budget');
      // 无周期起止 / 无限额 / 无预算上限 → 不判定
      expect(zoomMatePaceRow(
        parseJson('{"budget_cap":100,"used_credit":25}') as Record<string, Json>, now)).assertEqual(null);
      expect(zoomMatePaceRow(parseJson('{"is_unlimited":true,"budget_cap":10,"used_credit":4,' +
        `"cycle_start_date":${now - 86400000},"cycle_end_date":${now + 86400000}}`) as Record<string, Json>, now))
        .assertEqual(null);
      // 周期过半但一点没用 → 落后 50%
      expect(zoomMatePaceRow(cycleStatus(0), now)!.value).assertEqual('50% behind budget');
      // 周期刚开始就已有消耗 → 放弃判定；重置点已过 → 同样放弃
      expect(zoomMatePaceText(10, 10080, now + 604800000, now)).assertEqual('');
      expect(zoomMatePaceText(10, 10080, now, now)).assertEqual('');
    });

    it('Claude_extra_usage_and_prepaid', 0, () => {
      // /usage 的 extra_usage：单位是"分"，period 取自源工程（Monthly cap）
      const cost = claudeExtraUsageCost(parseJson(
        '{"used_credits":1250,"monthly_limit":5000,"currency":"USD"}'));
      expect(cost != null).assertTrue();
      expect(cost!.used).assertEqual(12.5);
      expect(cost!.limit).assertEqual(50);
      expect(cost!.remaining).assertEqual(37.5);
      expect(cost!.period).assertEqual('Monthly cap');
      // monthly_credit_limit 别名 与 缺省币种
      const alias = claudeExtraUsageCost(parseJson('{"used_credits":0,"monthly_credit_limit":100}'));
      expect(alias!.currency).assertEqual('USD');
      expect(alias!.limit).assertEqual(1);
      // 无法构图 → null
      expect(claudeExtraUsageCost(parseJson('{"used_credits":10}'))).assertEqual(null);
      expect(claudeExtraUsageCost(parseJson('{"used_credits":10,"monthly_limit":0}'))).assertEqual(null);
      expect(claudeExtraUsageCost(null)).assertEqual(null);

      // /overage_spend_limit：is_enabled 不为 true 时不出费用
      expect(claudeOverageSpendLimitCost(parseJson(
        '{"is_enabled":false,"used_credits":10,"monthly_credit_limit":100,"currency":"USD"}')))
        .assertEqual(null);
      const overage = claudeOverageSpendLimitCost(parseJson(
        '{"is_enabled":true,"used_credits":250,"monthly_credit_limit":1000,"currency":"USD"}'));
      expect(overage!.used).assertEqual(2.5);
      expect(overage!.remaining).assertEqual(7.5);

      // /prepaid/credits：同币种覆盖余额，不同币种保留原值；无原费用时单独立卡（Extra usage）
      const withPrepaid = claudePrepaidBalanceCost(
        parseJson('{"amount":9.99,"currency":"USD"}'), cost);
      expect(withPrepaid!.remaining).assertEqual(9.99);
      expect(withPrepaid!.used).assertEqual(12.5);
      expect(withPrepaid!.period).assertEqual('Monthly cap');
      const currencyMismatch = claudePrepaidBalanceCost(
        parseJson('{"amount":9.99,"currency":"CNY"}'), cost);
      expect(currencyMismatch!.remaining).assertEqual(37.5);
      const onlyPrepaid = claudePrepaidBalanceCost(
        parseJson('{"amount":3.5,"currency":"USD"}'), null);
      expect(onlyPrepaid!.period).assertEqual('Extra usage');
      expect(onlyPrepaid!.used).assertEqual(0);
      // 无预付数据：原样返回
      expect(claudePrepaidBalanceCost(parseJson('{}'), cost)!.remaining).assertEqual(37.5);
    });

    it('Metadata_window_labels', 0, () => {
      // 窗口标签表（对照 macOS ProviderMetadata 的 sessionLabel/weeklyLabel/opusLabel）
      const codex = windowLabelsFor('codex');
      expect(codex.primary).assertEqual('Session');
      expect(codex.secondary).assertEqual('Weekly');
      expect(codex.tertiary).assertEqual('');
      const claude = windowLabelsFor('claude');
      expect(claude.primary).assertEqual('Session');
      expect(claude.tertiary).assertEqual('Sonnet');
      const nCmd = windowLabelsFor('commandcode');
      expect(nCmd.primary).assertEqual('5-hour');
      expect(nCmd.secondary).assertEqual('Weekly');
      expect(nCmd.tertiary).assertEqual('Monthly');
      // 未登记的服务商不得报错：返回空表，UI 回落中文默认名
      const none = windowLabelsFor('crof');
      expect(none.primary).assertEqual('');
      expect(none.secondary).assertEqual('');
      expect(none.tertiary).assertEqual('');

      // 按元数据补齐：仅填空值，服务商显式标签优先
      const snap = UsageSnapshot.success(
        makeWindow(10, 0, true), makeWindow(20, 0, true), null);
      applyWindowLabels(snap, 'codex');
      expect(snap.primaryLabel).assertEqual('Session');
      expect(snap.secondaryLabel).assertEqual('Weekly');
      // 第三窗口为 null：不补标签（保持空串，避免“无窗口却有标题”）
      expect(snap.tertiaryLabel).assertEqual('');

      const explicit = UsageSnapshot.success(
        makeWindow(10, 0, true), makeWindow(20, 0, true), null);
      explicit.primaryLabel = 'Primary';
      applyWindowLabels(explicit, 'codex');
      expect(explicit.primaryLabel).assertEqual('Primary');
      expect(explicit.secondaryLabel).assertEqual('Weekly');
    });

    it('Metadata_default_flags', 0, () => {
      // defaultEnabled: 源工程仅 Codex 为 true；isPrimaryProvider: Claude / Codex
      expect(isDefaultEnabledProvider('codex')).assertTrue();
      expect(isDefaultEnabledProvider('claude')).assertFalse();
      expect(isDefaultEnabledProvider('deepseek')).assertFalse();
      expect(isPrimaryProvider('claude')).assertTrue();
      expect(isPrimaryProvider('codex')).assertTrue();
      expect(isPrimaryProvider('openrouter')).assertFalse();
    });

    it('Synthetic_quota_windows', 0, () => {
      // 百分比直取
      const w = syntheticQuotaWindow(parseJson('{"percentUsed":25,"resetAt":"2026-10-01T00:00:00Z"}'));
      expect(w != null).assertTrue();
      expect(w!.usedPercent).assertEqual(25);
      expect(w!.resetsAt).assertEqual(Date.UTC(2026, 9, 1));
      // 小数比率 → 百分点
      expect(syntheticQuotaWindow(parseJson('{"percent":0.5}'))!.usedPercent).assertEqual(50);
      // 剩余百分比取反
      expect(syntheticQuotaWindow(parseJson('{"percentRemaining":30}'))!.usedPercent).assertEqual(70);
      // used/limit 换算（插件别名表）
      expect(syntheticQuotaWindow(parseJson('{"used":3,"limit":12}'))!.usedPercent).assertEqual(25);
      // 秒级时间戳 → 毫秒
      expect(syntheticQuotaWindow(parseJson('{"used":1,"limit":4,"resetAt":1780000000}'))!.resetsAt)
        .assertEqual(1780000000000);
      // 无法识别 / 非法输入 → null
      expect(syntheticQuotaWindow(parseJson('{"name":"x"}'))).assertEqual(null);
      expect(syntheticQuotaWindow(null)).assertEqual(null);
    });

    it('ClawRouter_credential_modes', 0, () => {
      // 带 "=" 的串按会话 Cookie；否则按 policy API Key（与 OpenCode Go 判别一致）
      expect(clawRouterIsApiKey('session=abc; other=1')).assertFalse();
      expect(clawRouterIsApiKey('cr_live_policy_key')).assertTrue();
      expect(clawRouterIsApiKey('   ')).assertFalse();
      expect(clawRouterIsApiKey('')).assertFalse();
      // 端点随之切换：Cookie → /usage，API Key → /v1/usage
      expect(clawRouterUsageUrl('session=abc', ''))
        .assertEqual('https://clawrouter.openclaw.ai/usage');
      expect(clawRouterUsageUrl('cr_live_policy_key', ''))
        .assertEqual('https://clawrouter.openclaw.ai/v1/usage');
      // 第二凭证栏可填自托管 Base URL：空值取默认，去尾斜杠
      expect(clawRouterBaseURL('')).assertEqual('https://clawrouter.openclaw.ai');
      expect(clawRouterBaseURL(' https://router.example.com/ '))
        .assertEqual('https://router.example.com');
      expect(clawRouterUsageUrl('cr_live_policy_key', 'https://router.example.com/'))
        .assertEqual('https://router.example.com/v1/usage');
    });

    it('OptionalDetails_policy_table', 0, () => {
      // 逐条对照源工程 ProviderOptionalDetailsPresentation 的 8 家声明
      const claude = optionalDetailsFor('anthropic-console');
      expect(claude.costSummaryTitles.length).assertEqual(2);
      expect(claude.costSummaryTitles[0]).assertEqual('Usage summary');
      expect(claude.hidesAllWithoutOptionalUsage).assertFalse();

      const deepseek = optionalDetailsFor('deepseek');
      expect(deepseek.hidesAllWithoutOptionalUsage).assertTrue();
      expect(deepseek.costSummaryTitles.indexOf('Spend') >= 0).assertTrue();

      const minimax = optionalDetailsFor('minimax');
      expect(minimax.hiddenTitlesWithoutOptionalUsage[0]).assertEqual('Billing history');

      const groq = optionalDetailsFor('groq');
      expect(groq.costSummaryTitles[0]).assertEqual('Usage summary');

      // 未声明的服务商为默认空策略
      const other = optionalDetailsFor('openrouter');
      expect(other.hidesAllWithoutOptionalUsage).assertFalse();
      expect(other.costSummaryTitles.length).assertEqual(0);
      expect(other.hiddenTitlesWithoutOptionalUsage.length).assertEqual(0);
    });

    it('OptionalDetails_visible_filter', 0, () => {
      const usage: ProviderDetailSection = {
        title: 'Usage',
        rows: [
          { label: 'Today', value: '1' },
          { label: 'Requests', value: '2' },
        ],
      };
      const spend: ProviderDetailSection = {
        title: 'Spend',
        rows: [{ label: 'model-a', value: '$1' }],
      };
      // DeepSeek：关闭可选明细时整块隐藏
      expect(visibleDetails('deepseek', [usage, spend], false, false).length).assertEqual(0);
      // 开启时两组都在
      expect(visibleDetails('deepseek', [usage, spend], true, false).length).assertEqual(2);

      // MiniMax：只隐藏 Billing history
      const billing: ProviderDetailSection = {
        title: 'Billing history',
        rows: [{ label: 'Today tokens', value: '10' }],
      };
      const quota: ProviderDetailSection = {
        title: 'Quota services',
        rows: [{ label: 'chat', value: '1 / 2' }],
      };
      const mm = visibleDetails('minimax', [quota, billing], false, false);
      expect(mm.length).assertEqual(1);
      expect(mm[0].title).assertEqual('Quota services');
      expect(visibleDetails('minimax', [quota, billing], true, false).length).assertEqual(2);

      // 未声明策略的服务商：无论开关都保留
      expect(visibleDetails('openrouter', [usage], false, false).length).assertEqual(1);
    });

    it('MiniMax_billing_history_web', 0, () => {
      const now = Date.UTC(2026, 8, 22, 12, 0, 0);
      const page = minimaxBillingPage(parseJson('{"base_resp":{"status_code":0},"total_cnt":3,"charge_records":[' +
        '{"consume_token":120,"consume_cash":"0.5","created_at":1789900000,"method":"chat","model":"abab6.5","result":"SUCCESS"},' +
        '{"consume_input_token":10,"consume_output_token":20,"consume_cash":"0.2","created_at":1789900001,"method":"chat","model":"abab6.5","result":"SUCCESS"},' +
        '{"consume_token":5,"created_at":1789900002,"method":"chat","model":"abab6.5","result":"FAILED"}]}'));
      expect(page != null).assertTrue();
      expect(page!.totalCount).assertEqual(3);
      expect(page!.records.length).assertEqual(3);
      // consume_token 优先，缺失时用 input+output；金额取 consume_cash
      expect(page!.records[0].tokens).assertEqual(120);
      expect(page!.records[1].tokens).assertEqual(30);
      expect(page!.records[0].cash).assertEqual(0.5);

      // status_code 非 0 视为失败
      expect(minimaxBillingPage(parseJson('{"base_resp":{"status_code":1004},"charge_records":[]}')))
        .assertEqual(null);

      // 非 SUCCESS 记录不参与聚合；金额求和；Top model/method 取前三
      const summary = minimaxAggregate(page!.records, 1789900001000);
      expect(summary.todayTokens).assertEqual(150);
      expect(summary.last30DaysTokens).assertEqual(150);
      expect(summary.todayCash).assertEqual(0.7);
      expect(summary.topModels.length).assertEqual(1);
      expect(summary.topModels[0].name).assertEqual('abab6.5');
      expect(summary.topMethods[0].name).assertEqual('chat');
      expect(minimaxCash(summary.last30DaysCash!)).assertEqual('0.70');

      // 超过 30 天的记录被丢弃，并可作为分页停止条件
      const old = new MiniMaxBillingRecord();
      old.tokens = 999;
      old.createdAtMs = 1789900001000 - 40 * 86400000;
      old.result = 'SUCCESS';
      expect(minimaxHasRecordBeforeWindow([old], 1789900001000)).assertTrue();
      expect(minimaxAggregate([old], 1789900001000).last30DaysTokens).assertEqual(0);

      // ymd / consume_time 也能定位日期（created_at 缺失时）：ymd 按本地零点解释
      const local = new Date(1789900001000);
      const m = local.getMonth() + 1;
      const d = local.getDate();
      const byYmd = new MiniMaxBillingRecord();
      byYmd.tokens = 7;
      byYmd.ymd = `${local.getFullYear()}-${m < 10 ? '0' : ''}${m}-${d < 10 ? '0' : ''}${d}`;
      expect(minimaxAggregate([byYmd], 1789900001000).todayTokens).assertEqual(7);
    });

    it('DeepSeek_platform_usage_by_api_key', 0, () => {
      const now = Date.UTC(2026, 8, 22, 12, 0, 0);
      const startSec = Math.floor(now / 1000) - 86400;
      const endSec = Math.floor(now / 1000) + 86400;
      const amount = parseJson('{"code":0,"data":{"biz_code":0,"biz_data":{"series":[' +
        '{"api_key":{"tracking_id":"key-a"},"model":"deepseek-chat","buckets":[' +
        '{"time":' + Math.floor(now / 1000) + ',"usage":{"PROMPT_CACHE_HIT_TOKEN":"100","PROMPT_CACHE_MISS_TOKEN":"50","RESPONSE_TOKEN":"25","REQUEST":"3"}}]}]}}}');
      const cost = parseJson('{"code":0,"data":{"biz_code":0,"biz_data":{"data":[' +
        '{"currency":"USD","series":[{"api_key":"key-a","model":"deepseek-chat","buckets":[' +
        '{"time":' + Math.floor(now / 1000) + ',"cost":{"value":"0.25"}}]}]}]}}}');
      const usage = deepseekPlatformUsage(amount, cost, now, startSec, endSec);
      expect(usage != null).assertTrue();
      expect(usage!.todayTokens).assertEqual(175);
      expect(usage!.periodTokens).assertEqual(175);
      expect(usage!.todayRequests).assertEqual(3);
      expect(usage!.periodCost).assertEqual(0.25);
      expect(usage!.topModel).assertEqual('deepseek-chat');
      expect(usage!.apiKeyCount).assertEqual(1);
      expect(usage!.currency).assertEqual('USD');

      // 明细分组：Usage + Spend（对照 detailSections），两组都带每日图表
      const sections = deepseekDetailSections(usage!);
      expect(sections.length).assertEqual(2);
      expect(sections[0].title).assertEqual('Usage');
      expect(sections[1].title).assertEqual('Spend');
      expect(sections[0].chart != null).assertTrue();
      expect(sections[0].chart!.title).assertEqual('Daily tokens');
      expect(sections[0].chart!.unit).assertEqual('tokens');
      expect(sections[0].chart!.kind).assertEqual('bars');
      expect(sections[0].chart!.points.length).assertEqual(1);
      expect(sections[0].chart!.points[0].value).assertEqual(175);
      expect(sections[1].chart != null).assertTrue();
      expect(sections[1].chart!.title).assertEqual('Daily cost');
      expect(sections[1].chart!.unit).assertEqual('USD');
      expect(sections[1].chart!.points[0].value).assertEqual(0.25);
      // 无花费（全 0 / 缺失）时不画「Daily cost」，只留花费行
      const noCost = deepseekPlatformUsage(amount, parseJson('{"code":0,"data":{"biz_code":0}}'),
        now, startSec, endSec);
      const noCostSections = deepseekDetailSections(noCost!);
      expect(noCostSections.length).assertEqual(1);
      expect(noCostSections[0].chart!.title).assertEqual('Daily tokens');
      expect(sections[0].rows[0].label).assertEqual('Today');
      expect(sections[1].rows[0].value).assertEqual('$0.2500');
      // 按币种取符号，CNY → ¥
      expect(deepseekCostText(1.5, 'CNY')).assertEqual('¥1.5000');

      // 周期标签按 period 取：by-key 路径是近 30 天
      expect(usage!.period).assertEqual('last30Days');
      expect(sections[0].rows[1].label).assertEqual('Last 30 days');
      // 今日无花费 → 显示 —（对照 Swift 的 cost 闭包对 nil 的处理）
      const noCostToday = deepseekPlatformUsage(amount,
        parseJson('{"code":0,"data":{"biz_code":0,"biz_data":{"data":[]}}}'),
        now, startSec, endSec);
      expect(deepseekDetailSections(noCostToday!)[0].rows[0].value.indexOf('—') === 0).assertTrue();

      // 桶时间落在窗口外 / 鉴权错误码 → 返回 null
      const outside = deepseekPlatformUsage(amount, cost, now, endSec, endSec + 86400);
      expect(outside!.periodTokens).assertEqual(0);
      const auth = deepseekPlatformUsage(
        parseJson('{"code":40003,"data":{"biz_data":{"series":[]}}}'), cost, now, startSec, endSec);
      expect(auth).assertEqual(null);

      // 千分位计数
      expect(deepseekCountText(1234567)).assertEqual('1,234,567');
      expect(deepseekCountText(999)).assertEqual('999');
    });

    it('DeepSeek_monthly_fallback', 0, () => {
      // 账户级月度路径（对照 DeepSeekUsageCostParser.parse）：amount 是 { total, days }，cost 是币种数组
      const now = Date.UTC(2026, 4, 26, 12, 0, 0); // 2026-05-26 12:00 UTC
      const monthStart = Date.UTC(2026, 4, 1, 0, 0, 0);
      const today = '2026-05-26';
      const amounts = parseJson('{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":{' +
        '"total":[{"model":"deepseek-v4-flash","usage":[' +
        '{"type":"PROMPT_CACHE_HIT_TOKEN","amount":"100686720"},' +
        '{"type":"PROMPT_CACHE_MISS_TOKEN","amount":"1305432"},' +
        '{"type":"RESPONSE_TOKEN","amount":"656338"},' +
        '{"type":"REQUEST","amount":"1212"}]}],' +
        '"days":[{"date":"2026-05-26","data":[{"model":"deepseek-v4-flash","usage":[' +
        '{"type":"PROMPT_CACHE_HIT_TOKEN","amount":"100686720"},' +
        '{"type":"PROMPT_CACHE_MISS_TOKEN","amount":"1305432"},' +
        '{"type":"RESPONSE_TOKEN","amount":"656338"},' +
        '{"type":"REQUEST","amount":"1212"}]}]},' +
        '{"date":"2026-04-20","data":[{"model":"deepseek-v4-flash","usage":[' +
        '{"type":"RESPONSE_TOKEN","amount":"999999"}]}]}]}}}');
      const costs = parseJson('{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":[{' +
        '"currency":"CNY","total":[{"model":"deepseek-v4-flash","usage":[' +
        '{"type":"PROMPT_CACHE_HIT_TOKEN","amount":"2.0137344000000000"},' +
        '{"type":"RESPONSE_TOKEN","amount":"1.3126760000000000"},' +
        '{"type":"REQUEST","amount":"0"}]}],' +
        '"days":[{"date":"2026-05-26","data":[{"model":"deepseek-v4-flash","usage":[' +
        '{"type":"PROMPT_CACHE_HIT_TOKEN","amount":"2.0137344000000000"},' +
        '{"type":"RESPONSE_TOKEN","amount":"1.3126760000000000"}]}]}]}]}}');

      const usage = deepseekMonthlyUsage(amounts, costs, now, monthStart);
      expect(usage != null).assertTrue();
      expect(usage!.period).assertEqual('currentMonth');
      expect(usage!.currency).assertEqual('CNY');
      expect(usage!.apiKeyCount).assertEqual(0);
      // 上个月（04-20）的记录被本月窗口过滤掉
      expect(usage!.daily.length).assertEqual(1);
      expect(usage!.daily[0].date).assertEqual(today);
      expect(usage!.todayTokens).assertEqual(100686720 + 1305432 + 656338);
      expect(usage!.todayRequests).assertEqual(1212);
      expect(usage!.periodTokens).assertEqual(usage!.todayTokens);
      expect(usage!.periodRequests).assertEqual(1212);
      expect(usage!.todayCost).assertEqual(2.0137344 + 1.312676);
      expect(usage!.periodCost).assertEqual(2.0137344 + 1.312676);
      expect(usage!.topModel).assertEqual('deepseek-v4-flash');
      expect(usage!.modelCosts.length).assertEqual(1);
      expect(usage!.modelCosts[0].model).assertEqual('deepseek-v4-flash');

      // 明细行：周期标签换成「本月」，图表照旧（Daily tokens + Daily cost）
      const sections = deepseekDetailSections(usage!);
      expect(sections.length).assertEqual(2);
      expect(sections[0].rows[1].label).assertEqual('This month');
      expect(sections[0].chart!.title).assertEqual('Daily tokens');
      expect(sections[0].chart!.points[0].label).assertEqual(today);
      expect(sections[1].chart!.title).assertEqual('Daily cost');
      expect(sections[1].chart!.unit).assertEqual('CNY');

      // 无 cost 数据 → 花费显示 —且不画花费图（对照 monthResult.cost 为 nil）
      const noCost = deepseekMonthlyUsage(amounts,
        parseJson('{"code":0,"data":{"biz_code":0,"biz_data":[]}}'), now, monthStart);
      expect(noCost!.periodCost).assertEqual(null);
      const noCostSections = deepseekDetailSections(noCost!);
      expect(noCostSections[0].rows[1].value.indexOf('—') === 0).assertTrue();
      expect(noCostSections.length).assertEqual(1);

      // 模型花费出现坏值（未知类别 / 非数字金额）→ 该模型整体丢弃
      const badCost = parseJson('{"code":0,"data":{"biz_code":0,"biz_data":[{' +
        '"currency":"USD","total":[{"model":"m-good","usage":[{"type":"RESPONSE_TOKEN","amount":"1.5"}]},' +
        '{"model":"m-bad","usage":[{"type":"RESPONSE_TOKEN","amount":"oops"}]},' +
        '{"model":"m-unknown","usage":[{"type":"SOMETHING_ELSE","amount":"3"}]}],"days":[]}]}}');
      const badUsage = deepseekMonthlyUsage(amounts, badCost, now, monthStart);
      expect(badUsage!.currency).assertEqual('USD');
      expect(badUsage!.modelCosts.length).assertEqual(1);
      expect(badUsage!.modelCosts[0].model).assertEqual('m-good');
      expect(badUsage!.modelCosts[0].cost).assertEqual(1.5);

      // 缺 biz_data / 鉴权错误码 → null
      expect(deepseekMonthlyUsage(parseJson('{"code":0,"data":{"biz_code":0}}'), costs, now, monthStart))
        .assertEqual(null);
      expect(deepseekMonthlyUsage(parseJson('{"code":40003,"data":null}'), costs, now, monthStart))
        .assertEqual(null);
    });

    it('OptionalDetails_replaced_rows', 0, () => {
      // 对照 OpenRouterProviderDescriptor 的 replacedDetailRows
      expect(replacedDetailRowsFor('openrouter', false)['Credits']).assertEqual(undefined);
      const replaced = replacedDetailRowsFor('openrouter', true);
      expect(replaced['Credits'].length).assertEqual(2);
      expect(replaced['API key'][0]).assertEqual('This month');

      // 费用卡可见时移除重复行；不可见时原样保留
      const credits: ProviderDetailSection = {
        title: 'Credits',
        rows: [
          { label: 'Remaining', value: '$5.00' },
          { label: 'Used', value: '$2.00' },
          { label: 'Total added', value: '$7.00' },
        ],
      };
      const keySection: ProviderDetailSection = {
        title: 'API key',
        rows: [
          { label: 'This month', value: '$1.00' },
          { label: 'Reset window', value: 'monthly' },
        ],
      };
      const filtered = visibleDetails('openrouter', [credits, keySection], true, true);
      expect(filtered.length).assertEqual(2);
      expect(filtered[0].rows.length).assertEqual(1);
      expect(filtered[0].rows[0].label).assertEqual('Total added');
      expect(filtered[1].rows.length).assertEqual(1);
      expect(filtered[1].rows[0].label).assertEqual('Reset window');

      // 三行全被移除的分组整体消失
      const onlyReplaced: ProviderDetailSection = {
        title: 'Credits',
        rows: [
          { label: 'Remaining', value: '$5.00' },
          { label: 'Used', value: '$2.00' },
        ],
      };
      expect(visibleDetails('openrouter', [onlyReplaced], true, true).length).assertEqual(0);
      expect(visibleDetails('openrouter', [onlyReplaced], true, false).length).assertEqual(1);

      // 行被费用卡吃光但带图表的分组要保留（对照源工程 chart 仍然渲染）
      const charted: ProviderDetailSection = {
        title: 'Credits',
        rows: [{ label: 'Remaining', value: '$5.00' }],
        chart: makeChart('Daily spend', 'USD', [{ label: '2026-09-01', value: 1 }]),
      };
      const kept = visibleDetails('openrouter', [charted], true, true);
      expect(kept.length).assertEqual(1);
      expect(kept[0].rows.length).assertEqual(0);
      expect(kept[0].chart != null).assertTrue();
    });

    it('Row_progress_bar', 0, () => {
      // 进度数值校验（对照 Row.Progress.init：分母必须 > 0，两个数都要有限）
      expect(rowProgress(3, 4)!.used).assertEqual(3);
      expect(rowProgress(3, 0)).assertEqual(undefined);
      expect(rowProgress(3, -1)).assertEqual(undefined);
      expect(rowProgress(NaN, 5)).assertEqual(undefined);
      expect(rowProgress(3, Infinity)).assertEqual(undefined);
      // 百分比不截断（超额计划），截断交给渲染层
      expect(progressPercent({ used: 3, total: 4 })).assertEqual(75);
      expect(progressPercent({ used: 150, total: 100 })).assertEqual(150);

      // 额度数字：千分位 + 最多两位小数、去掉尾随 0
      expect(Format.creditsNumber(1234.5)).assertEqual('1,234.5');
      expect(Format.creditsNumber(0)).assertEqual('0');
      expect(Format.creditsNumber(1000000)).assertEqual('1,000,000');
      expect(Format.creditsNumber(0.25)).assertEqual('0.25');
      expect(Format.creditsNumber(-2500)).assertEqual('-2,500');

      // 席位额度解析（对照 CopilotCreditEntitlementParser.parse）：只接受完整数字
      expect(copilotSeatEntitlement('')).assertEqual(undefined);
      expect(copilotSeatEntitlement('0')).assertEqual(undefined);
      expect(copilotSeatEntitlement('-5')).assertEqual(undefined);
      expect(copilotSeatEntitlement('abc')).assertEqual(undefined);
      expect(copilotSeatEntitlement('12abc')).assertEqual(undefined);
      expect(copilotSeatEntitlement('inf')).assertEqual(undefined);
      expect(copilotSeatEntitlement('1e999')).assertEqual(undefined);
      expect(copilotSeatEntitlement(' 1500 ')).assertEqual(1500);
      expect(copilotSeatEntitlement('2.5')).assertEqual(2.5);

      // Cred行：未填额度 → 纯数字无进度条；填了 → "used / total" + 进度条 + 重置副文本
      const now = 1780000000000;
      const plain = copilotCreditRows(1500, undefined, now);
      expect(plain.length).assertEqual(1);
      expect(plain[0].value).assertEqual('1,500');
      expect(plain[0].progress).assertEqual(undefined);
      expect(plain[0].secondary != null).assertTrue();
      const withSeat = copilotCreditRows(1500, 2000, now);
      expect(withSeat[0].value).assertEqual('1,500 / 2,000');
      expect(withSeat[0].progress!.used).assertEqual(1500);
      expect(withSeat[0].progress!.total).assertEqual(2000);
      expect(progressPercent(withSeat[0].progress!)).assertEqual(75);
      // 无重置时间时不给副文本
      expect(copilotCreditRows(1, 4, 0)[0].secondary).assertEqual(undefined);

      // 缓存往返：合法进度保留，非法进度（分母 0 / 非数字）丢弃
      const snap = UsageSnapshot.success(makeWindow(10, 0, true), null, null);
      snap.details = [{
        title: 'Credits',
        rows: [
          { label: 'Credits used', value: '1,500 / 2,000', progress: { used: 1500, total: 2000 } },
          { label: 'Bad', value: 'x', progress: { used: 1, total: 0 } },
        ],
      }];
      const restored = UsageSnapshot.fromStored(JSON.stringify(snap));
      expect(restored!.details[0].rows[0].progress!.total).assertEqual(2000);
      expect(restored!.details[0].rows[1].progress).assertEqual(undefined);
      // 过滤不破坏进度条（行原样带过去）
      const kept = visibleDetails('copilot', restored!.details, true, false);
      expect(kept[0].rows[0].progress!.used).assertEqual(1500);
    });

    it('Detail_chart_pipeline', 0, () => {
      // makeChart：裁到 120 点，丢掉 NaN/Infinity
      const many: ProviderChartPoint[] = [];
      for (let i = 0; i < 140; i++) {
        many.push({ label: `d${i}`, value: i });
      }
      const truncated = makeChart('Daily tokens', 'tokens', many);
      expect(truncated.points.length).assertEqual(120);
      expect(truncated.kind).assertEqual('bars');
      const dirty = makeChart('x', 'y', [{ label: 'a', value: NaN }, { label: 'b', value: 2 }]);
      expect(dirty.points.length).assertEqual(1);
      expect(dirty.points[0].label).assertEqual('b');
      // 折线类型与单位/标题原样保留
      const line = makeChart('Daily cost', 'USD', [{ label: 'a', value: 1 }], 'line');
      expect(line.kind).assertEqual('line');
      expect(line.unit).assertEqual('USD');

      // 缓存往返：图表保留；损坏的图表/分组在入口被丢弃（避免 UI 读 undefined）
      const snap = UsageSnapshot.success(makeWindow(10, 0, true), null, null);
      snap.details = [{
        title: 'Credit history',
        rows: [{ label: 'Today', value: '4' }],
        chart: makeChart('Daily credits', 'credits', [{ label: '2026-09-22', value: 4 }]),
      }];
      const restored = UsageSnapshot.fromStored(JSON.stringify(snap));
      expect(restored != null).assertTrue();
      expect(restored!.details.length).assertEqual(1);
      expect(restored!.details[0].chart != null).assertTrue();
      expect(restored!.details[0].chart!.points.length).assertEqual(1);
      expect(restored!.details[0].chart!.points[0].value).assertEqual(4);
      expect(restored!.details[0].chart!.unit).assertEqual('credits');

      // 旧缓存没有 chart 字段 → 无图表且不崩
      const legacy = UsageSnapshot.fromStored(
        '{"ok":true,"details":[{"title":"Usage","rows":[{"label":"Today","value":"1"}]}]}');
      expect(legacy!.details.length).assertEqual(1);
      expect(legacy!.details[0].chart).assertEqual(undefined);
      // points 不是数组 / 分组缺 title / 行缺字段 → 丢弃
      const broken = UsageSnapshot.fromStored('{"ok":true,"details":[' +
        '{"title":"A","rows":[],"chart":{"kind":"bars","points":"nope"}},' +
        '{"rows":[{"label":"x","value":"1"}]},' +
        '{"title":"C","rows":[{"label":1},{"label":"ok","value":"2"}]}]}');
      expect(broken!.details.length).assertEqual(1);
      expect(broken!.details[0].title).assertEqual('C');
      expect(broken!.details[0].rows.length).assertEqual(1);
      expect(broken!.details[0].chart).assertEqual(undefined);
    });
  });
}
