import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ApiResult } from './ApiResult';

const DOMAIN = 0x0000;
const TAG = 'JMCache';
const CACHE_CAPACITY = 64;

// 统一 TTL 常量（毫秒），避免散落魔法数字
export const TTL_SETTING = 6 * 60 * 60 * 1000;
export const TTL_HOME = 60 * 60 * 1000;
export const TTL_DETAIL = 30 * 60 * 1000;

interface CacheEntry {
  data: Object;
  expireAt: number;
}

export type Fetcher<T> = () => Promise<ApiResult<T>>;

// 缓存解密后的明文对象 + TTL + 并发去重。token 在 client 生命周期固定，故缓存明文最稳妥
export class CacheStore {
  private readonly cache: util.LRUCache<string, CacheEntry> = new util.LRUCache<string, CacheEntry>(CACHE_CAPACITY);
  private readonly inflight: Map<string, Promise<ApiResult<Object>>> = new Map<string, Promise<ApiResult<Object>>>();

  async getOrFetch<T>(key: string, ttlMs: number, fetcher: Fetcher<T>): Promise<ApiResult<T>> {
    const now = Date.now();
    const entry = this.cache.get(key);
    if (entry !== undefined && entry.expireAt > now) {
      hilog.info(DOMAIN, TAG, 'cache hit key=%{public}s', key);
      return { ok: true, code: 200, data: entry.data as T };
    }
    const pending = this.inflight.get(key);
    if (pending !== undefined) {
      hilog.info(DOMAIN, TAG, 'cache inflight join key=%{public}s', key);
      return await pending as ApiResult<T>;
    }
    return this.fetchAndStore(key, ttlMs, fetcher);
  }

  private async fetchAndStore<T>(key: string, ttlMs: number, fetcher: Fetcher<T>): Promise<ApiResult<T>> {
    const task: Promise<ApiResult<Object>> = fetcher().then((result: ApiResult<T>) => {
      if (result.ok && result.data !== undefined && result.data !== null) {
        this.cache.put(key, { data: result.data as Object, expireAt: Date.now() + ttlMs });
        hilog.info(DOMAIN, TAG, 'cache store key=%{public}s ttl=%{public}d', key, ttlMs);
      }
      return result as ApiResult<Object>;
    });
    this.inflight.set(key, task);
    try {
      return await task as ApiResult<T>;
    } finally {
      this.inflight.delete(key);
    }
  }

  invalidate(key: string): void {
    this.cache.remove(key);
    hilog.info(DOMAIN, TAG, 'cache invalidate key=%{public}s', key);
  }

  invalidateAll(): void {
    this.cache.clear();
    hilog.info(DOMAIN, TAG, 'cache invalidate all');
  }
}
