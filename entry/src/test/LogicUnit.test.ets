import { describe, it, expect } from '@ohos/hypium';
import { Format } from '../main/ets/common/Format';
import { Theme } from '../main/ets/common/Theme';
import { parseJson, asObj, asArray, str, num, optNum, optStr } from '../main/ets/net/Json';
import { makeWindow, UsageSnapshot, RateWindow, ProviderDescriptor, ProviderSetting, ProviderState,
  AuthKind, defaultReminder } from '../main/ets/model/Models';
import { parseDetailParam, DetailRouteParam } from '../main/ets/common/Nav';
import { chutesWindow } from '../main/ets/providers/MoreProviders';
import { zaiLimitWindow, t3chatFindCustomerData } from '../main/ets/providers/MoreProviders2';
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
import { HistoryDay } from '../main/ets/model/Models';
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
  codexAuthorizeUrl,
  decodeJwtPayload,
  extractChatgptAccountId,
  extractSessionKey,
  makePkce,
  parseCallbackUrl,
  sha256Base64Url,
  sha256Bytes,
} from '../main/ets/common/OAuth';

/** 构造只带一个主窗口的服务商状态（提醒测试用） */
function stateWith(primary: RateWindow, title: string = '演示', enabled: boolean = true): ProviderState {
  const d: ProviderDescriptor = {
    id: 'demo', title: title, authKind: AuthKind.DEMO,
    accentColor: '#16D3B4', authHint: '', authUrl: ''
  };
  const s = new ProviderState(d, { enabled: enabled, credential: '', credential2: '' });
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

    it('Accounts_parse_roundtrip', 0, () => {
      const json = '[{"aid":"a1","name":"账号 1","credential":"sk-1","credential2":"org1","refreshToken":"rt1"},' +
        '{"aid":"a2","name":"账号 2","credential":"sk-2","credential2":"","refreshToken":""}]';
      const list = parseAccounts(json);
      expect(list.length).assertEqual(2);
      expect(list[0].aid).assertEqual('a1');
      expect(list[0].name).assertEqual('账号 1');
      expect(list[0].credential).assertEqual('sk-1');
      expect(list[0].credential2).assertEqual('org1');
      expect(list[0].refreshToken).assertEqual('rt1');
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

    it('Accounts_add_dedupe_remove', 0, () => {
      expect(nextAccountName([])).assertEqual('账号 1');
      // 新增
      const r1 = addAccountToList([], 'cred-1', '', 'rt-1', 1000);
      expect(r1.deduped).assertFalse();
      expect(r1.list.length).assertEqual(1);
      expect(r1.account.name).assertEqual('账号 1');
      expect(r1.account.aid).assertEqual('a1000');
      // 同凭证去重：仅刷新辅助字段并复用
      const r2 = addAccountToList(r1.list, 'cred-1', 'org-x', 'rt-2', 2000);
      expect(r2.deduped).assertTrue();
      expect(r2.list.length).assertEqual(1);
      expect(r2.account.credential2).assertEqual('org-x');
      expect(r2.account.refreshToken).assertEqual('rt-2');
      // 不同凭证：新增为 账号 2
      const r3 = addAccountToList(r2.list, 'cred-2', '', '', 3000);
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
      const rm3 = removeAccountFromList([{ aid: 'a1', name: 'n', credential: 'c', credential2: '', refreshToken: '' }], 'a1', 'a1');
      expect(rm3.list.length).assertEqual(0);
      expect(rm3.newActive).assertEqual('');
      // 空凭证（待填账号）不去重：连续添加各自成账号
      const e1 = addAccountToList([], '', '', '', 1000);
      const e2 = addAccountToList(e1.list, '', '', '', 2000);
      expect(e1.deduped).assertFalse();
      expect(e2.deduped).assertFalse();
      expect(e2.list.length).assertEqual(2);
      expect(e2.account.name).assertEqual('账号 2');
      // 同毫秒连续添加：aid 必须唯一
      const s1 = addAccountToList([], 'x1', '', '', 5000);
      const s2 = addAccountToList(s1.list, 'x2', '', '', 5000);
      expect(s1.account.aid === s2.account.aid).assertFalse();
      const s3 = addAccountToList(s2.list, 'x3', '', '', 5000);
      expect(s3.account.aid === s1.account.aid).assertFalse();
      expect(s3.account.aid === s2.account.aid).assertFalse();
      expect(s3.list.length).assertEqual(3);
    });

    it('Accounts_rename', 0, () => {
      const list = parseAccounts(
        '[{"aid":"a1","name":"账号 1","credential":"c1","credential2":"","refreshToken":""},' +
        '{"aid":"a2","name":"账号 2","credential":"c2","credential2":"","refreshToken":""}]');
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
  });
}
