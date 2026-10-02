# CodexBar 华为应用市场（AppGallery）上架流程

本文记录从零到上架华为应用市场的完整流程与本项目相关的注意事项。上架前请先通读
[AppGallery Connect 华为应用市场官方文档](https://developer.huawei.com/consumer/cn/agconnect/)。

## 0. 前置条件

| 事项 | 说明 |
| --- | --- |
| 开发者账号 | [华为开发者联盟](https://developer.huawei.com/consumer/cn/) 注册并完成实名认证（个人或企业）。个人账号即可上架，但部分权益（如代理提醒）审核更严格 |
| 隐私政策 URL | 本项目为 [`docs/privacy.html`](privacy.html)，需公网可访问（GitHub Pages 开启 main 分支 `/docs` 目录后即为 <https://sternelee.github.io/codexbar/privacy.html>）。AGC 备案信息中填该 URL，**必须 https** |
| 版权证明 | 个人开发者部分类目需补充权利声明；应用名含他人商标时会被驳回 |

## 1. AppGallery Connect 创建应用

1. 登录 [AppGallery Connect](https://developer.huawei.com/consumer/cn/service/josp/agc/index.html) →「我的项目」→ 添加项目
2. 「添加应用」：
   - **平台**：HarmonyOS（APP）
   - **应用名称**：CodexBar
   - **包名**：`com.sternelee.codexbar`（须与 `AppScope/app.json5` 的 `bundleName` 完全一致）
   - **设备**：手机
   - **应用分类**：工具（符合代理提醒权益申请的类目要求）
3. 记下 AGC 分配的 **APP ID / CP ID**，后续申请证书与权益都会用到

## 2. 申请发布证书与 Profile（与调试签名不同）

调试签名（`build-profile.json5` 中现有 `signingConfigs.default`）**不能用于上架**，需申请发布态签名材料：

1. AGC →「用户与访问」→「证书、App ID 及 Profile」→「HarmonyOS App」：
   - 「证书」→ 新增 → 上传 CSR（DevEco Studio 可生成，或用 keytool）→ 下载 **发布证书 `.cer`**
   - 「Profile」→ 新增 → 选择发布证书、勾选申请的权限（本项目为 `ohos.permission.INTERNET` 与 `ohos.permission.PUBLISH_AGENT_REMINDER`）→ 下载 **发布 Profile `.p7b`**
   - 密钥库 `.p12`（含密码）在生成 CSR 时本地产生，妥善备份，**丢失无法补发**
2. 本地 `build-profile.json5` 新增发布签名配置（**该文件含密钥口令，永不提交 git**）：

```json5
"signingConfigs": [
  {
    "name": "release",
    "type": "HarmonyOS",
    "material": {
      "certpath": "/path/to/release.cer",
      "storeFile": "/path/to/release.p12",
      "keyAlias": "发布密钥别名",
      "keyPassword": "…",
      "profile": "/path/to/release.p7b",
      "storePassword": "…",
      "signAlg": "SHA256withECDSA"
    }
  }
]
```

并让 `products.default` 的 release 模式引用 `"signingConfig": "release"`（也可在 DevEco Studio
File → Project Structure → Signing Configs 里图形化配置，勾选发布证书）。

## 3. 构建发布包（App Pack）

上架格式是 **`.app`（App Pack）**，不是单模块 `.hap`：

```bash
export DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw \
  --mode project -p product=default -p buildMode=release assembleApp --no-daemon
```

产物：`build/outputs/default/default-default-signed.app`（DevEco Studio 里等价操作是
Build → Build App(s)/Hap(s) → Build App(s)）。

上架前自查：

- `AppScope/app.json5` 的 `versionCode` / `versionName` 已递增（当前 1000000 / 1.0.0）
- release 构建日志无 ERROR；`AppScope` 的 `label`、图标为上架展示内容
- 确认产物内的权限声明与 AGC Profile 申请的权限一致，多声明会被审核打回

## 4. 敏感权限 / 权益申请（本项目涉及一项）

`ohos.permission.PUBLISH_AGENT_REMINDER`（后台代理提醒）在手机/平板上受**管控**：

1. AGC →「我的项目」→ 本项目 →「HarmonyOS API 权益」→「代理提醒」提交申请
2. 申请条件：应用类目为工具/商务/效率/金融理财/教育/生活服务/旅游/医疗/运动健康/游戏之一；
   用量/额度类提醒属于允许场景，营销类禁止
3. 需提交：应用分类截图（AGC「应用信息」页）、申请说明（建议写明「额度即将恢复的到点提醒，
   属工具类应用的时间提醒场景」）
4. 审批通过后权益开通，`publishReminder` 才能正常调用；**未开通不影响上架**，应用内已做
   降级（回退进程内提醒），建议在版本说明或应用描述里注明后台提醒依赖系统权益

## 5. AGC 填写版本信息并提审

1. 「我的项目」→「分发」→「版本管理」→ 创建版本，上传 `.app`
2. 必填项：
   - **版本说明**：更新日志（新版本写了什么，中文即可）
   - **截图**：2–5 张，手机端建议 1080×2340 左右的实机截图（仪表盘、详情页、统计页）
   - **内容分级**：按问卷填写（本项目无敏感内容，一般 3+）
   - **隐私政策 URL**：填第 0 步的 https 地址；「数据收集」声明与本应用一致——
     **不收集任何用户数据，凭证仅存本机，网络请求仅直连各服务商官方接口**
   - **权限用途说明**：`INTERNET`（查询用量数据）、`PUBLISH_AGENT_REMINDER`（额度重置到点提醒）
3. 提交审核。审核一般 1–3 个工作日，常见驳回原因：
   - 权限声明与实际用途描述不清（照上一条写法可避免）
   - 隐私政策不可访问或与实际行为不一致
   - 功能不完整 / 崩溃（提审前用云真机回归一遍）

## 6. 发布

- 审核通过后选择发布方式：**全员发布** 或 **分阶段发布**（灰度，建议首次上架用 10% 灰度观察）
- 发布后可在 AGC「版本管理」看到各阶段进度，可暂停/撤回
- 后续更新：递增 `versionCode` → 重新构建 `.app` → 重复第 5–6 步

## 7. 提审前检查清单

- [ ] `versionCode` 已递增，release `.app` 构建成功
- [ ] 发布证书 / Profile 未过期（Profile 有效期在 AGC 可查）
- [ ] 隐私政策 URL 公网 https 可访问，内容与应用实际行为一致
- [ ] 截图与版本说明已备齐
- [ ] 真机冒烟：添加凭证 → 刷新 → 详情页 → 提醒开关 → 桌面卡片
- [ ] 代理提醒权益状态确认（已开通 / 未开通且降级路径可用）
