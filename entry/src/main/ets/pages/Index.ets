/**
 * CodexBar Mobile — 仪表盘
 * 服务商用量卡片列表：用量条 + 重置倒计时 + 余额 + 下拉刷新。
 */

import { primaryDisplayWindow, ProviderState, RateWindow } from '../model/Models';
import { AppStore } from '../store/AppStore';
import { Theme } from '../common/Theme';
import { Format } from '../common/Format';
import { Nav } from '../common/Nav';
import { L, AppLang, currentLang } from '../common/I18n';
import { CompactWindowBlock } from '../view/UsageBar';
import { ProviderIcon } from '../view/ProviderIcon';

@Entry
@Component
struct Index {
  /** 同步 AppStore.version，用于触发重建 */
  @State ver: number = 0;
  /** 显示语言；变化时经 build 根的 ForEach 整页重建，让所有 L()/LT() 文案立即切换 */
  @State lang: AppLang = currentLang();
  /** 每秒 +1，驱动倒计时刷新 */
  @State tick: number = 0;
  @State isRefreshing: boolean = false;
  /**
   * 滚动揭示：已渐入到第几个卡片（-1 = 全部待进场）。
   * 进场级联只揭示初始视口（范围由 onScrollIndex 首次回调给出），
   * 之后滚动到的新卡片在进入视口时渐入；上滑回看不重播。
   */
  @State revealEdge: number = -1;
  private introStarted: boolean = false;
  private introTarget: number = 0;
  private timerId: number = -1;
  private introTimer: number = -1;

  aboutToAppear(): void {
    const store = AppStore.get();
    store.load();
    this.ver = store.version;
    store.refreshAll();
    this.timerId = setInterval(() => {
      if (AppStore.get().version !== this.ver) {
        this.ver = AppStore.get().version;
      }
      if (currentLang() !== this.lang) {
        this.lang = currentLang();
      }
      this.tick += 1;
    }, 1000);
  }

  aboutToDisappear(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
    if (this.introTimer >= 0) {
      clearInterval(this.introTimer);
      this.introTimer = -1;
    }
  }

  /**
   * 进场级联：卡片逐个淡入上浮（45ms 交错、300ms Friction 曲线），揭示到 introTarget 为止。
   * 只在首次挂载播一轮；之后刷新 / 重建（ForEach key 变化）不重播，
   * 滚动揭示由 onScrollReveal 接管。
   */
  private startIntro(): void {
    if (this.introStarted) {
      return;
    }
    this.introStarted = true;
    this.introTimer = setInterval(() => {
      if (this.revealEdge >= this.introTarget) {
        clearInterval(this.introTimer);
        this.introTimer = -1;
        return;
      }
      const next = this.revealEdge + 1;
      this.getUIContext().animateTo({ duration: 300, curve: Curve.Friction }, () => {
        this.revealEdge = next;
      });
    }, 45);
  }

  /** 滚动 / 首次布局：把新进视口的卡片纳入揭示范围（渐入 + 上浮） */
  private onScrollReveal(first: number, last: number): void {
    if (last <= this.revealEdge) {
      return;
    }
    if (!this.introStarted || this.introTimer >= 0) {
      // 级联尚未开始或仍在进行：只延伸级联目标，保持逐个交错的节奏
      this.introTarget = Math.max(this.introTarget, last);
      if (!this.introStarted) {
        this.startIntro();
      }
      return;
    }
    this.getUIContext().animateTo({ duration: 300, curve: Curve.Friction }, () => {
      this.revealEdge = last;
    });
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
      return L('查询中…', 'Loading…');
    }
    if (s.setting.enabled && s.setting.credential.length === 0) {
      return L('未配置凭证', 'No credential');
    }
    const snap = s.snapshot;
    if (snap == null) {
      return L('未刷新', 'Not refreshed');
    }
    if (!snap.ok) {
      return snap.error;
    }
    if (snap.providerCost != null) {
      // 卡片另起余额行时（按量花费型，如 OpenRouter）摘要就报余额，否则报卡片上的大号数字
      const balance = snap.providerCost.balanceText;
      if (balance != null && balance.length > 0) {
        return L(`余额 ${balance}`, `Balance ${balance}`);
      }
      return `余额 ${snap.providerCost.displayText}`;
    }
    return L('已更新', 'Updated');
  }

  /** 主泳道的展示窗口（命中绑定泳道投影时替换百分比与重置时间） */
  private primaryWindow(s: ProviderState): RateWindow | null {
    return primaryDisplayWindow(s.descriptor.id, s.snapshot, Date.now());
  }

  build() {
    Column() {
    ForEach([this.lang], (l: AppLang) => {
    Column() {
      // 顶栏
      Row({ space: Theme.rowGap }) {
        Column({ space: Theme.gapXxs }) {
          Text('CodexBar')
            .fontSize(Theme.fsTitle)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.text)
          Text(L(`AI 额度速览 · ${AppStore.get().enabledCount()} 家已启用`, `AI Quota at a Glance · ${AppStore.get().enabledCount()} enabled`))
            .fontSize(Theme.fsCaption)
            .fontColor(Theme.textDim)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Button(this.isRefreshing ? L('刷新中', 'Refreshing') : L('刷新', 'Refresh'))
          .fontSize(Theme.fsBody)
          .fontColor(Theme.bg)
          .backgroundColor(Theme.accent)
          .height(32)
          .padding({ left: Theme.cardPad, right: Theme.cardPad })
          .onClick(() => {
            this.doRefresh();
          })

        Button() {
          Text('📊')
            .fontSize(Theme.fsName)
            .fontColor(Theme.text)
        }
        .backgroundColor(Theme.card)
        .border({ width: 1, color: Theme.stroke })
        .shadow(Theme.cardShadow())
        .height(32)
        .width(36)
        .borderRadius(Theme.radiusInput)
        .onClick(() => {
          Nav.toStats('');
        })

        Button() {
          Text('⚙')
            .fontSize(Theme.fsHead)
            .fontColor(Theme.text)
        }
        .backgroundColor(Theme.card)
        .border({ width: 1, color: Theme.stroke })
        .shadow(Theme.cardShadow())
        .height(32)
        .width(36)
        .borderRadius(Theme.radiusInput)
        .onClick(() => {
          Nav.toSettings();
        })
      }
      .width('100%')
      .padding({ left: Theme.pad, right: Theme.pad, top: Theme.cardPad, bottom: Theme.rowGap })

      Refresh({ refreshing: this.isRefreshing }) {
        List({ space: Theme.gap }) {
          ForEach(this.items(this.ver, this.tick), (s: ProviderState, idx: number) => {
            ListItem() {
              this.providerCard(s, idx)
            }
          }, (s: ProviderState) => `${s.descriptor.id}_${s.loading}_${s.snapshot != null ? s.snapshot.updatedAt : 0}_${Math.floor(this.tick / 30)}`)
        }
        .width('100%')
        .height('100%')
        .padding({ left: Theme.pad, right: Theme.pad, bottom: Theme.padBottom })
        .scrollBar(BarState.Off)
        .onAppear(() => {
          this.startIntro();
        })
        .onScrollIndex((first: number, last: number) => {
          this.onScrollReveal(first, last);
        })
      }
      .layoutWeight(1)
      .onRefreshing(() => {
        this.doRefresh();
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
    }, (l: AppLang) => l)
    }
    .width('100%')
    .height('100%')
  }

  /** 路由过渡：进二级页时首页向左轻移做视差，返回时从左侧滑回 */
  pageTransition() {
    PageTransitionExit({ type: RouteType.Push, duration: 320, curve: Curve.Friction })
      .translate({ x: '-16%' })
    PageTransitionEnter({ type: RouteType.Pop, duration: 320, curve: Curve.Friction })
      .translate({ x: '-16%' })
  }

  @Builder
  providerCard(s: ProviderState, idx: number) {
    Column({ space: Theme.rowGap }) {
      // 头部：名称 + 摘要
      Row({ space: Theme.rowGap }) {
        ProviderIcon({ providerId: s.descriptor.id, accentColor: s.descriptor.accentColor, iconSize: 32 })
        Text(s.descriptor.title)
          .fontSize(Theme.fsName)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.summaryOf(s))
          .fontSize(Theme.fsCaption)
          .fontColor(s.snapshot != null && !s.snapshot.ok ? Theme.danger : Theme.textDim)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')

      // 用量窗口（最多两个，详情页看全部）；Nowdex 风格紧凑块：大号百分比 + 点阵刻度尺 + ⏱ 倒计时
      if (s.snapshot != null && s.snapshot.ok) {
        if (s.snapshot.primary != null) {
          CompactWindowBlock({
            title: s.snapshot.primaryLabel.length > 0 ? s.snapshot.primaryLabel : L('会话', 'Session'),
            win: this.primaryWindow(s) ?? s.snapshot.primary,
            animKey: `${s.descriptor.id}_primary`
          })
        }
        if (s.snapshot.secondary != null) {
          CompactWindowBlock({
            title: s.snapshot.secondaryLabel.length > 0 ? s.snapshot.secondaryLabel : L('每周', 'Weekly'),
            win: s.snapshot.secondary,
            animKey: `${s.descriptor.id}_secondary`
          })
        }
        // 第三窗：紧凑行（标签 + 小号百分比，无进度条；对照 Nowdex cursor-row）
        if (s.snapshot.tertiary != null) {
          Row() {
            Text(s.snapshot.tertiaryLabel.length > 0 ? s.snapshot.tertiaryLabel : L('月度', 'Monthly'))
              .fontSize(Theme.fsCaption)
              .fontColor(Theme.textDim)
            Blank()
            Text(Format.percent(s.snapshot.tertiary.usedPercent))
              .fontSize(Theme.fsCaption)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.barColor(s.snapshot.tertiary.usedPercent, s.snapshot.tertiary.usageKnown))
          }
          .width('100%')
        }
        if (s.snapshot.providerCost != null && s.snapshot.primary == null) {
          Row() {
            Text(s.snapshot.providerCost.displayText)
              .fontSize(Theme.fsMetricSm)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.text)
            Blank()
            Text(s.snapshot.providerCost.currency)
              .fontSize(Theme.fsCaption)
              .fontColor(Theme.textDim)
          }
          .width('100%')
        }
      }

      // 加载中
      if (s.loading) {
        Row({ space: Theme.gapSm }) {
          LoadingProgress().width(14).height(14).color(Theme.accent)
          Text(L('正在获取用量…', 'Fetching usage…'))
            .fontSize(Theme.fsCaption)
            .fontColor(Theme.textDim)
        }
        .width('100%')
      }

      // 未配置提示
      if (!s.loading && s.setting.credential.length === 0) {
        Row({ space: Theme.gapXs }) {
          Text('🔑')
            .fontSize(Theme.fsCaption)
          Text(L('点击去设置页添加凭证', 'Tap to add a credential in Settings'))
            .fontSize(Theme.fsCaption)
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
    .shadow(Theme.cardShadow())
    // 进场 / 滚动揭示：未揭示的卡片先隐藏并下移 18vp，随 revealEdge 渐入上浮
    .opacity(idx > this.revealEdge ? 0 : 1)
    .translate({ y: idx > this.revealEdge ? 18 : 0 })
    .onClick(() => {
      Nav.toDetail(s.descriptor.id);
    })
  }
}
