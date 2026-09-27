import { describe, it, expect } from '@ohos/hypium';
import { Format } from '../main/ets/common/Format';
import { extractDeepSeekTokenCandidates, extractDeepSeekUserToken } from '../main/ets/common/OAuth';
import { Theme } from '../main/ets/common/Theme';
import { parseJson, asObj, asArray, str, num, optNum, optStr, Json } from '../main/ets/net/Json';
import { makeWindow, UsageSnapshot, RateWindow, ProviderDescriptor, ProviderDetailSection, ProviderSetting,
  ProviderState, AuthKind, applyWindowLabels, bindingQuotaLanesFor, bindingQuotaProjection, creditsHintFor, defaultReminder,
  extraFields, extraValue, isDefaultEnabledProvider, isPrimaryProvider, isWidgetSelectable, makeChart, MONTHLY_WINDOW_MINUTES,
  needsSecondCredential, optionalDetailsFor, parseExtra, pct, primaryDisplayWindow,
  progressPercent, ProviderCostSnapshot, replacedDetailRowsFor, rowProgress, setExtraValue, supportsCredits,
  visibleDetails, WEEKLY_WINDOW_MINUTES, widgetHeroLane, windowLabelsFor
} from '../main/ets/model/Models';
import { parseDetailParam, DetailRouteParam } from '../main/ets/common/Nav';
import { chutesWindow, manusLanes, perplexityLanes, perplexityPools } from '../main/ets/providers/MoreProviders';
import { nousLane } from '../main/ets/providers/MoreProviders3';
import { deepseekCostText, deepseekCountText, deepseekDetailSections, deepseekMonthlyUsage,
  deepseekPlatformUsage, siliconflowErrorText, siliconflowCnErrorText, SILICONFLOW_HOSTS } from '../main/ets/providers/ApiKeyProviders';
import { HttpResult } from '../main/ets/net/Http';
import { copilotCreditRows, copilotSeatEntitlement } from '../main/ets/providers/ApiKeyProviders2';
import {
  minimaxAggregate,
  minimaxBillingPage,
  minimaxCash,
  minimaxHasRecordBeforeWindow,
  MiniMaxBillingRecord,
  t3chatFindCustomerData,
  zaiDisambiguateWindowTitles,
  zaiLimitWindow
} from '../main/ets/providers/MoreProviders2';
import {
  elevenLabsLoginMethod,
  elevenLabsSlotWindows,
  ElevenLabsSlot,
  neuralWattQuota,
  neuralWattWindows,
  sub2APIWindows,
  titleCaseWords,
  commandCodeCookieHeader,
  commandCodeIsApiKey,
  commandCodeMonthlyWindow,
  commandCodeNormalize,
  commandCodePlanFor,
  commandCodeUSD,
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
  cursorGrokBotWindow,
  cursorParseDailyUsage,
  cursorParseMembers,
  cursorParseRequestQuota,
  cursorParseSummary,
  cursorPlanName,
} from '../main/ets/providers/CursorProvider';
import {
  claudeExtraRateWindows,
  claudeExtraUsageCost,
  claudeIsAllModelsScope,
  claudeOverageSpendLimitCost,
  claudePrepaidBalanceCost,
  claudeSlug,
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
import { buildWidgetItems, parseWidgetSelection, widgetDisplayedIds, WidgetDataStore } from '../main/ets/store/WidgetData';
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
  bedrockDailyCostList,
  bedrockDailyRange,
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
  doubaoProbeSnapshot,
  doubaoQuotasFromAgentPlan,
  doubaoQuotasFromCodingPlan,
  doubaoSignedSnapshot,
} from '../main/ets/providers/DoubaoProvider';

/** 构造只带一个主窗口的服务商状态（提醒测试用）；id 默认 test，卡片挑选测试需要区分服务商时显式传入 */
function stateWith(
  primary: RateWindow,
  title: string = '测试',
  enabled: boolean = true,
  id: string = 'test'
): ProviderState {
  const d: ProviderDescriptor = {
    id: id, title: title, authKind: AuthKind.SESSION,
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

    // 颜色本身已是资源引用（无法在宿主单测里比较），因此断言分级与品牌色兜底这两层纯逻辑
    it('Theme_barColor_thresholds', 0, () => {
      expect(Theme.barLevel(10, true)).assertEqual('ok');
      expect(Theme.barLevel(69.9, true)).assertEqual('ok');
      expect(Theme.barLevel(70, true)).assertEqual('warn');
      expect(Theme.barLevel(89.9, true)).assertEqual('warn');
      expect(Theme.barLevel(90, true)).assertEqual('danger');
      expect(Theme.barLevel(95, false)).assertEqual('unknown');
    });

    it('Theme_brand_tint_fallback', 0, () => {
      // 近白 / 近黑 / 非 hex 一律回落到当前模式的主色（AppStorage 缺失时按暗色）
      const fallback = '#16D3B4';
      expect(Theme.brandTint('#FFFFFF')).assertEqual(fallback);
      expect(Theme.brandTint('#000000')).assertEqual(fallback);
      expect(Theme.brandTint('accent')).assertEqual(fallback);
      expect(Theme.brandTint('#FDFDFD')).assertEqual(fallback);
      expect(Theme.brandTint('#0A0A0A')).assertEqual(fallback);
      // 中间调品牌色原样保留
      expect(Theme.brandTint('#6366F1')).assertEqual('#6366F1');
      expect(Theme.brandTint('#0EA5E9')).assertEqual('#0EA5E9');
    });

    // 字号 / 间距 / 半径刻度：页面统一引用这些常量，不允许再出现插队值
    it('Theme_scale_ladder', 0, () => {
      expect(Theme.fsTitle > Theme.fsHead).assertTrue();
      expect(Theme.fsHead > Theme.fsHeading).assertTrue();
      expect(Theme.fsHeading > Theme.fsName).assertTrue();
      expect(Theme.fsName > Theme.fsLabel).assertTrue();
      expect(Theme.fsLabel > Theme.fsBody).assertTrue();
      expect(Theme.fsBody > Theme.fsCaption).assertTrue();
      expect(Theme.fsCaption > Theme.fsMicro).assertTrue();
      expect(Theme.fsMicro > Theme.fsAxis).assertTrue();
      // 金额与图标字形各自独立于正文阶梯（大字号展示位）
      expect(Theme.fsMetric > Theme.fsTitle).assertTrue();
      expect(Theme.fsMetricSm > Theme.fsHeading).assertTrue();
      expect(Theme.fsEmojiLg > Theme.fsMetric).assertTrue();

      // 间距：贴紧 < 极小 < 紧凑 < 行内 < 卡片间 < 卡片内边距 < 页面边距 < 区块 < 页面底部
      expect(Theme.gapXxs < Theme.gapXs).assertTrue();
      expect(Theme.gapXs < Theme.gapSm).assertTrue();
      expect(Theme.gapSm < Theme.rowGap).assertTrue();
      expect(Theme.rowGap < Theme.gap).assertTrue();
      expect(Theme.gap < Theme.cardPad).assertTrue();
      expect(Theme.cardPad < Theme.pad).assertTrue();
      expect(Theme.pad < Theme.gapLg).assertTrue();
      expect(Theme.gapLg < Theme.padBottom).assertTrue();

      // 半径：卡片 > 图标按钮 > 输入框 > 标签 chip
      expect(Theme.radius > Theme.radiusBtn).assertTrue();
      expect(Theme.radiusBtn > Theme.radiusInput).assertTrue();
      expect(Theme.radiusInput > Theme.radiusChip).assertTrue();

      // 卡片阴影半径非负；暗色下为 0（层级交给描边，深底上的黑投影不可见）
      expect(Theme.cardShadowRadius() >= 0).assertTrue();
      expect(Theme.cardShadow().radius).assertEqual(Theme.cardShadowRadius());
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

    it('Zai_duplicate_window_titles', 0, () => {
      // 两个 TOKENS_LIMIT（5 小时 + 30 天）原本同名「Token 配额」→ 追加时长区分
      const five: Record<string, Object> = JSON.parse(
        '{"type":"TOKENS_LIMIT","unit":5,"number":5,"percentage":30,"usage":1000,"remaining":700}'
      ) as Record<string, Object>;
      const month: Record<string, Object> = JSON.parse(
        '{"type":"TOKENS_LIMIT","unit":1,"number":30,"percentage":10,"usage":5000,"remaining":4500}'
      ) as Record<string, Object>;
      const w1 = zaiLimitWindow(five)!;
      const w2 = zaiLimitWindow(month)!;
      const w3 = zaiLimitWindow(JSON.parse(
        '{"type":"CREDIT_LIMIT","unit":1,"number":7,"percentage":20}') as Record<string, Object>)!;
      zaiDisambiguateWindowTitles([w1, w2, w3], ['5 小时', '30 天', '7 天']);
      expect(w1.title).assertEqual('Token 配额（5 小时）');
      expect(w2.title).assertEqual('Token 配额（30 天）');
      // 唯一标题不受影响
      expect(w3.title).assertEqual('Credit 配额');
      // 无时长信息的重复窗口保持原标题
      const w4 = zaiLimitWindow(five)!;
      const w5 = zaiLimitWindow(month)!;
      zaiDisambiguateWindowTitles([w4, w5], ['', '']);
      expect(w4.title).assertEqual('Token 配额');
      expect(w5.title).assertEqual('Token 配额');
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
        expect(hit.title.indexOf('测试') >= 0).assertTrue();
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
      const a = stateWith(makeWindow(42, now + 2 * 3600000, true), 'Alpha');      const rows = buildWidgetItems([a], now);
      expect(rows.length).assertEqual(1);
      expect(rows[0].name).assertEqual('Alpha');
      expect(rows[0].pct).assertEqual('42%');
      expect(rows[0].barPct).assertEqual(42);
      expect(rows[0].level).assertEqual('ok');
      expect(rows[0].cd.indexOf('2小时') >= 0).assertTrue();
      // 过滤：未启用 / 失败快照 / 无窗口
      const off = stateWith(makeWindow(10, 0, true), 'Off', false);
      const fail = stateWith(makeWindow(10, 0, true), 'Fail');
      fail.snapshot = UsageSnapshot.failure('x');
      const empty = stateWith(makeWindow(10, 0, true), 'Empty');
      empty.snapshot = UsageSnapshot.success(null, null, null);
      const rows2 = buildWidgetItems([off, fail, empty, a], now);
      expect(rows2.length).assertEqual(1);
      // 按用量降序（数据上限 8 条，不及上限时全部保留；鸿蒙卡片再自行截前 2 / 4 条）
      const many: ProviderState[] = [];
      for (let i = 0; i < 6; i++) {
        many.push(stateWith(makeWindow(10 + i * 10, 0, true), `P${i}`));
      }
      const rows3 = buildWidgetItems(many, now);
      expect(rows3.length).assertEqual(6);
      expect(rows3[0].name).assertEqual('P5');
      expect(rows3[3].name).assertEqual('P2');
      // 无主窗口回退次窗口；usageKnown=false 灰色；重置已过无倒计时
      const b = stateWith(makeWindow(1, 0, true), 'B');
      b.snapshot = UsageSnapshot.success(null, makeWindow(55, now - 60000, false), null);
      const rows4 = buildWidgetItems([b], now);
      expect(rows4.length).assertEqual(1);
      expect(rows4[0].pct).assertEqual('55%');
      expect(rows4[0].level).assertEqual('unknown');
      expect(rows4[0].cd).assertEqual('');
    });

    it('Widget_selection', 0, () => {
      const now = 1758000000000;
      const a = stateWith(makeWindow(42, 0, true), 'Alpha', true, 'alpha');
      const b = stateWith(makeWindow(90, 0, true), 'Beta', true, 'beta');
      const c = stateWith(makeWindow(10, 0, true), 'Gamma', true, 'gamma');
      const off = stateWith(makeWindow(70, 0, true), 'Delta', false, 'delta');
      const all: ProviderState[] = [a, b, c, off];
      // 自动模式（未挑选）：按用量降序
      const auto = buildWidgetItems(all, now);
      expect(auto.length).assertEqual(3);
      expect(auto[0].name).assertEqual('Beta');
      // 挑选模式：只取指定服务商，且顺序就是挑选顺序（用量高低不再重排）
      const picked = buildWidgetItems(all, now, ['gamma', 'alpha']);
      expect(picked.length).assertEqual(2);
      expect(picked[0].name).assertEqual('Gamma');
      expect(picked[1].name).assertEqual('Alpha');
      // 未启用的 / 不存在的 ID：跳过，不影响其余行
      const picked2 = buildWidgetItems(all, now, ['delta', 'nope', 'beta']);
      expect(picked2.length).assertEqual(1);
      expect(picked2[0].name).assertEqual('Beta');
      // 数据行上限 8 条：选了 10 家只出前 8（安卓组件可拉伸显示到 8 行，
      // 鸿蒙 2x2 / 2x4 卡再自行截前 2 / 4 条）
      const many: ProviderState[] = [];
      const ids: string[] = [];
      for (let i = 0; i < 10; i++) {
        ids.push(`p${i}`);
        many.push(stateWith(makeWindow(10 + i * 5, 0, true), `P${i}`, true, `p${i}`));
      }
      const clamped = buildWidgetItems(many, now, ids);
      expect(clamped.length).assertEqual(8);
      expect(clamped[0].name).assertEqual('P0');
      expect(clamped[7].name).assertEqual('P7');
      // 自动模式同样受上限约束（按用量降序后截断）
      expect(buildWidgetItems(many, now).length).assertEqual(8);
      // 清空选择（「恢复自动」）等价于自动模式
      expect(buildWidgetItems(all, now, []).length).assertEqual(auto.length);
    });

    it('Widget_displayed_ids', 0, () => {
      // 与 buildWidgetItems 同一挑选逻辑，返回 id 而不是行数据：
      // 自动模式按用量降序，挑选模式按用户顺序
      const now = 1758000000000;
      const a = stateWith(makeWindow(42, 0, true), 'Alpha', true, 'alpha');
      const b = stateWith(makeWindow(90, 0, true), 'Beta', true, 'beta');
      const fail = stateWith(makeWindow(70, 0, true), 'Fail', true, 'fail');
      fail.snapshot = UsageSnapshot.failure('x');
      const all: ProviderState[] = [a, b, fail];
      const auto = widgetDisplayedIds(all, []);
      expect(auto.length).assertEqual(2);
      expect(auto[0]).assertEqual('beta');
      expect(auto[1]).assertEqual('alpha');
      const picked = widgetDisplayedIds(all, ['alpha', 'beta']);
      expect(picked.length).assertEqual(2);
      expect(picked[0]).assertEqual('alpha');
      expect(picked[1]).assertEqual('beta');
      // 失败快照 / 不存在的 id 不会出现在刷新目标里
      const withFail = widgetDisplayedIds(all, ['fail', 'nope', 'beta']);
      expect(withFail.length).assertEqual(1);
      expect(withFail[0]).assertEqual('beta');
      // 自动模式同样受 8 条上限约束
      const many: ProviderState[] = [];
      const ids: string[] = [];
      for (let i = 0; i < 10; i++) {
        ids.push(`p${i}`);
        many.push(stateWith(makeWindow(10 + i * 5, 0, true), `P${i}`, true, `p${i}`));
      }
      expect(widgetDisplayedIds(many, ids).length).assertEqual(8);
      expect(widgetDisplayedIds(many, []).length).assertEqual(8);
    });

    it('Widget_selection_parse', 0, () => {
      // 损坏 / 非数组 / 空文本 → 自动模式（空数组）
      expect(parseWidgetSelection('').length).assertEqual(0);
      expect(parseWidgetSelection('{bad').length).assertEqual(0);
      expect(parseWidgetSelection('{"a":1}').length).assertEqual(0);
      // 去重 + 丢弃空串 / 非字符串项，保持原顺序
      const list = parseWidgetSelection('["claude","","codex","claude",123]');
      expect(list.length).assertEqual(2);
      expect(list[0]).assertEqual('claude');
      expect(list[1]).assertEqual('codex');
    });

    it('Widget_cross_platform_contract', 0, () => {
      // 安卓原生桌面组件（widget/WidgetData.java + WidgetRenderer.java）读的是同一个 JSON，
      // 这里守住跨端契约：字段名、数值范围、等级取值三者任一漂移，组件就会静默显示空态。
      // WidgetDataStore.update 内部取 Date.now()，因此这里用真实时钟构造重置时间
      const now = Date.now();
      const text = WidgetDataStore.update([stateWith(makeWindow(83, now + 7200000, true), 'Claude')]);
      expect(text.length > 0).assertTrue();
      const root = asObj(parseJson(text));
      expect(root != null).assertTrue();
      expect(typeof str(root, 'updatedAt')).assertEqual('string');
      expect(str(root, 'updatedAt').length > 0).assertTrue();

      const items = asArray(root!.items);
      expect(items != null).assertTrue();
      expect(items!.length).assertEqual(1);
      const row = asObj(items![0]);
      expect(row != null).assertTrue();
      // Java 侧读取的五个键：name / pct / barPct / level / cd
      expect(str(row, 'name')).assertEqual('Claude');
      expect(str(row, 'pct')).assertEqual('83%');
      expect(num(row, 'barPct')).assertEqual(83);
      expect(str(row, 'level')).assertEqual('warn');
      expect(str(row, 'cd').length > 0).assertTrue();
      // barPct 落在 0-100（Java 侧还会 clamp，但源头就该是合法的）
      const bar = num(row, 'barPct');
      expect(bar >= 0 && bar <= 100).assertTrue();
      // level 取值必须是 Java 侧 levelColor 映射覆盖的集合，否则组件会掉到默认灰
      const levels: string[] = ['ok', 'warn', 'danger', 'unknown'];
      expect(levels.indexOf(str(row, 'level')) >= 0).assertTrue();
      // 等级阈值同样要对得上（83 → warn / 95 → danger / 10 → ok）
      const dangerRow = asObj(asArray(asObj(parseJson(
        WidgetDataStore.update([stateWith(makeWindow(95, now, true), 'A')])))!.items)![0]);
      expect(str(dangerRow, 'level')).assertEqual('danger');
      const okRow = asObj(asArray(asObj(parseJson(
        WidgetDataStore.update([stateWith(makeWindow(10, now, true), 'B')])))!.items)![0]);
      expect(str(okRow, 'level')).assertEqual('ok');

      // 跨端文件桥：未初始化沙箱目录时返回空串，调用方据此跳过落盘
      expect(WidgetDataStore.sandboxDir()).assertEqual('');
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

      // 成本历史日线：区间近 30 天整日；逐日解析只累加 Bedrock 分组、保留两位小数
      const dailyRange = bedrockDailyRange(now);
      expect(dailyRange.start).assertEqual('2026-08-24');
      expect(dailyRange.end).assertEqual('2026-09-23');
      const dailyJson = parseJson('{"ResultsByTime":[' +
        '{"TimePeriod":{"Start":"2026-09-21"},"Groups":[' +
        '{"Keys":["Amazon Bedrock"],"Metrics":{"UnblendedCost":{"Amount":"1.005"}}},' +
        '{"Keys":["Amazon EC2"],"Metrics":{"UnblendedCost":{"Amount":"8"}}}]},' +
        '{"TimePeriod":{"Start":"2026-09-22"},"Groups":[' +
        '{"Keys":["Bedrock"],"Metrics":{"UnblendedCost":{"Amount":"2.34"}}}]}],' +
        '"NextPageToken":"d-2"}');
      const daily = bedrockDailyCostList(dailyJson);
      expect(daily.length).assertEqual(2);
      expect(daily[0].date).assertEqual('2026-09-21');
      expect(daily[0].cost).assertEqual(1.01);
      expect(daily[1].cost).assertEqual(2.34);
      expect(bedrockDailyCostList(parseJson('{"ResultsByTime":[]}')).length).assertEqual(0);
      expect(bedrockDailyCostList(parseJson('{}')).length).assertEqual(0);

      // 展示映射：dailyPoints 非空时附加 Cost history 图表分节；为空 / null 时不出现
      const withDaily = bedrockSnapshot(20, 100, null, 'us-east-1', now,
        [{ label: '09-21', value: 1.01 }, { label: '09-22', value: 2.34 }]);
      expect(withDaily.details.length).assertEqual(2);
      expect(withDaily.details[1].title).assertEqual('Cost history');
      expect(withDaily.details[1].chart != null).assertTrue();
      expect(withDaily.details[1].chart!.points.length).assertEqual(2);
      expect(withDaily.details[1].chart!.points[0].value).assertEqual(1.01);
      expect(bedrockSnapshot(20, 100, null, 'us-east-1', now).details.length).assertEqual(1);
      expect(bedrockSnapshot(20, 100, null, 'us-east-1', now, []).details.length).assertEqual(1);
    });

    it('Widget_metadata_and_hero_lane', 0, () => {
      // widgetSelectable：false 名单不出现在桌面小组件（对照源工程 ProviderMetadata）
      expect(isWidgetSelectable('claude')).assertTrue();
      expect(isWidgetSelectable('codex')).assertTrue();
      expect(isWidgetSelectable('cursor')).assertTrue();
      expect(isWidgetSelectable('deepseek')).assertTrue();
      expect(isWidgetSelectable('openrouter')).assertTrue();
      expect(isWidgetSelectable('kimi-coding')).assertTrue();
      expect(isWidgetSelectable('doubao')).assertFalse();
      expect(isWidgetSelectable('xai')).assertFalse();
      expect(isWidgetSelectable('perplexity')).assertFalse();
      expect(isWidgetSelectable('commandcode')).assertFalse();
      expect(isWidgetSelectable('bedrock')).assertFalse();
      expect(isWidgetSelectable('moonshot')).assertFalse();

      // supportsCredits / creditsHint（对照源工程 metadata）
      expect(supportsCredits('codex')).assertTrue();
      expect(supportsCredits('openrouter')).assertTrue();
      expect(supportsCredits('mimo')).assertTrue();
      expect(supportsCredits('zoommate')).assertTrue();
      expect(supportsCredits('amp')).assertTrue();
      expect(supportsCredits('codebuff')).assertTrue();
      expect(supportsCredits('commandcode')).assertTrue();
      expect(supportsCredits('claude')).assertFalse();
      expect(creditsHintFor('openrouter')).assertEqual('Credit balance from OpenRouter API');
      expect(creditsHintFor('claude')).assertEqual('');

      // hero 泳道（对照 WidgetTilePlan.bindingLane）：主 + 绑定泳道里剩余最少的一条
      const now = 1758000000000;
      // 无绑定泳道 / 无快照：沿用主泳道或 null，不标注窗口名
      expect(widgetHeroLane('groq', null)).assertEqual(null);
      const plain = UsageSnapshot.success(makeWindow(30, now, true), null, null);
      const plainHero = widgetHeroLane('groq', plain);
      expect(plainHero != null).assertTrue();
      expect(plainHero!.isPrimary).assertTrue();
      expect(plainHero!.label).assertEqual('');
      expect(plainHero!.window.usedPercent).assertEqual(30);
      // 主泳道更紧：hero = 主泳道（不换数字，不标注）
      const claudeTight = UsageSnapshot.success(makeWindow(90, now, true), makeWindow(40, now, true), null);
      applyWindowLabels(claudeTight, 'claude');
      const heroA = widgetHeroLane('claude', claudeTight);
      expect(heroA != null).assertTrue();
      expect(heroA!.isPrimary).assertTrue();
      expect(heroA!.label).assertEqual('');
      expect(heroA!.window.usedPercent).assertEqual(90);
      // 周泳道更紧：hero = Weekly，标注窗口名
      const claudeWeeklyTight = UsageSnapshot.success(makeWindow(20, now, true), makeWindow(96, now, true), null);
      applyWindowLabels(claudeWeeklyTight, 'claude');
      const heroB = widgetHeroLane('claude', claudeWeeklyTight);
      expect(heroB != null).assertTrue();
      expect(heroB!.isPrimary).assertFalse();
      expect(heroB!.label).assertEqual('Weekly');
      expect(heroB!.window.usedPercent).assertEqual(96);
      // 并列（都 100%）：主泳道优先（渲染端再套绑定投影给出闸门恢复时间）
      const claudeBothOut = UsageSnapshot.success(makeWindow(100, now, true), makeWindow(100, now, true), null);
      const heroC = widgetHeroLane('claude', claudeBothOut);
      expect(heroC != null).assertTrue();
      expect(heroC!.isPrimary).assertTrue();
      // usageKnown=false 的窗口不参与度量；三槽都在时取剩余最少的（月度窗）
      const doubao = UsageSnapshot.success(
        makeWindow(30, now, true), makeWindow(50, now, true), makeWindow(80, now, true));
      applyWindowLabels(doubao, 'doubao');
      const heroD = widgetHeroLane('doubao', doubao);
      expect(heroD != null).assertTrue();
      expect(heroD!.isPrimary).assertFalse();
      expect(heroD!.label).assertEqual('Monthly');
      expect(heroD!.window.usedPercent).assertEqual(80);
      const doubaoMonthly = UsageSnapshot.success(
        makeWindow(30, now, true), makeWindow(20, now, true), makeWindow(99, now, true));
      applyWindowLabels(doubaoMonthly, 'doubao');
      const heroE = widgetHeroLane('doubao', doubaoMonthly);
      expect(heroE != null).assertTrue();
      expect(heroE!.isPrimary).assertFalse();
      expect(heroE!.label).assertEqual('Monthly');
      expect(heroE!.window.usedPercent).assertEqual(99);
      const unknownLanes = UsageSnapshot.success(makeWindow(0, 0, false), makeWindow(0, 0, false), null);
      const heroF = widgetHeroLane('claude', unknownLanes);
      expect(heroF != null).assertTrue();
      expect(heroF!.isPrimary).assertTrue();
      // 主泳道缺失：回退次窗口 / 附加窗口，不标注
      const noPrimary = UsageSnapshot.success(null, makeWindow(55, now, true), null);
      const heroG = widgetHeroLane('groq', noPrimary);
      expect(heroG != null).assertTrue();
      expect(heroG!.isPrimary).assertFalse();
      expect(heroG!.label).assertEqual('');
      expect(heroG!.window.usedPercent).assertEqual(55);
      expect(widgetHeroLane('groq', UsageSnapshot.success(null, null, null))).assertEqual(null);

      // 卡片数据行：不可挑选的服务商不出现在自动与挑选两种模式里
      const pick = stateWith(makeWindow(42, 0, true), 'Doubao', true, 'doubao');
      expect(buildWidgetItems([pick], 1758000000000).length).assertEqual(0);
      expect(buildWidgetItems([pick], 1758000000000, ['doubao']).length).assertEqual(0);
      // hero 泳道接管卡片行：周泳道 96% 比主泳道 20% 更紧，卡片显示 96% + Weekly 标注
      const claudeState = stateWith(makeWindow(20, now + 3600000, true), 'Claude', true, 'claude');
      claudeState.snapshot = claudeWeeklyTight;
      const heroRows = buildWidgetItems([claudeState], now);
      expect(heroRows.length).assertEqual(1);
      expect(heroRows[0].pct).assertEqual('96%');
      expect(heroRows[0].lane).assertEqual('Weekly');
      // hero 为主泳道时不标注
      const claudeState2 = stateWith(makeWindow(90, now + 3600000, true), 'Claude', true, 'claude');
      claudeState2.snapshot = claudeTight;
      const heroRows2 = buildWidgetItems([claudeState2], now);
      expect(heroRows2.length).assertEqual(1);
      expect(heroRows2[0].pct).assertEqual('90%');
      expect(heroRows2[0].lane).assertEqual('');
    });

    it('Widget_balance_fallback_hero', 0, () => {
      // 余额回退（对照 macOS WidgetFallbackHero + providerBalance）：
      // 无配额泳道但快照成功的服务商不上 100% 误导条，也不整条消失——余额当大号数字
      const now = 1758000000000;

      // DeepSeek 型：无窗口、providerCost.displayText 即余额
      const deep = stateWith(makeWindow(0, 0, true), 'DeepSeek', true, 'deepseek');
      deep.snapshot = UsageSnapshot.success(null, null, null);
      deep.snapshot.providerCost = {
        remaining: 110, used: 0, currency: 'CNY', displayText: '¥110.00',
      };
      const deepRows = buildWidgetItems([deep], now);
      expect(deepRows.length).assertEqual(1);
      expect(deepRows[0].pct).assertEqual('¥110.00');
      expect(deepRows[0].lane).assertEqual('Balance');
      expect(deepRows[0].cd).assertEqual('');
      expect(deepRows[0].barPct).assertEqual(0);
      expect(deepRows[0].level).assertEqual('unknown');

      // OpenRouter 未设上限型：大号数字是花费、余额在 balanceText，回退取余额
      const or = stateWith(makeWindow(0, 0, true), 'OpenRouter', true, 'openrouter');
      or.snapshot = UsageSnapshot.success(null, null, null);
      or.snapshot.providerCost = {
        remaining: 0, used: 5, currency: 'USD', displayText: '$5.00',
        balanceText: '$12.34', period: 'This month (API key)', limit: 0,
      };
      const orRows = buildWidgetItems([or], now);
      expect(orRows.length).assertEqual(1);
      expect(orRows[0].pct).assertEqual('$12.34');
      expect(orRows[0].lane).assertEqual('Balance');

      // 无窗口且拿不到任何余额数字：仍然不上卡片
      const none = stateWith(makeWindow(0, 0, true), 'None', true, 'groq');
      none.snapshot = UsageSnapshot.success(null, null, null);
      expect(buildWidgetItems([none], now).length).assertEqual(0);
      const spendOnly = stateWith(makeWindow(0, 0, true), 'SpendOnly', true, 'groq');
      spendOnly.snapshot = UsageSnapshot.success(null, null, null);
      spendOnly.snapshot.providerCost = {
        remaining: 0, used: 5, currency: 'USD', displayText: '$5.00', limit: 0,
      };
      expect(buildWidgetItems([spendOnly], now).length).assertEqual(0);

      // 挑选模式同样受益：DeepSeek / OpenRouter 可挑选且出现在卡片行里
      const picked = buildWidgetItems([deep, or], now, ['openrouter', 'deepseek']);
      expect(picked.length).assertEqual(2);
      expect(picked[0].pct).assertEqual('$12.34');
      expect(picked[1].pct).assertEqual('¥110.00');

      // 有配额泳道的服务商不受回退影响：仍按百分比展示
      const capped = stateWith(makeWindow(35, now + 3600000, true), 'OpenRouter', true, 'openrouter');
      capped.snapshot = UsageSnapshot.success(makeWindow(35, now + 3600000, true), null, null);
      capped.snapshot.providerCost = {
        remaining: 12, used: 3, currency: 'USD', displayText: '$12.00', balanceText: '$12.00',
      };
      const cappedRows = buildWidgetItems([capped], now);
      expect(cappedRows.length).assertEqual(1);
      expect(cappedRows[0].pct).assertEqual('35%');
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
      // 对照 OpenRouterProviderDescriptor 的 costPresenter：逐条件判定，
      // 卡片只吃掉自己展示的那一行，否则余额会被静默吞掉
      const capCost: ProviderCostSnapshot = {
        remaining: 5, used: 2, currency: 'USD', displayText: '$2.00',
        period: 'This month (API key)', balanceText: '$5.00'
      };
      const keyCost: ProviderCostSnapshot = {
        remaining: 0, used: 2, currency: 'USD', displayText: '$2.00', period: 'Total key usage'
      };
      const accountCost: ProviderCostSnapshot = {
        remaining: 0, used: 2, currency: 'USD', displayText: '$2.00', period: 'Total account usage'
      };
      const plainCost: ProviderCostSnapshot = {
        remaining: 0, used: 2, currency: 'USD', displayText: '$2.00', period: 'Monthly cap'
      };

      // 费用卡不可见：不删任何行
      expect(replacedDetailRowsFor('openrouter', false)['Credits']).assertEqual(undefined);
      // 卡片没有余额行（周期为 Total key usage）：Credits 一行不动
      expect(replacedDetailRowsFor('openrouter', true, keyCost)['Credits']).assertEqual(undefined);
      // 卡片带余额行：只删 Credits 的 Remaining
      const withBalance = replacedDetailRowsFor('openrouter', true, capCost);
      expect(withBalance['Credits'].length).assertEqual(1);
      expect(withBalance['Credits'][0]).assertEqual('Remaining');
      expect(withBalance['API key'][0]).assertEqual('This month');
      // 卡片承载账户总用量：只删 Credits 的 Used
      const account = replacedDetailRowsFor('openrouter', true, accountCost);
      expect(account['Credits'].length).assertEqual(1);
      expect(account['Credits'][0]).assertEqual('Used');
      expect(account['API key']).assertEqual(undefined);
      // 其他服务商不受影响
      expect(replacedDetailRowsFor('claude', true, plainCost)['Credits']).assertEqual(undefined);

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
      const filtered = visibleDetails('openrouter', [credits, keySection], true, true, capCost);
      expect(filtered.length).assertEqual(2);
      expect(filtered[0].rows.length).assertEqual(2);
      expect(filtered[0].rows[0].label).assertEqual('Used');
      expect(filtered[0].rows[1].label).assertEqual('Total added');
      expect(filtered[1].rows.length).assertEqual(1);
      expect(filtered[1].rows[0].label).assertEqual('Reset window');

      // 卡片没带余额行时，Credits 三行原样保留（余额不被吃掉）
      const noBalance = visibleDetails('openrouter', [credits], true, true, keyCost);
      expect(noBalance.length).assertEqual(1);
      expect(noBalance[0].rows.length).assertEqual(3);

      // 卡片把两行都吃掉的分组整体消失
      const onlyReplaced: ProviderDetailSection = {
        title: 'Credits',
        rows: [
          { label: 'Remaining', value: '$5.00' },
          { label: 'Used', value: '$2.00' },
        ],
      };
      const bothCost: ProviderCostSnapshot = {
        remaining: 5, used: 2, currency: 'USD', displayText: '$2.00',
        period: 'Total account usage', balanceText: '$5.00'
      };
      expect(visibleDetails('openrouter', [onlyReplaced], true, true, bothCost).length).assertEqual(0);
      expect(visibleDetails('openrouter', [onlyReplaced], true, false).length).assertEqual(1);

      // 行被费用卡吃光但带图表的分组要保留（对照源工程 chart 仍然渲染）
      const charted: ProviderDetailSection = {
        title: 'Credits',
        rows: [{ label: 'Remaining', value: '$5.00' }],
        chart: makeChart('Daily spend', 'USD', [{ label: '2026-09-01', value: 1 }]),
      };
      const kept = visibleDetails('openrouter', [charted], true, true, capCost);
      expect(kept.length).assertEqual(1);
      expect(kept[0].rows.length).assertEqual(0);
      expect(kept[0].chart != null).assertTrue();
    });

    it('Cursor_provider', 0, () => {
      // 计划名映射（对照 formatMembershipType）
      expect(cursorPlanName('pro')).assertEqual('Cursor Pro');
      expect(cursorPlanName('free_trial')).assertEqual('Cursor Pro Trial');
      expect(cursorPlanName('enterprise')).assertEqual('Cursor Enterprise');
      expect(cursorPlanName('mystery')).assertEqual('Cursor mystery');
      expect(cursorPlanName(null)).assertEqual('Cursor');
      // 窗口标签（对照 CursorProviderDescriptor 的 session/weekly/opusLabel）
      const labels = windowLabelsFor('cursor');
      expect(labels.primary).assertEqual('Total');
      expect(labels.secondary).assertEqual('Cursor');
      expect(labels.tertiary).assertEqual('Third Party');

      // 顶层百分比优先
      const total = cursorParseSummary(parseJson(
        '{"membershipType":"pro","billingCycleEnd":"2026-09-30T00:00:00.000Z",' +
        '"individualUsage":{"plan":{"used":2000,"limit":2000,"totalPercentUsed":42.5}}}'));
      expect(total != null).assertTrue();
      expect(total!.headlinePercent()).assertEqual(42.5);
      expect(total!.membershipType).assertEqual('pro');

      // 无顶层百分比：Auto 与 API 取均值
      const avg = cursorParseSummary(parseJson(
        '{"individualUsage":{"plan":{"autoPercentUsed":30,"apiPercentUsed":50}}}'));
      expect(avg!.headlinePercent()).assertEqual(40);
      // 只有 API 百分比
      expect(cursorParseSummary(parseJson(
        '{"individualUsage":{"plan":{"apiPercentUsed":12}}}'))!.headlinePercent()).assertEqual(12);
      // 退到分 / 上限
      expect(cursorParseSummary(parseJson(
        '{"individualUsage":{"plan":{"used":1000,"limit":4000}}}'))!.headlinePercent()).assertEqual(25);
      // 再退到 individualUsage.overall，最后到 teamUsage.pooled
      const overallPct = cursorParseSummary(parseJson(
        '{"individualUsage":{"overall":{"used":7384,"limit":10000}}}'))!.headlinePercent();
      expect(Math.round(overallPct * 100) / 100).assertEqual(73.84);
      expect(cursorParseSummary(parseJson(
        '{"teamUsage":{"pooled":{"used":50,"limit":200}}}'))!.headlinePercent()).assertEqual(25);
      // 什么都缺：0
      expect(cursorParseSummary(parseJson('{}'))!.headlinePercent()).assertEqual(0);
      expect(cursorParseSummary(null)).assertEqual(null);

      // 旧版按请求数计划：maxRequestUsage 必须 > 0
      const quota = cursorParseRequestQuota(parseJson(
        '{"gpt-4":{"numRequestsTotal":120,"maxRequestUsage":500}}'));
      expect(quota != null).assertTrue();
      expect(quota!.used).assertEqual(120);
      expect(quota!.limit).assertEqual(500);
      expect(quota!.usedPercent()).assertEqual(24);
      expect(cursorParseRequestQuota(parseJson('{"gpt-4":{"numRequests":3}}'))).assertEqual(null);
      expect(cursorParseRequestQuota(parseJson('{"startOfMonth":"2026-09-01"}'))).assertEqual(null);

      // Grok Bot：有额度才出窗口；试用未过期但无额度时按试用到期处理
      const now = 1758000000000;
      const sand = cursorGrokBotWindow(parseJson(
        '{"usagePercent":63.2,"includedLimitZero":false,' +
        '"nextResetTimestampUtc":"2026-09-28T00:00:00.000Z"}'), now);
      expect(sand != null).assertTrue();
      expect(sand!.id).assertEqual('cursor-grok-bot');
      expect(sand!.title).assertEqual('Grok Bot');
      expect(sand!.window.usedPercent).assertEqual(63.2);
      expect(sand!.window.resetsAt).assertEqual(Date.parse('2026-09-28T00:00:00.000Z'));
      expect(cursorGrokBotWindow(parseJson('{"usagePercent":10,"includedLimitZero":true}'), now))
        .assertEqual(null);
      expect(cursorGrokBotWindow(parseJson('{"includedLimitZero":false}'), now)).assertEqual(null);

      // Admin API Key：成员花费与每日请求量解析（字段缺失记 0）
      const members = cursorParseMembers(parseJson(
        '{"teamMemberSpend":[{"email":"a@x.com","overallSpendCents":1250,' +
        '"monthlyLimitDollars":40},{"email":"b@x.com","spendCents":300}]}'));
      expect(members.length).assertEqual(2);
      expect(members[0].overallSpendCents).assertEqual(1250);
      expect(members[0].monthlyLimitDollars).assertEqual(40);
      // overallSpendCents 缺失时回落 spendCents
      expect(members[1].overallSpendCents).assertEqual(300);
      expect(members[1].monthlyLimitDollars).assertEqual(null);
      expect(cursorParseMembers(parseJson('{}')).length).assertEqual(0);

      const daily = cursorParseDailyUsage(parseJson(
        '{"data":[{"date":"2026-09-02","subscriptionIncludedReqs":10,"usageBasedReqs":2,' +
        '"apiKeyReqs":1},{"date":"2026-09-01","subscriptionIncludedReqs":4}]}'));
      expect(daily.length).assertEqual(2);
      expect(daily[0].date).assertEqual('2026-09-01'); // 升序
      expect(daily[0].total()).assertEqual(4);
      expect(daily[1].total()).assertEqual(13);
      // 缺 date 的行丢弃
      expect(cursorParseDailyUsage(parseJson('{"data":[{"subscriptionIncludedReqs":1}]}')).length)
        .assertEqual(0);
    });

    it('CommandCode_credential', 0, () => {
      // 规整：整段 Cookie 头 / Cookie: 前缀 / cURL 抓包 / 引号（对照 CookieHeaderNormalizer.normalize）
      expect(commandCodeNormalize('Cookie: a=1; b=2')).assertEqual('a=1; b=2');
      expect(commandCodeNormalize("  curl -H 'Cookie: __Secure-better-auth.session_token=abc; _ga=x' " +
        "-H 'accept: application/json' https://api.commandcode.ai/internal/billing/credits  "))
        .assertEqual('__Secure-better-auth.session_token=abc; _ga=x');
      expect(commandCodeNormalize("-b 'a=1; b=2'")).assertEqual('a=1; b=2');
      expect(commandCodeNormalize('--cookie "__Secure-better-auth.session_token=x"'))
        .assertEqual('__Secure-better-auth.session_token=x');
      // 首尾成对引号去掉
      expect(commandCodeNormalize("'a=1'")).assertEqual('a=1');
      expect(commandCodeNormalize('  __Secure-better-auth.session_token=abc  '))
        .assertEqual('__Secure-better-auth.session_token=abc');
      expect(commandCodeNormalize('')).assertEqual('');

      // 组装 Cookie 头（对照 CommandCodeCookieHeader.override）
      expect(commandCodeCookieHeader('_ga=GA1.2.123; __Secure-better-auth.session_token=abc123; foo=bar'))
        .assertEqual('__Secure-better-auth.session_token=abc123');
      expect(commandCodeCookieHeader('_ga=1; __Secure-commandcode_prod_.session_token=abc123'))
        .assertEqual('__Secure-commandcode_prod_.session_token=abc123');
      expect(commandCodeCookieHeader('better-auth.session_token=plain-token'))
        .assertEqual('better-auth.session_token=plain-token');
      // 裸令牌按生产会话 Cookie 名补齐（旧实现把它当 API Key 发 Bearer，必然 401）
      expect(commandCodeCookieHeader('bare-value'))
        .assertEqual('__Secure-better-auth.session_token=bare-value');
      // Cookie: 前缀 / cURL 抓包不再整串塞进 Cookie 头
      expect(commandCodeCookieHeader('Cookie: __Secure-better-auth.session_token=abc'))
        .assertEqual('__Secure-better-auth.session_token=abc');
      expect(commandCodeCookieHeader('')).assertEqual('');
      // 无已知会话 Cookie 名时整串照发（对照 importer 的「sending all domain cookies」）
      expect(commandCodeCookieHeader('foo=1; bar=2')).assertEqual('foo=1; bar=2');

      // API Key 判定：仅 user_ 前缀走 Bearer（官方 CLI 的 COMMAND_CODE_API_KEY）
      expect(commandCodeIsApiKey('user_abc123')).assertTrue();
      expect(commandCodeIsApiKey('bare-value')).assertFalse();
      expect(commandCodeIsApiKey('__Secure-better-auth.session_token=abc')).assertFalse();
      expect(commandCodeIsApiKey('user_a=b')).assertFalse();
      expect(commandCodeIsApiKey('')).assertFalse();

      // 窗口标签（对照 CommandCodeProviderDescriptor 的 session/weekly/opusLabel）
      const labels = windowLabelsFor('commandcode');
      expect(labels.primary).assertEqual('5-hour');
      expect(labels.secondary).assertEqual('Weekly');
      expect(labels.tertiary).assertEqual('Monthly');
    });

    it('CommandCode_plan_catalog', 0, () => {
      // 套餐目录（对照 CommandCodePlanCatalog.plans）
      expect(commandCodePlanFor('individual-go')!.monthlyCreditsUSD).assertEqual(10);
      expect(commandCodePlanFor('individual-go')!.displayName).assertEqual('Go');
      expect(commandCodePlanFor('individual-goat')!.monthlyCreditsUSD).assertEqual(70);
      expect(commandCodePlanFor('individual-pro')!.monthlyCreditsUSD).assertEqual(30);
      expect(commandCodePlanFor('individual-pro-v1')!.monthlyCreditsUSD).assertEqual(80);
      expect(commandCodePlanFor('individual-max')!.monthlyCreditsUSD).assertEqual(150);
      expect(commandCodePlanFor('individual-ultra')!.monthlyCreditsUSD).assertEqual(300);
      // 大小写不敏感；未登记的 planId 不得当成免费版
      expect(commandCodePlanFor('Individual-Max')!.monthlyCreditsUSD).assertEqual(150);
      expect(commandCodePlanFor('individual-future')).assertEqual(null);
      expect(commandCodePlanFor('')).assertEqual(null);
      expect(commandCodePlanFor(null)).assertEqual(null);

      // 美元文案（对照 formatUSD：< $100 两位小数，否则取整）
      expect(commandCodeUSD(10)).assertEqual('$10.00');
      expect(commandCodeUSD(3.2)).assertEqual('$3.20');
      expect(commandCodeUSD(150)).assertEqual('$150');

      const periodEnd = Date.parse('2026-10-01T00:00:00.000Z');
      // 有套餐：已用 = 总额 − 剩余，百分比按总额算
      const go = commandCodeMonthlyWindow(commandCodePlanFor('individual-go'), 6.4, 0, periodEnd, true);
      expect(go != null).assertTrue();
      expect(go!.usedPercent).assertEqual(36);
      expect(go!.resetsAt).assertEqual(periodEnd);
      // 剩余超过总额（预算内的已购额度）：截断到 0%
      expect(commandCodeMonthlyWindow(commandCodePlanFor('individual-go'), 25, 0, periodEnd, true)!
        .usedPercent).assertEqual(0);
      // 欠费透支：截断到 100%
      expect(commandCodeMonthlyWindow(commandCodePlanFor('individual-go'), -4, 0, periodEnd, true)!
        .usedPercent).assertEqual(100);

      // 免费版（订阅查询显式返回 null）：仍有余额时报 0%
      const free = commandCodeMonthlyWindow(null, 0, 5, periodEnd, true);
      expect(free != null).assertTrue();
      expect(free!.usedPercent).assertEqual(0);
      // 完全没额度：不出泳道
      expect(commandCodeMonthlyWindow(null, 0, 0, periodEnd, true)).assertEqual(null);

      // 订阅查询失败：总额不可知，宁可不出月度泳道（不得报 0% 假装未动用）
      expect(commandCodeMonthlyWindow(null, 7.5, 0, 0, false)).assertEqual(null);
      // 目录外 planId：同样不可定尺寸（fetch 里 freeTier 也为假）
      expect(commandCodeMonthlyWindow(commandCodePlanFor('individual-future'), 7.5, 0, 0, false))
        .assertEqual(null);
    });

    it('Balance_only_lane_catalog', 0, () => {
      // pct（对照插件运行时的 ctx.pct）：分母非正/非法一律 100%，其余截断到 [0, 100]
      expect(pct(50, 100)).assertEqual(50);
      expect(pct(0, 0)).assertEqual(100);
      expect(pct(5, -1)).assertEqual(100);
      expect(pct(5, NaN)).assertEqual(100);
      expect(pct(250, 100)).assertEqual(100);
      expect(pct(-5, 100)).assertEqual(0);

      // Manus（对照插件 manus.js）：月度套餐额度与刷新额度各一条泳道
      const nextRefresh = Date.parse('2026-10-01T00:00:00.000Z');
      const manus = manusLanes(1000, 400, 30, 100, nextRefresh);
      expect(manus.primary!.usedPercent).assertEqual(60);
      expect(manus.secondary!.usedPercent).assertEqual(70);
      expect(manus.secondary!.resetsAt).assertEqual(nextRefresh);
      // 分母为 0/缺失时不出泳道（不得报 0% 假装未动用）
      const noMonthly = manusLanes(0, 0, 30, 100, nextRefresh);
      expect(noMonthly.primary).assertEqual(null);
      expect(noMonthly.secondary != null).assertTrue();
      expect(manusLanes(1000, 400, 0, 0, 0).secondary).assertEqual(null);
      // 周期额度超过月度额度（跨期结算）时截断到 0%
      expect(manusLanes(100, 180, 0, 0, 0).primary!.usedPercent).assertEqual(0);

      // Nous（对照插件 nous.js）：月度授予是分母、剩余是分子，缺一不出泳道
      expect(nousLane(100, 25, nextRefresh)!.usedPercent).assertEqual(75);
      expect(nousLane(100, 25, nextRefresh)!.resetsAt).assertEqual(nextRefresh);
      expect(nousLane(100, 150, 0)!.usedPercent).assertEqual(0);
      expect(nousLane(null, 25, 0)).assertEqual(null);
      expect(nousLane(0, 25, 0)).assertEqual(null);
      expect(nousLane(100, null, 0)).assertEqual(null);

      // Perplexity（对照插件 perplexity.js）：分池 + 周期 → 已购 → 赠金 的扣减顺序
      const nowSec = 1780000000;
      const grants: Json[] = asArray(parseJson(`[
        {"type":"recurring","amount_cents":2000},
        {"type":"purchased","amount_cents":300},
        {"type":"promotional","amount_cents":500,"expires_at_ts":${nowSec + 3600}},
        {"type":"promotional","amount_cents":400,"expires_at_ts":${nowSec - 3600}}
      ]`))!;
      const pools = perplexityPools(grants, 1200, 1000, nowSec);
      expect(pools.recurring).assertEqual(2000);
      // 过期赠金不入分母
      expect(pools.promo).assertEqual(500);
      // 已购池取 grants 汇总与 current_period_purchased_cents 的较大值
      expect(pools.purchased).assertEqual(1000);
      expect(pools.recurringUsed).assertEqual(1200);
      expect(pools.purchasedUsed).assertEqual(0);
      expect(pools.promoUsed).assertEqual(0);
      expect(pools.promoExpiry).assertEqual(nowSec + 3600);
      // 周期池被吃满后溢出到已购池，再到赠金池
      const spill = perplexityPools(grants, 2400, 0, nowSec);
      expect(spill.recurringUsed).assertEqual(2000);
      expect(spill.purchasedUsed).assertEqual(300);
      expect(spill.promoUsed).assertEqual(100);

      const lanes = perplexityLanes(pools, nextRefresh);
      expect(lanes.primary!.usedPercent).assertEqual(60);
      expect(lanes.primary!.resetsAt).assertEqual(nextRefresh);
      expect(lanes.secondary!.usedPercent).assertEqual(0);
      expect(lanes.tertiary!.usedPercent).assertEqual(0);
      // 只有赠金/已购时不出主泳道（源工程同样没有主泳道）
      const paidOnlyGrants: Json[] = asArray(parseJson(`[
        {"type":"purchased","amount_cents":300},
        {"type":"promotional","amount_cents":500,"expires_at_ts":${nowSec + 3600}}
      ]`))!;
      // 扣减顺序是 周期 → 已购 → 赠金：已购池先被吃掉，赠金池这时仍是 0%
      const noRecurring = perplexityLanes(perplexityPools(paidOnlyGrants, 100, 0, nowSec), 0);
      expect(noRecurring.primary).assertEqual(null);
      expect(noRecurring.secondary!.usedPercent).assertEqual(0);
      expect(Math.round(noRecurring.tertiary!.usedPercent)).assertEqual(33);
      // 只有未过期赠金时（没有周期/已购池）：赠金泳道才出比例
      const promoOnlyGrants: Json[] = asArray(parseJson(`[
        {"type":"promotional","amount_cents":500,"expires_at_ts":${nowSec + 3600}}
      ]`))!;
      const promoOnly = perplexityLanes(perplexityPools(promoOnlyGrants, 100, 0, nowSec), 0);
      expect(promoOnly.primary).assertEqual(null);
      expect(promoOnly.secondary!.usedPercent).assertEqual(20);
      expect(promoOnly.tertiary!.usedPercent).assertEqual(100);
      // 三池全空：主泳道 100%（空额度条）+ 续费时间，赠金/已购泳道也是 100%
      const noGrants: Json[] = asArray(parseJson('[]'))!;
      const empty = perplexityLanes(perplexityPools(noGrants, 0, 0, nowSec), nextRefresh);
      expect(empty.primary!.usedPercent).assertEqual(100);
      expect(empty.primary!.resetsAt).assertEqual(nextRefresh);
      expect(empty.secondary!.usedPercent).assertEqual(100);
      expect(empty.tertiary!.usedPercent).assertEqual(100);
    });

    it('Extra_lane_catalog', 0, () => {
      // 词首大写（对照插件 title()）：下划线换空格 + 每词首字母大写
      expect(titleCaseWords('neural_watt')).assertEqual('Neural Watt');
      expect(titleCaseWords('day')).assertEqual('Day');
      expect(titleCaseWords('PRO')).assertEqual('Pro');

      // ElevenLabs 席位泳道（对照插件 elevenlabs.js）：分子分母都在且分母 > 0 才出
      const voiceSlot = new ElevenLabsSlot();
      voiceSlot.id = 'voice-slots';
      voiceSlot.title = 'Voice slots';
      voiceSlot.used = 3;
      voiceSlot.limit = 10;
      const missingLimit = new ElevenLabsSlot();
      missingLimit.id = 'professional-voices';
      missingLimit.title = 'Professional voices';
      missingLimit.used = 1;
      const zeroLimit = new ElevenLabsSlot();
      zeroLimit.id = 'zero';
      zeroLimit.title = 'Zero';
      zeroLimit.used = 1;
      zeroLimit.limit = 0;
      const slots = elevenLabsSlotWindows([voiceSlot, missingLimit, zeroLimit]);
      expect(slots.length).assertEqual(1);
      expect(slots[0].id).assertEqual('voice-slots');
      expect(slots[0].window.usedPercent).assertEqual(30);
      // 计划名：tier 词首大写，非 active 的 status 拼在后面
      expect(elevenLabsLoginMethod('creator_pro', null)).assertEqual('Creator Pro');
      expect(elevenLabsLoginMethod('free', 'trialing')).assertEqual('Free · trialing');
      expect(elevenLabsLoginMethod('free', 'active')).assertEqual('Free');
      expect(elevenLabsLoginMethod(null, 'past_due')).assertEqual('past_due');

      // NeuralWatt（对照插件 neuralwatt.js）：主泳道是订阅 kWh，密钥限额是附加泳道
      const quotaJson = '{"balance":{"credits_remaining_usd":12.5,"credits_used_usd":7.5,' +
        '"accounting_method":"prepaid"},"subscription":{"kwh_included":40,"kwh_used":10,' +
        '"current_period_end":"2026-10-01T00:00:00.000Z","plan":"scale_plan"},' +
        '"key":{"allowance":{"limit_usd":5,"spent_usd":2,"period":"daily"}}}';
      const quota = neuralWattQuota(asObj(parseJson(quotaJson))!);
      expect(quota.totalUSD).assertEqual(20);
      expect(quota.usedUSD).assertEqual(7.5);
      expect(quota.remainingUSD).assertEqual(12.5);
      expect(quota.kwhIncluded).assertEqual(40);
      expect(quota.kwhConsumed).assertEqual(10);
      const watt = neuralWattWindows(quota);
      expect(watt.primary!.usedPercent).assertEqual(25);
      expect(watt.primary!.resetsAt).assertEqual(Date.parse('2026-10-01T00:00:00.000Z'));
      expect(watt.extras.length).assertEqual(1);
      expect(watt.extras[0].id).assertEqual('key-allowance');
      expect(watt.extras[0].title).assertEqual('Key Daily');
      expect(watt.extras[0].window.usedPercent).assertEqual(40);
      // 密钥被封锁 → 100%
      const blockedRoot = asObj(parseJson(
        '{"key":{"allowance":{"limit_usd":5,"spent_usd":1,"blocked":true}}}'))!;
      const blocked = neuralWattQuota(blockedRoot);
      expect(neuralWattWindows(blocked).extras[0].window.usedPercent).assertEqual(100);
      expect(neuralWattWindows(blocked).extras[0].title).assertEqual('Key Allowance');
      // 额度字段缺失：不出主泳道也不出附加泳道
      const bare = neuralWattQuota(asObj(parseJson('{}'))!);
      expect(neuralWattWindows(bare).primary).assertEqual(null);
      expect(neuralWattWindows(bare).extras.length).assertEqual(0);

      // Sub2API（对照插件 sub2api.js）：有订阅包时用日/周/月，否则回退配额；rate_limits 是附加泳道
      const subJson = '{"balance":12,"subscription":{"daily_usage_usd":3,"daily_limit_usd":10,' +
        '"weekly_usage_usd":20,"weekly_limit_usd":40,"monthly_usage_usd":50},' +
        '"rate_limits":[{"window":"5h","limit":5,"used":1,"remaining":4},' +
        '{"window":"7d","limit":20,"used":5,"remaining":15}]}';
      const subWindows = sub2APIWindows(asObj(parseJson(subJson))!);
      expect(subWindows.primary!.usedPercent).assertEqual(30);
      expect(subWindows.secondary!.usedPercent).assertEqual(50);
      // 月度只有 used、没有 limit：不出泳道
      expect(subWindows.tertiary).assertEqual(null);
      expect(subWindows.extras.length).assertEqual(2);
      expect(subWindows.extras[0].id).assertEqual('5h');
      expect(subWindows.extras[0].title).assertEqual('5 hour limit');
      expect(subWindows.extras[0].window.usedPercent).assertEqual(20);
      expect(subWindows.extras[1].title).assertEqual('7 day limit');
      const quotaOnly = sub2APIWindows(asObj(parseJson(
        '{"quota":{"used":25,"limit":100,"remaining":75}}'))!);
      expect(quotaOnly.primary!.usedPercent).assertEqual(25);
      expect(quotaOnly.secondary).assertEqual(null);
      expect(quotaOnly.extras.length).assertEqual(0);

      // Claude（对照 ClaudeWebExtraRateWindowParser + ClaudeScopedWeeklyLimitMapper）
      expect(claudeSlug('Claude 3.5 Sonnet')).assertEqual('claude-3-5-sonnet');
      expect(claudeSlug('--Opus--')).assertEqual('opus');
      expect(claudeIsAllModelsScope('', 'All models')).assertTrue();
      expect(claudeIsAllModelsScope('claude-all-models', 'Everything')).assertTrue();
      expect(claudeIsAllModelsScope('claude-sonnet', 'Sonnet')).assertFalse();
      const claudeJson = '{"limits":[' +
        '{"kind":"weekly_scoped","group":"weekly","percent":42,' +
        '"resets_at":"2026-10-01T00:00:00.000Z","scope":{"model":{"id":"claude-sonnet-4","display_name":"Sonnet 4"}}},' +
        '{"kind":"weekly_scoped","group":"weekly","percent":10,' +
        '"scope":{"model":{"id":"claude-all-models","display_name":"All models"}}},' +
        '{"kind":"weekly_scoped","group":"weekly","percent":5,' +
        '"scope":{"model":{"id":"claude-sonnet-4","display_name":"Sonnet 4"}}},' +
        '{"kind":"session","group":"weekly","percent":90,' +
        '"scope":{"model":{"id":"claude-opus","display_name":"Opus"}}}],' +
        '"seven_day_routines":{"utilization":7,"resets_at":"2026-09-30T00:00:00.000Z"}}';
      const claudeWindows = claudeExtraRateWindows(asObj(parseJson(claudeJson))!);
      // 模型限定周额度在前（重复 id 与 all-models 跳过），Daily Routines 在后
      expect(claudeWindows.length).assertEqual(2);
      expect(claudeWindows[0].id).assertEqual('claude-weekly-scoped-claude-sonnet-4');
      expect(claudeWindows[0].title).assertEqual('Sonnet 4 only');
      expect(claudeWindows[0].window.usedPercent).assertEqual(42);
      expect(claudeWindows[0].window.resetsAt).assertEqual(Date.parse('2026-10-01T00:00:00.000Z'));
      expect(claudeWindows[1].id).assertEqual('claude-routines');
      expect(claudeWindows[1].title).assertEqual('Daily Routines');
      expect(claudeWindows[1].window.usedPercent).assertEqual(7);
      // 候选键的先后顺序：seven_day_routines 优先于 cowork
      const coworkOnly = claudeExtraRateWindows(asObj(parseJson('{"cowork":{"utilization":3}}'))!);
      expect(coworkOnly.length).assertEqual(1);
      expect(coworkOnly[0].id).assertEqual('claude-routines');
      expect(claudeExtraRateWindows(asObj(parseJson('{}'))!).length).assertEqual(0);
    });

    it('Lane_mapping_and_labels', 0, () => {
      // 标签表补齐（对照 ProviderDescriptor.metadata）：Amp 与控制台 Admin API（同上 Claude descriptor）
      const ampLabels = windowLabelsFor('amp');
      expect(ampLabels.primary).assertEqual('Amp Free');
      expect(ampLabels.secondary).assertEqual('Balance');
      const consoleLabels = windowLabelsFor('anthropic-console');
      expect(consoleLabels.primary).assertEqual('Session');
      expect(consoleLabels.secondary).assertEqual('Weekly');
      expect(consoleLabels.tertiary).assertEqual('Sonnet');
      // 未登记的服务商仍返回全空（UI 回落中文默认名）
      expect(windowLabelsFor('siliconflow').primary).assertEqual('');

      // 绑定泳道表（对照 primaryBindingQuotaLanes + 各 fetcher 的 windowMinutes）
      const claudeLanes = bindingQuotaLanesFor('claude');
      expect(claudeLanes.length).assertEqual(1);
      expect(claudeLanes[0].slot).assertEqual('secondary');
      expect(claudeLanes[0].minutes).assertEqual(WEEKLY_WINDOW_MINUTES);
      expect(bindingQuotaLanesFor('anthropic-console').length).assertEqual(1);
      const triLanes = bindingQuotaLanesFor('clinepass');
      expect(triLanes.length).assertEqual(2);
      expect(triLanes[1].slot).assertEqual('tertiary');
      expect(triLanes[1].minutes).assertEqual(MONTHLY_WINDOW_MINUTES);
      // 四小时的 chutes 主泳道绑定月度池
      expect(bindingQuotaLanesFor('chutes')[0].minutes).assertEqual(MONTHLY_WINDOW_MINUTES);
      // 未声明的服务商不受任何更长泳道绑定
      expect(bindingQuotaLanesFor('openrouter').length).assertEqual(0);
      expect(bindingQuotaLanesFor('kimi-coding').length).assertEqual(0);

      const now = Date.parse('2026-09-24T12:00:00.000Z');
      const weekReset = now + 3 * 24 * 60 * 60 * 1000;
      const hourReset = now + 2 * 60 * 60 * 1000;

      // 周额度还有剩余 → 不投影
      expect(bindingQuotaProjection(
        makeWindow(20, hourReset), [makeWindow(60, weekReset)], [WEEKLY_WINDOW_MINUTES], now))
        .assertEqual(null);
      // 周额度耗尽 → 主泳道按 100% + 周重置时间展示
      const capped = bindingQuotaProjection(
        makeWindow(20, hourReset), [makeWindow(100, weekReset)], [WEEKLY_WINDOW_MINUTES], now)!;
      expect(capped.usedPercent).assertEqual(100);
      expect(capped.resetsAt).assertEqual(weekReset);
      // 更短的泳道不能卡住主泳道（源工程用 minutes > primaryMinutes 过滤）
      expect(bindingQuotaProjection(
        makeWindow(20, hourReset), [makeWindow(100, hourReset)], [60], now)).assertEqual(null);
      // 耗尽但重置时间已过 → 视为已恢复，不投影
      expect(bindingQuotaProjection(
        makeWindow(20, hourReset), [makeWindow(100, now - 1000)], [WEEKLY_WINDOW_MINUTES], now))
        .assertEqual(null);
      // 无重置时间的闸门：不承诺时间（0 = 不显示倒计时）
      const unknownReset = bindingQuotaProjection(
        makeWindow(20, hourReset), [makeWindow(100, 0)], [WEEKLY_WINDOW_MINUTES], now)!;
      expect(unknownReset.resetsAt).assertEqual(0);
      // 主泳道自己也没了 + 周额度也没了 → 取更晚的那个重置时间
      const bothOut = bindingQuotaProjection(
        makeWindow(100, weekReset + 86400000), [makeWindow(100, weekReset)],
        [WEEKLY_WINDOW_MINUTES], now)!;
      expect(bothOut.resetsAt).assertEqual(weekReset + 86400000);
      // 非有限/未知用量：usageKnown=false 的 0% 占位不算耗尽
      expect(bindingQuotaProjection(
        makeWindow(0, 0, false), [makeWindow(0, 0, false)], [WEEKLY_WINDOW_MINUTES], now))
        .assertEqual(null);

      // 展示窗口：只有真的命中绑定泳道才替换百分比与重置时间
      const snap = UsageSnapshot.success(makeWindow(20, hourReset), makeWindow(100, weekReset), null);
      const shown = primaryDisplayWindow('claude', snap, now)!;
      expect(shown.usedPercent).assertEqual(100);
      expect(shown.resetsAt).assertEqual(weekReset);
      // 同一条快照对未声明绑定泳道的服务商原样输出
      expect(primaryDisplayWindow('openrouter', snap, now)!.usedPercent).assertEqual(20);
      // 绑定泳道但快照里没有该泳道（如 Claude 只有主泳道）→ 原样输出
      const primaryOnly = UsageSnapshot.success(makeWindow(20, hourReset), null, null);
      expect(primaryDisplayWindow('claude', primaryOnly, now)!.usedPercent).assertEqual(20);
      // 没有快照 / 没有主泳道 → null
      expect(primaryDisplayWindow('claude', null, now)).assertEqual(null);
      expect(primaryDisplayWindow('claude', UsageSnapshot.success(null, makeWindow(100, weekReset), null), now))
        .assertEqual(null);
      // 主泳道被卡住时明细行不受影响：快照本身未被改写
      expect(snap.primary!.usedPercent).assertEqual(20);

      // Doubao 请求桶探测窗口的泳道名（对照 DoubaoProviderDescriptor.primaryLabel）
      const probe = doubaoParseProbe(200, {
        'x-ratelimit-limit-requests': '100',
        'x-ratelimit-remaining-requests': '40',
        'x-ratelimit-reset-requests': '60s',
      }, now);
      const probeSnap = doubaoProbeSnapshot(probe);
      expect(probeSnap.primaryLabel).assertEqual('Requests');
      expect(probeSnap.primary!.usedPercent).assertEqual(60);
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

    it('DeepSeek_token_capture', 0, () => {
      const jwt = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.payload.sig';
      // userToken 裸串 / 被引号包裹 / JSON 编码，三种形态都能取
      expect(extractDeepSeekUserToken(jwt)).assertEqual(jwt);
      expect(extractDeepSeekUserToken(`"${jwt}"`)).assertEqual(jwt);
      expect(extractDeepSeekUserToken(JSON.stringify(jwt))).assertEqual(jwt);
      // 对象形态 { value: … }
      expect(extractDeepSeekUserToken(JSON.stringify({ value: jwt }))).assertEqual(jwt);
      // 匿名/短令牌被拒
      expect(extractDeepSeekUserToken('short')).assertEqual('');
      expect(extractDeepSeekUserToken('')).assertEqual('');

      // 扫描兜底：userToken 优先，其次按出现顺序；外层引号（runJavaScript 编码）先剥掉
      const scan = JSON.stringify({ userToken: jwt, DS_TOKEN: `{"token":"${jwt}"}` });
      const list = extractDeepSeekTokenCandidates(scan);
      expect(list.length).assertEqual(1);
      expect(list[0]).assertEqual(jwt);
      const quoted = extractDeepSeekTokenCandidates(JSON.stringify(scan));
      expect(quoted.length).assertEqual(1);
      expect(quoted[0]).assertEqual(jwt);
      // userToken 缺席时从改名键里取
      const renamed = extractDeepSeekTokenCandidates(JSON.stringify({ platform_token: jwt }));
      expect(renamed.length).assertEqual(1);
      expect(renamed[0]).assertEqual(jwt);
      // 无 token 键 / 非对象 / 空串 → 空
      expect(extractDeepSeekTokenCandidates(JSON.stringify({ theme: 'dark' })).length).assertEqual(0);
      expect(extractDeepSeekTokenCandidates('not json').length).assertEqual(0);
      expect(extractDeepSeekTokenCandidates('').length).assertEqual(0);
    });

    it('Siliconflow_error_text_and_hosts', 0, () => {
      // 错误文案优先透出服务端 message
      const r1 = new HttpResult();
      r1.code = 410;
      r1.body = '{"code":20026,"message":"This API has been deprecated"}';
      expect(siliconflowErrorText(r1)).assertEqual('This API has been deprecated (HTTP 410)');
      const r2 = new HttpResult();
      r2.code = 401;
      r2.body = '{"code":30014,"message":"Token is invalid."}';
      expect(siliconflowErrorText(r2)).assertEqual('Token is invalid. (HTTP 401)');
      // 无 message / 非 JSON 体回退到通用文案
      const r3 = new HttpResult();
      r3.code = 410;
      r3.body = '';
      expect(siliconflowErrorText(r3)).assertEqual('请求失败 (HTTP 410)');
      const r4 = new HttpResult();
      r4.code = 410;
      r4.body = '<html>Blocked</html>';
      expect(siliconflowErrorText(r4)).assertEqual('请求失败 (HTTP 410)');
      // 国内站优先，国际站兜底
      expect(SILICONFLOW_HOSTS.length).assertEqual(2);
      expect(SILICONFLOW_HOSTS[0]).assertEqual('https://api.siliconflow.cn');
      expect(SILICONFLOW_HOSTS[1]).assertEqual('https://api.siliconflow.com');
      // 国内站 410 转译为止血提示（官方停用，不代表 Key 无效），原始信息保留
      const gone = new HttpResult();
      gone.code = 410;
      gone.body = '{"code":20092,"message":"This endpoint is deprecated and is no longer available.","data":null}';
      const notice = siliconflowCnErrorText(gone);
      expect(notice.includes('已由官方停止服务')).assertTrue();
      expect(notice.includes('这不表示 API Key 无效')).assertTrue();
      expect(notice.includes('20092')).assertTrue();
      // 410 之外的国内站错误不触发止血文案
      const invalid = new HttpResult();
      invalid.code = 401;
      invalid.body = '{"code":30014,"message":"Token is invalid."}';
      expect(siliconflowCnErrorText(invalid)).assertEqual('Token is invalid. (HTTP 401)');
    });
  });
}
