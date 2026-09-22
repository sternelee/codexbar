/**
 * CodexBar Mobile — 主题
 *
 * 颜色全部走资源引用（`$r('app.color.*')`），`resources/base` 是明亮值、
 * `resources/dark` 是暗色值，系统深色模式切换时由框架自动换值，不需要手工监听。
 *
 * 两处例外必须用字面色值（框架只能解析资源，Canvas 2D 与表单 JSON 不能）：
 *  1. Canvas 2D 的 `fillStyle` / `strokeStyle` —— 走 `Theme.chart*()`，
 *     由 `Theme.isDark()`（AppStorage 里由 EntryAbility 写入的系统色彩模式）决定；
 *  2. 服务卡片数据（FormBindingData 是 JSON）—— 走用量「等级」而不是色值，
 *     由卡片页自己映射到资源色。
 */

/** 需要字面色值的 Canvas 调色板（与 base/dark 两份 color.json 保持同一组值） */
interface ChartPalette {
  accent: string;
  stroke: string;
  track: string;
}

const DARK_PALETTE: ChartPalette = { accent: '#16D3B4', stroke: '#26262F', track: '#3A3A44' };
const LIGHT_PALETTE: ChartPalette = { accent: '#0A8471', stroke: '#E5E5EB', track: '#D9D9E0' };

export class Theme {
  // ---------------------------------------------------------------- 颜色资源

  // 取色器而不是字段：模块加载期不做资源解析（宿主单测环境没有资源表），
  // 并且声明为 Resource 以便同时满足 `ResourceColor` 与更窄的 `string | Resource` 参数。

  /** 页面背景 */
  static get bg(): Resource {
    return $r('app.color.bg');
  }

  /** 卡片背景 */
  static get card(): Resource {
    return $r('app.color.card');
  }

  /** 卡片描边 */
  static get stroke(): Resource {
    return $r('app.color.stroke');
  }

  /** 主文字 */
  static get text(): Resource {
    return $r('app.color.text');
  }

  /** 次级文字 */
  static get textDim(): Resource {
    return $r('app.color.text_dim');
  }

  /** 强调（应用主色，取自 codexbar.app 的青绿色；明亮模式用加深版保证白底可读） */
  static get accent(): Resource {
    return $r('app.color.accent');
  }

  /** 通用成功 */
  static get ok(): Resource {
    return $r('app.color.ok');
  }

  /** 警告（>70% 用量） */
  static get warn(): Resource {
    return $r('app.color.warn');
  }

  /** 危险（>90% 用量） */
  static get danger(): Resource {
    return $r('app.color.danger');
  }

  /** 输入框背景 */
  static get input(): Resource {
    return $r('app.color.input');
  }

  /** 进度条轨道（用量未知时的灰条） */
  static get barTrack(): Resource {
    return $r('app.color.bar_track');
  }

  /** 图标衬底与其描边（明亮模式下衬底需要一圈描边才不会糊在卡片上） */
  static get iconPlate(): Resource {
    return $r('app.color.icon_plate');
  }

  static get iconPlateEdge(): Resource {
    return $r('app.color.icon_plate_edge');
  }

  /** 危险提示底色（错误条 / 危险按钮底） */
  static get dangerTint(): Resource {
    return $r('app.color.danger_tint');
  }

  // ------------------------------------------------------------------ 尺度

  /** 半径 */
  static readonly radius: number = 16;
  /** 页面左右边距 */
  static readonly pad: number = 16;
  /** 卡片内边距 */
  static readonly cardPad: number = 14;
  /** 卡片之间的间距 */
  static readonly gap: number = 12;
  /** 控件行内间距 */
  static readonly rowGap: number = 10;

  // -------------------------------------------------------------- 运行时色彩

  /** 由 EntryAbility 写入 AppStorage 的系统色彩模式 */
  private static readonly DARK_KEY: string = 'isDarkMode';

  /** 当前是否暗色（未知时按暗色，保持历史观感） */
  static isDark(): boolean {
    try {
      const v = AppStorage.get<boolean>(Theme.DARK_KEY);
      return v == null ? true : v;
    } catch (e) {
      // 宿主单测环境没有 AppStorage：退回暗色
      return true;
    }
  }

  /** 记录系统色彩模式（EntryAbility 启动与配置变更时调用） */
  static setDark(dark: boolean): void {
    AppStorage.setOrCreate(Theme.DARK_KEY, dark);
  }

  /** Canvas 用：强调色字面值 */
  static chartAccent(): string {
    return Theme.palette().accent;
  }

  /** Canvas 用：基线/轨道字面值 */
  static chartStroke(): string {
    return Theme.palette().stroke;
  }

  private static palette(): ChartPalette {
    return Theme.isDark() ? DARK_PALETTE : LIGHT_PALETTE;
  }

  // ------------------------------------------------------------------ 取色

  /**
   * 按用量取进度条颜色（CodexBar 语义：正常→警告→危险）。
   * usageKnown=false 时返回轨道灰。
   */
  static barColor(usedPercent: number, usageKnown: boolean): Resource {
    if (!usageKnown) {
      return Theme.barTrack;
    }
    if (usedPercent >= 90) {
      return Theme.danger;
    }
    if (usedPercent >= 70) {
      return Theme.warn;
    }
    return Theme.accent;
  }

  /** 进度条颜色等级（表单 JSON 用：卡片页自己映射到资源色） */
  static barLevel(usedPercent: number, usageKnown: boolean): string {
    if (!usageKnown) {
      return 'unknown';
    }
    if (usedPercent >= 90) {
      return 'danger';
    }
    if (usedPercent >= 70) {
      return 'warn';
    }
    return 'ok';
  }

  /**
   * 品牌强调色的可用化：近白（Warp）在浅底上、近黑（ElevenLabs）在深底上都会「消失」，
   * 这类极端值统一回落到应用主色，其余原样使用。
   * 返回字面色值，因此可以喂给任何接受 ResourceColor 的位置。
   */
  static brandTint(hex: string): string {
    const fallback = Theme.isDark() ? DARK_PALETTE.accent : LIGHT_PALETTE.accent;
    if (hex.length !== 7 || hex.charAt(0) !== '#') {
      return fallback;
    }
    const r = parseInt(hex.substring(1, 3), 16);
    const g = parseInt(hex.substring(3, 5), 16);
    const b = parseInt(hex.substring(5, 7), 16);
    if (!isFinite(r) || !isFinite(g) || !isFinite(b)) {
      return fallback;
    }
    const luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
    if (luminance > 0.85 || luminance < 0.08) {
      return fallback;
    }
    return hex;
  }
}
