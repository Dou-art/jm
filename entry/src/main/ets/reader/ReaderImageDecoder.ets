import { image } from '@kit.ImageKit';
import { taskpool, util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { decodeRawInWorker, DecodeRawResult } from './ReaderDecodeTask';

const DOMAIN = 0x0000;
const TAG = 'JMApp';
const DECODE_CACHE_CAPACITY = 16;

export interface DecodedReaderImage {
  pixelMap: image.PixelMap;
  width: number;
  height: number;
}

// LRU 缓存解码结果，淘汰时释放 PixelMap 占用的内存，杜绝无界 Map 泄漏
class DecodeLruCache extends util.LRUCache<string, DecodedReaderImage> {
  constructor(capacity: number) {
    super(capacity);
  }

  afterRemoval(
    isEvict: boolean,
    key: string,
    value: DecodedReaderImage,
    newValue: DecodedReaderImage
  ): void {
    // 仅在容量淘汰（非 put 覆盖同 key）时释放，避免释放仍在用的新值
    if (isEvict && newValue === undefined) {
      value.pixelMap.release();
      hilog.info(DOMAIN, TAG, 'decode cache evict release key=%{public}s', key);
    }
  }
}

const decodeCache: DecodeLruCache = new DecodeLruCache(DECODE_CACHE_CAPACITY);
const inflight: Map<string, Promise<DecodedReaderImage>> = new Map<string, Promise<DecodedReaderImage>>();

export function clearDecodeCache(): void {
  const keys = decodeCache.keys();
  for (let index = 0; index < keys.length; index++) {
    const item = decodeCache.get(keys[index]);
    if (item !== undefined) {
      item.pixelMap.release();
    }
  }
  decodeCache.clear();
  hilog.info(DOMAIN, TAG, 'decode cache cleared count=%{public}d', keys.length);
}

async function decodeImage(url: string, seed: number): Promise<DecodedReaderImage> {
  // 下载 + 像素重组解扰在 TaskPool 子线程完成，返回可转移的 ArrayBuffer，主线程仅 createPixelMap，避免卡帧
  hilog.info(DOMAIN, TAG, 'decode dispatch taskpool seed=%{public}d', seed);
  const raw = await taskpool.execute(decodeRawInWorker, url, seed) as DecodeRawResult;
  hilog.info(DOMAIN, TAG, 'decode worker done %{public}dx%{public}d', raw.width, raw.height);
  const pixelMap = await image.createPixelMap(raw.buffer, {
    size: {
      width: raw.width,
      height: raw.height
    },
    pixelFormat: image.PixelMapFormat.RGBA_8888,
    editable: false
  });
  return {
    pixelMap,
    width: raw.width,
    height: raw.height
  };
}

export function getDecodedReaderImage(url: string, seed: number): Promise<DecodedReaderImage> {
  const key = `${seed}:${url}`;
  const cached = decodeCache.get(key);
  if (cached !== undefined) {
    return Promise.resolve(cached);
  }
  const pending = inflight.get(key);
  if (pending !== undefined) {
    return pending;
  }
  const promise = decodeImage(url, seed).then((result: DecodedReaderImage) => {
    decodeCache.put(key, result);
    inflight.delete(key);
    return result;
  }).catch((error: Error) => {
    inflight.delete(key);
    hilog.error(DOMAIN, TAG, 'decode reader image failed %{public}s', error.message);
    throw error as Error;
  });
  inflight.set(key, promise);
  return promise;
}
