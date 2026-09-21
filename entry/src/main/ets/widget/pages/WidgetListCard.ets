/**
 * CodexBar Mobile — 2x4 服务卡片
 * 显示最紧急的 4 家服务商用量；点击打开应用。
 */

interface WidgetListCardItem {
  name: string;
  pct: string;
  barPct: number;
  color: string;
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
        .fontColor('#F2F2F7')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width(72)
      Row() {
        Row()
          .width(`${item.barPct}%`)
          .height('100%')
          .borderRadius(2)
          .backgroundColor(item.color)
      }
      .layoutWeight(1)
      .height(4)
      .borderRadius(2)
      .backgroundColor('#26262F')
      Text(item.pct)
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor(item.color)
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
        ForEach(this.items, (item: WidgetListCardItem, idx: number) => {
          if (idx < 4) {
            Column({ space: 2 }) {
              this.itemRow(item)
              if (item.cd.length > 0 && idx < 2) {
                Text(item.cd)
                  .fontSize(9)
                  .fontColor('#8E8E99')
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
    .backgroundColor('#0B0B0F')
    .onClick(() => {
      postCardAction(this, {
        'action': 'router',
        'abilityName': 'EntryAbility'
      });
    })
  }
}
