/**
 * CodexBar Mobile — 展示格式化工具
 * 对应 Swift 版的倒计时/百分比/金额格式化逻辑（精简迁移）。
 */

export class Format {
  /** 百分比：85.0 → "85%"；85.4 → "85.4%" */
  static percent(p: number): string {
    const rounded = Math.round(p * 10) / 10;
    if (rounded === Math.floor(rounded)) {
      return `${Math.floor(rounded)}%`;
    }
    return `${rounded.toFixed(1)}%`;
  }

  /** 金额：12.5 + "USD" → "$12.50"；CNY → "¥12.50" */
  static money(amount: number, currency: string): string {
    const symbol = currency === 'CNY' ? '¥' : currency === 'EUR' ? '€' : currency === 'GBP' ? '£' : '$';
    return `${symbol}${amount.toFixed(2)}`;
  }

  /** 剩余毫秒 → "3天4小时" / "2小时15分" / "45分钟" / "30秒" */
  static countdown(msUntil: number): string {
    if (msUntil <= 0) {
      return '已重置';
    }
    const totalSec = Math.floor(msUntil / 1000);
    const days = Math.floor(totalSec / 86400);
    const hours = Math.floor((totalSec % 86400) / 3600);
    const minutes = Math.floor((totalSec % 3600) / 60);
    const seconds = totalSec % 60;
    if (days > 0) {
      return hours > 0 ? `${days}天${hours}小时` : `${days}天`;
    }
    if (hours > 0) {
      return minutes > 0 ? `${hours}小时${minutes}分` : `${hours}小时`;
    }
    if (minutes > 0) {
      return `${minutes}分钟`;
    }
    return `${seconds}秒`;
  }

  /** Unix 毫秒 → "HH:mm" */
  static clock(ms: number): string {
    const d = new Date(ms);
    const h = d.getHours().toString().padStart(2, '0');
    const m = d.getMinutes().toString().padStart(2, '0');
    return `${h}:${m}`;
  }

  /** Unix 毫秒 → "M月d日 HH:mm" */
  static dateTime(ms: number): string {
    const d = new Date(ms);
    return `${d.getMonth() + 1}月${d.getDate()}日 ${Format.clock(ms)}`;
  }

  /** 相对时间："刚刚" / "5分钟前" / "2小时前" */
  static ago(ms: number): string {
    if (ms <= 0) {
      return '从未';
    }
    const diff = Date.now() - ms;
    if (diff < 60 * 1000) {
      return '刚刚';
    }
    if (diff < 3600 * 1000) {
      return `${Math.floor(diff / 60000)}分钟前`;
    }
    if (diff < 86400 * 1000) {
      return `${Math.floor(diff / 3600000)}小时前`;
    }
    return Format.dateTime(ms);
  }

  /** 大数缩写：1234 → "1.2K"，1234567 → "1.23M" */
  static compact(n: number): string {
    if (n >= 1_000_000_000) {
      return `${(n / 1_000_000_000).toFixed(2)}B`;
    }
    if (n >= 1_000_000) {
      return `${(n / 1_000_000).toFixed(2)}M`;
    }
    if (n >= 1000) {
      return `${(n / 1000).toFixed(1)}K`;
    }
    return `${n}`;
  }
}
