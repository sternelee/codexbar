package com.example.codexbar.widget;

import android.appwidget.AppWidgetManager;
import android.content.ComponentName;
import android.content.Context;
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
 */
public final class WidgetUpdater {
    /** 各组件提供方对应的最大行数（2x2 速览 2 行、2x4 列表 4 行） */
    private static final int ROWS_QUICK = 2;
    private static final int ROWS_LIST = 4;

    private static final List<FileObserver> observers = new ArrayList<>();
    /** watcher → 监听目录路径（用于幂等判断） */
    private static final Map<FileObserver, String> watchedPaths = new HashMap<>();

    private WidgetUpdater() {
    }

    /** 刷新全部已添加的组件实例，并确保摘要文件监听已启动 */
    public static void updateAll(Context ctx) {
        Context app = ctx.getApplicationContext();
        AppWidgetManager manager = AppWidgetManager.getInstance(app);
        update(manager, app, WidgetQuickProvider.class, ROWS_QUICK);
        update(manager, app, WidgetListProvider.class, ROWS_LIST);
        ensureObserver(app);
    }

    private static void update(AppWidgetManager manager, Context ctx, Class<?> provider, int maxRows) {
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
        try {
            RemoteViews views = WidgetRenderer.build(ctx, maxRows);
            for (int id : ids) {
                manager.updateAppWidget(id, views);
            }
            Log.i(WidgetFiles.TAG, "updated " + ids.length + " x " + provider.getSimpleName());
        } catch (Exception e) {
            Log.w(WidgetFiles.TAG, "update widget failed: " + provider.getSimpleName(), e);
        }
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
