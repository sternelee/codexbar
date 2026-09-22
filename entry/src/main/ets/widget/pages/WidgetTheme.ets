/**
 * CodexBar Mobile — 服务卡片配色
 *
 * 卡片数据经 FormBindingData 序列化成 JSON，塞不进资源引用，
 * 所以应用侧只传用量「等级」（ok / warn / danger / unknown），
 * 由卡片页在这里映射到 `$r('app.color.bar_*')`，随系统深浅色自动换值。
 */

/** 用量等级 → 进度条/百分比颜色资源 */
export function widgetLevelColor(level: string): Resource {
  if (level === 'danger') {
    return $r('app.color.bar_danger');
  }
  if (level === 'warn') {
    return $r('app.color.bar_warn');
  }
  if (level === 'ok') {
    return $r('app.color.bar_ok');
  }
  return $r('app.color.bar_track');
}
