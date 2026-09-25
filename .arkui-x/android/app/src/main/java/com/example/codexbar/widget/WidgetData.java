package com.example.codexbar.widget;

import android.content.Context;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * 卡片摘要数据（字段与 ArkTS 侧 store/WidgetData.ets 一一对应）。
 *
 * 容错策略与卡片页保持一致：条目缺名称、数值越界或整体损坏时丢弃/回落空态，
 * 组件宁可不显示，也不抛异常（RemoteViews 渲染抛异常会直接显示「无法加载」）。
 */
final class WidgetData {
    /** 组件里最多展示的行数上限（安卓端布局比鸿蒙宽裕，留一点余量） */
    private static final int MAX_ITEMS = 8;

    static final class Item {
        final String name;
        final String pct;
        final int barPct;
        final String level;
        final String cd;
        /** hero 泳道名（绑定泳道比主泳道更紧时标注，如 "Weekly"）；主泳道为空串 */
        final String lane;

        Item(String name, String pct, int barPct, String level, String cd, String lane) {
            this.name = name;
            this.pct = pct;
            this.barPct = barPct;
            this.level = level;
            this.cd = cd;
            this.lane = lane == null ? "" : lane;
        }
    }

    final String updatedAt;
    final List<Item> items;

    private WidgetData(String updatedAt, List<Item> items) {
        this.updatedAt = updatedAt;
        this.items = items;
    }

    static WidgetData empty() {
        return new WidgetData("", Collections.<Item>emptyList());
    }

    /** 读取并解析摘要文件；文件缺失、损坏一律回落空态 */
    static WidgetData load(Context ctx) {
        File file = WidgetFiles.resolve(ctx);
        if (file == null) {
            return empty();
        }
        StringBuilder sb = new StringBuilder();
        try (BufferedReader reader = new BufferedReader(
                new InputStreamReader(new FileInputStream(file), StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) {
                sb.append(line);
            }
        } catch (Exception e) {
            Log.w(WidgetFiles.TAG, "read widget data failed", e);
            return empty();
        }
        return parse(sb.toString());
    }

    /** 纯解析：非法 JSON / 缺失字段按空态处理（可单独验证） */
    static WidgetData parse(String json) {
        if (json == null || json.isEmpty()) {
            return empty();
        }
        try {
            JSONObject root = new JSONObject(json);
            List<Item> items = new ArrayList<>();
            JSONArray arr = root.optJSONArray("items");
            if (arr != null) {
                for (int i = 0; i < arr.length() && items.size() < MAX_ITEMS; i++) {
                    JSONObject o = arr.optJSONObject(i);
                    if (o == null) {
                        continue;
                    }
                    String name = o.optString("name", "");
                    if (name.isEmpty()) {
                        continue;
                    }
                    double raw = o.optDouble("barPct", 0);
                    int bar = Double.isNaN(raw) ? 0 : (int) Math.round(raw);
                    items.add(new Item(
                            name,
                            o.optString("pct", ""),
                            Math.max(0, Math.min(100, bar)),
                            o.optString("level", "unknown"),
                            o.optString("cd", ""),
                            o.optString("lane", "")));
                }
            }
            return new WidgetData(root.optString("updatedAt", ""), items);
        } catch (Exception e) {
            Log.w(WidgetFiles.TAG, "parse widget data failed: " + e.getMessage());
            return empty();
        }
    }
}
