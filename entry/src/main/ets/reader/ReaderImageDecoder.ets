import http from '@ohos.net.http';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'JMApp';

export interface DecodedReaderImage {
  pixelMap: image.PixelMap;
  width: number;
  height: number;
}

interface DecodeCacheItem {
  promise: Promise<DecodedReaderImage>;
}

const decodeCache: Map<string, DecodeCacheItem> = new Map<string, DecodeCacheItem>();

async function downloadImage(url: string): Promise<ArrayBuffer> {
  const request = http.createHttp();
  try {
    const response = await request.request(url, {
      method: http.RequestMethod.GET,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      connectTimeout: 30000,
      readTimeout: 30000,
      header: {
        'User-Agent': 'Mozilla/5.0 HarmonyOS JMReader',
        'Referer': url
      }
    });
    const code = Number(response.responseCode);
    if (code < 200 || code >= 300) {
      throw new Error(`image network error: ${code}`);
    }
    if (response.result instanceof ArrayBuffer) {
      return response.result;
    }
    throw new Error('image response is not ArrayBuffer');
  } finally {
    request.destroy();
  }
}

function copyRows(
  source: Uint8Array,
  target: Uint8Array,
  width: number,
  sourceY: number,
  targetY: number,
  height: number
): void {
  const stride = width * 4;
  for (let row = 0; row < height; row++) {
    const sourceOffset = (sourceY + row) * stride;
    const targetOffset = (targetY + row) * stride;
    target.set(source.subarray(sourceOffset, sourceOffset + stride), targetOffset);
  }
}

function swapRedBlue(bytes: Uint8Array): void {
  for (let index = 0; index < bytes.length; index += 4) {
    const red = bytes[index];
    bytes[index] = bytes[index + 2];
    bytes[index + 2] = red;
  }
}

async function decodeImage(url: string, seed: number): Promise<DecodedReaderImage> {
  const buffer = await downloadImage(url);
  const source = image.createImageSource(buffer);
  let original: image.PixelMap | null = null;
  try {
    original = await source.createPixelMap({
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
      editable: true
    });
    const info = await original.getImageInfo();
    const width = info.size.width;
    const height = info.size.height;
    const sourceBuffer = new ArrayBuffer(width * height * 4);
    await original.readPixelsToBuffer(sourceBuffer);

    if (seed <= 1) {
      return {
        pixelMap: original,
        width,
        height
      };
    }

    const sourceBytes = new Uint8Array(sourceBuffer);
    const targetBuffer = new ArrayBuffer(width * height * 4);
    const targetBytes = new Uint8Array(targetBuffer);
    const baseHeight = Math.floor(height / seed);
    const remainder = height % seed;

    for (let index = 0; index < seed; index++) {
      let sliceHeight = baseHeight;
      let targetY = baseHeight * index;
      const sourceY = height - baseHeight * (index + 1) - remainder;
      if (index === 0) {
        sliceHeight += remainder;
      } else {
        targetY += remainder;
      }
      copyRows(sourceBytes, targetBytes, width, sourceY, targetY, sliceHeight);
    }
    swapRedBlue(targetBytes);

    const decoded = await image.createPixelMap(targetBuffer, {
      size: {
        width,
        height
      },
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      editable: false
    });
    await original.release();
    original = null;
    return {
      pixelMap: decoded,
      width,
      height
    };
  } finally {
    await source.release();
  }
}

export function getDecodedReaderImage(url: string, seed: number): Promise<DecodedReaderImage> {
  const key = `${seed}:${url}`;
  const cached = decodeCache.get(key);
  if (cached !== undefined) {
    return cached.promise;
  }
  const promise = decodeImage(url, seed).catch((error: Error) => {
    decodeCache.delete(key);
    hilog.error(DOMAIN, TAG, 'decode reader image failed %{public}s', error.message);
    throw error;
  });
  decodeCache.set(key, { promise });
  return promise;
}
