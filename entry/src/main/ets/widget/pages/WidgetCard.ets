/**
 * CodexBar Mobile — 2x2 服务卡片
 * 桌面上左右滑动（Swiper 轮播）切换显示的服务商，一页一家；
 * 点击打开应用。数据由应用刷新后经 formBindingData 推送。
 *
 * 颜色全部取 `$r('app.color.*')`：卡片进程按系统深浅色自动换值，
 * 因此数据里传的是用量「等级」（level）而不是色值。
 */

import { widgetLevelColor } from './WidgetTheme';

interface WidgetCardItem {
  name: string;
  pct: string;
  barPct: number;
  level: string;
  cd: string;
}

@Entry
@Component
struct WidgetCard {
  @LocalStorageProp('updatedAt') updatedAt: string = '';
  @LocalStorageProp('items') items: WidgetCardItem[] = [];

  @Builder
  itemRow(item: WidgetCardItem) {
    Column({ space: 3 }) {
      Row({ space: 6 }) {
        Text(item.name)
          .fontSize(11)
          .fontColor($r('app.color.text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(item.pct)
          .fontSize(12)
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
      .height(4)
      .borderRadius(2)
      .backgroundColor($r('app.color.stroke'))

      if (item.cd.length > 0) {
        Text(item.cd)
          .fontSize(9)
          .fontColor($r('app.color.text_dim'))
          .maxLines(1)
      }
    }
    .width('100%')
  }

  build() {
    Column({ space: 8 }) {
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
          ForEach(this.items, (item: WidgetCardItem, idx: number) => {
            Column({ space: 6 }) {
              this.itemRow(item)
              // 轮播位置提示：第 x / n 家
              Text(`${idx + 1} / ${this.items.length}`)
                .fontSize(8)
                .fontColor($r('app.color.text_dim'))
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
          }, (item: WidgetCardItem, idx: number) => `${idx}_${item.name}_${item.pct}`)
        }
        .indicator(true)
        .loop(true)
        .width('100%')
        .layoutWeight(1)
      }
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
