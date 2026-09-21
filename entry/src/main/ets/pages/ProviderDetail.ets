/**
 * CodexBar Mobile — 服务商详情页
 * 展示全部用量窗口、余额、账号身份、明细与错误信息。
 */

import { AuthKind, NamedRateWindow, ProviderDetailRow, ProviderDetailSection, ProviderState } from '../model/Models';
import { AppStore } from '../store/AppStore';
import { Theme } from '../common/Theme';
import { Format } from '../common/Format';
import { Nav } from '../common/Nav';
import { WindowBlock } from '../view/UsageBar';
import { ProviderIcon } from '../view/ProviderIcon';

@Entry
@Component
struct ProviderDetail {
  @State providerId: string = '';
  @State ver: number = 0;
  @State tick: number = 0;
  private timerId: number = -1;

  aboutToAppear(): void {
    this.providerId = Nav.detailParam();
    this.ver = AppStore.get().version;
    this.timerId = setInterval(() => {
      if (AppStore.get().version !== this.ver) {
        this.ver = AppStore.get().version;
      }
      this.tick += 1;
    }, 1000);
  }

  aboutToDisappear(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  state(v: number, t: number): ProviderState | null {
    return AppStore.get().find(this.providerId);
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

        Text(this.state(this.ver, this.tick) != null ? this.state(this.ver, this.tick)!.descriptor.title : '')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.text)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Button() {
          Text('↻')
            .fontSize(18)
            .fontColor(Theme.accent)
        }
        .backgroundColor(Theme.card)
        .width(36)
        .height(36)
        .borderRadius(12)
        .onClick(() => {
          AppStore.get().refreshOne(this.providerId);
        })
      }
      .width('100%')
      .padding({ left: Theme.pad, right: Theme.pad, top: 12, bottom: 8 })

      List({ space: 12 }) {
        if (this.state(this.ver, this.tick) != null) {
          ListItem() {
            this.body(this.state(this.ver, this.tick)!)
          }
        } else {
          ListItem() {
            Column({ space: 10 }) {
              Text('未找到该服务商')
                .fontSize(15)
                .fontColor(Theme.text)
              Text(`路由参数异常："${this.providerId}"，请返回列表重试`)
                .fontSize(12)
                .fontColor(Theme.textDim)
            }
            .width('100%')
            .padding(20)
            .borderRadius(Theme.radius)
            .backgroundColor(Theme.card)
            .border({ width: 1, color: Theme.stroke })
          }
        }
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

  @Builder
  body(s: ProviderState) {
    Column({ space: 12 }) {
      // 账号卡片
      Column({ space: 6 }) {
        Row({ space: 8 }) {
          ProviderIcon({ providerId: s.descriptor.id, accentColor: s.descriptor.accentColor, iconSize: 36 })
          Text(s.descriptor.title)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.text)
          Blank()
          Text(s.loading ? '查询中…' : `更新于 ${Format.ago(s.lastSuccessAt)}`)
            .fontSize(12)
            .fontColor(Theme.textDim)
        }
        .width('100%')

        if (s.snapshot != null && s.snapshot.ok && s.snapshot.identity != null) {
          Text([s.snapshot.identity.accountOrganization, s.snapshot.identity.accountEmail]
            .filter(x => x.length > 0)
            .join(' · '))
            .fontSize(12)
            .fontColor(Theme.textDim)
            .maxLines(2)
        }
        if (s.snapshot != null && !s.snapshot.ok) {
          Row({ space: 6 }) {
            Text('⚠')
              .fontSize(13)
            Text(s.snapshot.error)
              .fontSize(13)
              .fontColor(Theme.danger)
              .layoutWeight(1)
          }
          .padding(10)
          .borderRadius(10)
          .backgroundColor('#2A1518')
          .width('100%')
        }
      }
      .width('100%')
      .padding(Theme.cardPad)
      .borderRadius(Theme.radius)
      .backgroundColor(Theme.card)
      .border({ width: 1, color: Theme.stroke })

      // 未配置凭证提示
      if (s.setting.credential.length === 0 && s.descriptor.authKind !== AuthKind.DEMO) {
        Column({ space: 10 }) {
          Text('🔑')
            .fontSize(22)
          Text('尚未配置凭证')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.text)
          Text(s.descriptor.authHint)
            .fontSize(12)
            .fontColor(Theme.textDim)
            .textAlign(TextAlign.Center)
          Button('去设置页添加')
            .fontSize(13)
            .fontColor(Theme.bg)
            .backgroundColor(Theme.accent)
            .height(34)
            .padding({ left: 18, right: 18 })
            .onClick(() => {
              Nav.toSettings();
            })
        }
        .width('100%')
        .padding(20)
        .borderRadius(Theme.radius)
        .backgroundColor(Theme.card)
        .border({ width: 1, color: Theme.stroke })
        .alignItems(HorizontalAlign.Center)
      }

      // 加载中
      if (s.loading) {
        Row({ space: 10 }) {
          LoadingProgress().width(18).height(18).color(Theme.accent)
          Text('正在获取用量…')
            .fontSize(13)
            .fontColor(Theme.textDim)
        }
        .justifyContent(FlexAlign.Center)
        .width('100%')
        .padding(18)
        .borderRadius(Theme.radius)
        .backgroundColor(Theme.card)
        .border({ width: 1, color: Theme.stroke })
      }

      // 尚未刷新（已配置但没数据）
      if (!s.loading && s.snapshot == null && s.setting.credential.length > 0) {
        Column({ space: 8 }) {
          Text('暂无数据')
            .fontSize(15)
            .fontColor(Theme.text)
          Text('点击右上角 ↻ 立即查询')
            .fontSize(12)
            .fontColor(Theme.textDim)
        }
        .width('100%')
        .padding(20)
        .borderRadius(Theme.radius)
        .backgroundColor(Theme.card)
        .border({ width: 1, color: Theme.stroke })
      }

      // 全部用量窗口
      if (s.snapshot != null && s.snapshot.ok) {
        ForEach(s.allWindows(), (w: NamedRateWindow) => {
          Column({ space: 8 }) {
            WindowBlock({ title: w.title, win: w.window, compact: false })
          }
          .width('100%')
          .padding(Theme.cardPad)
          .borderRadius(Theme.radius)
          .backgroundColor(Theme.card)
          .border({ width: 1, color: Theme.stroke })
        }, (w: NamedRateWindow) => `${w.id}_${w.window.usedPercent}_${Math.floor(this.tick / 30)}`)
      }

      // 余额
      if (s.snapshot != null && s.snapshot.ok && s.snapshot.providerCost != null) {
        Column({ space: 6 }) {
          Text('余额')
            .fontSize(12)
            .fontColor(Theme.textDim)
          Row() {
            Text(s.snapshot.providerCost.displayText)
              .fontSize(26)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.text)
          }
          .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding(Theme.cardPad)
        .borderRadius(Theme.radius)
        .backgroundColor(Theme.card)
        .border({ width: 1, color: Theme.stroke })
      }

      // 明细分组
      if (s.snapshot != null && s.snapshot.ok) {
        ForEach(s.snapshot.details, (sec: ProviderDetailSection) => {
          Column({ space: 8 }) {
            Text(sec.title)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.text)
            ForEach(sec.rows, (r: ProviderDetailRow) => {
              Row() {
                Text(r.label)
                  .fontSize(13)
                  .fontColor(Theme.textDim)
                Blank()
                Text(r.value)
                  .fontSize(13)
                  .fontColor(Theme.text)
              }
              .width('100%')
            }, (r: ProviderDetailRow) => `${r.label}_${r.value}`)
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding(Theme.cardPad)
          .borderRadius(Theme.radius)
          .backgroundColor(Theme.card)
          .border({ width: 1, color: Theme.stroke })
        }, (sec: ProviderDetailSection) => sec.title)
      }

      // 认证说明
      if (s.descriptor.authKind !== AuthKind.DEMO && s.descriptor.authUrl.length > 0) {
        Text(`凭证获取：${s.descriptor.authUrl}`)
          .fontSize(11)
          .fontColor(Theme.textDim)
          .width('100%')
          .padding({ left: 4 })
      }
    }
    .width('100%')
  }
}
