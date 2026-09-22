package com.example.codexbar.widget;

import android.content.Context;
import android.util.Log;

import java.io.File;
import java.io.FileFilter;
import java.util.ArrayList;
import java.util.List;

/**
 * 卡片摘要文件定位。
 *
 * ArkTS 侧（store/WidgetFile.ets）把摘要 JSON 写进自己的能力沙箱 files 目录，
 * 各平台落盘路径不同，实测：
 *  - Android（ArkUI-X）：沙箱虚拟路径会再叠一层，落在 &lt;dataDir&gt;/files/files/；
 *  - HarmonyOS：就是 files 目录（该文件对鸿蒙无用，仅作跨端统一）。
 * 因此这里按「已知候选 → 有界递归查找」逐级尝试，命中后缓存，避免每次渲染都遍历。
 */
final class WidgetFiles {
    static final String FILE_NAME = "widget_data.json";
    static final String TAG = "CodexBarWidget";

    /** 递归查找的最大深度（应用数据目录下的 files/、files/files/ 等足够覆盖） */
    private static final int MAX_DEPTH = 3;

    private static String cachedPath;

    private WidgetFiles() {
    }

    /** 返回摘要文件；尚未写过时返回 null（组件显示空态） */
    static File resolve(Context ctx) {
        if (cachedPath != null) {
            File cached = new File(cachedPath);
            if (cached.isFile()) {
                return cached;
            }
            cachedPath = null;
        }
        for (File dir : candidates(ctx)) {
            File hit = new File(dir, FILE_NAME);
            if (hit.isFile()) {
                return remember(hit);
            }
        }
        File found = search(ctx.getDataDir(), FILE_NAME, MAX_DEPTH);
        if (found != null) {
            return remember(found);
        }
        Log.i(TAG, "widget data file not found; checked " + candidates(ctx).size() + " dir(s) under "
                + ctx.getDataDir().getAbsolutePath());
        return null;
    }

    /** 需要监听的目录：ArkTS 换新版沙箱映射时也不会漏掉写事件 */
    static List<File> watchDirs(Context ctx) {
        List<File> dirs = new ArrayList<>();
        for (File dir : candidates(ctx)) {
            // ArkUI-X 的沙箱子目录（<filesDir>/files）在首次刷新前可能还不存在，
            // 而 FileObserver 只能监听已存在的目录：先建再听，否则第一次写入收不到事件。
            // 这是应用自己的私有目录，提前建空目录无副作用。
            if (!dir.isDirectory()) {
                dir.mkdirs();
            }
            addDir(dirs, dir);
        }
        File resolved = resolve(ctx);
        if (resolved != null) {
            addDir(dirs, resolved.getParentFile());
        }
        return dirs;
    }

    private static List<File> candidates(Context ctx) {
        List<File> dirs = new ArrayList<>();
        File files = ctx.getFilesDir();
        dirs.add(files);
        // ArkUI-X 安卓侧沙箱映射：虚拟 /data/storage/el2/base/files 落到 <filesDir>/files
        dirs.add(new File(files, "files"));
        return dirs;
    }

    private static void addDir(List<File> dirs, File dir) {
        if (dir == null || !dir.isDirectory()) {
            return;
        }
        for (File existing : dirs) {
            if (existing.getAbsolutePath().equals(dir.getAbsolutePath())) {
                return;
            }
        }
        dirs.add(dir);
    }

    private static File remember(File f) {
        cachedPath = f.getAbsolutePath();
        Log.i(TAG, "widget data file: " + cachedPath);
        return f;
    }

    private static File search(File dir, String name, int depth) {
        if (dir == null || depth < 0 || !dir.isDirectory()) {
            return null;
        }
        File[] hits = dir.listFiles(new FileFilter() {
            @Override
            public boolean accept(File pathname) {
                return pathname.isFile() && name.equals(pathname.getName());
            }
        });
        if (hits != null && hits.length > 0) {
            return hits[0];
        }
        File[] dirs = dir.listFiles(new FileFilter() {
            @Override
            public boolean accept(File pathname) {
                return pathname.isDirectory();
            }
        });
        if (dirs == null) {
            return null;
        }
        for (File sub : dirs) {
            File hit = search(sub, name, depth - 1);
            if (hit != null) {
                return hit;
            }
        }
        return null;
    }
}
