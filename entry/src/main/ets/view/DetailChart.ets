/**
 * CodexBar Mobile — 明细分组图表
 *
 * 对应 macOS 版 ProviderDetailSectionsContent.ProviderDetailChartContent：
 * 顶部一行「标题 + 单位」，下面按 chart.kind 画柱状（默认）或折线，底部一条基线。
 * 柱体高度按「最大值归一化」定标（UsageChartScale），颜色按占比加深，
 * 0 值画 1px 细条而不是消失（源工程 height 最小 3 / fill 最小 0.18）。
 */

import { ProviderChart, ProviderChartPoint } from '../model/Models';
import { Theme } from '../common/Theme';

/** 绘图区高度（对照源工程 chart .frame(height: 58)） */
const PLOT_HEIGHT: number = 58;
/** 柱间距 */
const BAR_GAP: number = 2;
/** 最多绘制的柱/点（源工程同款上限） */
const MAX_RENDER_POINTS: number = 120;

@Component
export struct DetailChart {
  chart: ProviderChart = { kind: 'bars', points: [] };
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  /** 参与绘制的点（裁到上限） */
  private points(): ProviderChartPoint[] {
    const all = this.chart.points;
    if (all.length <= MAX_RENDER_POINTS) {
      return all;
    }
    return all.slice(all.length - MAX_RENDER_POINTS);
  }

  /** 归一化定标：全零/负数序列时返回 0（此时不画柱体，只留基线） */
  private maximum(pts: ProviderChartPoint[]): number {
    let max = 0;
    for (let i = 0; i < pts.length; i++) {
      const v = pts[i].value;
      if (isFinite(v) && v > max) {
        max = v;
      }
    }
    return max;
  }

  build() {
    Column({ space: 3 }) {
      if (this.hasCaption()) {
        Row({ space: 6 }) {
          if (this.chart.title != null && this.chart.title!.length > 0) {
            Text(this.chart.title!)
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.textDim)
          }
          Blank()
          if (this.chart.unit != null && this.chart.unit!.length > 0) {
            Text(this.chart.unit!)
              .fontSize(11)
              .fontColor(Theme.textDim)
          }
        }
        .width('100%')
      }

      Canvas(this.ctx)
        .width('100%')
        .height(PLOT_HEIGHT)
        .onReady(() => {
          this.draw();
        })
    }
    .width('100%')
  }

  private hasCaption(): boolean {
    const t = this.chart.title;
    const u = this.chart.unit;
    return (t != null && t.length > 0) || (u != null && u.length > 0);
  }

  /** 绘制入口：空数据只画基线 */
  private draw(): void {
    const pts = this.points();
    const width = this.ctx.width;
    const height = this.ctx.height;
    this.ctx.clearRect(0, 0, width, height);
    if (pts.length === 0 || width <= 0) {
      return;
    }
    const max = this.maximum(pts);
    const baseY = height - 0.5;

    // 基线（源工程 overlay 的 1px 线）。Canvas 2D 只认字面色值，故走 Theme.chart*()。
    this.ctx.strokeStyle = Theme.chartStroke();
    this.ctx.lineWidth = 1;
    this.ctx.beginPath();
    this.ctx.moveTo(0, baseY);
    this.ctx.lineTo(width, baseY);
    this.ctx.stroke();

    if (max <= 0) {
      return;
    }
    if (this.chart.kind === 'line') {
      this.drawLine(pts, max, width, height);
    } else {
      this.drawBars(pts, max, width, height);
    }
  }

  /** 柱状：等宽柱 + 2px 间距，高度按占比，颜色按占比加深（最小 0.18 alpha） */
  private drawBars(pts: ProviderChartPoint[], max: number, width: number, height: number): void {
    const slot = (width - BAR_GAP * (pts.length - 1)) / pts.length;
    const barW = slot > 0 ? slot : 1;
    const usable = height - 1;
    for (let i = 0; i < pts.length; i++) {
      const value = pts[i].value;
      const ratio = value > 0 && isFinite(value) ? Math.min(value / max, 1) : 0;
      const barH = ratio > 0 ? Math.max(3, ratio * usable) : 1;
      const x = i * (barW + BAR_GAP);
      this.ctx.fillStyle = this.barFill(ratio);
      this.ctx.fillRect(x, height - barH, barW, barH);
    }
  }

  /** 折线：2px 圆角折线 + 3px 圆点（单点时居中） */
  private drawLine(pts: ProviderChartPoint[], max: number, width: number, height: number): void {
    const step = pts.length === 1 ? 0 : width / (pts.length - 1);
    const usable = height - 1;
    this.ctx.strokeStyle = Theme.chartAccent();
    this.ctx.lineWidth = 2;
    this.ctx.beginPath();
    for (let i = 0; i < pts.length; i++) {
      const x = pts.length === 1 ? width / 2 : step * i;
      const ratio = pts[i].value > 0 && isFinite(pts[i].value) ? Math.min(pts[i].value / max, 1) : 0;
      const y = height - ratio * usable;
      if (i === 0) {
        this.ctx.moveTo(x, y);
      } else {
        this.ctx.lineTo(x, y);
      }
    }
    this.ctx.stroke();
    this.ctx.fillStyle = Theme.chartAccent();
    for (let i = 0; i < pts.length; i++) {
      const x = pts.length === 1 ? width / 2 : step * i;
      const ratio = pts[i].value > 0 && isFinite(pts[i].value) ? Math.min(pts[i].value / max, 1) : 0;
      const y = height - ratio * usable;
      this.ctx.beginPath();
      this.ctx.arc(x, y, 1.5, 0, Math.PI * 2);
      this.ctx.fill();
    }
  }

  /**
   * 柱体颜色：强调色按占比加深（0.42 → 1.0），零值柱保持最浅，
   * 源工程还给填充设了 0.18 下限，这里通过 ratio 归一化后保持一致观感。
   */
  private barFill(ratio: number): string {
    const clamped = Math.max(0.18, ratio);
    const alpha = 0.42 + clamped * 0.58;
    return this.withAlpha(Theme.chartAccent(), alpha);
  }

  /** #RRGGBB + alpha → rgba(...) */
  private withAlpha(hex: string, alpha: number): string {
    const r = parseInt(hex.substring(1, 3), 16);
    const g = parseInt(hex.substring(3, 5), 16);
    const b = parseInt(hex.substring(5, 7), 16);
    return `rgba(${r}, ${g}, ${b}, ${Math.round(alpha * 100) / 100})`;
  }
}
