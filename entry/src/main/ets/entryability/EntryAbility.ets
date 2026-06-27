import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { clearDecodeCache } from '../reader/ReaderImageDecoder';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private windowStage: window.WindowStage | null = null;
  private static readonly CONTENT_COLOR_DARK: string = '#111111';
  private static readonly CONTENT_COLOR_LIGHT: string = '#F2F3F5';

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      AppStorage.setOrCreate('currentColorMode', this.context.config.colorMode);
      AppStorage.setOrCreate('abilityContext', this.context);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    AppStorage.setOrCreate('currentColorMode', newConfig.colorMode);
    this.applySystemBar(newConfig.colorMode);
  }

  private isDark(mode: number): boolean {
    return mode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  private applySystemBar(colorMode: number | undefined): void {
    try {
      const resolved = colorMode ?? ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
      const contentColor = this.isDark(resolved)
        ? EntryAbility.CONTENT_COLOR_LIGHT
        : EntryAbility.CONTENT_COLOR_DARK;
      this.windowStage?.getMainWindowSync().setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        navigationBarColor: '#00000000',
        statusBarContentColor: contentColor,
        navigationBarContentColor: contentColor
      });
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'applySystemBar failed: %{public}s', JSON.stringify(err));
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');
    this.windowStage = windowStage;
    const mainWindow = windowStage.getMainWindowSync();
    mainWindow.setWindowLayoutFullScreen(true);
    this.applySystemBar(this.context.config.colorMode);

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

  onMemoryLevel(level: AbilityConstant.MemoryLevel): void {
    // 内存紧张时主动释放解码缓存，配合 LRU 杜绝 OOM
    if (level === AbilityConstant.MemoryLevel.MEMORY_LEVEL_CRITICAL
      || level === AbilityConstant.MemoryLevel.MEMORY_LEVEL_LOW) {
      clearDecodeCache();
      hilog.info(DOMAIN, 'testTag', 'onMemoryLevel cleared decode cache level=%{public}d', level);
    }
  }
}
