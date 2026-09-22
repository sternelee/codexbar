package com.example.codexbar.widget;

import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.Context;
import android.content.Intent;

/**
 * 安卓桌面组件基类：任何生命周期回调都直接重渲染全部实例。
 *
 * 组件数据来自应用进程写出的摘要文件，provider 自身不持有状态，所以
 * 「添加 / 删除 / 尺寸变化 / 定时更新 / 点击」一律走同一套刷新逻辑即可。
 * 子类只用来区分尺寸对应的行数（见 {@link WidgetUpdater}）。
 */
public abstract class CodexBarWidgetProvider extends AppWidgetProvider {

    @Override
    public void onUpdate(Context context, AppWidgetManager appWidgetManager, int[] appWidgetIds) {
        WidgetUpdater.updateAll(context);
    }

    @Override
    public void onAppWidgetOptionsChanged(Context context, AppWidgetManager appWidgetManager,
                                          int appWidgetId, android.os.Bundle newOptions) {
        WidgetUpdater.updateAll(context);
    }

    @Override
    public void onEnabled(Context context) {
        WidgetUpdater.updateAll(context);
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        super.onReceive(context, intent);
        WidgetUpdater.updateAll(context);
    }
}
