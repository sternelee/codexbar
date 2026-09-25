/**
 * CodexBar Mobile — 用量条组件
 */

import { RateWindow, makeWindow } from '../model/Models';
import { Theme } from '../common/Theme';
import { Format } from '../common/Format';

/**
 * 数值过渡记忆：animKey → 上一次展示的百分比。
 * 首页 / 详情页的 ForEach key 携带刷新时间，数据一更新整块就重建——
 * 组件在 aboutToAppear 从记忆值起步、onAppear 时动画到目标值，
 * 这样重建后数值与进度条依然平滑过渡，而不是每次都从 0 重扫一遍。
 */
const percentMemory: Map<string, number> = new Map<string, number>();

/** 读取记忆的起点百分比；没有记忆（首次出现）从 0 扫入 */
function rememberedPercent(key: string): number {
  const v = percentMemory.get(key);
  return v != null ? v : 0;
}

/** 记忆当前目标值，供下一次重建作为动画起点 */
function rememberPercent(key: string, target: number): void {
  if (key.length > 0) {
    percentMemory.set(key, target);
  }
}

/** 数值过渡的公共节奏：与进场动画同一套减速曲线 */
const TWEEN_MS = 480;

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
 * 传 animKey 时启用数值过渡（见 percentMemory 说明）。
 */
@Component
export struct RowProgressBar {
  @Prop percent: number = 0;
  /** 服务商主色（hex 或资源引用；调用方经 Theme.brandTint 处理极端色值） */
  @Prop tint: ResourceColor = Theme.accent;
  /** 数值过渡锚点（服务商 id + 分组 + 行名）；空串 = 不做过渡 */
  @Prop animKey: string = '';
  @State animPercent: number = -1;

  aboutToAppear(): void {
    if (this.animKey.length > 0) {
      this.animPercent = rememberedPercent(this.animKey);
      rememberPercent(this.animKey, this.percent);
    }
  }

  build() {
    Stack({ alignContent: Alignment.Start }) {
      Row()
        .width('100%')
        .height(5)
        .borderRadius(2.5)
        .backgroundColor(Theme.stroke)
      Row()
        .width(`${Math.max(0, Math.min(100, this.animPercent >= 0 ? this.animPercent : this.percent))}%`)
        .height(5)
        .borderRadius(2.5)
        .backgroundColor(this.tint)
    }
    .width('100%')
    .onAppear(() => {
      if (this.animKey.length === 0 || this.animPercent === this.percent) {
        return;
      }
      this.getUIContext().animateTo({ duration: TWEEN_MS, curve: Curve.Friction }, () => {
        this.animPercent = this.percent;
      });
    })
  }
}

/** 一个用量窗口块：名称 + 百分比 + 进度条 + 重置倒计时；传 animKey 时百分比数字与进度条做数值过渡 */
@Component
export struct WindowBlock {
  @Prop title: string = '';
  @Prop win: RateWindow = makeWindow(0, 0, false);
  @Prop compact: boolean = false;
  /** 数值过渡锚点（服务商 id + 窗口 id）；空串 = 不做过渡（直接展示目标值） */
  @Prop animKey: string = '';
  @State animPercent: number = -1;

  aboutToAppear(): void {
    if (this.animKey.length > 0) {
      this.animPercent = rememberedPercent(this.animKey);
      rememberPercent(this.animKey, this.win.usedPercent);
    }
  }

  private shownPercent(): number {
    return this.animPercent >= 0 ? this.animPercent : this.win.usedPercent;
  }

  build() {
    Column({ space: Theme.gapXs }) {
      Row() {
        Text(this.title)
          .fontSize(this.compact ? Theme.fsCaption : Theme.fsBody)
          .fontColor(Theme.textDim)
        Blank()
        Text(Format.percent(this.shownPercent()))
          .fontSize(this.compact ? Theme.fsCaption : Theme.fsBody)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.barColor(this.win.usedPercent, this.win.usageKnown))
      }
      .width('100%')

      UsageBar({ percent: this.shownPercent(), usageKnown: this.win.usageKnown })

      if (this.win.resetsAt > 0) {
        Text(` ${Format.resetIn(this.win.resetsAt - Date.now())}`)
          .fontSize(Theme.fsMicro)
          .fontColor(Theme.textDim)
          .margin({ top: Theme.gapXxs })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .onAppear(() => {
      if (this.animKey.length === 0 || this.animPercent === this.win.usedPercent) {
        return;
      }
      this.getUIContext().animateTo({ duration: TWEEN_MS, curve: Curve.Friction }, () => {
        this.animPercent = this.win.usedPercent;
      });
    })
  }
}
