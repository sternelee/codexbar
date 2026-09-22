# CodexBar Mobile — AI 额度查询工具（HarmonyOS ArkTS）

> 「May your tokens never run out.」—— 在鸿蒙手机上随时查看每个 AI 服务商的用量、额度与重置倒计时。

本项目是 [CodexBar](https://github.com/steipete/CodexBar)（macOS 菜单栏应用，Swift，追踪约 75 家 AI 服务商限额）向 **HarmonyOS ArkTS 移动端** 的迁移版本，并借助 **ArkUI-X**（`.arkui-x/`，`crossplatform: true`，platforms: `android` / `ios`）面向 **鸿蒙手机、Android、iOS** 三个平台。

- SDK：`targetSdkVersion 26.0.0`（HarmonyOS 7.0）、`compatibleSdkVersion 6.1.1(24)`（见 `build-profile.json5`）
- 入口：`entry` 模块 · `EntryAbility` · `pages/Index`

## 功能

> **两条凭证线并存，按需选用**：既支持 API Key / 访问令牌 / AK-SK 签名直连，也支持网页 Cookie（如 claude.ai `sessionKey`）与应用内「网页登录」OAuth（Codex PKCE 授权 + refresh token 静默续期）。每个服务商的查询与展示逻辑均逐一对照 macOS 版 Swift 源码迁移；同一家服务商可二选一填写凭证（例如 Codex 既可粘贴 PAT，也可网页登录；ClawRouter / OpenCode Go 既能填会话 Cookie，也能填 API Key）。

- **仪表盘**：服务商卡片列表，用量进度条（会话 / 每周 / 每月窗口）、重置倒计时（秒级刷新）、余额展示、下拉刷新与一键全量刷新；列表将已配置凭证的服务商排在前面（已启用优先，组内保持注册表顺序）。窗口名优先取服务商自定义标签，其余由元数据表统一补齐（对照源工程 `ProviderMetadata` 的 `sessionLabel`/`weeklyLabel`/`opusLabel`，如 Codex 的 Session / Weekly、Claude 的 Session / Weekly / Sonnet、Copilot 的 Premium / Chat、Kimi 编码版的 7-day usage / 5-hour usage）。
- **详情页**：全部用量窗口、余额、账号身份、明细分组、错误原因、单服务商刷新；未配置或凭证失效时可在页内直接配置，保存后立即清除旧的失败提示并以新凭证重新查询。
- **提醒设置**（详情页）：逐服务商开启额度提醒——任一窗口用量达到阈值（50–95%，默认 90%）提示"额度即将用尽"；窗口重置前 5/15/30/60 分钟提示"额度即将恢复"。同一窗口同一周期只提醒一条（去重键随重置时间轮换），通知经 `@ohos.notificationManager` 三端插件发送，应用进程存活期间有效；点击通知可跳回应用（HarmonyOS 经 wantAgent 拉起 EntryAbility，Android/iOS 无该模块时走系统默认行为）。
- **用量统计**（仪表盘 📊 进入，对标 macOS CostHistoryChartMenuView）：按服务商的每日柱形图——「用量增量（百分点）」与「消费（余额降幅估算）」双指标、近7天/近30天范围切换；峰值日黄色帽、[0, 中点, 最大] 刻度、首末日期轴；今日/近7天/近30天合计。数据为本地刷新采样估算（每日最后样本，保留 62 天），与源工程扫描 CLI 会话的精确统计存在差异。
- **桌面卡片**（HarmonyOS 服务卡片，对标 macOS WidgetExtension）：2x2 速览卡（最紧急 2 家）与 2x4 列表卡（4 家），显示用量条 + 重置倒计时，点击进应用。应用每次刷新成功即写入摘要数据并即时推送已添加的卡片，另有 30 分钟定时更新兜底。
- **多账号**（全部服务商）：设置卡片「账号」条——点 chip 切换激活账号（立即刷新）、「＋」添加、长按弹出重命名/删除菜单（内联输入行改名，删除带确认框）；详情页显示当前激活账号名。Claude / Codex 的「＋」直接进入网页登录流程，其他服务商建空账号、填凭证保存即生效。同凭证自动去重（并补齐 refresh token / 额外字段），删除激活账号时自动转移到第一个剩余账号；凭证解析顺序为激活账号 → 旧单凭证键（完全向后兼容）。
- **应用内网页登录**（Claude / Codex / DeepSeek）：设置页或详情页点「网页登录」进入内嵌网页——Claude 自动从登录会话中捕获 `sessionKey`，DeepSeek 从 `platform.deepseek.com` 的 `localStorage.userToken` 捕获平台会话（与 macOS 读浏览器数据同一个键，所以用户只需填 API Key），Codex 走 PKCE 授权（本地回调解析 + JWT 提取账号 ID）；刷新返回 401/403 时用保存的 refresh token 静默续期并重试一次，无需重新登录。
- **额外配置字段**（`extraConfig`）：需要 3 个以上输入的服务商在设置页/详情页动态渲染字段——Azure OpenAI 的 Endpoint / Deployment / API 版本、Bedrock 的 Region / Session Token / 预算、v0 的 Scope、Copilot 的 Enterprise 域名。
- **设置页**：逐服务商开关 + 凭证录入（含额外字段），凭证仅存本机（`@ohos.data.preferences`），刷新时直连服务商接口。
- **明亮 / 暗色自适配**：配色全部走资源引用，`resources/base/element/color.json`（明亮）与 `resources/dark/element/color.json`（暗色）各一套，跟随系统深浅色即时切换，无需手工监听；启动窗口背景、服务卡片、明细图表与品牌图标衬底一并适配（卡片数据只能传 JSON，所以传的是用量「等级」而不是色值）。
- **演示模式**：无需任何凭证即可体验全部 UI。

## 支持的服务商（61 家 + 演示模式）

| 服务商 | 方式 | 凭证 | 展示内容 |
|---|---|---|---|
| Claude | Web 会话 / 网页登录 | claude.ai `sessionKey`（设置页「网页登录」自动捕获） | 5 小时/每周 会话窗口 + 订阅计划 |
| Codex (ChatGPT) | 网页登录 OAuth + PAT | PKCE 授权（refresh token 自动续期）或 OpenAI PAT | 主/次窗口 + 模型附加限制 + 账号/套餐 |
| v0 | API Key | v0 Platform API Key（可选 Scope） | 计费窗口 + 速率限制窗口 + 按量余额 |
| Amp | Access Token | `AMP_API_KEY` | Agent / Orb 用量窗口 + Amp Free 免费额度 + Individual/Workspace 余额 |
| Azure OpenAI | API Key | API Key + Endpoint + Deployment（+ API 版本） | 部署/模型校验结果、端点与版本明细 |
| Ollama | API Key | ollama.com API Key | 云端模型目录数量、Key 有效性校验 |
| Copilot | GitHub Token | GitHub PAT（需 copilot 读权限） | Premium / Chat 配额窗口 + Credits 计数 + 订阅计划 |
| OpenAI Platform | API Key | `sk-…` | 额度使用率 + 剩余/已用 |
| Anthropic 控制台 | Admin API Key | `sk-ant-admin…` | 本月 token 用量（输入/输出/缓存） |
| OpenRouter | API Key | `sk-or-v1-…` | 额度使用率 + 剩余额度 |
| DeepSeek | API Key（平台会话自动获取） | 只需 `sk-…`；用量明细的平台会话由详情页「网页登录」自动抓取（对照 macOS 自动读浏览器，无需手填令牌） | 余额（首页只显 `¥X.XX`，详情页说明行才是 macOS 原句 `(Paid: … / Granted: …)`）+ `Usage`（Today / Last 30 days 或 This month / Requests / API keys / Top model + 每日 token 图）与 `Spend`（各模型花费 + 每日花费图）；by-key 失败自动回退月度账户数据 |
| Kimi (Moonshot) | API Key | `sk-…` | 可用余额（现金/代金券） |
| SiliconFlow 硅基流动 | API Key | `sk-…` | 总余额（充值/赠送） |
| Kimi 编码版 (kimi.com / kimi.ai) | 访问令牌 / API Key | kimi.com authToken 或 Kimi Code API Key（sk-…） | 编码额度 5 小时/每周/月度 窗口 + 计划名（intl 自动降级） |
| Manus | 会话令牌 | manus.im 会话 token | 用量窗口 + 额度构成 |
| Perplexity | Web 会话 | perplexity.ai 会话 Cookie | 余额与用量窗口 |
| MiMo (小米) | Web 会话 | platform.xiaomimimo.com 会话 Cookie | 配额窗口 + 明细 |
| Mistral | Web 会话 | admin.mistral.ai 会话 Cookie | 余额明细 |
| T3 Chat | Web 会话 | t3.chat 会话 Cookie | 4 小时/月度 用量窗口 + 订阅 |
| Qoder | Web 会话 | qoder.com（或 .cn）会话 Cookie | Big Model Credits 配额 |
| Muse Code | Web 会话 | Muse 会话 Cookie | 订阅额度构成 |
| ZenMux | Management Key | `zenmux.ai` 管理密钥 | 5h/7d 配额 + PAYG 余额 + 套餐 |
| DeepInfra | API Key | deepinfra.com Key | 余额/上限/本月花费 |
| Chutes | API Key | chutes.ai Key | 4h 滚动 + 月度配额窗口（别名容错解析） |
| MiniMax | API Token（+ 可选平台会话 Cookie） | 平台密钥；第二栏 platform.minimaxi.com 会话 Cookie | 周期/每周配额窗口（token_plan 与 coding_plan 双端点降级）+ `Billing history` 账单明细 |
| Kilo Code | API Key | Key（可选组织 ID） | Kilo Pass 用量 + 信用块明细 |
| Poe | API Key | poe.com/api/keys | 积分余额 |
| z.ai / GLM 智谱 | API Key | z.ai 或 BigModel Key | 配额窗口（Token/时间/Credit 多限流） |
| xAI (Grok) | Management Key | Key + Team ID | 预付余额 |
| Venice | API Key | venice.ai Key | USD/Diem 余额 |
| Nous Research | Portal Token | 访问令牌 | 订阅额度构成 |
| Deepgram | API Key | Token 认证 | 音频时长/请求/Token 用量 |
| ClinePass | API Key | cline.bot Key | 5h/周/月 限额窗口 |
| Crof | API Key | crof.ai Key | 积分余额 + 可用请求 |
| Synthetic | API Key | synthetic.new Key | 多配额窗口（别名容错） |
| ClawRouter | Web 会话 / API Key | 会话 Cookie，或 policy API Key（第二栏可填自托管 Base URL） | micros 月度预算 + 请求/Token 汇总 + 被路由服务商费用 Top20 |
| LiteLLM | 虚拟密钥 | 自托管地址 + Key | 预算消耗率 + 重置时间 |
| LLM Proxy | API Key | 自托管地址 + Key | 配额组窗口 |
| ElevenLabs | API Key | `xi-api-key` | 字符用量窗口 + 套餐 |
| Factory AI | API Key | Bearer（fk-…） | billing/limits 限额窗口 + analytics 近30天 token 用量 |
| Fireworks | API Key | Bearer | 近 30 天计费汇总（lineItems 求和） |
| NeuralWatt | API Key | Bearer | 额度余量/已用/周期额度 |
| IBM Bob | API Key | JWT/Apikey | 各团队 Bobcoin 用量 + 预算窗口 |
| Ai& | API Key | Bearer | 近 30 天消费（分页汇总） |
| Codebuff | API Key | Bearer | 配额窗口 + 订阅状态 |
| Sub2API | API Key | 自托管地址 + Key | 日/周/月 用量 + 余额 |
| Devin | Bearer Token | 会话令牌 + 组织 | 配额窗口 |
| Abacus | Web 会话 | apps.abacus.ai 会话 Cookie | 用量/余额窗口 |
| Command Code | Web 会话 / API Key | commandcode.ai 会话 Cookie 或 API Key | 用量窗口 |
| LongCat | Web 会话 | longcat.chat 会话 Cookie | 配额窗口 |
| ZoomMate | 会话令牌 | zoommate.zoom.us 会话令牌或 Cookie | 用量窗口 |
| Notion AI | Web 会话 | app.notion.com Cookie（含 `token_v2`） | AI 信用额度 |
| HuggingFace | Token | Bearer（Billing 读权限） | 推理计费窗口 + ZeroGPU |
| Warp | API Key | Bearer | 请求额度窗口（GraphQL GetRequestLimitInfo） |
| OpenCode | Web 会话 | opencode.ai 会话 Cookie；可选第二栏填工作区 ID | 订阅/用量窗口（`_server` RPC） |
| OpenCode Go | Web 会话 / API Key | opencode.ai 会话 Cookie 或 OpenCode Zen API Key | 5 小时（rolling）/每周/月度 用量窗口 |
| Groq | Web 会话 | groq.com `stytch_session` Cookie；可选第二栏填组织 ID | 订阅额度 + 活动 API 用量 |
| 阿里云百炼编码计划 | API Key | 百炼/DashScope Key（intl/cn） | 5 小时/周/账单月 配额窗口 |
| Doubao (豆包/火山方舟) | AK/SK 或 API Key | 火山方舟 AK + Secret Access Key（或单独 Ark API Key） | 编码计划 5h/周/月 + Agent 计划窗口；仅填 API Key 时按请求额度探测 |
| AWS Bedrock | AWS Access Key + Secret | Access Key ID + Secret Access Key（可选 Region / Session Token / 月度预算） | Cost Explorer 本月 Bedrock 花费 + 预算使用率 + 近14天 Claude tokens/请求数 |
| 演示模式 | 无 | — | 拟真数据 |

### 其余服务商可行性分级（对照源工程 75+ 家）

- **本轮恢复（网页会话 / OAuth 网页登录）**：Claude（claude.ai `sessionKey`，应用内网页登录自动捕获）、Codex（PKCE 授权 + refresh token 续期，同时保留 PAT 路径）、Perplexity、Manus、MiMo、Mistral、T3 Chat、Qoder、Muse Code、Abacus、Command Code、LongCat、ZoomMate、Notion AI、OpenCode（`_server` RPC），以及 Groq / Kimi 编码版 / ClawRouter / OpenCode Go 的 Cookie 路径。对应 API Key 侧能力保留：Claude/Anthropic 控制台走 Admin API Key（`anthropic-console`），Kimi 走 Kimi Code API Key，ClawRouter / OpenCode Go 可填 API Key。
- **仍不迁移（桌面专属 / CLI 探测 / HTML 抓取）**：Gemini / Antigravity / Vertex AI（OAuth 或桌面授权）、AWS Bedrock Profile 模式、Azure 容器外端点、Cursor / Augment / Windsurf / JetBrains / Zed / CodeRabbit（CLI 探测或浏览器 Cookie 存储）、Kiro（AWS）、Copilot 预算页括取、Ollama 本地、StepFun（设备注册）、QwenCloud 与 Alibaba Token Plan（阿里云控制台 Cookie+sec_token 签名 RPC 网关）、Grok 消费版（需桌面 `grok login`）、Sakana / Replicate（HTML 解析）、Pi（本地 CLI 会话读取器）、Wayfinder（仅 localhost）、Helmcode / TypeSafe（网页会话）。

> Doubao（豆包/火山方舟）与 AWS Bedrock 同为 AK/SK 签名模式：火山引擎 Top OpenAPI 与 AWS SigV4（Cost Explorer / CloudWatch）都建立在 `common/Crypto.ets` 的纯 TS HMAC-SHA256 链上（`common/VolcSign.ets` / `common/AwsSign.ets`），三端零平台依赖。

端点与解析逻辑逐一对照 Swift 源码迁移（见下表）；API Key / 访问令牌 / AK-SK 签名与网页 Cookie / OAuth 网页登录两条线并存，仍不迁移的服务商见上方范围说明。

## 架构与迁移映射

```
entry/src/main/ets/
├── model/Models.ets          ← UsageFetcher.swift (UsageSnapshot/RateWindow/NamedRateWindow/ProviderDescriptor…)
├── common/
│   ├── Theme.ets             ← 主题取色器（资源引用 + 尺度 + Canvas/品牌色适配）
│   ├── Format.ets            ← 倒计时/百分比/金额格式化
│   ├── Nav.ets               ← 路由与 Toast
│   ├── Notify.ets            ← 本地通知封装（@ohos.notificationManager 三端插件 + 授权请求 + 点击拉起应用）
│   ├── WantAgent.ets         ← 通知 wantAgent 构建（独立模块，便于跨端动态加载降级）
│   ├── OAuth.ets             ← Codex PKCE 授权 / 回调解析 / JWT 账号提取 / Claude sessionKey 捕获
│   ├── Crypto.ets            ← 纯 TS SHA-256 / HMAC-SHA256 / Base64URL（三端零依赖，可本地单测）
│   ├── VolcSign.ets          ← 火山引擎 V4 请求签名（Doubao，复用 Crypto）
│   └── AwsSign.ets           ← AWS SigV4 请求签名（Bedrock，复用 Crypto）
├── net/
│   ├── Http.ets              ← ProviderHTTPTransport（@ohos.net.http 封装，ArkUI-X 三端映射）
│   └── Json.ets              ← JSONSerialization 解析辅助（ArkTS 严格模式）
├── store/
│   ├── Settings.ets          ← resolved config（~/.config/codexbar/config.json）→ Preferences
│   ├── Reminders.ets         ← 额度提醒引擎（阈值/提前量判定 + 30s 周期检查 + 周期去重）
│   ├── UsageHistory.ets      ← 用量历史采样与统计派生（统计页数据源）
│   ├── WidgetData.ets        ← 桌面卡片摘要数据
│   └── AppStore.ets          ← 用量状态中心 + 并发刷新编排
├── providers/
│   ├── ProviderBase.ets      ← UsageFetcher 协议 → UsageProvider 接口
│   ├── ProviderRegistry.ets  ← Provider 目录注册表
│   ├── ApiKeyProviders2.ets  ← Providers/{V0, Amp, AzureOpenAI, Ollama, Copilot}（本轮新增）
│   ├── ClaudeProvider.ets    ← Providers/Claude/ClaudeWeb/ClaudeWebUsageFetcher.swift（claude.ai sessionKey）
│   ├── CodexProvider.ets     ← Providers/Codex/{CodexOAuth,CodexPAT}（wham/usage + whoami，OAuth 自动续期）
│   ├── ApiKeyProviders.ets   ← Providers/{OpenRouter,DeepSeek,Moonshot,SiliconFlow,OpenAI,Claude(ClaudeAdminAPI)}
│   ├── MoreProviders.ets     ← Providers/{ZenMux,DeepInfra,Kimi Code,Kimi 编码版,Chutes}
│   ├── MoreProviders2.ets    ← Providers/{MiniMax,Kilo,Poe,Zai}
│   ├── MoreProviders3.ets    ← Providers/{XAI,Venice,Nous,Deepgram,ClinePass,Crof,Synthetic,ClawRouter(Cookie/API Key),LiteLLM,LLMProxy}（含 QuickJS 插件移植）
│   ├── MoreProviders4.ets    ← Providers/{ElevenLabs,Fireworks,NeuralWatt,IBMBob,Ai&,Codebuff,Sub2API,Devin,ZoomMate,Notion}
│   ├── MoreProviders5.ets    ← Providers/{HuggingFace,Warp,OpenCode(Cookie RPC),OpenCodeGo(Cookie/Zen API Key),Groq(stytch 会话)}
│   ├── MoreProviders6.ets    ← Providers/{Alibaba/AlibabaCodingPlan 百炼编码计划, Factory}
│   ├── DoubaoProvider.ets    ← Providers/Doubao/{DoubaoUsageFetcher,DoubaoVolcengineSigner}
│   ├── BedrockProvider.ets   ← Providers/Bedrock/{BedrockUsageStats,BedrockCloudWatchUsage,BedrockAWSSigner}
│   └── DemoProvider.ets      ← 演示数据
├── view/
│   ├── DetailChart.ets       ← 明细分组图表（ProviderDetailSection.Chart 的柱状/折线渲染）
│   ├── UsageBar.ets          ← 用量条 + 窗口块 + 明细行内进度条（Row.progress）
│   └── ProviderIcon.ets      ← 服务商品牌图标（lobe-icons 彩色 SVG + 白色圆角衬底）
├── pages/
│   ├── Index.ets             ← 菜单弹层 → 移动仪表盘
│   ├── ProviderDetail.ets    ← 服务商详情
│   ├── SettingsPage.ets      ← Settings → Providers 设置
│   ├── OAuthLogin.ets        ← 应用内网页登录（Claude sessionKey 捕获 / Codex PKCE）
│   └── StatsPage.ets         ← 用量统计（柱形图 + 周/月合计）
├── form/FormPush.ets         ← 鸿蒙专属卡片推送（动态加载）
├── entryformability/EntryFormAbility.ets ← 服务卡片 FormExtensionAbility（添加/定时更新/移除）
├── widget/pages/            ← 卡片页：WidgetCard(2x2)、WidgetListCard(2x4)、WidgetTheme(等级→资源色)
└── entryability/EntryAbility.ets     ← 启动时把系统色彩模式写入 AppStorage（供 Canvas 取用）
```

```
entry/src/main/resources/
├── base/element/color.json   ← 明亮模式调色板（bg/card/stroke/text/accent/条形色…）
└── dark/element/color.json   ← 暗色模式同名调色板（限定词目录，系统切换时自动生效）
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
# hvigorw 随 DevEco Studio 分发；不在 PATH 上时用绝对路径（并确保 DEVECO_SDK_HOME 指向 SDK）：
#   export DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk
#   /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw --mode module ...
hvigorw --mode module -p module=entry@default -p isLocalTest=true test
# 结果：Tests run: 50, Failure: 0（entry/.test/default/intermediates/test/coverage_data/test_result.txt）
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
| HarmonyOS 7.0（target API 26，最低兼容 API 24） | `entry-default-unsigned.hap` | 本轮重验：`devecocli check arkts` 0 error + 本地单元测试 50/50 + hvigor BUILD SUCCESSFUL |
| Android（arm64-v8a / armeabi-v7a） | `app-release.apk` | 上一版本产物（真机 MEY-AN00 安装、启动与交互正常）；本轮需 `ace build apk` 重建 |
| iOS（Simulator arm64） | `app.app` | 上一版本产物（iPhone 16 模拟器渲染正常）；本轮需 `ace build ios` 重建 |

## 图标

服务商品牌图标来自 [lobehub/lobe-icons](https://github.com/lobehub/lobe-icons)（MIT）的彩色/品牌 SVG，存放于 `entry/src/main/resources/rawfile/icons/`，经规范化（尺寸 1em→24、currentColor→纯黑）后由 `Image($rawfile(...))` 加载，渲染在白色圆角衬底上以保证深色主题下单色品牌标的可见性。本轮共 57 个 SVG：除 v0 / Amp / Ollama / Bedrock / Copilot / Chutes / ClawRouter / Codebuff / Deepgram / LiteLLM / NeuralWatt / Sub2API / Synthetic / Warp / 阿里云百炼 / Ai& / ClinePass 外，另从源工程 `Sources/CodexBar/Resources/ProviderIcon-*.svg` 补齐了恢复服务商的品牌标——Claude `claude-color`、Manus、Perplexity、MiMo `xiaomimimo`、Mistral、Qoder、Muse `meta-color`、Notion、OpenCode，以及此前只有彩色圆点的 T3 Chat / Abacus / **Command Code** / LongCat / ZoomMate / Factory AI（白稿已按品牌色或黑色重着色以适配白色圆角衬底）。未收录品牌图的服务商仅 Crof（该服务商在源工程已退役，无官方资源）与演示模式，回退为强调色圆点；Azure OpenAI 复用 OpenAI 图标。

强调色同样对齐源工程的 `ProviderBranding.color`：Claude `#CC7C5E`、Command Code `#A04DFD`、Abacus `#38BDF8`、LongCat `#FFD100`、ZoomMate `#0B5CFF`、Notion `#337EA9`、T3 Chat `#F56647`、Qoder `#10B981`、Perplexity `#20B2AA`、Manus `#34322D`、OpenCode / OpenCode Go `#3B82F6`、Groq `#F56844`、Kimi 编码版 `#FE603C`、ClawRouter `#596EF6`。

## 隐私

凭证仅保存在本机应用数据目录，不经过任何中间服务器；刷新时由设备直连各服务商接口（与 macOS 版 "Privacy-first" 原则一致）。

## 后续计划

本轮已完成（明亮/暗色主题自适配 + UI 一致性）：把「深色单主题」改成跟随系统的双主题。

- **颜色全部资源化**：新增 `resources/base/element/color.json`（明亮）与 `resources/dark/element/color.json`（暗色同名额），`common/Theme.ets` 由「静态 hex 常量」改为资源取色器（`static get bg(): Resource` → `$r('app.color.bg')`），因此 250 多处调用点一行未改就跟着系统切换；暗色值与原观感逐项对齐（`bg #0B0B0F` / `card #17171E` / `accent #16D3B4` …），明亮值另调一套（`bg #F2F2F7` / `card #FFFFFF` / `accent #0A8471` 等，主色加深以保证白底对比度）。启动窗口背景也从写死白改成双主题。
- **两处必须字面色值的例外**：① Canvas 2D（`DetailChart.ets` 的 `fillStyle`/`strokeStyle`）走 `Theme.chartAccent()/chartStroke()`，由 `Theme.isDark()` 决定，而该标记由 `EntryAbility.applyColorMode()` 从 `resourceManager.getConfigurationSync().colorMode` 写入 AppStorage（`onConfigurationUpdate` 时刷新）；② 服务卡片数据是 FormBindingData 的 JSON，塞不进资源引用，因此 `WidgetItem.color` 改为 `level`（ok/warn/danger/unknown），由新增的 `widget/pages/WidgetTheme.ets` 映射到 `$r('app.color.bar_*)`，卡片随手系统深浅色换色。
- **UI 一致性微调**：7 个圆角图标按钮（返回/刷新/统计/设置等）补一圈 `Theme.stroke` 描边，白色按钮在明亮模式的浅灰底上仍有边界；服务商图标衬底保持白色（白底才托得住 OpenAI、Bedrock 这类单色标）但新增 `icon_plate_edge` 描边（暗色下与衬底同色即不可见）；错误提示条的 `#2A1518` 与品牌图标回退点的极端色值（Warp 的 `#FFFFFF`、ElevenLabs 的 `#000000`）统一走 `Theme.dangerTint` / `Theme.brandTint()`；新增 `Theme.gap`/`rowGap` 间距常量。
- **测试**：`Theme.barColor` 这类「返回资源引用」的 API 无法在宿主单测里比较，改为断言纯逻辑层——`Theme.barLevel`（阈值分级）与 `Theme.brandTint`（近白/近黑/非 hex 回落主色、中间调原样保留）；卡片用例同步改断言 `level`。

本轮已完成（DeepSeek 明细逐条对账）：把 DeepSeek 详情页对着 `DeepSeekUsageFetcher` / `DeepSeekUsageCostParser` 逐行核了一遍。

- **月度回退路径**（源工程的关键行为）：macOS 先请求 `by_api_key/amount` + `by_api_key/cost`（近 30 天），**任何一步失败就回退到账户级** `usage/amount` + `usage/cost?month=&year=`（本月）。我们原来失败就只剩余额，现在补上这条回退：`deepseekMonthlyUsage` 复刻 `parse` + 月度聚合（`total[]` 出 Top model 与模型花费、`days[]` 按「本月且不晚于当下」过滤出每日序列、cost 的 `biz_data` 是币种数组取首块、`apiKeyCount = 0`）。
- **周期标签**：明细第二行按 `period` 取 `Last 30 days`（by-key）或 `This month`（回退），不再写死。
- **金额缺失显示 `—`**：`Today` / 周期行的花费为空时按源工程的 `cost` 闭包显示 `—`，不再把 nil 当 0；今日 token 仍是千分位。
- **数值解析收紧**：`parseTokenAmount` = `Int64(text) ?? 0`、`parseCostAmount` = `Double(text) ?? 0`，所以 `"1.5"`、`0.25abc` 一律记 0（原来是宽容 `parseFloat`）；模型花费里出现未知类别或缺金额时**整个模型丢弃**（`ModelCostTotals.unavailable` 语义）。
- **余额文案对齐**：`ProviderCostSnapshot` 新增可选的 `detailText`——首页卡片与详情页大号数字只显示短文案 `¥12.00`，macOS 余额窗口的原句 `¥12.00 (Paid: ¥10.00 / Granted: ¥2.00)` 只在详情页作为说明行出现（不会把首页卡片撞成两行）；余额为 0 时补「请在 platform.deepseek.com 充值」提示；余额构成行按 总额 / 充值 / 赠送 排列。
- **明细不可用时的提示**：平台会话缺失或已失效时，详情页出现 `用量明细` → 平台用量 提示行（对照 macOS 的 `.notRequested` / `.webSessionRequired` 菜单提示），而不是默默什么都不显示。

本轮已完成（明细图表 + ZoomMate Pace）：把源工程 `ProviderDetailSection.Chart` 落到 UI 层并接上已有的每日序列。

- **图表渲染**（`view/DetailChart.ets`）：详情页每个明细分组在行下方按 `chart.kind` 画柱状（默认）或折线——柱体按「最大值归一化」定标、颜色按占比加深、0 值画 1px 细条（对照 `UsageChartScale` + `ProviderDetailChartContent` 的 `max(3, ratio*height)` / `max(0.18, ratio)` 下限），顶部一行「标题 + 单位」，底部 1px 基线；点序列裁到 120 条（`maximumPointsPerChart`）。
- **接上每日序列的五家**：Anthropic 控制台 `Usage summary` → `Daily spend`(USD)；Groq `Usage summary` → `Daily spend`(USD)（活动行按本地日聚合，且补齐 `n_non_cached` 缺失时回退成上下文总量的取值）；MiniMax `Billing history` → `Daily tokens`；DeepSeek `Usage` → `Daily tokens`、`Spend` → `Daily cost`（全 0/缺失时不画费用图，仅保留花费行）；ZoomMate `Credit history` → `Daily credits`。
- **行内进度条**（`ProviderDetailSection.Row.progress`）：明细行行尾数字下面多一条细进度条（`view/UsageBar.ets` 的 `RowProgressBar`，中性轨道 + 服务商主色填充）；模型新增 `RowProgress` + `rowProgress(used, total)`（分母必须 > 0 且两个数有限，否则按无进度条处理）与 `progressPercent`（**不截断**，超额计划 > 100，截断只在渲染层）；缓存还原会把非法进度丢掉（分母 ≤ 0 / 非数字）。生产者按源工程接上 **Copilot**：设置里新增可选「席位包含额度」（`seatEntitlement`，对照 macOS 的 seat credit entitlement 输入框，`copilotSeatEntitlement` 只接受完整正数，`1e999`/`12abc` 一律忽略），填了之后 `Credits` 分组的 `Credits used` 行变成 `已用 / 额度` 并带进度条，未填则维持纯数字（GitHub 不公开包含额度上限，分母只能手填）；顺手把该行的重置副文本也补上（`Format.dateTime`）。数字格式新增 `Format.creditsNumber`（千分位 + 最多两位小数、去尾随 0）。
- **缓存与可见性**：`UsageSnapshot.fromStored` 新增逐字段校验（缺 `chart` 的旧缓存按无图表处理，`points` 非数组/空标题/缺字段的分组与行直接丢弃），避免 UI 读 `undefined`；`visibleDetails` 在删除被费用卡承载的重复行后保留图表（行被吃光但有图表的分组照旧渲染，与源工程一致）。
- **ZoomMate · Pace 行**：复刻 `ZoomMateCreditStatus.pacingVerdict` —— 预算上限 > 0 且非无限额、周期起止可解析时，以周期长度作为 `windowMinutes` 走 `UsagePace.weekly(workDays: nil)` 的线性分支（|delta| ≤2 = `On track`，≤6/≤12/更大分别对应 slightly/normal/far 的 ahead/behind 文案）；周期刚开头就已有消耗或重置点已过时不判定。明细同步收敛为 `Credit history`（Today / 30d credits / Pace）。
- **ZoomMate 历史分页**：由单次 `limit=200` 改成源工程同款 `limit=50` 逐页翻（`page*limit < total` 且 ≤20 页），并在「空页」「整页都早于 30 天窗口起点」时停页；每日聚合窗口统一为「今天往前 29 天」的本地零点（`dailyBreakdown` 语义），`is_deleted` / `cost` 缺失或为负 / `time` 无法解析的记录一律跳过。

本轮已完成（DeepSeek 凭证体验对齐 macOS“只填 API Key”）：重新核了源工程后发现 macOS 的 DeepSeek 界面本来就**没有**平台会话输入框——`DeepSeekProviderDescriptor` 的令牌账号支持是 `requiresManualCookieSource: false`，会话由 `DeepSeekPlatformTokenImporter` 自动从浏览器（Chrome localStorage 的 `userToken`）或 `DEEPSEEK_PLATFORM_TOKEN` 环境变量取得；对比 MiniMax 是 `requiresManualCookieSource: true`，所以那边 macOS 确实有手填 Cookie 框。

- **DeepSeek 不再要求（也不再提供）手填平台令牌**：`needsSecondCredential('deepseek')` 改为 `false`，设置页与详情页凭证卡不再出现第二个输入框；API Key 不变。
- **会话改由应用内「网页登录」自动获取**：详情页在「已填 API Key、缺平台会话」时显示卡片（一键跳转 `platform.deepseek.com`，登录后读 WebView 里 `localStorage.userToken`，与 macOS 读的是同一个键），设置页也有「网页登录」按钮；鸿蒙端读不到其他应用的浏览器数据，一次点击是可用的最小代价。
- **提示文案随之调整**：无会话时 `用量明细` 提示行改为「点详情页「网页登录」自动获取平台会话后可见近 30 天用量与花费」；凭证提示改为「用量明细需「网页登录」一次自动获取平台会话」；会话过期时提示重新登录。
- **仍保留 API Key 直试平台接口**的尽力尝试（能通就直接出明细，不需要任何额外动作）。

本轮已完成（明细行与 optionalDetails 对齐）：把各家 `details` 分组逐条对照源工程实现补齐，并把 Swift 的 `ProviderUsagePresentation.optionalDetails` / `ProviderCostPresentation.replacedDetailRows` 两条可见性规则落成代码。

- **策略层**（`model/Models.ets`）：`optionalDetailsFor(id)` 登记源工程仅有的 8 条声明（Claude Admin 与 Groq / OpenAI / zAI 的 `costSummaryTitles`、MiniMax 的 `Billing history`、DeepSeek 与 Sakana 的 `hidesAllWithoutOptionalUsage`；Sakana 未迁移服务商，表内保留对应字段便于后续接入）；`replacedDetailRowsFor(id, costVisible)` 复刻 OpenRouter / TypeSafe 的“费用卡已展示时删除重复行”；`visibleDetails(...)` 把两者串成一次过滤，详情页 `sections()` 单点调用。
- **设置项**：设置页新增“展示可选用量明细”开关（`Settings.showOptionalDetails`，默认开启，对应 macOS `showOptionalCreditsAndExtraUsage`）；关闭后 DeepSeek 整块隐藏明细、MiniMax 隐藏 `Billing history`。
- **网页会话明细**：MiniMax 与 DeepSeek 新增网页会话路径（与源工程同名同语义）。两者的手填入口按 macOS 的 `requiresManualCookieSource` 区分：MiniMax 为 `true`（保留第二凭证输入框，可粘贴 Cookie Header），DeepSeek 为 `false`（界面不提供令牌输入框，平台会话只由应用内「网页登录」自动抓取）。留空/未登录则行为与之前一致。
  - **MiniMax · Billing history**：`GET platform.{minimaxi.com|minimax.io}/account/amount?page=N&limit=100&aggregate=false`（Cookie + `x-requested-with` + 控制台 UA，两域名依次回退），逐页拉到“早于 30 天窗口”为止；聚合器复刻 `MiniMaxBillingHistoryParser`（跳过非 SUCCESS、`consume_token` 优先否则 input+output、`consume_cash_after_voucher` 优先，按本地日/model/method 累加，Top 取前三）→ 分组行：Today tokens / 30d tokens / Today cash / Models / Top model / Top method / 30d cash。关闭“展示可选用量明细”时该分组隐藏（策略表已配 `hiddenTitlesWithoutOptionalUsage`）。
  - **DeepSeek · Usage + Spend**：`GET platform.deepseek.com/api/v0/usage/by_api_key/{amount,cost}?start=&end=&tz=`（`Bearer <平台会话令牌>` + `x-client-platform: web`），逐桶合并 near-30-day 序列（`PROMPT_CACHE_HIT_TOKEN` / `PROMPT_CACHE_MISS_TOKEN` / `RESPONSE_TOKEN` 计 token，`REQUEST` 计请求数），花费优先取“USD 且有金额”的币种块 → 分组行：Today / Last 30 days（花费 · tokens）、Requests、API keys、Top model，以及 Spend 分组（各模型花费，降序）。配合 `hidesAllWithoutOptionalUsage`，关闭开关时两个分组整体隐藏。
- **逐家明细补齐**：

| 服务商 | 补齐内容（对照源工程） |
|---|---|
| Anthropic 控制台 | 由单月 token 汇总改为 `cost_report` + `usage_report`（UTC 31 日桶）：`Usage summary`（Today/7d/30d spend、Today/30d tokens、Cache read、Top model）+ `Cost items`（花费明细前 20）+ 费用卡 `Last 30 days` |
| OpenAI Platform | 旧 dashboard 回退路径按源工程 `openai.js` 回退分支对齐：`API credits` 三行（Available / Used / Granted）、费用卡周期 `API credits`、以授予额度为分母的配额、identity `API balance: …` |
| Groq | 活动接口按 `n_context_tokens_total - n_non_cached_context_tokens_total` 计缓存、`context + generated` 计 Token：`Usage summary`（Spend/Requests/Tokens/Cached input）+ `Models`（前 20，tokens/requests）+ 费用卡 |
| z.ai / GLM | `Quota details`（Token/Credit quota、Session quota、时段费率 Peak/Off-peak + 倒计时、MCP quota） |
| xAI | `Billing summary`（Prepaid balance + 近 30 天花费，时段分析接口尽力查询）+ 费用卡周期 `Prepaid credits` |
| ClawRouter | `Usage`（Requests 副文本成功/失败、Tokens 副文本输入/输出、Actual cost 6 位小数、Budget ledger）+ 预算行 + `Routed providers`（按花费降序前 20） |
| Deepgram | 逐项目累加 `usage/breakdown`：`Usage summary`（Requests、Audio + billable hours、Agent hours、Tokens、TTS characters、Period） |
| HuggingFace | `Inference Providers`（Billable/Gross/Included/Spending limit/Requests）+ 独立 `ZeroGPU` 分组（GPU time used/remaining） |
| Nous | `Subscription`（Subscription credits / Monthly grant / Rollover / Renews）+ `Credits`（Top-up / Total usable） |
| Muse Code | `Muse Code subscription`（Plan、5 hours %、Weekly %；无用量时 Quota 兜底行）+ 身份邮箱 |
| Poe | `Points`（Current balance、Today/Last 7 days/Last 30 days 汇总、Top model、Usage mix），分页拉取 `points_history` |
| Sub2API | 新增 `Usage summary`（Balance + Today/All time 的 requests 与 tokens，副文本为花费） |
| IBM Bob | 分组改名 `Bobcoin usage`，行文案按 TeamUsage（`instanceName · teamName`、`used / limit Bobcoins`、套餐副文本） |
| MiMo | 分组改名 `Credits`，`Balance` 行按 `balanceDetail` 拼 `¥X (Paid: ¥Y / Granted: ¥Z)` |
| ZoomMate | 明细收敛为 `Credit history`（Today / 30d credits / Pace + `Daily credits` 柱状图），余额与周期交由主窗口承载 |
| Amp | `Monthly allowances` 补 Orb 行（`< 1h` / `Nh` + a1.small-equivalent 副文本），`Credits` 的 Individual 补副文本 |
| Codex | `wham/usage` 的 credits 节点 → 费用卡（币种 `Credits`、周期 `Extra usage`） |

本轮已完成（元数据对齐）：把 61 家服务商的窗口标签、泳道顺序、默认开关逐条对照源工程 Swift 描述符校准——`windowLabelsFor` 集中登记标签表（Codex 的 Primary/Secondary 改为 Session/Weekly；Kimi 编码版按 `primary=.weekly` 绑定把 7 天池换到主窗口；ClinePass 的月度额度从附加窗口提升为第三窗口；Synthetic 按插件 `synthetic.js` 的具名泳道 rollingFiveHourLimit / weeklyTokenLimit / search.hourly 落位并回退扫描配额数组；`isDefaultEnabledProvider` 仅 Codex 默认开启、`isPrimaryProvider` 为 Claude/Codex）；标签在 AppStore 统一补齐（缓存回放与刷新成功后各一次），服务商显式标签优先不被覆盖。

本轮已完成（两条凭证线并存）：恢复网页 Cookie / OAuth 网页登录整条线（Claude 网页会话、Codex PKCE + refresh 续期、Perplexity / Manus / MiMo / Mistral / T3 Chat / Qoder / Muse / Abacus / Command Code / LongCat / ZoomMate / Notion / OpenCode、Groq 会话），与新增的 API Key 服务商（V0 / Amp / Azure OpenAI / Ollama / Copilot / Bedrock）并存；ClawRouter / OpenCode Go 保留双模式（Cookie 或 API Key）；`ProviderAccount` 同时承载 refreshToken 与 extraConfig。

待办（按优先级）：

1. **泳道门控与明细行**：
   - `primaryBindingQuotaLanes`（Claude/Chutes/ZenMux/z.ai/CommandCode 为 `.secondary`，ClinePass/Doubao/阿里云百炼为 `.secondary + .tertiary`）：源工程语义是「较长的配额泳道有余额时，会话泳道才可用」，目前我们只标注窗口、未渲染该“受限”状态。
   - `widgetSelectable: false`（如 Doubao / xAI / Perplexity / CommandCode 等）在源工程里不出现在桌面小组件；我们的卡片目前是按用量自动取前 4 家，尚未接这个开关。
   - `supportsCredits: true`（Codex / OpenRouter / MiMo / CommandCode / ZoomMate / Amp / Codebuff）对应源工程的 Credits 泳道与 `creditsHint`，我们只在 `providerCost` 存在时展示费用。
   - **明细行剩余项**：Venice 的网页版 `Credits` 六行（`Bank cap`/`Next refill`）与其 `Used this cycle` 进度条——需要平台网页会话而非 API Key（源工程的 `progress` 只来自 VeniceWebUsageFetcher 与 Copilot，Copilot 已接）；HuggingFace 的 `Credits` 分组（Billing 页 HTML 抓余额）；Poe 的 `Daily points` 图表（源工程也未给 Poe 配 chart，其“每日点数”只在用量项里展示）；IBMBob 的 `teams/{id}/users/{userID}` 逐人预算端点；MiniMax 的平台网页版配额（HTML 抓取，我们仍用 API Token）（DeepSeek 未带平台令牌时已按 macOS 的 `webSessionRequired` 提示处理）；`costSummaryTitles` 目前只作为策略表保留（源工程用它把分组从“用量项选择器”里排除，我们没有该选择器）。图表已覆盖源工程全部 5 处 `makeChart`（Claude Admin / Groq / MiniMax / DeepSeek / ZoomMate），其余服务商源工程本就不画图。
2. **Bedrock 成本日线**：源工程 `fetchDailyReport`（Cost Explorer DAILY 粒度）用于成本历史曲线，当前仅取本月汇总，统计页暂无 Bedrock 成本曲线。
3. **三端重验证**：本轮仅重跑本地单测与 HarmonyOS HAP 构建；Android/iOS 产物为上一版本，需 `ace build apk` / `ace build ios` 重新构建并验证新增与恢复的服务商。

仍明确不迁移（桌面专属 / CLI 探测 / HTML 抓取）：Windsurf、Sakana、Replicate、TypeSafe、Helmcode、StepFun、QwenCloud、Alibaba Token Plan、Cursor、Augment、JetBrains、Antigravity、Vertex AI / Gemini、Copilot 预算页抓取、Bedrock Profile 模式、Kiro、Ollama 本地、Pi、CodeRabbit、Wayfinder、Zed。
