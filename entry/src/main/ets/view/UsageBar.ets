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

/**
 * 明细行内进度条（对照 UsageProgressBar 在明细行里的用法）：
 * 中性轨道 + 服务商主色填充；传入的百分比按 0..100 截断（超额计划的原始数值由行文案保留）。
 */
@Component
export struct RowProgressBar {
  @Prop percent: number = 0;
  /** 服务商主色（hex 或资源引用；调用方经 Theme.brandTint 处理极端色值） */
  @Prop tint: ResourceColor = Theme.accent;

  build() {
    Stack({ alignContent: Alignment.Start }) {
      Row()
        .width('100%')
        .height(5)
        .borderRadius(2.5)
        .backgroundColor(Theme.stroke)
      Row()
        .width(`${Math.max(0, Math.min(100, this.percent))}%`)
        .height(5)
        .borderRadius(2.5)
        .backgroundColor(this.tint)
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
    Column({ space: Theme.gapXs }) {
      Row() {
        Text(this.title)
          .fontSize(this.compact ? Theme.fsCaption : Theme.fsBody)
          .fontColor(Theme.textDim)
        Blank()
        Text(Format.percent(this.win.usedPercent))
          .fontSize(this.compact ? Theme.fsCaption : Theme.fsBody)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.barColor(this.win.usedPercent, this.win.usageKnown))
      }
      .width('100%')

      UsageBar({ percent: this.win.usedPercent, usageKnown: this.win.usageKnown })

      if (this.win.resetsAt > 0) {
        Text(` ${Format.resetIn(this.win.resetsAt - Date.now())}`)
          .fontSize(Theme.fsMicro)
          .fontColor(Theme.textDim)
          .margin({ top: Theme.gapXxs })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
