/**
 * CodexBar Mobile — 2x4 服务卡片
 * 桌面上左右滑动（Swiper 轮播）切换显示的服务商，一页一家（含倒计时）；
 * 点击打开应用。颜色走 `$r('app.color.*')`，随系统深浅色自动换值。
 */

import { widgetLevelColor } from './WidgetTheme';

interface WidgetListCardItem {
  name: string;
  pct: string;
  barPct: number;
  level: string;
  cd: string;
  /** hero 泳道名（绑定泳道比主泳道更紧时标注，如 "Weekly"）；主泳道为空 */
  lane?: string;
}

@Entry
@Component
struct WidgetListCard {
  @LocalStorageProp('updatedAt') updatedAt: string = '';
  @LocalStorageProp('items') items: WidgetListCardItem[] = [];

  @Builder
  itemRow(item: WidgetListCardItem) {
    Row({ space: 8 }) {
      Text(item.name)
        .fontSize(11)
        .fontColor($r('app.color.text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width(72)
      Row() {
        Row()
          .width(`${item.barPct}%`)
          .height('100%')
          .borderRadius(2)
          .backgroundColor(widgetLevelColor(item.level))
      }
      .layoutWeight(1)
      .height(4)
      .borderRadius(2)
      .backgroundColor($r('app.color.stroke'))
      Text(item.pct)
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor(widgetLevelColor(item.level))
        .width(38)
        .textAlign(TextAlign.End)
    }
    .width('100%')
  }

  build() {
    Column({ space: 7 }) {
      Row({ space: 4 }) {
        Text('CodexBar')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.accent'))
          .layoutWeight(1)
        Text(this.updatedAt)
          .fontSize(9)
          .fontColor($r('app.color.text_dim'))
          .maxLines(1)
      }
      .width('100%')

      if (this.items.length === 0) {
        Text('打开应用刷新数据')
          .fontSize(11)
          .fontColor($r('app.color.text_dim'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
      } else {
        Swiper() {
          ForEach(this.items, (item: WidgetListCardItem, idx: number) => {
            Column({ space: 8 }) {
              // 一页一家：服务名 + 大号百分比 + 进度条 + 重置倒计时
              Row({ space: 8 }) {
                Text(item.name)
                  .fontSize(13)
                  .fontColor($r('app.color.text'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                Text(item.pct)
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(widgetLevelColor(item.level))
              }
              .width('100%')

              Row() {
                Row()
                  .width(`${item.barPct}%`)
                  .height('100%')
                  .borderRadius(2)
                  .backgroundColor(widgetLevelColor(item.level))
              }
              .width('100%')
              .height(5)
              .borderRadius(2)
              .backgroundColor($r('app.color.stroke'))

              if (item.cd.length > 0 || (item.lane != null && item.lane.length > 0)) {
                Text(item.lane != null && item.lane.length > 0
                  ? (item.cd.length > 0 ? `${item.lane} · ${item.cd}` : item.lane)
                  : item.cd)
                  .fontSize(10)
                  .fontColor($r('app.color.text_dim'))
                  .maxLines(1)
                  .width('100%')
              }

              Text(`${idx + 1} / ${this.items.length}`)
                .fontSize(8)
                .fontColor($r('app.color.text_dim'))
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
          }, (item: WidgetListCardItem, idx: number) => `${idx}_${item.name}_${item.pct}_${item.cd}_${item.lane == null ? '' : item.lane}`)
        }
        .indicator(true)
        .loop(true)
        .width('100%')
        .layoutWeight(1)
      }

      // 右下角刷新：只重查当前显示中的服务商（message → EntryFormAbility）
      Row() {
        Text('↻')
          .fontSize(13)
          .fontColor($r('app.color.text'))
          .width(22)
          .height(22)
          .textAlign(TextAlign.Center)
          .borderRadius(11)
          .backgroundColor($r('app.color.stroke'))
          .onClick(() => {
            postCardAction(this, {
              'action': 'message',
              'params': { 'event': 'refresh' }
            });
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor($r('app.color.bg'))
    .onClick(() => {
      postCardAction(this, {
        'action': 'router',
        'abilityName': 'EntryAbility'
      });
    })
  }
}
