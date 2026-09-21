/**
 * CodexBar Mobile — 用量条组件
 */

import { RateWindow, makeWindow } from '../model/Models';
import { Theme } from '../common/Theme';
import { Format } from '../common/Format';

@Component
export struct UsageBar {
  @Prop percent: number = 0;
  @Prop usageKnown: boolean = true;

  build() {
    Stack({ alignContent: Alignment.Start }) {
      Row()
        .width('100%')
        .height(6)
        .borderRadius(3)
        .backgroundColor(Theme.stroke)
      Row()
        .width(`${Math.max(0, Math.min(100, this.percent))}%`)
        .height(6)
        .borderRadius(3)
        .backgroundColor(Theme.barColor(this.percent, this.usageKnown))
    }
    .width('100%')
  }
}

/** 一个用量窗口块：名称 + 百分比 + 进度条 + 重置倒计时 */
@Component
export struct WindowBlock {
  @Prop title: string = '';
  @Prop win: RateWindow = makeWindow(0, 0, false);
  @Prop compact: boolean = false;

  build() {
    Column({ space: 6 }) {
      Row() {
        Text(this.title)
          .fontSize(this.compact ? 12 : 13)
          .fontColor(Theme.textDim)
        Blank()
        Text(Format.percent(this.win.usedPercent))
          .fontSize(this.compact ? 12 : 13)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.barColor(this.win.usedPercent, this.win.usageKnown))
      }
      .width('100%')

      UsageBar({ percent: this.win.usedPercent, usageKnown: this.win.usageKnown })

      if (this.win.resetsAt > 0) {
        Text(` ${Format.resetIn(this.win.resetsAt - Date.now())}`)
          .fontSize(11)
          .fontColor(Theme.textDim)
          .margin({ top: 2 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
