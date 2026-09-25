/**
 * CodexBar Mobile — 用量统计页
 *
 * 每日柱形图（用量增量百分点 / 消费估算）+ 今日/近7天/近30天合计。
 * 柱形图样式对照 macOS CostHistoryChartMenuView：峰值日黄色帽、
 * [0, 中点, 最大] 刻度、首末日期 X 轴。数据为刷新采样估算（详见 UsageHistory）。
 */

import { router } from '@kit.ArkUI';
import { ProviderState } from '../model/Models';
import { AppStore } from '../store/AppStore';
import { Settings } from '../store/Settings';
import {
  ChartPoint,
  costDeltas,
  dateKeyMinus,
  localDateKey,
  scaleFraction,
  scaleMax,
  sumLast,
  usageDeltas,
  yAxisTicks,
} from '../store/UsageHistory';
import { Format } from '../common/Format';
import { Theme } from '../common/Theme';
import { Nav, parseDetailParam } from '../common/Nav';

@Entry
@Component
struct StatsPage {
  @State @Watch('onChartSource') providerId: string = '';
  @State @Watch('onChartSource') metric: string = 'usage';
  @State @Watch('onChartSource') range: number = 7;
  @State ver: number = 0;
  /** 点选的日期键（柱形图选中日） */
  @State selectedDay: string = '';
  /** 柱形图数值过渡进度 0..1（进场 / 换数据源时从 0 长到 1） */
  @State chartReveal: number = 0;
  private chartPrimed: boolean = false;

  aboutToAppear(): void {
    // 路由指定服务商；未指定或不带历史数据时默认选第一个有数据的
    const routed = parseDetailParam(router.getParams() as Object | null);
    const list = this.historyProviders(0);
    let picked = routed;
    if (list.length > 0) {
      let known = false;
      for (let i = 0; i < list.length; i++) {
        if (list[i].descriptor.id === picked) {
          known = true;
          break;
        }
      }
      if (!known) {
        picked = list[0].descriptor.id;
      }
    }
    this.providerId = picked;
    this.ver = AppStore.get().version;
  }

  onPageShow(): void {
    this.ver += 1;
  }

  /** 换服务商 / 指标 / 区间：柱形图从基线重新长一遍（首次挂载的赋值不重播） */
  private onChartSource(): void {
    if (!this.chartPrimed) {
      return;
    }
    this.chartReveal = 0;
    this.getUIContext().animateTo({ duration: 480, curve: Curve.Friction }, () => {
      this.chartReveal = 1;
    });
  }

  /** 有历史数据的服务商；路由指定的优先 */
  historyProviders(v: number): ProviderState[] {
    const out: ProviderState[] = [];
    const states = AppStore.get().states;
    for (let i = 0; i < states.length; i++) {
      if (Settings.history(states[i].descriptor.id).length >= 2) {
        out.push(states[i]);
      }
    }
    return out;
  }

  hasBalanceHistory(pid: string): boolean {
    const records = Settings.history(pid);
    for (let i = 0; i < records.length; i++) {
      if (records[i].b >= 0) {
        return true;
      }
    }
    return false;
  }

  points(v: number): ChartPoint[] {
    const pid = this.providerId;
    if (pid.length === 0) {
      return [];
    }
    const records = Settings.history(pid);
    const all = this.metric === 'usage' ? usageDeltas(records) : costDeltas(records);
    const from = dateKeyMinus(localDateKey(Date.now()), this.range - 1);
    const out: ChartPoint[] = [];
    for (let i = 0; i < all.length; i++) {
      if (all[i].d >= from) {
        out.push(all[i]);
      }
    }
    return out;
  }

  /** Select 选项（仅有历史数据的服务商） */
  private providerOptions(): SelectOption[] {
    const list = this.historyProviders(this.ver);
    const out: SelectOption[] = [];
    for (let i = 0; i < list.length; i++) {
      out.push({ value: list[i].descriptor.title });
    }
    return out;
  }

  /** 当前服务商在选项里的下标；未匹配返回 -1 */
  private selectedIdx(): number {
    const list = this.historyProviders(this.ver);
    for (let i = 0; i < list.length; i++) {
      if (list[i].descriptor.id === this.providerId) {
        return i;
      }
    }
    return -1;
  }

  /** Select 显示文案（当前服务商名） */
  private selectedName(): string {
    const idx = this.selectedIdx();
    const list = this.historyProviders(this.ver);
    return idx >= 0 && idx < list.length ? list[idx].descriptor.title : '选择服务商';
  }

  fmtValue(v: number): string {
    if (this.metric === 'usage') {
      return `${Math.round(v * 10) / 10}%`;
    }
    return v >= 10 ? `$${v.toFixed(0)}` : `$${v.toFixed(2)}`;
  }

  build() {
    Column() {
      // 顶栏
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

        Text('用量统计')
          .fontSize(Theme.fsHead)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.text)
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: Theme.pad, right: Theme.pad, top: Theme.gap, bottom: Theme.gapSm })

      if (this.historyProviders(this.ver).length === 0) {
        Column({ space: Theme.rowGap }) {
          Text('📊')
            .fontSize(Theme.fsEmojiLg)
          Text('暂无统计数据')
            .fontSize(Theme.fsName)
            .fontColor(Theme.text)
          Text('回仪表盘点「刷新」积累数据')
            .fontSize(Theme.fsCaption)
            .fontColor(Theme.textDim)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: Theme.gap }) {
          // 服务商下拉选择器
          ListItem() {
            Row({ space: Theme.gapSm }) {
              Text('服务商')
                .fontSize(Theme.fsBody)
                .fontColor(Theme.textDim)
              Select(this.providerOptions())
                .selected(this.selectedIdx())
                .value(this.selectedName())
                .font({ size: Theme.fsBody, weight: FontWeight.Medium })
                .fontColor(Theme.text)
                .selectedOptionFont({ size: Theme.fsBody, weight: FontWeight.Medium })
                .selectedOptionBgColor(Theme.input)
                .optionFont({ size: Theme.fsBody })
                .optionBgColor(Theme.card)
                .backgroundColor(Theme.input)
                .borderRadius(Theme.radiusInput)
                .height(36)
                .layoutWeight(1)
                .onSelect((index: number, value: string) => {
                  const list = this.historyProviders(this.ver);
                  if (index >= 0 && index < list.length) {
                    this.providerId = list[index].descriptor.id;
                    if (!this.hasBalanceHistory(this.providerId) && this.metric === 'cost') {
                      this.metric = 'usage';
                    }
                  }
                })
            }
            .width('100%')
          }

          // 指标 + 范围
          ListItem() {
            Row({ space: Theme.rowGap }) {
              Row({ space: Theme.gapXs }) {
                Text('用量')
                  .fontSize(Theme.fsCaption)
                  .fontColor(this.metric === 'usage' ? Theme.bg : Theme.textDim)
                  .backgroundColor(this.metric === 'usage' ? Theme.accent : Theme.input)
                  .padding({ left: Theme.gap, right: Theme.gap, top: Theme.gapXs, bottom: Theme.gapXs })
                  .borderRadius(Theme.radiusInput)
                  .onClick(() => {
                    this.metric = 'usage';
                  })
                if (this.hasBalanceHistory(this.providerId)) {
                  Text('消费')
                    .fontSize(Theme.fsCaption)
                    .fontColor(this.metric === 'cost' ? Theme.bg : Theme.textDim)
                    .backgroundColor(this.metric === 'cost' ? Theme.accent : Theme.input)
                    .padding({ left: Theme.gap, right: Theme.gap, top: Theme.gapXs, bottom: Theme.gapXs })
                    .borderRadius(Theme.radiusInput)
                    .onClick(() => {
                      this.metric = 'cost';
                    })
                }
              }

              Blank()

              Row({ space: Theme.gapXs }) {
                Text('近7天')
                  .fontSize(Theme.fsCaption)
                  .fontColor(this.range === 7 ? Theme.bg : Theme.textDim)
                  .backgroundColor(this.range === 7 ? Theme.accent : Theme.input)
                  .padding({ left: Theme.rowGap, right: Theme.rowGap, top: Theme.gapXs, bottom: Theme.gapXs })
                  .borderRadius(Theme.radiusInput)
                  .onClick(() => {
                    this.range = 7;
                  })
                Text('近30天')
                  .fontSize(Theme.fsCaption)
                  .fontColor(this.range === 30 ? Theme.bg : Theme.textDim)
                  .backgroundColor(this.range === 30 ? Theme.accent : Theme.input)
                  .padding({ left: Theme.rowGap, right: Theme.rowGap, top: Theme.gapXs, bottom: Theme.gapXs })
                  .borderRadius(Theme.radiusInput)
                  .onClick(() => {
                    this.range = 30;
                  })
              }
            }
            .width('100%')
          }

          // 柱形图卡片
          ListItem() {
            this.chartCard()
          }

          // 合计：三个区间收进同一张卡，标题 + 分割线与数值行分层
          ListItem() {
            Column({ space: Theme.gapSm }) {
              Text('合计')
                .fontSize(Theme.fsCaption)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.text)
                .letterSpacing(Theme.tracking)
              Divider()
                .width('100%')
                .strokeWidth(1)
                .color(Theme.stroke)
              Row() {
                Text('今日')
                  .fontSize(Theme.fsBody)
                  .fontColor(Theme.textDim)
                Blank()
                Text(this.fmtValue(sumLast(this.points(this.ver), localDateKey(Date.now()), 1)))
                  .fontSize(Theme.fsBody)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Theme.text)
              }
              .width('100%')
              Row() {
                Text('近7天')
                  .fontSize(Theme.fsBody)
                  .fontColor(Theme.textDim)
                Blank()
                Text(this.fmtValue(sumLast(this.points(this.ver), localDateKey(Date.now()), 7)))
                  .fontSize(Theme.fsBody)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Theme.text)
              }
              .width('100%')
              Row() {
                Text('近30天')
                  .fontSize(Theme.fsBody)
                  .fontColor(Theme.textDim)
                Blank()
                Text(this.fmtValue(sumLast(this.points(this.ver), localDateKey(Date.now()), 30)))
                  .fontSize(Theme.fsBody)
                  .fontWeight(FontWeight.Medium)
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
            .shadow(Theme.cardShadow())
          }

          ListItem() {
            Text('基于刷新采样估算：每日取最后一次成功查询的用量/余额推算增量，与真实计费存在差异。')
              .fontSize(Theme.fsMicro)
              .fontColor(Theme.textDim)
              .width('100%')
          }
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: Theme.pad, right: Theme.pad, bottom: Theme.padBottom })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
  }

  @Builder
  chartCard() {
    Column({ space: Theme.rowGap }) {
      this.chartBody()
    }
    .width('100%')
    .padding(Theme.cardPad)
    .borderRadius(Theme.radius)
    .backgroundColor(Theme.card)
    .border({ width: 1, color: Theme.stroke })
    .shadow(Theme.cardShadow())
    .onAppear(() => {
      // 进场：柱形图从基线长出（之后换数据源由 onChartSource 重播）
      this.chartPrimed = true;
      this.getUIContext().animateTo({ duration: 480, curve: Curve.Friction }, () => {
        this.chartReveal = 1;
      });
    })
  }

  @Builder
  chartBody() {
    Row({ space: Theme.gapXs }) {
      // Y 轴标签
      Column({ space: 0 }) {
        Text(this.yLabel(1))
          .fontSize(Theme.fsAxis)
          .fontColor(Theme.textDim)
        Blank()
        Text(this.yLabel(0.5))
          .fontSize(Theme.fsAxis)
          .fontColor(Theme.textDim)
        Blank()
        Text('0')
          .fontSize(Theme.fsAxis)
          .fontColor(Theme.textDim)
      }
      .height(130)
      .alignItems(HorizontalAlign.End)

      // 柱区
      Row({ space: 2 }) {
        ForEach(this.points(this.ver), (pt: ChartPoint, idx: number) => {
          Column({ space: 0 }) {
            // 峰值黄帽（对照 macOS：峰值柱顶部 5% 高亮）
            if (this.isPeak(pt)) {
              Row()
                .width('100%')
                .height(130 * 0.05 * this.frac(pt) * this.chartReveal)
                .backgroundColor(Theme.warn)
            }
            Row()
              .width('100%')
              .height(130 * (this.frac(pt) - (this.isPeak(pt) ? 0.05 * this.frac(pt) : 0)) * this.chartReveal)
              .backgroundColor(Theme.accent)
          }
          .height(130)
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.End)
          .onClick(() => {
            this.selectedDay = pt.d;
          })
        }, (pt: ChartPoint, idx: number) => `${pt.d}_${pt.v}`)
      }
      .layoutWeight(1)
      .height(130)
      .alignItems(VerticalAlign.Bottom)
    }
    .width('100%')

    // X 轴：首/末日期
    Row() {
      Text(this.firstLabel())
        .fontSize(Theme.fsAxis)
        .fontColor(Theme.textDim)
      Blank()
      Text(this.selectedSummary())
        .fontSize(Theme.fsAxis)
        .fontColor(Theme.text)
      Blank()
      Text(this.lastLabel())
        .fontSize(Theme.fsAxis)
        .fontColor(Theme.textDim)
    }
    .width('100%')
  }

  yLabel(frac: number): string {
    const pts = this.points(this.ver);
    const max = scaleMax(pts.map((p: ChartPoint) => p.v));
    const ticks = yAxisTicks(max, this.metric === 'cost');
    if (ticks.length === 0) {
      return '';
    }
    const v = frac === 1 ? ticks[ticks.length - 1] : (ticks.length > 2 ? ticks[1] : ticks[ticks.length - 1] / 2);
    if (this.metric === 'usage') {
      return `${Math.round(v * 10) / 10}%`;
    }
    return v >= 10 ? `$${v.toFixed(0)}` : `$${v.toFixed(2)}`;
  }

  frac(pt: ChartPoint): number {
    return scaleFraction(pt.v, scaleMax(this.points(this.ver).map((p: ChartPoint) => p.v)));
  }

  isPeak(pt: ChartPoint): boolean {
    const pts = this.points(this.ver);
    if (pts.length === 0) {
      return false;
    }
    const max = scaleMax(pts.map((p: ChartPoint) => p.v));
    return max > 0 && pt.v === max;
  }

  firstLabel(): string {
    const pts = this.points(this.ver);
    return pts.length > 0 ? pts[0].label : '';
  }

  lastLabel(): string {
    const pts = this.points(this.ver);
    return pts.length > 0 ? pts[pts.length - 1].label : '';
  }

  /** 选中日摘要（默认最后一天） */
  selectedSummary(): string {
    const pts = this.points(this.ver);
    if (pts.length === 0) {
      return '';
    }
    let pt = pts[pts.length - 1];
    if (this.selectedDay.length > 0) {
      for (let i = 0; i < pts.length; i++) {
        if (pts[i].d === this.selectedDay) {
          pt = pts[i];
          break;
        }
      }
    }
    return `${pt.label}: ${this.fmtValue(pt.v)}`;
  }

  /** 路由过渡：从右侧滑入 / 滑出 */
  pageTransition() {
    PageTransitionEnter({ type: RouteType.Push, duration: 320, curve: Curve.Friction })
      .translate({ x: '100%' })
    PageTransitionEnter({ type: RouteType.Pop, duration: 320, curve: Curve.Friction })
      .translate({ x: '-16%' })
    PageTransitionExit({ type: RouteType.Pop, duration: 320, curve: Curve.Friction })
      .translate({ x: '100%' })
    PageTransitionExit({ type: RouteType.Push, duration: 320, curve: Curve.Friction })
      .translate({ x: '-16%' })
  }
}
