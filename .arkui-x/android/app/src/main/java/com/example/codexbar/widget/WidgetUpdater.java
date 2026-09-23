package com.example.codexbar.widget;

import android.appwidget.AppWidgetManager;
import android.content.ComponentName;
import android.content.Context;
import android.os.Bundle;
import android.os.FileObserver;
import android.util.Log;
import android.widget.RemoteViews;

import java.io.File;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * 卡片刷新编排：更新全部已添加的组件实例，并监听摘要文件变化做到「应用刷新完，卡片跟着变」。
 *
 * 数据链路：ArkTS 刷新成功 → 写沙箱 widget_data.json →
 * 本进程内的 FileObserver 收到写事件 → 重渲染全部组件实例。
 * 应用进程不在时由系统的定时更新兜底（updatePeriodMillis = 30 分钟）。
 *
 * 行数：每个实例按自己的实际高度算能放下几行（组件可自由拉伸），算不出来时
 * 退回该类型的默认行数（2x2 速览 2 行、2x4 列表 4 行）。
 */
public final class WidgetUpdater {
    /** 拿不到实例尺寸时的默认行数（与组件初始尺寸对应） */
    private static final int DEFAULT_ROWS_QUICK = 2;
    private static final int DEFAULT_ROWS_LIST = 4;

    /**
     * 高度换算用到的两个尺度（dp）：标题栏 + 上下内边距，以及单行
     * 「服务商名 / 用量条 / 重置倒计时」的占位。RemoteViews 改不了间距，
     * 只能按布局里的固定值估出来，宁可少放一行也不让它被裁掉。
     */
    private static final int HEADER_DP = 48;
    private static final int ROW_DP = 36;
    /** 行数上限，与 ArkTS 侧的数据行上限（WidgetData.ets 的 MAX_ITEMS）保持一致 */
    private static final int MAX_ROWS = 8;

    private static final List<FileObserver> observers = new ArrayList<>();
    /** watcher → 监听目录路径（用于幂等判断） */
    private static final Map<FileObserver, String> watchedPaths = new HashMap<>();

    private WidgetUpdater() {
    }

    /** 刷新全部已添加的组件实例，并确保摘要文件监听已启动 */
    public static void updateAll(Context ctx) {
        Context app = ctx.getApplicationContext();
        AppWidgetManager manager = AppWidgetManager.getInstance(app);
        update(manager, app, WidgetQuickProvider.class, DEFAULT_ROWS_QUICK);
        update(manager, app, WidgetListProvider.class, DEFAULT_ROWS_LIST);
        ensureObserver(app);
    }

    private static void update(AppWidgetManager manager, Context ctx, Class<?> provider, int defaultRows) {
        ComponentName name = new ComponentName(ctx, provider);
        int[] ids;
        try {
            ids = manager.getAppWidgetIds(name);
        } catch (Exception e) {
            Log.w(WidgetFiles.TAG, "query widget ids failed: " + provider.getSimpleName(), e);
            return;
        }
        if (ids == null || ids.length == 0) {
            return;
        }
        // 摘要文件每个实例都一样，只读一次；行数不同的实例各自出 RemoteViews
        WidgetData data = WidgetData.load(ctx);
        try {
            for (int id : ids) {
                int rows = rowsFor(manager, id, defaultRows);
                manager.updateAppWidget(id, WidgetRenderer.build(ctx, data, rows));
            }
            Log.i(WidgetFiles.TAG, "updated " + ids.length + " x " + provider.getSimpleName());
        } catch (Exception e) {
            Log.w(WidgetFiles.TAG, "update widget failed: " + provider.getSimpleName(), e);
        }
    }

    /**
     * 实例高度（dp）→ 可放下的行数。
     * 不低于该类型的默认行数（高度信息缺失或过小时保持原观感），有空间才往上加，最多 {@link #MAX_ROWS} 行。
     */
    private static int rowsFor(AppWidgetManager manager, int id, int defaultRows) {
        int minHeight = 0;
        try {
            Bundle options = manager.getAppWidgetOptions(id);
            if (options != null) {
                minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0);
            }
        } catch (Exception e) {
            Log.w(WidgetFiles.TAG, "read widget options failed: " + id, e);
        }
        if (minHeight <= 0) {
            return defaultRows;
        }
        int bySize = (minHeight - HEADER_DP) / ROW_DP;
        return Math.max(defaultRows, Math.min(MAX_ROWS, bySize));
    }

    /**
     * 幂等：为全部候选目录（ArkUI-X 安卓沙箱会多叠一层 files/）装上监听，
     * 已装过的目录跳过——后续 updateAll 时若又出现新目录（如首次刷新后才创建的沙箱子目录）
     * 会被补上。某个目录装不上就略过，最差情况退回系统定时更新。
     */
    static synchronized void ensureObserver(Context ctx) {
        final Context app = ctx.getApplicationContext();
        for (File dir : WidgetFiles.watchDirs(app)) {
            if (isWatched(dir)) {
                continue;
            }
            try {
                FileObserver watcher = new FileObserver(dir.getAbsolutePath(),
                        FileObserver.CLOSE_WRITE | FileObserver.CREATE | FileObserver.MOVED_TO) {
                    @Override
                    public void onEvent(int event, String path) {
                        if (path != null && path.endsWith(WidgetFiles.FILE_NAME)) {
                            Log.i(WidgetFiles.TAG, "widget data changed, refreshing widgets");
                            updateAll(app);
                        }
                    }
                };
                watcher.startWatching();
                observers.add(watcher);
                watchedPaths.put(watcher, dir.getAbsolutePath());
                Log.i(WidgetFiles.TAG, "watching " + dir.getAbsolutePath());
            } catch (Exception e) {
                Log.w(WidgetFiles.TAG, "start file observer failed: " + dir.getAbsolutePath(), e);
            }
        }
    }

    private static boolean isWatched(File dir) {
        final String path = dir.getAbsolutePath();
        for (FileObserver watcher : observers) {
            if (path.equals(watchedPaths.get(watcher))) {
                return true;
            }
        }
        return false;
    }
}
