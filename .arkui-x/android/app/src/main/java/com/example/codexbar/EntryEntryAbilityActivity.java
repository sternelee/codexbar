package com.example.codexbar;

import android.os.Bundle;
import android.util.Log;

import ohos.stage.ability.adapter.StageActivity;


/**
 * Example ace activity class, which will load ArkUI-X ability instance.
 * StageActivity is provided by ArkUI-X
 * @see <a href=
 * "https://gitee.com/arkui-x/docs/blob/master/zh-cn/application-dev/tutorial/how-to-integrate-arkui-into-android.md">
 * to build android library</a>
 */
public class EntryEntryAbilityActivity extends StageActivity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        Log.e("HiHelloWorld", "EntryEntryAbilityActivity");
        
        // 实例名格式：<HarmonyOS bundleName>:<moduleName>:<abilityName>:<instanceName>
        // 必须与 AppScope/app.json5 的 bundleName 一致，否则 ArkTS 找不到
        // `@bundle:<bundleName>/entry/ets/...` 的模块记录，启动后只显示白屏。
        setInstanceName("com.sternelee.codexbar:entry:EntryAbility:");
        super.onCreate(savedInstanceState);
    }
}
