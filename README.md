# CodexBar Mobile — AI 额度查询工具（HarmonyOS ArkTS）

> 「May your tokens never run out.」—— 在鸿蒙手机上随时查看每个 AI 服务商的用量、额度与重置倒计时。

本项目是 [CodexBar](https://github.com/steipete/CodexBar)（macOS 菜单栏应用，Swift，追踪约 75 家 AI 服务商限额）向 **HarmonyOS ArkTS 移动端** 的迁移版本，并借助 **ArkUI-X**（`.arkui-x/`，`crossplatform: true`，platforms: `android` / `ios`）面向 **鸿蒙手机、Android、iOS** 三个平台。

- SDK：`targetSdkVersion / compatibleSdkVersion 26.0.0`（HarmonyOS 7.0）
- 入口：`entry` 模块 · `EntryAbility` · `pages/Index`

## 功能

- **仪表盘**：服务商卡片列表，用量进度条（会话 / 每周 / 每月窗口）、重置倒计时（秒级刷新）、余额展示、下拉刷新与一键全量刷新。
- **详情页**：全部用量窗口、余额、账号身份、明细分组、错误原因、单服务商刷新。
- **提醒设置**（详情页）：逐服务商开启额度提醒——任一窗口用量达到阈值（50–95%，默认 90%）提示"额度即将用尽"；窗口重置前 5/15/30/60 分钟提示"额度即将恢复"。同一窗口同一周期只提醒一条（去重键随重置时间轮换），通知经 `@ohos.notificationManager` 三端插件发送，应用进程存活期间有效。
- **网页登录**（Claude / Codex）：设置页点「网页登录」在应用内 Web 组件直接完成登录——Claude 登录 claude.ai 后自动捕获 `sessionKey` Cookie（`fetchCookie` 轮询）；Codex 走完整 PKCE 授权码流程（client_id/端点与 Codex CLI 一致，回调 `localhost:1455` 由 Web 组件拦截换取令牌，access token 自动解析 `chatgpt_account_id`），支持 refresh token 静默续期（401/403 自动换新重试）。
- **设置页**：逐服务商开关 + 凭证录入，凭证仅存本机（`@ohos.data.preferences`），刷新时直连服务商接口。
- **演示模式**：无需任何凭证即可体验全部 UI。

## 支持的服务商（v8，52 家）

| 服务商 | 方式 | 凭证 | 展示内容 |
|---|---|---|---|
| Claude | Web 会话 | claude.ai 的 `sessionKey` Cookie | 5 小时会话 / 每周 / Opus 每周 窗口 + 组织/邮箱 |
| Codex (ChatGPT) | OAuth 令牌 | `chatgpt.com` access token（可选账号 ID） | 主/次窗口 + 模型附加限制 |
| OpenAI Platform | API Key | `sk-…` | 额度使用率 + 剩余/已用 |
| Anthropic 控制台 | Admin API Key | `sk-ant-admin…` | 本月 token 用量（输入/输出/缓存） |
| OpenRouter | API Key | `sk-or-v1-…` | 额度使用率 + 剩余额度 |
| DeepSeek | API Key | `sk-…` | 余额（总额/赠送/充值） |
| Kimi (Moonshot) | API Key | `sk-…` | 可用余额（现金/代金券） |
| SiliconFlow 硅基流动 | API Key | `sk-…` | 总余额（充值/赠送） |
| Kimi 编码版 (kimi.com) | authToken | `kimi-auth` 值 | 编码额度 5h/7d/月 窗口 |
| ZenMux | Management Key | `zenmux.ai` 管理密钥 | 5h/7d 配额 + PAYG 余额 + 套餐 |
| Manus | 会话 token | `manus.im` token | 总额度及构成 + 下次刷新倒计时 |
| DeepInfra | API Key | deepinfra.com Key | 余额/上限/本月花费 |
| Perplexity | 会话 Cookie | perplexity.ai Cookie | 余额/赠金/续费时间 |
| Chutes | API Key | chutes.ai Key | 4h 滚动 + 月度配额窗口（别名容错解析） |
| MiniMax | API Token | 平台密钥 | 周期/每周配额窗口（token_plan 与 coding_plan 双端点降级） |
| MiMo (小米) | 会话 Cookie | platform Cookie | 余额 + 月度 token 配额 + 套餐 |
| Mistral | 会话 Cookie | admin Cookie | 钱包余额/信用额度/进行中消费 |
| Kilo Code | API Key | Key（可选组织 ID） | Kilo Pass 用量 + 信用块明细 |
| Poe | API Key | poe.com/api/keys | 积分余额 |
| T3 Chat | 会话 Cookie | t3.chat Cookie | 4 小时/月度用量窗口 + 套餐 |
| z.ai / GLM 智谱 | API Key | z.ai 或 BigModel Key | 配额窗口（Token/时间/Credit 多限流） |
| xAI (Grok) | Management Key | Key + Team ID | 预付余额 |
| Qoder | 会话 Cookie | qoder.com Cookie | Big Model Credits 用量窗口 |
| Venice | API Key | venice.ai Key | USD/Diem 余额 |
| Nous Research | Portal Token | 访问令牌 | 订阅额度构成 |
| Muse Code (Meta) | 设备令牌 | muse login 令牌 | 订阅窗口用量 + 周用量 |
| Deepgram | API Key | Token 认证 | 音频时长/请求/Token 用量 |
| ClinePass | API Key | cline.bot Key | 5h/周/月 限额窗口 |
| Crof | API Key | crof.ai Key | 积分余额 + 可用请求 |
| Synthetic | API Key | synthetic.new Key | 多配额窗口（别名容错） |
| ClawRouter | 会话 Cookie | openclaw.ai Cookie | micros 预算 + 请求/Token 汇总 |
| LiteLLM | 虚拟密钥 | 自托管地址 + Key | 预算消耗率 + 重置时间 |
| LLM Proxy | API Key | 自托管地址 + Key | 配额组窗口 |
| ElevenLabs | API Key | `xi-api-key` | 字符用量窗口 + 套餐 |
| Fireworks | API Key | Bearer | 近 30 天计费汇总（lineItems 求和） |
| NeuralWatt | API Key | Bearer | 额度余量/已用/周期额度 |
| IBM Bob | API Key | JWT/Apikey | 各团队 Bobcoin 用量 + 预算窗口 |
| Ai& | API Key | Bearer | 近 30 天消费（分页汇总） |
| Codebuff | API Key | Bearer | 配额窗口 + 订阅状态 |
| Sub2API | API Key | 自托管地址 + Key | 日/周/月 用量 + 余额 |
| Devin | Bearer Token | 会话令牌 + 组织 | 配额窗口 |
| Abacus | 会话 Cookie | apps.abacus.ai Cookie | 算力点用量 + 套餐 |
| Command Code | 会话 Cookie | commandcode.ai Cookie | 额度 + 5 小时窗口 |
| LongCat | 会话 Cookie | longcat.chat Cookie | Token 份额窗口 |
| ZoomMate | 令牌/Cookie | zoommate.zoom.us | 今日/每周 额度窗口 |
| Notion AI | 会话 Cookie | 含 token_v2 | 额度速率窗口 |
| HuggingFace | Token | Bearer（Billing 读权限） | 推理计费窗口 + ZeroGPU |
| Warp | API Key | Bearer | 请求额度窗口（GraphQL GetRequestLimitInfo） |
| OpenCode | 会话 Cookie | Cookie（可选工作区 ID） | 订阅/PAYG 计费窗口（_server RPC） |
| OpenCode Go | 会话 Cookie | Cookie | Go 计费窗口 |
| Groq | 会话 Cookie | stytch_session（可选组织 ID） | 近 30 天活动用量（Stytch 交换） |
| 阿里云百炼编码计划 | API Key | 百炼/DashScope Key（intl/cn） | 5 小时/周/账单月 配额窗口 |
| 演示模式 | 无 | — | 拟真数据 |

### 其余服务商可行性分级（对照源工程 75+ 家）

- **桌面专属（无法移动化）**：依赖本地 CLI 配置/钥匙串/浏览器 Cookie 存储导入器、云控制台签名 RPC 或 IAM 签名的服务：Ollama 本地、AWS Bedrock、VertexAI/Gemini OAuth、Azure、Copilot、Cursor（浏览器抓取）、Doubao（火山 HMAC）、Kiro（AWS）、Antigravity、StepFun（设备注册）、QwenCloud 与 Alibaba Token Plan（阿里云控制台 Cookie+sec_token 签名 RPC 网关）、Grok 消费版（需桌面 `grok login` 授权，区别于已迁移的 xAI Management API）、Pi（本地 CLI 会话读取器）、Amp/Augment/JetBrains/Zed/CodeRabbit/Factory（CLI 探测/本地会话基础设施）、Wayfinder（仅 localhost）。
- **HTML 抓取 / 桌面专属（最终分类）**：Sakana（计费页 HTML 解析）、Replicate（HTML 抓取）、Windsurf（依赖 Devin 会话探测基础设施）、Ollama 本地、AWS Bedrock、VertexAI/Gemini OAuth、Azure、Copilot、Cursor、Doubao（火山 HMAC）、Kiro（AWS）、Antigravity、StepFun（设备注册）、QwenCloud（阿里云控制台签名 RPC）、Amp/Augment/JetBrains/Zed/CodeRabbit/Factory（CLI 探测/本地会话）、Wayfinder（仅 localhost）。除上述外，源工程全部服务商均已迁移。

端点与解析逻辑逐一对照 Swift 源码迁移（见下表），凭证登录态刷新流程与 macOS 版一致。

## 架构与迁移映射

```
entry/src/main/ets/
├── model/Models.ets          ← UsageFetcher.swift (UsageSnapshot/RateWindow/NamedRateWindow/ProviderDescriptor…)
├── common/
│   ├── Theme.ets             ← 菜单栏弹层深色风格（docs/codexbar.png）
│   ├── Format.ets            ← 倒计时/百分比/金额格式化
│   ├── Nav.ets               ← 路由与 Toast
│   ├── Notify.ets            ← 本地通知封装（@ohos.notificationManager 三端插件 + 授权请求）
│   └── OAuth.ets             ← 纯 TS SHA-256/PKCE/JWT 解码 + Codex 授权码换令牌/刷新
├── net/
│   ├── Http.ets              ← ProviderHTTPTransport（@ohos.net.http 封装，ArkUI-X 三端映射）
│   └── Json.ets              ← JSONSerialization 解析辅助（ArkTS 严格模式）
├── store/
│   ├── Settings.ets          ← resolved config（~/.config/codexbar/config.json）→ Preferences
│   ├── Reminders.ets         ← 额度提醒引擎（阈值/提前量判定 + 30s 周期检查 + 周期去重）
│   └── AppStore.ets          ← 用量状态中心 + 并发刷新编排
├── providers/
│   ├── ProviderBase.ets      ← UsageFetcher 协议 → UsageProvider 接口
│   ├── ProviderRegistry.ets  ← Provider 目录注册表
│   ├── ClaudeProvider.ets    ← Providers/Claude/ClaudeWeb/ClaudeWebAPIFetcher.swift
│   ├── CodexProvider.ets     ← Providers/Codex/CodexOAuth/CodexOAuthUsageFetcher.swift
│   ├── ApiKeyProviders.ets   ← Providers/{OpenRouter,DeepSeek,Moonshot,SiliconFlow,OpenAI,Claude(ClaudeAdminAPI)}
│   ├── MoreProviders.ets     ← Providers/{ZenMux,Manus,DeepInfra,Perplexity,Kimi(kimi.com),Chutes}
│   ├── MoreProviders2.ets    ← Providers/{MiniMax,MiMo,Mistral,Kilo,Poe,T3Chat,Zai}
│   ├── MoreProviders3.ets    ← Providers/{XAI,Qoder,Venice,Nous,Muse,Deepgram,ClinePass,Crof,Synthetic,ClawRouter,LiteLLM,LLMProxy}（含 QuickJS 插件移植）
│   ├── MoreProviders4.ets    ← Providers/{ElevenLabs,Fireworks,NeuralWatt,IBMBob,Ai&,Codebuff,Sub2API,Devin,Abacus,CommandCode,LongCat,ZoomMate,Notion}
│   ├── MoreProviders5.ets    ← Providers/{HuggingFace,Warp,OpenCode,OpenCodeGo,Groq}
│   ├── MoreProviders6.ets    ← Providers/Alibaba/{AlibabaCodingPlan 百炼编码计划}
│   └── DemoProvider.ets      ← 演示数据
├── view/UsageBar.ets         ← 用量条 + 窗口块组件
├── view/ProviderIcon.ets     ← 服务商品牌图标（lobe-icons 彩色 SVG + 白色圆角衬底）
├── pages/
│   ├── Index.ets             ← 菜单弹层 → 移动仪表盘
│   ├── ProviderDetail.ets    ← 服务商详情
│   ├── SettingsPage.ets      ← Settings → Providers 设置
│   └── OAuthLogin.ets        ← 应用内网页登录（Web 组件 + 回调拦截 + Cookie 轮询）
└── entryability/EntryAbility.ets
```

## 构建与运行（HarmonyOS）

```bash
# 1. 静态检查
devecocli check arkts

# 2. 构建 HAP
devecocli build

# 3. 签名（首次需要；华为开发者账号 OAuth + 连接设备注册）
devecocli auth login
devecocli signature generate --product default

# 4. 运行（模拟器或真机）
devecocli run

# 补充：本地宿主单元测试（纯逻辑层，无需设备）
hvigorw --mode module -p module=entry@default -p isLocalTest=true test
# 结果：Tests run: 8, Failure: 0（entry/.test/default/intermediates/test/coverage_data/test_result.txt）
```

## 构建与运行（Android / iOS，经 ArkUI-X，已验证）

工程已含 ArkUI-X 跨平台脚手架（`.arkui-x/android` Gradle 工程、`.arkui-x/ios` Xcode 工程），`arkui-x-config.json5` 声明 `crossplatform: true`。代码层仅使用 ArkUI-X 支持的 `@ohos` 能力（`@ohos.net.http`、`@ohos.data.preferences`、路由、ArkUI 声明式 UI），并已经过跨平台编译验证：

```bash
# Android：编译 ArkTS → 拷贝引擎库/资产 → Gradle 打包，一条命令完成
ace build apk
# 产物：.arkui-x/android/app/build/outputs/apk/release/app-release.apk (~72MB)
# 安装/启动到连接的 Android 设备：
ace install apk && ace launch apk

# iOS（模拟器）：
ace build ios --debug --simulator
# 产物：.arkui-x/ios/build/outputs/app/app.app
# 安装/启动到已启动的模拟器：
xcrun simctl install <udid> .arkui-x/ios/build/outputs/app/app.app
xcrun simctl launch <udid> com.example.codexbar
```

> `ace` CLI 位于 ArkUI-X SDK（`~/Library/ArkUI-X/Sdk/<ver>/arkui-x/toolchains/bin/ace`），环境配置用 `ace config`（android-sdk / harmonyos-sdk / java-sdk 等）。iOS 首次构建如遇 `IPHONEOS_DEPLOYMENT_TARGET` 过旧告警，已在工程中修正为 15.0；真机发行版用 `ace build ios -r` 并配置签名团队。

### 三端验证记录

| 平台 | 产物 | 验证 |
|---|---|---|
| HarmonyOS 7.0 (API 26) | `entry-default-unsigned.hap` | hvigor BUILD SUCCESSFUL + 本地单元测试 8/8 |
| Android（arm64-v8a / armeabi-v7a） | `app-release.apk` | 真机（MEY-AN00）安装、启动、设置页/卡片/开关/输入框/保存交互正常 |
| iOS（Simulator arm64） | `app.app` | iPhone 16 模拟器启动，仪表盘 8 家服务商卡片渲染正常（`screenshots/ios-dashboard.png`）|

## 图标

服务商品牌图标来自 [lobehub/lobe-icons](https://github.com/lobehub/lobe-icons)（MIT）的彩色/品牌 SVG，存放于 `entry/src/main/resources/rawfile/icons/`，经规范化（尺寸 1em→24、currentColor→纯黑）后由 `Image($rawfile(...))` 加载，渲染在白色圆角衬底上以保证深色主题下单色品牌标的可见性。无品牌图的服务商（Chutes、T3Chat、Deepgram、Crof、Synthetic、LiteLLM、演示模式）回退为强调色圆点。

## 隐私

凭证仅保存在本机应用数据目录，不经过任何中间服务器；刷新时由设备直连各服务商接口（与 macOS 版 "Privacy-first" 原则一致）。

## 后续计划

- 更多服务商（MiniMax、智谱 GLM、火山方舟/豆包、Groq、xAI 等）
- 桌面小组件（对标 macOS WidgetExtension）与用量历史曲线
- 多账号切换（对应 macOS 版 Managed Accounts）
