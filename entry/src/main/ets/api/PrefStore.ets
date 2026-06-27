import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'JMPref';
const JM_PREF = 'jm_cache';

// preferences 持久化封装：依赖注入 context，失败显式打日志且按「无缓存」处理，不伪造数据
export class PrefStore {
  private readonly context: common.UIAbilityContext;
  private store: preferences.Preferences | null = null;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  private async ensureStore(): Promise<preferences.Preferences> {
    if (this.store !== null) {
      return this.store;
    }
    this.store = await preferences.getPreferences(this.context, JM_PREF);
    return this.store;
  }

  async getString(key: string, defaultValue: string): Promise<string> {
    try {
      const store = await this.ensureStore();
      return await store.get(key, defaultValue) as string;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      hilog.error(DOMAIN, TAG, 'getString failed key=%{public}s msg=%{public}s', key, message);
      return defaultValue;
    }
  }

  async putString(key: string, value: string): Promise<void> {
    try {
      const store = await this.ensureStore();
      await store.put(key, value);
      await store.flush();
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      hilog.error(DOMAIN, TAG, 'putString failed key=%{public}s msg=%{public}s', key, message);
    }
  }

  async getObject<T>(key: string): Promise<T | null> {
    const raw = await this.getString(key, '');
    if (raw.length === 0) {
      return null;
    }
    try {
      return JSON.parse(raw) as T;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      hilog.error(DOMAIN, TAG, 'getObject parse failed key=%{public}s msg=%{public}s', key, message);
      return null;
    }
  }

  async putObject<T>(key: string, value: T): Promise<void> {
    await this.putString(key, JSON.stringify(value));
  }
}
