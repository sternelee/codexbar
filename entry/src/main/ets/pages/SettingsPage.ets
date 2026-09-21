/**
 * CodexBar Mobile — 设置页
 * 逐个服务商：开关、凭证输入、保存；凭证仅保存在本机 Preferences。
 */

import { AuthKind, ProviderDescriptor, ProviderState } from '../model/Models';
import { AppStore } from '../store/AppStore';
import { Theme } from '../common/Theme';
import { Nav } from '../common/Nav';
import { ProviderIcon } from '../view/ProviderIcon';

/** 单个服务商的设置卡片：内部持有编辑态 */
@Component
struct ProviderSettingCard {
  @State isEnabled: boolean = false;
  @State credential: string = '';
  @State credential2: string = '';
  private descriptor: ProviderDescriptor | null = null;
  private needSecond: boolean = false;
  pid: string = '';

  aboutToAppear(): void {
    const store = AppStore.get();
    for (let i = 0; i < store.states.length; i++) {
      const s = store.states[i];
      if (s.descriptor.id === this.pid) {
        this.descriptor = s.descriptor;
        this.isEnabled = s.setting.enabled;
        this.credential = s.setting.credential;
        this.credential2 = s.setting.credential2;
        const pid = s.descriptor.id;
        this.needSecond = pid === 'claude' || pid === 'codex' || pid === 'kilo' ||
          pid === 'xai' || pid === 'litellm' || pid === 'llmproxy' ||
          pid === 'sub2api' || pid === 'devin';
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
    });
    Nav.toast('已保存');
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
            TextInput({ text: this.credential2, placeholder: '可选：组织 / 账号 ID' })
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
        }

        Row({ space: 10 }) {
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
  }

  ids(v: number): string[] {
    const list: string[] = [];
    const states = AppStore.get().states;
    for (let i = 0; i < states.length; i++) {
      list.push(states[i].descriptor.id);
    }
    return list;
  }

  build() {
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
          Column({ space: 4 }) {
            Text('凭证仅保存在本机应用数据中，刷新时直连服务商接口。')
              .fontSize(12)
              .fontColor(Theme.textDim)
          }
          .width('100%')
          .padding(12)
        }

        ForEach(this.ids(this.ver), (id: string) => {
          ListItem() {
            ProviderSettingCard({ pid: id })
          }
        }, (id: string) => id)
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: Theme.pad, right: Theme.pad, bottom: 24 })
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
  }
}
