/**
 * CodexBar Mobile — 2x2 服务卡片
 * 显示最紧急的 2 家服务商用量；点击打开应用。
 * 数据由应用刷新后经 formBindingData 推送（items 数组，按用量降序）。
 */

interface WidgetCardItem {
  name: string;
  pct: string;
  barPct: number;
  color: string;
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
          .fontColor('#F2F2F7')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(item.pct)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(item.color)
      }
      .width('100%')

      Row() {
        Row()
          .width(`${item.barPct}%`)
          .height('100%')
          .borderRadius(2)
          .backgroundColor(item.color)
      }
      .width('100%')
      .height(4)
      .borderRadius(2)
      .backgroundColor('#26262F')

      if (item.cd.length > 0) {
        Text(item.cd)
          .fontSize(9)
          .fontColor('#8E8E99')
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
          .fontColor('#16D3B4')
          .layoutWeight(1)
        Text(this.updatedAt)
          .fontSize(9)
          .fontColor('#8E8E99')
          .maxLines(1)
      }
      .width('100%')

      if (this.items.length === 0) {
        Text('打开应用刷新数据')
          .fontSize(11)
          .fontColor('#8E8E99')
          .width('100%')
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
      } else {
        ForEach(this.items, (item: WidgetCardItem, idx: number) => {
          if (idx < 2) {
            Column() {
              this.itemRow(item)
            }
          }
        }, (item: WidgetCardItem, idx: number) => `${idx}_${item.name}_${item.pct}`)
      }
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor('#0B0B0F')
    .onClick(() => {
      postCardAction(this, {
        'action': 'router',
        'abilityName': 'EntryAbility'
      });
    })
  }
}
