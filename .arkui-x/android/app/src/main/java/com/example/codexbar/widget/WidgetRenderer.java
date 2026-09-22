package com.example.codexbar.widget;

import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.view.View;
import android.widget.RemoteViews;

import com.example.codexbar.R;

/**
 * 把摘要数据渲染成 RemoteViews。
 *
 * 布局与鸿蒙卡片保持同一套信息层级：标题 + 更新时间、逐行「服务商 / 用量条 / 百分比 /
 * 重置倒计时」；用量条随等级换色（百分比文字同步换色），空数据时显示「打开应用刷新数据」。
 *
 * 说明：RemoteViews 不支持运行时改视图尺寸，所以用量条走 {@link android.widget.ProgressBar}
 * （max=100 + progressDrawable），靠 progress 表达占比。
 */
final class WidgetRenderer {

    private WidgetRenderer() {
    }

    static RemoteViews build(Context ctx, int maxRows) {
        WidgetData data = WidgetData.load(ctx);
        RemoteViews views = new RemoteViews(ctx.getPackageName(), R.layout.widget_codexbar);
        views.setTextViewText(R.id.widget_updated, data.updatedAt);
        views.removeAllViews(R.id.widget_rows);

        if (data.items.isEmpty()) {
            views.setViewVisibility(R.id.widget_empty, View.VISIBLE);
        } else {
            views.setViewVisibility(R.id.widget_empty, View.GONE);
            int count = Math.min(data.items.size(), maxRows);
            for (int i = 0; i < count; i++) {
                views.addView(R.id.widget_rows, rowViews(ctx, data.items.get(i)));
            }
        }

        PendingIntent launch = launchIntent(ctx);
        if (launch != null) {
            views.setOnClickPendingIntent(R.id.widget_root, launch);
        }
        return views;
    }

    private static RemoteViews rowViews(Context ctx, WidgetData.Item item) {
        RemoteViews row = new RemoteViews(ctx.getPackageName(), R.layout.widget_row);
        row.setTextViewText(R.id.row_name, item.name);
        row.setTextViewText(R.id.row_pct, item.pct);
        row.setTextColor(R.id.row_pct, levelColor(ctx, item.level));
        row.setProgressBar(R.id.row_bar, 100, item.barPct, false);
        if (item.cd.isEmpty()) {
            row.setViewVisibility(R.id.row_cd, View.GONE);
        } else {
            row.setViewVisibility(R.id.row_cd, View.VISIBLE);
            row.setTextViewText(R.id.row_cd, item.cd);
        }
        return row;
    }

    /** 用量等级 → 颜色（与主题里的 bar_* 同一套语义） */
    private static int levelColor(Context ctx, String level) {
        int res;
        if ("danger".equals(level)) {
            res = R.color.widget_danger;
        } else if ("warn".equals(level)) {
            res = R.color.widget_warn;
        } else if ("ok".equals(level)) {
            res = R.color.widget_ok;
        } else {
            res = R.color.widget_dim;
        }
        return ctx.getColor(res);
    }

    /** 点击卡片回到应用主界面（拿不到启动 Intent 时不设点击，避免误触发） */
    private static PendingIntent launchIntent(Context ctx) {
        Intent intent = ctx.getPackageManager().getLaunchIntentForPackage(ctx.getPackageName());
        if (intent == null) {
            return null;
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        return PendingIntent.getActivity(ctx, 0, intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }
}
