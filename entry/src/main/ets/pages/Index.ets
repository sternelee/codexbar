/**
 * CodexBar Mobile — 仪表盘
 * 服务商用量卡片列表：用量条 + 重置倒计时 + 余额 + 下拉刷新。
 */

import { AuthKind, ProviderState } from '../model/Models';
import { AppStore } from '../store/AppStore';
import { Theme } from '../common/Theme';
import { Format } from '../common/Format';
import { Nav } from '../common/Nav';
import { WindowBlock } from '../view/UsageBar';
import { ProviderIcon } from '../view/ProviderIcon';

@Entry
@Component
struct Index {
  /** 同步 AppStore.version，用于触发重建 */
  @State ver: number = 0;
  /** 每秒 +1，驱动倒计时刷新 */
  @State tick: number = 0;
  @State isRefreshing: boolean = false;
  private timerId: number = -1;

  aboutToAppear(): void {
    const store = AppStore.get();
    store.load();
    this.ver = store.version;
    store.refreshAll();
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

  /** 显式引用 ver/tick 以注册渲染依赖；已配置凭证的服务商排在前面（组内保持注册表顺序） */
  items(v: number, t: number): ProviderState[] {
    return AppStore.get().orderedStates();
  }

  async doRefresh(): Promise<void> {
    this.isRefreshing = true;
    await AppStore.get().refreshAll();
    this.isRefreshing = false;
  }

  /** 卡片状态摘要（右侧一行字） */
  summaryOf(s: ProviderState): string {
    if (s.loading) {
      return '查询中…';
    }
    if (s.setting.enabled && s.setting.credential.length === 0 && s.descriptor.authKind !== AuthKind.DEMO) {
      return '未配置凭证';
    }
    const snap = s.snapshot;
    if (snap == null) {
      return '未刷新';
    }
    if (!snap.ok) {
      return snap.error;
    }
    if (snap.providerCost != null) {
      return `余额 ${snap.providerCost.displayText}`;
    }
    if (snap.primary != null) {
      return Format.percent(snap.primary.usedPercent);
    }
    return '已更新';
  }

  build() {
    Column() {
      // 顶栏
      Row({ space: 10 }) {
        Column({ space: 2 }) {
          Text('CodexBar')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.text)
          Text(`AI 额度速览 · ${AppStore.get().enabledCount()} 家已启用`)
            .fontSize(12)
            .fontColor(Theme.textDim)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Button(this.isRefreshing ? '刷新中' : '刷新')
          .fontSize(13)
          .fontColor(Theme.bg)
          .backgroundColor(Theme.accent)
          .height(32)
          .padding({ left: 14, right: 14 })
          .onClick(() => {
            this.doRefresh();
          })

        Button() {
          Text('📊')
            .fontSize(15)
            .fontColor(Theme.text)
        }
        .backgroundColor(Theme.card)
        .border({ width: 1, color: Theme.stroke })
        .height(32)
        .width(36)
        .borderRadius(10)
        .onClick(() => {
          Nav.toStats('');
        })

        Button() {
          Text('⚙')
            .fontSize(18)
            .fontColor(Theme.text)
        }
        .backgroundColor(Theme.card)
        .border({ width: 1, color: Theme.stroke })
        .height(32)
        .width(36)
        .borderRadius(10)
        .onClick(() => {
          Nav.toSettings();
        })
      }
      .width('100%')
      .padding({ left: Theme.pad, right: Theme.pad, top: 14, bottom: 10 })

      Refresh({ refreshing: this.isRefreshing }) {
        List({ space: 12 }) {
          ForEach(this.items(this.ver, this.tick), (s: ProviderState) => {
            ListItem() {
              this.providerCard(s)
            }
          }, (s: ProviderState) => `${s.descriptor.id}_${s.loading}_${s.snapshot != null ? s.snapshot.updatedAt : 0}_${Math.floor(this.tick / 30)}`)
        }
        .width('100%')
        .height('100%')
        .padding({ left: Theme.pad, right: Theme.pad, bottom: 24 })
        .scrollBar(BarState.Off)
      }
      .layoutWeight(1)
      .onRefreshing(() => {
        this.doRefresh();
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
  }

  @Builder
  providerCard(s: ProviderState) {
    Column({ space: 10 }) {
      // 头部：名称 + 摘要
      Row({ space: 10 }) {
        ProviderIcon({ providerId: s.descriptor.id, accentColor: s.descriptor.accentColor, iconSize: 32 })
        Text(s.descriptor.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.summaryOf(s))
          .fontSize(12)
          .fontColor(s.snapshot != null && !s.snapshot.ok ? Theme.danger : Theme.textDim)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')

      // 用量窗口（最多两个，详情页看全部）
      if (s.snapshot != null && s.snapshot.ok) {
        if (s.snapshot.primary != null) {
          WindowBlock({
            title: s.snapshot.primaryLabel.length > 0 ? s.snapshot.primaryLabel : '会话',
            win: s.snapshot.primary,
            compact: true
          })
        }
        if (s.snapshot.secondary != null) {
          WindowBlock({
            title: s.snapshot.secondaryLabel.length > 0 ? s.snapshot.secondaryLabel : '每周',
            win: s.snapshot.secondary,
            compact: true
          })
        }
        if (s.snapshot.providerCost != null && s.snapshot.primary == null) {
          Row() {
            Text(s.snapshot.providerCost.displayText)
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.text)
            Blank()
            Text(s.snapshot.providerCost.currency)
              .fontSize(12)
              .fontColor(Theme.textDim)
          }
          .width('100%')
        }
      }

      // 加载中
      if (s.loading) {
        Row({ space: 8 }) {
          LoadingProgress().width(14).height(14).color(Theme.accent)
          Text('正在获取用量…')
            .fontSize(12)
            .fontColor(Theme.textDim)
        }
        .width('100%')
      }

      // 未配置提示
      if (!s.loading && s.setting.credential.length === 0 && s.descriptor.authKind !== AuthKind.DEMO) {
        Row({ space: 6 }) {
          Text('🔑')
            .fontSize(12)
          Text('点击去设置页添加凭证')
            .fontSize(12)
            .fontColor(Theme.textDim)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(Theme.cardPad)
    .borderRadius(Theme.radius)
    .backgroundColor(Theme.card)
    .border({ width: 1, color: Theme.stroke })
    .onClick(() => {
      Nav.toDetail(s.descriptor.id);
    })
  }
}
