/**
 * CodexBar Mobile — 跨端桌面组件数据桥
 *
 * 鸿蒙侧用 Form Kit（FormBindingData / formProvider）直接把数据推给卡片；
 * 但 Android/iOS 上的桌面组件是**各平台原生的**（安卓为 AppWidget/RemoteViews），
 * 读不到 FormBindingData。所以这里额外把同一份摘要 JSON 落成应用私有目录下的
 * 文件，由原生组件进程自行读取。
 *
 * 本文件静态依赖 @ohos.file.fs，因此只允许被**动态 import** 调用：
 * 万一某平台没有文件能力，AppStore 里的 catch 会兜住，不影响刷新主流程。
 * 文件名与安卓侧 `widget/WidgetFiles.java` 的常量一一对应。
 */

import fs from '@ohos.file.fs';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'WidgetFile';

/** 卡片摘要文件名（安卓侧读取同名文件） */
export const WIDGET_FILE_NAME = 'widget_data.json';

/**
 * 把摘要 JSON 写入 dir/widget_data.json；返回写入的绝对路径。
 * 失败时抛异常（并留一条日志），由调用方兜底——落盘只是跨端组件的可选通路。
 */
export function writeWidgetJson(dir: string, json: string): string {
  const path = `${dir}/${WIDGET_FILE_NAME}`;
  try {
    const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, json);
    } finally {
      fs.closeSync(file);
    }
    // 实测各端沙箱前缀不同（如 ArkUI-X 安卓会多一层 files/），
    // 打印真实路径便于原生组件侧核对与排查
    hilog.info(DOMAIN, TAG, 'widget json written: %{public}s', path);
    return path;
  } catch (e) {
    const msg = e instanceof Error ? e.message : JSON.stringify(e);
    hilog.warn(DOMAIN, TAG, 'write widget json failed: %{public}s', msg);
    // ArkTS 只允许 throw Error 类型（arkts-limited-throw）
    throw new Error(msg);
  }
}
