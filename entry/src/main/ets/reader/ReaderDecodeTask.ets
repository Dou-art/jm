import http from '@ohos.net.http';
import { image } from '@kit.ImageKit';

// worker 线程产出的原始解扰像素，buffer 可跨线程转移；主线程据此 createPixelMap
export interface DecodeRawResult {
  buffer: ArrayBuffer;
  width: number;
  height: number;
}

// @Concurrent 函数必须顶层、自包含，不能引用闭包或同文件其他函数，故下载与像素重组全部内联
@Concurrent
async function decodeRawInWorker(url: string, seed: number): Promise<DecodeRawResult> {
  const TIMEOUT_MS = 30000;
  const request = http.createHttp();
  let buffer: ArrayBuffer;
  try {
    const response = await request.request(url, {
      method: http.RequestMethod.GET,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      connectTimeout: TIMEOUT_MS,
      readTimeout: TIMEOUT_MS,
      header: {
        'User-Agent': 'Mozilla/5.0 HarmonyOS JMReader',
        'Referer': url
      }
    });
    const code = Number(response.responseCode);
    if (code < 200 || code >= 300) {
      throw new Error(`image network error: ${code}`);
    }
    if (!(response.result instanceof ArrayBuffer)) {
      throw new Error('image response is not ArrayBuffer');
    }
    buffer = response.result;
  } finally {
    request.destroy();
  }

  const source = image.createImageSource(buffer);
  try {
    const original = await source.createPixelMap({
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
      editable: true
    });
    const info = await original.getImageInfo();
    const width = info.size.width;
    const height = info.size.height;
    const sourceBuffer = new ArrayBuffer(width * height * 4);
    await original.readPixelsToBuffer(sourceBuffer);
    await original.release();

    if (seed <= 1) {
      const bytes = new Uint8Array(sourceBuffer);
      for (let index = 0; index < bytes.length; index += 4) {
        const red = bytes[index];
        bytes[index] = bytes[index + 2];
        bytes[index + 2] = red;
      }
      return { buffer: sourceBuffer, width, height };
    }

    const sourceBytes = new Uint8Array(sourceBuffer);
    const targetBuffer = new ArrayBuffer(width * height * 4);
    const targetBytes = new Uint8Array(targetBuffer);
    const stride = width * 4;
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
      for (let row = 0; row < sliceHeight; row++) {
        const sourceOffset = (sourceY + row) * stride;
        const targetOffset = (targetY + row) * stride;
        targetBytes.set(sourceBytes.subarray(sourceOffset, sourceOffset + stride), targetOffset);
      }
    }
    for (let index = 0; index < targetBytes.length; index += 4) {
      const red = targetBytes[index];
      targetBytes[index] = targetBytes[index + 2];
      targetBytes[index + 2] = red;
    }
    return { buffer: targetBuffer, width, height };
  } finally {
    await source.release();
  }
}

export { decodeRawInWorker };
