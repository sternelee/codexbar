/**
 * CodexBar Mobile — 2x4 服务卡片
 * 显示最紧急的 4 家服务商用量；点击打开应用。
 * 颜色走 `$r('app.color.*')`，随系统深浅色自动换值（数据里传用量等级）。
 */

import { widgetLevelColor } from './WidgetTheme';

interface WidgetListCardItem {
  name: string;
  pct: string;
  barPct: number;
  level: string;
  cd: string;
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
        ForEach(this.items, (item: WidgetListCardItem, idx: number) => {
          if (idx < 4) {
            Column({ space: 2 }) {
              this.itemRow(item)
              if (item.cd.length > 0 && idx < 2) {
                Text(item.cd)
                  .fontSize(9)
                  .fontColor($r('app.color.text_dim'))
                  .maxLines(1)
                  .width('100%')
              }
            }
            .width('100%')
          }
        }, (item: WidgetListCardItem, idx: number) => `${idx}_${item.name}_${item.pct}_${item.cd}`)
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
