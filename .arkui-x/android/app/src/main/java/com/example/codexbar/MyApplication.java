package com.example.codexbar;

import android.util.Log;

import com.example.codexbar.widget.WidgetUpdater;

import ohos.stage.ability.adapter.StageApplication;

/**
 * Example ace application class, which will load ArkUI-X application instance.
 * StageApplication is provided by ArkUI-X
 * @see <a href=
 * "https://gitee.com/arkui-x/docs/blob/master/zh-cn/application-dev/tutorial/how-to-integrate-arkui-into-android.md">
 * to build android library</a>
 */
public class MyApplication extends StageApplication {
    private static final String LOG_TAG = "HiHelloWorld";

    private static final String RES_NAME = "res";

    @Override
    public void onCreate() {
        Log.e(LOG_TAG, "MyApplication");
        super.onCreate();
        Log.e(LOG_TAG, "MyApplication onCreate");
        // 应用进程一起来就接上桌面组件：
        // FileObserver 监听 ArkTS 侧写出的摘要文件，刷新成功即可即时更新卡片；
        // 首帧顺带重渲染一次，避免进程重启后卡片停在旧数据上。
        try {
            WidgetUpdater.updateAll(this);
        } catch (Throwable t) {
            Log.w(LOG_TAG, "widget bootstrap failed", t);
        }
    }
}
