/**
 * CodexBar Mobile — 设置页
 * 逐个服务商：开关、凭证输入、保存；凭证仅保存在本机 Preferences。
 */

import { promptAction } from '@kit.ArkUI';
import {
  AuthKind,
  extraFields,
  extraValue,
  ExtraField,
  needsSecondCredential,
  ProviderAccount,
  ProviderDescriptor,
  secondCredentialHint,
  setExtraValue
} from '../model/Models';
import { AppStore } from '../store/AppStore';
import { Settings } from '../store/Settings';
import { Theme } from '../common/Theme';
import { Nav } from '../common/Nav';
import { ProviderIcon } from '../view/ProviderIcon';

/** 单个服务商的设置卡片：内部持有编辑态 */
@Component
struct ProviderSettingCard {
  @State isEnabled: boolean = false;
  @State credential: string = '';
  @State credential2: string = '';
  /** 额外字段（JSON 对象文本，键由 extraFields(pid) 定义） */
  @State extraJson: string = '';
  /** 父页面版本号；返回本页/切换账号后 +1 触发重读 */
  @Prop @Watch('reloadFromStore') rev: number = 0;
  /** 卡片内账号操作计数：添加/切换/删除后 +1 立即重渲染 */
  @State accRev: number = 0;
  /** 正在重命名的账号 ID 与输入内容（内联编辑行） */
  @State renamingAid: string = '';
  @State renameText: string = '';
  private descriptor: ProviderDescriptor | null = null;
  private needSecond: boolean = false;
  private secondHint: string = '可选：组织 / 账号 ID';
  private fields: ExtraField[] = [];
  /** Claude / Codex 支持应用内网页登录（Cookie / PKCE）；DeepSeek 用它取平台会话补第二栏 */
  private canWebLogin: boolean = false;
  /** 网页登录会新建账号的服务商（DeepSeek 只回填平台会话，不建账号） */
  private webLoginMakesAccount: boolean = false;
  /** 请求父页面弹确认框（卡片内不放弹窗，保证覆盖全屏与主题一致） */
  onAsk: (title: string, message: string, confirmText: string, action: () => void) => void =
    (_t: string, _m: string, _c: string, _a: () => void) => {};
  pid: string = '';

  aboutToAppear(): void {
    this.reloadFromStore();
  }

  reloadFromStore(): void {
    const store = AppStore.get();
    for (let i = 0; i < store.states.length; i++) {
      const s = store.states[i];
      if (s.descriptor.id === this.pid) {
        this.descriptor = s.descriptor;
        this.isEnabled = s.setting.enabled;
        this.credential = s.setting.credential;
        this.credential2 = s.setting.credential2;
        this.extraJson = s.setting.extraConfig;
        const pid = s.descriptor.id;
        this.needSecond = needsSecondCredential(pid);
        this.secondHint = secondCredentialHint(pid);
        this.fields = extraFields(pid);
        this.canWebLogin = pid === 'claude' || pid === 'codex' || pid === 'deepseek';
        this.webLoginMakesAccount = pid === 'claude' || pid === 'codex';
        break;
      }
    }
  }

  save(): void {
    if (this.descriptor == null) {
      return;
    }
    AppStore.get().applySetting(this.descriptor.id, {
      enabled: this.isEnabled,
      credential: this.credential.trim(),
      credential2: this.credential2.trim(),
      extraConfig: this.extraJson.trim(),
    });
    Nav.toast('已保存');
  }

  /** 删除账号（长按菜单触发，确认后执行） */
  confirmDeleteAccount(a: ProviderAccount, pid: string): void {
    this.onAsk('删除账号', `确定删除「${a.name}」？`, '删除', () => {
      Settings.removeAccount(pid, a.aid);
      AppStore.get().reloadSetting(pid);
      AppStore.get().refreshOne(pid);
      this.reloadFromStore();
      this.accRev += 1;
      Nav.toast('已删除');
    });
  }

  /** 长按账号 chip：重命名 / 删除 动作菜单 */
  showAccountActions(a: ProviderAccount): void {
    promptAction.showActionMenu({
      title: a.name,
      buttons: [
        { text: '重命名', color: Theme.text },
        { text: '删除', color: Theme.danger },
      ]
    }).then((res: promptAction.ActionMenuSuccessResponse) => {
      if (res.index === 0) {
        this.renamingAid = a.aid;
        this.renameText = a.name;
        this.accRev += 1;
      } else if (res.index === 1) {
        this.confirmDeleteAccount(a, this.pid);
      }
    }).catch(() => {});
  }

  submitRename(): void {
    const name = this.renameText.trim();
    if (this.renamingAid.length > 0 && name.length > 0) {
      Settings.renameAccount(this.pid, this.renamingAid, name);
      Nav.toast('已重命名');
    }
    this.renamingAid = '';
    this.renameText = '';
    this.accRev += 1;
  }

  cancelRename(): void {
    this.renamingAid = '';
    this.renameText = '';
    this.accRev += 1;
  }

  /** 账号条：chip 切换激活、＋ 添加、长按删除。所有非演示服务商可用；
   *  Claude/Codex 的 ＋ 走网页登录，其余直接建空账号由用户填凭证 */
  @Builder
  accountBar() {
    if (this.descriptor != null && this.descriptor.authKind !== AuthKind.DEMO) {
      Row({ space: 8 }) {
        Text('账号')
          .fontSize(12)
          .fontColor(Theme.textDim)
        ForEach(Settings.accounts(this.pid), (a: ProviderAccount) => {
          Text(a.name)
            .fontSize(12)
            .fontColor(Settings.activeAccountId(this.pid) === a.aid ? Theme.bg : Theme.textDim)
            .backgroundColor(Settings.activeAccountId(this.pid) === a.aid ? Theme.accent : Theme.input)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .borderRadius(9)
            .maxLines(1)
            .onClick(() => {
              if (Settings.activeAccountId(this.pid) !== a.aid) {
                AppStore.get().switchAccount(this.pid, a.aid);
                this.reloadFromStore();
                this.accRev += 1;
                Nav.toast(`已切换到${a.name}`);
              }
            })
            .gesture(LongPressGesture().onAction(() => {
              this.showAccountActions(a);
            }))
        }, (a: ProviderAccount) => `${a.aid}_${Settings.activeAccountId(this.pid) === a.aid}_${this.rev}_${this.accRev}`)
        Text('＋')
          .fontSize(13)
          .fontColor(Theme.accent)
          .backgroundColor(Theme.input)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(9)
          .onClick(() => {
            this.addAccount();
          })
      }
      .width('100%')

      // 内联重命名行
      if (this.renamingAid.length > 0) {
        Row({ space: 8 }) {
          TextInput({ text: this.renameText, placeholder: '账号名称' })
            .fontSize(13)
            .fontColor(Theme.text)
            .placeholderColor(Theme.textDim)
            .backgroundColor(Theme.input)
            .borderRadius(9)
            .height(34)
            .layoutWeight(1)
            .onChange((v: string) => {
              this.renameText = v;
            })
          Text('✓')
            .fontSize(15)
            .fontColor(Theme.accent)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .onClick(() => {
              this.submitRename();
            })
          Text('✕')
            .fontSize(14)
            .fontColor(Theme.textDim)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .onClick(() => {
              this.cancelRename();
            })
        }
        .width('100%')
      }
    }
  }

  /** ＋ 按钮：Claude/Codex 走网页登录加号；其他服务商建空账号待填凭证 */
  addAccount(): void {
    if (this.webLoginMakesAccount) {
      Nav.toOAuthLogin(this.pid, true);
      return;
    }
    const res = Settings.addAccount(this.pid, '', '', '');
    AppStore.get().reloadSetting(this.pid);
    this.reloadFromStore();
    this.accRev += 1;
    Nav.toast(`已添加${res.account.name}，填写凭证后保存`);
  }

  build() {
    if (this.descriptor != null) {
      Column({ space: 10 }) {
        Row({ space: 10 }) {
          ProviderIcon({ providerId: this.descriptor.id, accentColor: this.descriptor.accentColor, iconSize: 32 })
          Text(this.descriptor.title)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.text)
            .layoutWeight(1)
            .maxLines(1)
          Toggle({ type: ToggleType.Switch, isOn: this.isEnabled })
            .selectedColor(Theme.accent)
            .onChange((isOn: boolean) => {
              this.isEnabled = isOn;
            })
        }
        .width('100%')

        // 多账号条（Claude/Codex）
        this.accountBar()

        if (this.descriptor.authKind !== AuthKind.DEMO) {
          TextInput({ text: this.credential, placeholder: this.descriptor.authHint })
            .fontSize(13)
            .fontColor(Theme.text)
            .placeholderColor(Theme.textDim)
            .placeholderFont({ size: 12 })
            .backgroundColor(Theme.input)
            .borderRadius(10)
            .height(42)
            .width('100%')
            .onChange((v: string) => {
              this.credential = v;
            })

          if (this.needSecond) {
            TextInput({ text: this.credential2, placeholder: this.secondHint })
              .fontSize(13)
              .fontColor(Theme.text)
              .placeholderColor(Theme.textDim)
              .placeholderFont({ size: 12 })
              .backgroundColor(Theme.input)
              .borderRadius(10)
              .height(42)
              .width('100%')
              .onChange((v: string) => {
                this.credential2 = v;
              })
          }

          // 额外字段（Endpoint / Deployment / Region 等）
          ForEach(this.fields, (f: ExtraField) => {
            TextInput({ text: extraValue(this.extraJson, f.key), placeholder: f.hint })
              .fontSize(13)
              .fontColor(Theme.text)
              .placeholderColor(Theme.textDim)
              .placeholderFont({ size: 12 })
              .backgroundColor(Theme.input)
              .borderRadius(10)
              .height(42)
              .width('100%')
              .onChange((v: string) => {
                this.extraJson = setExtraValue(this.extraJson, f.key, v);
              })
          }, (f: ExtraField) => `${this.pid}_${f.key}`)
        }

        Row({ space: 10 }) {
          if (this.canWebLogin) {
            Button('网页登录')
              .fontSize(13)
              .fontColor(Theme.accent)
              .backgroundColor(Theme.input)
              .border({ width: 1, color: Theme.accent })
              .height(30)
              .padding({ left: 14, right: 14 })
              .onClick(() => {
                Nav.toOAuthLogin(this.pid);
              })
          }
          if (this.descriptor.authUrl.length > 0) {
            Text(`获取凭证 ↗`)
              .fontSize(12)
              .fontColor(Theme.accent)
              .layoutWeight(1)
              .maxLines(1)
          } else {
            Text(this.descriptor.authHint)
              .fontSize(11)
              .fontColor(Theme.textDim)
              .layoutWeight(1)
              .maxLines(2)
          }
          Button('保存')
            .fontSize(13)
            .fontColor(Theme.bg)
            .backgroundColor(Theme.accent)
            .height(30)
            .padding({ left: 16, right: 16 })
            .onClick(() => {
              this.save();
            })
        }
        .width('100%')
      }
      .width('100%')
      .padding(Theme.cardPad)
      .borderRadius(Theme.radius)
      .backgroundColor(Theme.card)
      .border({ width: 1, color: Theme.stroke })
    }
  }
}

@Entry
@Component
struct SettingsPage {
  @State ver: number = 0;

  aboutToAppear(): void {
    this.ver = AppStore.get().version;
    this.showOptional = Settings.showOptionalDetails();
  }

  /** 搜索关键字（按名称/ID 过滤） */
  @State keyword: string = '';
  /** 是否展示可选用量 / 额度明细（对照 macOS showOptionalCreditsAndExtraUsage） */
  @State showOptional: boolean = true;
  /** 自绘确认弹窗状态 */
  @State askVisible: boolean = false;
  @State askTitle: string = '';
  @State askMessage: string = '';
  @State askConfirmText: string = '确认';
  private askAction: (() => void) | null = null;

  /** 返回本页时刷新账号条 */
  onPageShow(): void {
    this.ver += 1;
  }

  askConfirm(title: string, message: string, confirmText: string, action: () => void): void {
    this.askTitle = title;
    this.askMessage = message;
    this.askConfirmText = confirmText;
    this.askAction = action;
    this.askVisible = true;
  }

  onAskClose(confirmed: boolean): void {
    const action = this.askAction;
    this.askVisible = false;
    this.askAction = null;
    if (confirmed && action != null) {
      action();
    }
  }

  /** 服务商列表；有关键字时按名称/ID 过滤 */
  ids(v: number, kw: string): string[] {
    const list: string[] = [];
    const key = kw.trim().toLowerCase();
    const states = AppStore.get().states;
    for (let i = 0; i < states.length; i++) {
      if (key.length > 0 &&
        states[i].descriptor.title.toLowerCase().indexOf(key) < 0 &&
        states[i].descriptor.id.toLowerCase().indexOf(key) < 0) {
        continue;
      }
      list.push(states[i].descriptor.id);
    }
    return list;
  }

  build() {
    Stack() {
    Column() {
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

        Text('设置')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.text)
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: Theme.pad, right: Theme.pad, top: 12, bottom: 8 })

      List({ space: 12 }) {
        ListItem() {
          TextInput({ placeholder: '🔍 搜索服务商', text: this.keyword })
            .fontSize(13)
            .fontColor(Theme.text)
            .placeholderColor(Theme.textDim)
            .placeholderFont({ size: 13 })
            .backgroundColor(Theme.input)
            .borderRadius(10)
            .height(38)
            .width('100%')
            .onChange((v: string) => {
              this.keyword = v;
            })
        }

        ListItem() {
          Column({ space: 4 }) {
            Text('凭证仅保存在本机应用数据中，刷新时直连服务商接口。')
              .fontSize(12)
              .fontColor(Theme.textDim)
          }
          .width('100%')
          .padding(12)
        }

        ListItem() {
          Row({ space: 10 }) {
            Column({ space: 3 }) {
              Text('展示可选用量明细')
                .fontSize(14)
                .fontColor(Theme.text)
              Text('关闭后按服务商策略隐藏可选分组（如 DeepSeek 用量、MiniMax 账单历史）')
                .fontSize(11)
                .fontColor(Theme.textDim)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.showOptional })
              .selectedColor(Theme.accent)
              .onChange((on: boolean) => {
                this.showOptional = on;
                Settings.setShowOptionalDetails(on);
                this.ver += 1;
              })
          }
          .width('100%')
          .padding(Theme.cardPad)
          .borderRadius(Theme.radius)
          .backgroundColor(Theme.card)
          .border({ width: 1, color: Theme.stroke })
        }

        if (this.ids(this.ver, this.keyword).length === 0) {
          ListItem() {
            Column({ space: 6 }) {
              Text('未找到匹配的服务商')
                .fontSize(14)
                .fontColor(Theme.text)
              Text('试试其他关键词，如 "Claude" 或 "deepseek"')
                .fontSize(11)
                .fontColor(Theme.textDim)
            }
            .width('100%')
            .padding(24)
            .alignItems(HorizontalAlign.Center)
          }
        }

        ForEach(this.ids(this.ver, this.keyword), (id: string) => {
          ListItem() {
            ProviderSettingCard({
              pid: id,
              rev: this.ver,
              onAsk: (t: string, m: string, c: string, a: () => void) => {
                this.askConfirm(t, m, c, a);
              }
            })
          }
        }, (id: string) => id)
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: Theme.pad, right: Theme.pad, bottom: 24 })
      .scrollBar(BarState.Off)
      }

      // 自绘确认弹窗（暗色模式可读，不依赖系统主题）
      if (this.askVisible) {
        Column() {
          Column({ space: 14 }) {
            Text(this.askTitle)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.text)
            Text(this.askMessage)
              .fontSize(13)
              .fontColor(Theme.textDim)
              .width('100%')
            Row({ space: 10 }) {
              Button('取消')
                .fontSize(14)
                .fontColor(Theme.textDim)
                .backgroundColor(Theme.input)
                .layoutWeight(1)
                .height(38)
                .onClick(() => {
                  this.onAskClose(false);
                })
              Button(this.askConfirmText)
                .fontSize(14)
                .fontColor(Theme.bg)
                .backgroundColor(Theme.danger)
                .layoutWeight(1)
                .height(38)
                .onClick(() => {
                  this.onAskClose(true);
                })
            }
            .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .padding(20)
          .borderRadius(Theme.radius)
          .backgroundColor(Theme.card)
          .border({ width: 1, color: Theme.stroke })
          .width('86%')
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.55)')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
  }
}
