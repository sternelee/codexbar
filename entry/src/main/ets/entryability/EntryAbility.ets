import { AbilityConstant, Configuration, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { resourceManager } from '@kit.LocalizationKit';
import { Settings } from '../store/Settings';
import { Notify } from '../common/Notify';
import { Theme } from '../common/Theme';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    Settings.init(this.context);
    Notify.init(this.context);
    this.applyColorMode();
  }

  /** 系统深浅色切换时刷新一下 AppStorage 里的标记（界面配色本身由资源自动换） */
  onConfigurationUpdate(newConfig: Configuration): void {
    this.applyColorMode();
  }

  /**
   * 把系统色彩模式写进 AppStorage，供 Canvas 2D 这类无法使用资源引用的场景取用。
   * 读取失败时按暗色，保持原有观感。
   */
  private applyColorMode(): void {
    try {
      const config: resourceManager.Configuration = this.context.resourceManager.getConfigurationSync();
      Theme.setDark(config.colorMode !== resourceManager.ColorMode.LIGHT);
    } catch (e) {
      hilog.warn(DOMAIN, 'testTag', 'read color mode failed');
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
