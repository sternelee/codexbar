/**
 * CodexBar Mobile — 展示格式化工具
 * 对应 Swift 版的倒计时/百分比/金额格式化逻辑（精简迁移）。
 * 时间单位/相对时间随显示语言输出（I18n.L）；默认中文。
 */

import { L, currentLang } from './I18n';

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

  /** 剩余毫秒 → "3天4小时" / "2小时15分" / "45分钟" / "30秒"；超过 99 天按绝对时间显示 */
  static countdown(msUntil: number): string {
    if (msUntil <= 0) {
      return L('已重置', 'Reset');
    }
    const totalSec = Math.floor(msUntil / 1000);
    const days = Math.floor(totalSec / 86400);
    if (days > 99) {
      return L(`重置于 ${Format.dateTime(Date.now() + msUntil)}`, `Resets ${Format.dateTime(Date.now() + msUntil)}`);
    }
    const hours = Math.floor((totalSec % 86400) / 3600);
    const minutes = Math.floor((totalSec % 3600) / 60);
    const seconds = totalSec % 60;
    if (days > 0) {
      return hours > 0 ? L(`${days}天${hours}小时`, `${days}d ${hours}h`) : L(`${days}天`, `${days}d`);
    }
    if (hours > 0) {
      return minutes > 0 ? L(`${hours}小时${minutes}分`, `${hours}h ${minutes}m`) : L(`${hours}小时`, `${hours}h`);
    }
    if (minutes > 0) {
      return L(`${minutes}分钟`, `${minutes}m`);
    }
    return L(`${seconds}秒`, `${seconds}s`);
  }

  /** 重置时间统一文案：已重置 / X后重置 / 重置于 日期（超 99 天封顶） */
  static resetIn(msUntil: number): string {
    if (msUntil <= 0) {
      return L('已重置', 'Reset');
    }
    const cd = Format.countdown(msUntil);
    if (cd === L('已重置', 'Reset') || cd.startsWith(L('重置于', 'Resets'))) {
      return cd;
    }
    return L(`${cd}后重置`, `Resets in ${cd}`);
  }

  /** Unix 毫秒 → "HH:mm" */
  static clock(ms: number): string {
    const d = new Date(ms);
    const h = d.getHours().toString().padStart(2, '0');
    const m = d.getMinutes().toString().padStart(2, '0');
    return `${h}:${m}`;
  }

  /** Unix 毫秒 → "M月d日 HH:mm" / "MMM d HH:mm" */
  static dateTime(ms: number): string {
    const d = new Date(ms);
    if (currentLang() === 'en') {
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return `${months[d.getMonth()]} ${d.getDate()} ${Format.clock(ms)}`;
    }
    return `${d.getMonth() + 1}月${d.getDate()}日 ${Format.clock(ms)}`;
  }

  /** 相对时间："刚刚" / "5分钟前" / "2小时前" */
  static ago(ms: number): string {
    if (ms <= 0) {
      return L('从未', 'Never');
    }
    const diff = Date.now() - ms;
    if (diff < 60 * 1000) {
      return L('刚刚', 'just now');
    }
    if (diff < 3600 * 1000) {
      return L(`${Math.floor(diff / 60000)}分钟前`, `${Math.floor(diff / 60000)}m ago`);
    }
    if (diff < 86400 * 1000) {
      return L(`${Math.floor(diff / 3600000)}小时前`, `${Math.floor(diff / 3600000)}h ago`);
    }
    return Format.dateTime(ms);
  }

  /**
   * 额度数字：千分位 + 最多两位小数、去掉尾随 0（对照 UsageFormatter.creditsNumberString）：
   * 1234.5 → "1,234.5"；0 → "0"；1000000 → "1,000,000"
   */
  static creditsNumber(value: number): string {
    if (!isFinite(value)) {
      return '0';
    }
    const rounded = Math.round(value * 100) / 100;
    const negative = rounded < 0;
    const fixed = Math.abs(rounded).toFixed(2);
    const intPart = fixed.substring(0, fixed.length - 3);
    const frac = fixed.substring(fixed.length - 2).replace(/0+$/, '');
    let grouped = '';
    for (let i = 0; i < intPart.length; i++) {
      grouped += intPart.charAt(i);
      const remaining = intPart.length - i - 1;
      if (remaining > 0 && remaining % 3 === 0) {
        grouped += ',';
      }
    }
    const text = frac.length > 0 ? `${grouped}.${frac}` : grouped;
    return negative ? `-${text}` : text;
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
