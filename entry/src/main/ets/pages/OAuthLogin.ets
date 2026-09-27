/**
 * CodexBar Mobile — 应用内网页登录
 *
 * - Codex：Web 组件打开 auth.openai.com 授权页（PKCE），
 *   拦截 localhost:1455 回调拿授权码 → 换令牌 → 自动提取账号 ID → 保存并刷新。
 * - Claude：Web 组件登录 claude.ai，轮询 Cookie 取 sessionKey → 保存并刷新。
 *
 * 登录成功即回写该服务商凭证（enabled=true）并触发一次查询。
 */

import web_webview from '@ohos.web.webview';
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Http } from '../net/Http';
import { asObj } from '../net/Json';
import { ProviderSetting } from '../model/Models';
import { AppStore } from '../store/AppStore';
import { Settings } from '../store/Settings';
import { Theme } from '../common/Theme';
import { Nav, parseDetailMode, parseDetailParam } from '../common/Nav';
import {
  CallbackCode,
  codexAuthorizeUrl,
  codexExchangeCode,
  CodexTokenSet,
  extractDeepSeekTokenCandidates,
  extractDeepSeekUserToken,
  deepSeekPlatformHeaders,
  DEEPSEEK_WEB_UA,
  extractSessionKey,
  makePkce,
  PkcePair,
  parseCallbackUrl,
} from '../common/OAuth';

const CODEX_CALLBACK_PREFIX = 'http://localhost:1455/auth/callback';
const CLAUDE_COOKIE_URL = 'https://claude.ai';
const DEEPSEEK_USAGE_URL = 'https://platform.deepseek.com/usage';
/** 读 localStorage.userToken（macOS 是从 Chrome 的同名键读，这里改成读应用内 Web 的同一键） */
const DEEPSEEK_TOKEN_SCRIPT = 'window.localStorage.getItem("userToken") || ""';
/** 兜底扫描：站点若不再用 userToken 键，取所有键名含 token 的项（JSON 对象串） */
const DEEPSEEK_TOKEN_SCAN_SCRIPT =
  '(function(){var o={};for(var i=0;i<localStorage.length;i++){var k=localStorage.key(i);' +
  'if(k&&k.toLowerCase().indexOf("token")>=0){o[k]=localStorage.getItem(k);}}' +
  'return JSON.stringify(o);})()';
/** 诊断用：localStorage 全部键名 */
const DEEPSEEK_KEYS_SCRIPT = 'Object.keys(window.localStorage).join(",")';
const DOMAIN = 0x0400;
const TAG = 'CodexBar.OAuthLogin';

@Entry
@Component
struct OAuthLogin {
  @State providerId: string = '';
  @State startUrl: string = '';
  @State status: string = '';
  @State failed: boolean = false;
  private controller: web_webview.WebviewController = new web_webview.WebviewController();
  private pkce: PkcePair | null = null;
  private done: boolean = false;
  private addMode: boolean = false;
  private timerId: number = -1;

  aboutToAppear(): void {
    const params = router.getParams() as Object | null;
    this.providerId = parseDetailParam(params);
    this.addMode = parseDetailMode(params) === 'add';
    const addSuffix = this.addMode ? '（将添加为新账号）' : '';
    if (this.providerId === 'codex') {
      this.pkce = makePkce(Date.now());
      this.startUrl = codexAuthorizeUrl(this.pkce);
      this.status = `在下方完成 ChatGPT 登录，授权后自动返回${addSuffix}`;
    } else if (this.providerId === 'claude') {
      this.startUrl = 'https://claude.ai/login';
      this.status = `在下方登录 claude.ai，成功后自动返回${addSuffix}`;
      this.timerId = setInterval(() => {
        this.pollClaudeCookie();
      }, 2000);
    } else if (this.providerId === 'deepseek') {
      this.startUrl = this.addMode ? 'https://platform.deepseek.com/sign_in' : DEEPSEEK_USAGE_URL;
      this.status = '在下方登录 platform.deepseek.com，成功后自动回填平台会话（不会改动已填的 API Key）';
      this.timerId = setInterval(() => {
        this.pollDeepSeekToken();
      }, 2000);
    } else {
      this.status = '不支持的服务商';
      this.failed = true;
    }
  }

  aboutToDisappear(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  /** Claude：读取 webview Cookie 中的 sessionKey（fetchCookie 异步版跨端可用） */
  private cookieInFlight: boolean = false;

  async pollClaudeCookie(): Promise<void> {
    if (this.done || this.cookieInFlight || this.providerId !== 'claude') {
      return;
    }
    this.cookieInFlight = true;
    try {
      const cookie = await web_webview.WebCookieManager.fetchCookie(CLAUDE_COOKIE_URL);
      const key = extractSessionKey(cookie);
      if (key.length > 0) {
        this.done = true;
        this.status = '已获取登录凭证，正在保存…';
        await this.saveAndBack(key, '');
      }
    } catch (e) {
      // Cookie API 不可用时静默；用户仍可回设置页手工粘贴
    }
    this.cookieInFlight = false;
  }

  /**
   * DeepSeek：读 Web 组件里 platform.deepseek.com 的 localStorage.userToken，
   * 与 macOS 从 Chrome localStorage 导入平台会话是同一个键、同一份数据。
   * userToken 取不到时扫描所有键名含 token 的项做兜底，候选逐个过平台接口校验。
   */
  private tokenInFlight: boolean = false;
  /** 已被平台接口明确判无效（401/403/业务码非 0）的候选令牌，避免 2 秒轮询反复打接口 */
  private rejectedTokens: string[] = [];

  private isRejectedToken(token: string): boolean {
    return this.rejectedTokens.indexOf(token) >= 0;
  }

  private rememberRejectedToken(token: string): void {
    if (this.rejectedTokens.indexOf(token) < 0) {
      this.rejectedTokens.push(token);
      // 只留最近 8 个，防止匿名令牌轮换撑爆
      while (this.rejectedTokens.length > 8) {
        this.rejectedTokens.shift();
      }
    }
  }

  async pollDeepSeekToken(): Promise<void> {
    if (this.done || this.tokenInFlight || this.providerId !== 'deepseek') {
      return;
    }
    this.tokenInFlight = true;
    try {
      // 候选来源 1：macOS 同款 userToken 键
      const primary = extractDeepSeekUserToken(await this.controller.runJavaScript(DEEPSEEK_TOKEN_SCRIPT));
      const candidates: string[] = [];
      if (primary.length > 0 && !this.isRejectedToken(primary)) {
        candidates.push(primary);
      }
      // 候选来源 2：键名含 token 的全部项（站点改键名时的兜底），也覆盖 userToken 被拒后的场景
      const scanList = extractDeepSeekTokenCandidates(
        await this.controller.runJavaScript(DEEPSEEK_TOKEN_SCAN_SCRIPT));
      for (let i = 0; i < scanList.length; i++) {
        const item = scanList[i];
        if (item.length > 0 && !this.isRejectedToken(item) && candidates.indexOf(item) < 0) {
          candidates.push(item);
        }
      }
      if (candidates.length === 0) {
        this.status = '登录 platform.deepseek.com 后会自动读取平台会话（仅 API Key 时明细不可用）';
        // 诊断：打印 localStorage 键名，便于定位站点改键
        const keys = await this.controller.runJavaScript(DEEPSEEK_KEYS_SCRIPT);
        hilog.info(DOMAIN, TAG, 'deepseek no candidate, localStorage keys: %{public}s', `${keys}`);
        this.tokenInFlight = false;
        return;
      }
      this.status = '正在校验平台会话…';
      let saved = false;
      for (let i = 0; i < candidates.length; i++) {
        const verdict = await this.validateDeepSeekToken(candidates[i]);
        if (verdict === 0) {
          this.done = true;
          this.status = '已获取平台会话，正在保存…';
          await this.saveDeepSeekSession(candidates[i]);
          saved = true;
          break;
        }
        if (verdict === 1) {
          this.rememberRejectedToken(candidates[i]);
        }
        // verdict === 2（网络异常/响应结构异常）：不缓存，下轮重试
      }
      if (!saved && !this.done) {
        this.status = '平台会话校验未通过，请确认已在下方完成登录后稍候';
      }
    } catch (e) {
      // 页面未就绪或 JS 执行被拒：静默重试，用户也可回设置页手工粘贴
      hilog.warn(DOMAIN, TAG, 'deepseek poll failed: %{public}s', `${e}`);
    }
    this.tokenInFlight = false;
  }

  /**
   * 校验候选令牌（对照 DeepSeekUsageFetcher.parseUserSummary 的成功判定）：
   * get_user_summary 返回 2xx，且 code（若有）为 0、data.biz_code（若有）为 0、
   * data.biz_data 存在才算有效。
   * 返回：0 有效；1 明确无效（401/403 或业务码非 0，可缓存不再重试）；
   * 2 不确定（网络失败/结构异常，下轮重试）。
   */
  private async validateDeepSeekToken(token: string): Promise<number> {
    // 必须带浏览器伪装头：平台 WAF 拦无 UA 的原生请求（429 Request Blocked）
    const headers = deepSeekPlatformHeaders(token);
    const resp = await Http.get('https://platform.deepseek.com/api/v0/users/get_user_summary', headers);
    if (!resp.ok) {
      hilog.warn(DOMAIN, TAG, 'deepseek summary http %{public}d body=%{public}s',
        resp.code, resp.body.substring(0, 200));
      return resp.code === 401 || resp.code === 403 ? 1 : 2;
    }
    const root = asObj(resp.json());
    if (root == null) {
      hilog.warn(DOMAIN, TAG, 'deepseek summary body not json: %{public}s', resp.body.substring(0, 200));
      return 2;
    }
    const code = root['code'];
    if (typeof code === 'number' && code !== 0) {
      hilog.warn(DOMAIN, TAG, 'deepseek summary code=%{public}d', code);
      return 1;
    }
    const data = asObj(root['data']);
    if (data == null) {
      hilog.warn(DOMAIN, TAG, 'deepseek summary missing data: %{public}s', resp.body.substring(0, 200));
      return 2;
    }
    const bizCode = data['biz_code'];
    if (typeof bizCode === 'number' && bizCode !== 0) {
      hilog.warn(DOMAIN, TAG, 'deepseek summary biz_code=%{public}d', bizCode);
      return 1;
    }
    if (asObj(data['biz_data']) == null) {
      hilog.warn(DOMAIN, TAG, 'deepseek summary missing biz_data: %{public}s', resp.body.substring(0, 200));
      return 2;
    }
    return 0;
  }

  /** DeepSeek：只写第二栏（平台会话），API Key 保持不动 */
  async saveDeepSeekSession(token: string): Promise<void> {
    const store = AppStore.get();
    const state = store.find(this.providerId);
    const apiKey = state != null ? state.setting.credential.trim() : '';
    store.applySetting(this.providerId, {
      enabled: true,
      credential: apiKey,
      credential2: token,
      extraConfig: state != null ? state.setting.extraConfig : '',
    });
    if (apiKey.length === 0) {
      Nav.toast('已获取平台会话，还需在设置页填写 DeepSeek API Key');
    } else {
      Nav.toast('已获取平台会话，正在刷新用量明细');
    }
    Nav.back();
  }

  /** Codex：拦截 localhost:1455 回调 */
  interceptCallback(url: string): boolean {
    if (this.done || this.providerId !== 'codex' || this.pkce == null) {
      return false;
    }
    if (!url.startsWith(CODEX_CALLBACK_PREFIX)) {
      return false;
    }
    const cb: CallbackCode | null = parseCallbackUrl(url);
    if (cb == null) {
      return true;
    }
    if (cb.state !== this.pkce.state) {
      this.status = '授权状态校验失败，请重试';
      this.failed = true;
      return true;
    }
    this.done = true;
    this.status = '授权成功，正在换取令牌…';
    this.exchangeAndSave(cb.code, this.pkce.verifier);
    return true;
  }

  async exchangeAndSave(code: string, verifier: string): Promise<void> {
    const set: CodexTokenSet = await codexExchangeCode(code, verifier);
    if (set.error.length > 0) {
      this.status = set.error;
      this.failed = true;
      this.done = false;
      return;
    }
    await this.saveAndBack(set.accessToken, set.refreshToken, set.accountId);
  }

  /** 保存凭证并返回：账号体系已存在或添加模式 → 账号入库；否则旧单凭证路径 */
  async saveAndBack(credential: string, refreshToken: string, accountId?: string): Promise<void> {
    const store = AppStore.get();
    const state = store.find(this.providerId);
    const current: ProviderSetting = state != null
      ? state.setting
      : { enabled: true, credential: '', credential2: '', extraConfig: '' };
    let cred2 = current.credential2.trim();
    if (this.providerId === 'codex') {
      if (cred2.length === 0 && accountId != null && accountId.length > 0) {
        cred2 = accountId;
      }
    }
    if (this.addMode || Settings.accountCount(this.providerId) > 0) {
      const res = Settings.addAccount(this.providerId, credential, cred2, refreshToken);
      store.reloadSetting(this.providerId);
      store.refreshOne(this.providerId);
      Nav.toast(res.deduped ? `已切换到${res.account.name}` : `已添加${res.account.name}`);
      Nav.back();
      return;
    }
    if (this.providerId === 'codex' && refreshToken.length > 0) {
      Settings.setOauthRefreshToken(this.providerId, refreshToken);
    }
    store.applySetting(this.providerId, {
      enabled: true,
      credential: credential,
      credential2: cred2,
      extraConfig: state != null ? state.setting.extraConfig : '',
    });
    Nav.toast('登录成功，凭证已保存');
    Nav.back();
  }

  /** 页面标题：按服务商区分（DeepSeek 只取平台会话，不是账号登录） */
  loginTitle(): string {
    if (this.providerId === 'codex') {
      return 'Codex 网页登录';
    }
    if (this.providerId === 'deepseek') {
      return 'DeepSeek 平台会话';
    }
    return 'Claude 网页登录';
  }

  build() {
    Column() {
      // 顶栏
      Row({ space: Theme.rowGap }) {
        Button() {
          Text('‹')
            .fontSize(Theme.fsGlyph)
            .fontColor(Theme.text)
        }
        .backgroundColor(Theme.card)
        .border({ width: 1, color: Theme.stroke })
        .shadow(Theme.cardShadow())
        .width(36)
        .height(36)
        .borderRadius(Theme.radiusBtn)
        .onClick(() => {
          Nav.back();
        })

        Column({ space: Theme.gapXxs }) {
          Text(this.loginTitle())
            .fontSize(Theme.fsHeading)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.text)
          Text(this.status)
            .fontSize(Theme.fsMicro)
            .fontColor(this.failed ? Theme.danger : Theme.textDim)
            .maxLines(2)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: Theme.pad, right: Theme.pad, top: Theme.gap, bottom: Theme.gapSm })

      if (this.startUrl.length > 0) {
        Web({ src: this.startUrl, controller: this.controller })
          .width('100%')
          .layoutWeight(1)
          // platform.deepseek.com 等 SPA 强依赖 localStorage，
          // ArkWeb 默认 domStorageAccess(false) 会直接白屏，必须显式开启
          .domStorageAccess(true)
          .javaScriptAccess(true)
          .databaseAccess(true)
          // 移动端 UA：页面走移动版布局；原生接口请求另用桌面 UA（见 deepSeekPlatformHeaders）
          .userAgent(DEEPSEEK_WEB_UA)
          .onLoadIntercept((event) => {
            const url = event.data.getRequestUrl();
            return this.interceptCallback(url);
          })
          .onPageEnd(() => {
            this.pollClaudeCookie();
            this.pollDeepSeekToken();
          })
      } else {
        Column({ space: Theme.gapSm }) {
          Text(this.status)
            .fontSize(Theme.fsLabel)
            .fontColor(this.failed ? Theme.danger : Theme.text)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
  }

  /** 路由过渡：从右侧滑入 / 滑出 */
  pageTransition() {
    PageTransitionEnter({ type: RouteType.Push, duration: 320, curve: Curve.Friction })
      .translate({ x: '100%' })
    PageTransitionEnter({ type: RouteType.Pop, duration: 320, curve: Curve.Friction })
      .translate({ x: '-16%' })
    PageTransitionExit({ type: RouteType.Pop, duration: 320, curve: Curve.Friction })
      .translate({ x: '100%' })
    PageTransitionExit({ type: RouteType.Push, duration: 320, curve: Curve.Friction })
      .translate({ x: '-16%' })
  }
}
