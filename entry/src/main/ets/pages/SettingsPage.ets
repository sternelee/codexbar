/**
 * CodexBar Mobile — 设置页
 * 逐个服务商：开关、凭证输入、保存；凭证仅保存在本机 Preferences。
 */

import { promptAction } from '@kit.ArkUI';
import {
  extraFields,
  extraValue,
  ExtraField,
  isWidgetSelectable,
  needsSecondCredential,
  ProviderAccount,
  ProviderDescriptor,
  secondCredentialHint,
  setExtraValue
} from '../model/Models';
import { AppStore } from '../store/AppStore';
import { Settings } from '../store/Settings';
import { WidgetDataStore } from '../store/WidgetData';
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

  /** 账号条：chip 切换激活、＋ 添加、长按删除；
   *  Claude/Codex 的 ＋ 走网页登录，其余直接建空账号由用户填凭证 */
  @Builder
  accountBar() {
    if (this.descriptor != null) {
      Row({ space: Theme.gapSm }) {
        Text('账号')
          .fontSize(Theme.fsCaption)
          .fontColor(Theme.textDim)
        ForEach(Settings.accounts(this.pid), (a: ProviderAccount) => {
          Text(a.name)
            .fontSize(Theme.fsCaption)
            .fontColor(Settings.activeAccountId(this.pid) === a.aid ? Theme.bg : Theme.textDim)
            .backgroundColor(Settings.activeAccountId(this.pid) === a.aid ? Theme.accent : Theme.input)
            .padding({ left: Theme.rowGap, right: Theme.rowGap, top: Theme.gapXxs, bottom: Theme.gapXxs })
            .borderRadius(Theme.radiusChip)
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
          .fontSize(Theme.fsBody)
          .fontColor(Theme.accent)
          .backgroundColor(Theme.input)
          .padding({ left: Theme.rowGap, right: Theme.rowGap, top: Theme.gapXxs, bottom: Theme.gapXxs })
          .borderRadius(Theme.radiusChip)
          .onClick(() => {
            this.addAccount();
          })
      }
      .width('100%')

      // 内联重命名行
      if (this.renamingAid.length > 0) {
        Row({ space: Theme.gapSm }) {
          TextInput({ text: this.renameText, placeholder: '账号名称' })
            .fontSize(Theme.fsBody)
            .fontColor(Theme.text)
            .placeholderColor(Theme.textDim)
            .backgroundColor(Theme.input)
            .borderRadius(Theme.radiusChip)
            .height(34)
            .layoutWeight(1)
            .onChange((v: string) => {
              this.renameText = v;
            })
          Text('✓')
            .fontSize(Theme.fsName)
            .fontColor(Theme.accent)
            .padding({ left: Theme.rowGap, right: Theme.rowGap, top: Theme.gapXxs, bottom: Theme.gapXxs })
            .onClick(() => {
              this.submitRename();
            })
          Text('✕')
            .fontSize(Theme.fsLabel)
            .fontColor(Theme.textDim)
            .padding({ left: Theme.rowGap, right: Theme.rowGap, top: Theme.gapXxs, bottom: Theme.gapXxs })
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
      Column({ space: Theme.rowGap }) {
        Row({ space: Theme.rowGap }) {
          ProviderIcon({ providerId: this.descriptor.id, accentColor: this.descriptor.accentColor, iconSize: 32 })
          Text(this.descriptor.title)
            .fontSize(Theme.fsName)
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

        TextInput({ text: this.credential, placeholder: this.descriptor.authHint })
            .fontSize(Theme.fsBody)
            .fontColor(Theme.text)
            .placeholderColor(Theme.textDim)
            .placeholderFont({ size: Theme.fsCaption })
            .backgroundColor(Theme.input)
            .borderRadius(Theme.radiusInput)
            .height(42)
            .width('100%')
            .onChange((v: string) => {
              this.credential = v;
            })

          if (this.needSecond) {
            TextInput({ text: this.credential2, placeholder: this.secondHint })
              .fontSize(Theme.fsBody)
              .fontColor(Theme.text)
              .placeholderColor(Theme.textDim)
              .placeholderFont({ size: Theme.fsCaption })
              .backgroundColor(Theme.input)
              .borderRadius(Theme.radiusInput)
              .height(42)
              .width('100%')
              .onChange((v: string) => {
                this.credential2 = v;
              })
          }

          // 额外字段（Endpoint / Deployment / Region 等）
          ForEach(this.fields, (f: ExtraField) => {
            TextInput({ text: extraValue(this.extraJson, f.key), placeholder: f.hint })
              .fontSize(Theme.fsBody)
              .fontColor(Theme.text)
              .placeholderColor(Theme.textDim)
              .placeholderFont({ size: Theme.fsCaption })
              .backgroundColor(Theme.input)
              .borderRadius(Theme.radiusInput)
              .height(42)
              .width('100%')
              .onChange((v: string) => {
                this.extraJson = setExtraValue(this.extraJson, f.key, v);
              })
          }, (f: ExtraField) => `${this.pid}_${f.key}`)

        Row({ space: Theme.rowGap }) {
          if (this.canWebLogin) {
            Button('网页登录')
              .fontSize(Theme.fsBody)
              .fontColor(Theme.accent)
              .backgroundColor(Theme.input)
              .border({ width: 1, color: Theme.accent })
              .height(30)
              .padding({ left: Theme.cardPad, right: Theme.cardPad })
              .onClick(() => {
                Nav.toOAuthLogin(this.pid);
              })
          }
          if (this.descriptor.authUrl.length > 0) {
            Text(`获取凭证 ↗`)
              .fontSize(Theme.fsCaption)
              .fontColor(Theme.accent)
              .layoutWeight(1)
              .maxLines(1)
          } else {
            Text(this.descriptor.authHint)
              .fontSize(Theme.fsMicro)
              .fontColor(Theme.textDim)
              .layoutWeight(1)
              .maxLines(2)
          }
          Button('保存')
            .fontSize(Theme.fsBody)
            .fontColor(Theme.bg)
            .backgroundColor(Theme.accent)
            .height(30)
            .padding({ left: Theme.pad, right: Theme.pad })
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
      .shadow(Theme.cardShadow())
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
    // 旧版本挑选过、如今按源工程 widgetSelectable: false 不再上卡片的服务商：一次性剔除并落盘
    const saved = WidgetDataStore.selectedIds();
    const kept: string[] = [];
    for (let i = 0; i < saved.length; i++) {
      if (isWidgetSelectable(saved[i])) {
        kept.push(saved[i]);
      }
    }
    if (kept.length !== saved.length) {
      WidgetDataStore.setSelectedIds(kept);
    }
    this.widgetSel = kept;
  }

  /**
   * 桌面组件的可选项 = 已启用且可挑选（isWidgetSelectable，对照源工程 widgetSelectable: false
   * 的服务商在桌面小组件里本就不出现）的服务商，外加已挑选但当前被关掉的可挑选服务商——
   * 否则它们在 chip 列表里消失，只能靠「恢复自动」清掉。
   */
  widgetCandidates(): string[] {
    const list: string[] = [];
    const states = AppStore.get().states;
    for (let i = 0; i < states.length; i++) {
      if (states[i].setting.enabled && isWidgetSelectable(states[i].descriptor.id)) {
        list.push(states[i].descriptor.id);
      }
    }
    for (let i = 0; i < this.widgetSel.length; i++) {
      if (list.indexOf(this.widgetSel[i]) < 0) {
        list.push(this.widgetSel[i]);
      }
    }
    return list;
  }

  private titleOf(providerId: string): string {
    const states = AppStore.get().states;
    for (let i = 0; i < states.length; i++) {
      if (states[i].descriptor.id === providerId) {
        return states[i].descriptor.title;
      }
    }
    return providerId;
  }

  /** chip 文案：已点选的前置序号，直接体现卡片上的顺序 */
  chipLabel(providerId: string): string {
    const idx = this.widgetSel.indexOf(providerId);
    const title = this.titleOf(providerId);
    return idx >= 0 ? `${idx + 1}. ${title}` : title;
  }

  /** 点选 / 取消：放到末位 == 卡片上排在后面 */
  toggleWidgetProvider(providerId: string): void {
    const next: string[] = [];
    let found = false;
    for (let i = 0; i < this.widgetSel.length; i++) {
      if (this.widgetSel[i] === providerId) {
        found = true;
      } else {
        next.push(this.widgetSel[i]);
      }
    }
    if (!found) {
      next.push(providerId);
    }
    this.widgetSel = next;
    this.afterWidgetSelectionChanged();
  }

  resetWidgetSelection(): void {
    this.widgetSel = [];
    this.afterWidgetSelectionChanged();
  }

  /** 落盘后立即按当前状态重建组件数据，不必等服务商刷新 */
  private afterWidgetSelectionChanged(): void {
    WidgetDataStore.setSelectedIds(this.widgetSel);
    AppStore.get().syncWidgets();
  }

  /** 搜索关键字（按名称/ID 过滤） */
  @State keyword: string = '';
  /** 是否展示可选用量 / 额度明细（对照 macOS showOptionalCreditsAndExtraUsage） */
  @State showOptional: boolean = true;
  /** 桌面组件显示的服务商 ID（按卡片上的出现顺序；空 = 自动） */
  @State widgetSel: string[] = [];
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

        Text('设置')
          .fontSize(Theme.fsHead)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.text)
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: Theme.pad, right: Theme.pad, top: Theme.gap, bottom: Theme.gapSm })

      List({ space: Theme.gap }) {
        ListItem() {
          TextInput({ placeholder: '🔍 搜索服务商', text: this.keyword })
            .fontSize(Theme.fsBody)
            .fontColor(Theme.text)
            .placeholderColor(Theme.textDim)
            .placeholderFont({ size: Theme.fsBody })
            .backgroundColor(Theme.input)
            .borderRadius(Theme.radiusInput)
            .height(38)
            .width('100%')
            .onChange((v: string) => {
              this.keyword = v;
            })
        }

        ListItem() {
          Column({ space: Theme.gapXxs }) {
            Text('凭证仅保存在本机应用数据中，刷新时直连服务商接口。')
              .fontSize(Theme.fsCaption)
              .fontColor(Theme.textDim)
          }
          .width('100%')
          .padding(Theme.gap)
        }

        ListItem() {
          Row({ space: Theme.rowGap }) {
            Column({ space: Theme.gapXxs }) {
              Text('展示可选用量明细')
                .fontSize(Theme.fsLabel)
                .fontColor(Theme.text)
              Text('关闭后按服务商策略隐藏可选分组（如 DeepSeek 用量、MiniMax 账单历史）')
                .fontSize(Theme.fsMicro)
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
          .shadow(Theme.cardShadow())
        }

        ListItem() {
          Column({ space: Theme.gapSm }) {
            Row() {
              Column({ space: Theme.gapXxs }) {
                Text('桌面组件显示')
                  .fontSize(Theme.fsLabel)
                  .fontColor(Theme.text)
                Text('点选要显示的服务商，顺序即卡片上的顺序；鸿蒙 2x2 / 2x4 卡取前 2 / 4 家，Android 组件按高度自适应（拉高可显示更多）；未选择时自动显示用量最高的若干家')
                  .fontSize(Theme.fsMicro)
                  .fontColor(Theme.textDim)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')

            if (this.widgetCandidates().length === 0) {
              Text('暂无已启用的服务商')
                .fontSize(Theme.fsMicro)
                .fontColor(Theme.textDim)
            } else {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.widgetCandidates(), (id: string) => {
                  Text(this.chipLabel(id))
                    .fontSize(Theme.fsCaption)
                    .fontColor(this.widgetSel.indexOf(id) >= 0 ? Theme.bg : Theme.textDim)
                    .backgroundColor(this.widgetSel.indexOf(id) >= 0 ? Theme.accent : Theme.input)
                    .border({ width: 1, color: this.widgetSel.indexOf(id) >= 0 ? Theme.accent : Theme.stroke })
                    .padding({ left: Theme.rowGap, right: Theme.rowGap, top: Theme.gapXs, bottom: Theme.gapXs })
                    .borderRadius(Theme.radiusChip)
                    .maxLines(1)
                    .margin({ right: Theme.gapSm, bottom: Theme.gapSm })
                    .onClick(() => {
                      this.toggleWidgetProvider(id);
                    })
                }, (id: string) => `${id}_${this.chipLabel(id)}`)
              }
              .width('100%')

              if (this.widgetSel.length > 0) {
                Text('恢复自动（按用量排序）')
                  .fontSize(Theme.fsMicro)
                  .fontColor(Theme.accent)
                  .onClick(() => {
                    this.resetWidgetSelection();
                  })
              }
            }
          }
          .width('100%')
          .padding(Theme.cardPad)
          .borderRadius(Theme.radius)
          .backgroundColor(Theme.card)
          .border({ width: 1, color: Theme.stroke })
          .shadow(Theme.cardShadow())
        }

        if (this.ids(this.ver, this.keyword).length === 0) {
          ListItem() {
            Column({ space: Theme.gapXs }) {
              Text('未找到匹配的服务商')
                .fontSize(Theme.fsLabel)
                .fontColor(Theme.text)
              Text('试试其他关键词，如 "Claude" 或 "deepseek"')
                .fontSize(Theme.fsMicro)
                .fontColor(Theme.textDim)
            }
            .width('100%')
            .padding(Theme.padBottom)
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
      .padding({ left: Theme.pad, right: Theme.pad, bottom: Theme.padBottom })
      .scrollBar(BarState.Off)
      }

      // 自绘确认弹窗（配色走主题资源，不受系统 AlertDialog 主题影响）
      if (this.askVisible) {
        Column() {
          Column({ space: Theme.cardPad }) {
            Text(this.askTitle)
              .fontSize(Theme.fsHeading)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.text)
            Text(this.askMessage)
              .fontSize(Theme.fsBody)
              .fontColor(Theme.textDim)
              .width('100%')
            Row({ space: Theme.rowGap }) {
              Button('取消')
                .fontSize(Theme.fsLabel)
                .fontColor(Theme.textDim)
                .backgroundColor(Theme.input)
                .layoutWeight(1)
                .height(38)
                .onClick(() => {
                  this.onAskClose(false);
                })
              Button(this.askConfirmText)
                .fontSize(Theme.fsLabel)
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
          .padding(Theme.gapLg)
          .borderRadius(Theme.radius)
          .backgroundColor(Theme.card)
          .border({ width: 1, color: Theme.stroke })
          .shadow(Theme.cardShadow())
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
