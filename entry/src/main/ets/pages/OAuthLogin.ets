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
import { ProviderSetting } from '../model/Models';
import { AppStore } from '../store/AppStore';
import { Settings } from '../store/Settings';
import { Theme } from '../common/Theme';
import { Nav, parseDetailParam } from '../common/Nav';
import {
  CallbackCode,
  codexAuthorizeUrl,
  codexExchangeCode,
  CodexTokenSet,
  extractSessionKey,
  makePkce,
  PkcePair,
  parseCallbackUrl,
} from '../common/OAuth';

const CODEX_CALLBACK_PREFIX = 'http://localhost:1455/auth/callback';
const CLAUDE_COOKIE_URL = 'https://claude.ai';

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
  private timerId: number = -1;

  aboutToAppear(): void {
    this.providerId = parseDetailParam(router.getParams() as Object | null);
    if (this.providerId === 'codex') {
      this.pkce = makePkce(Date.now());
      this.startUrl = codexAuthorizeUrl(this.pkce);
      this.status = '在下方完成 ChatGPT 登录，授权后自动返回';
    } else if (this.providerId === 'claude') {
      this.startUrl = 'https://claude.ai/login';
      this.status = '在下方登录 claude.ai，成功后自动返回';
      this.timerId = setInterval(() => {
        this.pollClaudeCookie();
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

  /** 保存凭证并返回（codex 可带 refreshToken/accountId） */
  async saveAndBack(credential: string, refreshToken: string, accountId?: string): Promise<void> {
    const store = AppStore.get();
    const state = store.find(this.providerId);
    const current: ProviderSetting = state != null
      ? state.setting
      : { enabled: true, credential: '', credential2: '' };
    let cred2 = current.credential2.trim();
    if (this.providerId === 'codex') {
      // 用户已填账号 ID 则保留；否则用 JWT 里的
      if (cred2.length === 0 && accountId != null && accountId.length > 0) {
        cred2 = accountId;
      }
      if (refreshToken.length > 0) {
        Settings.setOauthRefreshToken(this.providerId, refreshToken);
      }
    }
    store.applySetting(this.providerId, {
      enabled: true,
      credential: credential,
      credential2: cred2,
    });
    Nav.toast('登录成功，凭证已保存');
    Nav.back();
  }

  build() {
    Column() {
      // 顶栏
      Row({ space: 10 }) {
        Button() {
          Text('‹')
            .fontSize(22)
            .fontColor(Theme.text)
        }
        .backgroundColor(Theme.card)
        .width(36)
        .height(36)
        .borderRadius(12)
        .onClick(() => {
          Nav.back();
        })

        Column({ space: 2 }) {
          Text(this.providerId === 'codex' ? 'Codex 网页登录' : 'Claude 网页登录')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.text)
          Text(this.status)
            .fontSize(11)
            .fontColor(this.failed ? Theme.danger : Theme.textDim)
            .maxLines(2)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: Theme.pad, right: Theme.pad, top: 12, bottom: 8 })

      if (this.startUrl.length > 0) {
        Web({ src: this.startUrl, controller: this.controller })
          .width('100%')
          .layoutWeight(1)
          .onLoadIntercept((event) => {
            const url = event.data.getRequestUrl();
            return this.interceptCallback(url);
          })
          .onPageEnd(() => {
            this.pollClaudeCookie();
          })
      } else {
        Column({ space: 8 }) {
          Text(this.status)
            .fontSize(14)
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
}
