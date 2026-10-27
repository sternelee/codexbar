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

/** Nowdex 风格点阵刻度尺：SEGMENTS 段圆角竖条，按百分比点亮（满/半/暗） */
const SEGMENTS: number = 24;

/** 绘制点阵刻度尺（单 Canvas 一次绘制，避免几十个 Row 节点） */
function drawSegmentScaleOn(canvas: CanvasRenderingContext2D, w: number, h: number, percent: number, tint: string): void {
  if (w <= 0 || h <= 0) {
    return;
  }
  canvas.clearRect(0, 0, w, h);
  const gap = 2;
  const segW = (w - gap * (SEGMENTS - 1)) / SEGMENTS;
  const segH = h * 0.7;
  const y = (h - segH) / 2;
  const filled = (Math.max(0, Math.min(100, percent)) / 100) * SEGMENTS;
  for (let i = 0; i < SEGMENTS; i++) {
    const x = i * (segW + gap);
    const illum = filled - i;
    canvas.globalAlpha = 1;
    if (illum >= 1) {
      canvas.fillStyle = tint;
    } else if (illum >= 0.5) {
      canvas.fillStyle = tint;
      canvas.globalAlpha = 0.5;
    } else {
      canvas.fillStyle = '#00000022';
    }
    const r = segW / 2;
    canvas.beginPath();
    canvas.moveTo(x + r, y);
    canvas.arcTo(x + segW, y, x + segW, y + segH, r);
    canvas.arcTo(x + segW, y + segH, x, y + segH, r);
    canvas.arcTo(x, y + segH, x, y, r);
    canvas.arcTo(x, y, x + segW, y, r);
    canvas.closePath();
    canvas.fill();
  }
  canvas.globalAlpha = 1;
}

@Component
export struct SegmentScaleBar {
  percent: number = 0;
  tint: ResourceColor = Theme.accent;
  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));

  build() {
    Canvas(this.canvasContext)
      .width('100%')
      .height(12)
      .onReady(() => {
        const c = this.canvasContext;
        // Canvas 需要字面色值，统一走 Theme 用量色板（随系统深浅色）
        drawSegmentScaleOn(c, c.width, c.height, this.percent, Theme.chartAccent());
      })
  }
}

@Component
export struct UsageBar {
  @Prop percent: number = 0;
  @Prop usageKnown: boolean = true;

  build() {
    Stack({ alignContent: Alignment.Start }) {
      Row()
        .width('100%')
        .height(8)
        .borderRadius(4)
        .backgroundColor(Theme.stroke)
      Row()
        .width(`${Math.max(0, Math.min(100, this.percent))}%`)
        .height(8)
        .borderRadius(4)
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

/**
 * 首页紧凑卡片的 Nowdex 风格窗口块：
 * 大号百分比在左下（38%），右上为窗口名 + ⏱ 倒计时，下方点阵刻度尺；传 animKey 时做数值过渡。
 * 详情页继续使用 WindowBlock（标题行 + 进度条 + 倒计时）。
 */
@Component
export struct CompactWindowBlock {
  @Prop title: string = '';
  @Prop win: RateWindow = makeWindow(0, 0, false);
  /** 数值过渡锚点（服务商 id + 窗口 id）；空串 = 不做过渡 */
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
    Row() {
      Column({ space: Theme.gapXxs }) {
        Text(Format.percent(this.shownPercent()))
          .fontSize(Theme.fsMetricSm)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.barColor(this.win.usedPercent, this.win.usageKnown))
        SegmentScaleBar({ percent: this.shownPercent() })
          .width(120)
      }
      .alignItems(HorizontalAlign.Start)

      Blank()

      Column({ space: Theme.gapXxs }) {
        Text(this.title)
          .fontSize(Theme.fsCaption)
          .fontColor(Theme.textDim)
        if (this.win.resetsAt > 0) {
          Text(`⏱ ${Format.resetIn(this.win.resetsAt - Date.now())}`)
            .fontSize(Theme.fsMicro)
            .fontColor(Theme.textDim)
        }
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
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
        Text(`⏱ ${Format.resetIn(this.win.resetsAt - Date.now())}`)
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
