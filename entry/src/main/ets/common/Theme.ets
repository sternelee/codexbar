/**
 * CodexBar Mobile — 主题常量
 * 参考 macOS 版菜单栏弹层的深色风格（docs/codexbar.png）。
 */

export class Theme {
  /** 页面背景 */
  static readonly bg: string = '#0B0B0F';
  /** 卡片背景 */
  static readonly card: string = '#17171E';
  /** 卡片描边 */
  static readonly stroke: string = '#26262F';
  /** 主文字 */
  static readonly text: string = '#F2F2F7';
  /** 次级文字 */
  static readonly textDim: string = '#8E8E99';
  /** 强调（应用主色，取自 codexbar.app 的青绿色） */
  static readonly accent: string = '#16D3B4';
  /** 通用成功 */
  static readonly ok: string = '#30D158';
  /** 警告（>70% 用量） */
  static readonly warn: string = '#FFD60A';
  /** 危险（>90% 用量） */
  static readonly danger: string = '#FF453A';
  /** 输入框背景 */
  static readonly input: string = '#1F1F28';

  /** 半径 */
  static readonly radius: number = 16;
  /** 页面左右边距 */
  static readonly pad: number = 16;
  /** 卡片内边距 */
  static readonly cardPad: number = 14;

  /**
   * 按用量取进度条颜色（CodexBar 语义：正常→警告→危险）。
   * usageKnown=false 时返回灰色。
   */
  static barColor(usedPercent: number, usageKnown: boolean): string {
    if (!usageKnown) {
      return '#3A3A44';
    }
    if (usedPercent >= 90) {
      return Theme.danger;
    }
    if (usedPercent >= 70) {
      return Theme.warn;
    }
    return Theme.accent;
  }
}
