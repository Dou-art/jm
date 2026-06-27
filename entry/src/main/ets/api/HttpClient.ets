import http from '@ohos.net.http';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { API_VERSION, DEFAULT_API_LIST, JmApiClientOptions, normalizeBaseUrl } from './ApiConfig';
import { ApiResult, failure, ResponseWrapper, success } from './ApiResult';
import { CookieJar } from './CookieJar';
import { aesEcbPkcs5DecryptBase64, createApiToken, nowApiTs } from './Crypto';

export type ParamValue = string | number | boolean | undefined | null;
export type QueryParams = Map<string, ParamValue>;
export type FormParts = Map<string, ParamValue>;
const DOMAIN = 0x0000;
const TAG = 'JMApi';

interface HeaderMap {
  tokenparam: string;
  token: string;
  Cookie?: string;
  'Content-Type'?: string;
}

interface RequestBody {
  contentType: string;
  data: string;
}

export class JmHttpClient {
  readonly cookieJar: CookieJar = new CookieJar();
  readonly apiTs: number;
  private tokenPromise: Promise<string>;
  private baseUrl: string;
  private timeoutMs: number;
  private cookiePersister: (() => void) | null = null;

  constructor(options?: JmApiClientOptions) {
    this.baseUrl = normalizeBaseUrl(options?.baseUrl ?? DEFAULT_API_LIST[0]);
    this.timeoutMs = options?.timeoutMs ?? 30000;
    this.apiTs = nowApiTs();
    this.tokenPromise = createApiToken(this.apiTs);
  }

  setCookiePersister(persister: () => void): void {
    this.cookiePersister = persister;
  }

  setBaseUrl(baseUrl: string): void {
    this.baseUrl = normalizeBaseUrl(baseUrl);
  }

  getBaseUrl(): string {
    return this.baseUrl;
  }

  async getJson<T>(path: string, query?: QueryParams): Promise<ApiResult<T>> {
    const raw = await this.requestText(path, http.RequestMethod.GET, query);
    if (!raw.ok) {
      return failure<T>(raw.message ?? 'request failed', raw.code, raw.cause);
    }
    return this.parseEncryptedResponse<T>(raw.data ?? '');
  }

  async getText(path: string, query?: QueryParams): Promise<ApiResult<string>> {
    return this.requestText(path, http.RequestMethod.GET, query);
  }

  async postMultipartJson<T>(path: string, parts: FormParts): Promise<ApiResult<T>> {
    const raw = await this.requestText(path, http.RequestMethod.POST, undefined, this.buildMultipartBody(parts));
    if (!raw.ok) {
      return failure<T>(raw.message ?? 'request failed', raw.code, raw.cause);
    }
    return this.parseEncryptedResponse<T>(raw.data ?? '');
  }

  async requestText(
    path: string,
    method: http.RequestMethod,
    query?: QueryParams,
    body?: RequestBody
  ): Promise<ApiResult<string>> {
    const token = await this.tokenPromise;
    const request = http.createHttp();
    const cookie = this.cookieJar.loadHeader();
    const headers: HeaderMap = this.buildHeaders(token, cookie, body);

    try {
      const url = this.buildUrl(path, query);
      hilog.info(DOMAIN, TAG, 'request %{public}s %{public}s', String(method), url);
      const options: http.HttpRequestOptions = {
        method,
        header: headers,
        extraData: body?.data,
        connectTimeout: this.timeoutMs,
        readTimeout: this.timeoutMs
      };
      const response = await request.request(url, options);
      if (response.cookies.length > 0) {
        this.cookieJar.saveFromSetCookie([response.cookies]);
        this.cookiePersister?.();
      }
      const code = Number(response.responseCode);
      const data = typeof response.result === 'string' ? response.result : JSON.stringify(response.result);
      hilog.info(DOMAIN, TAG, 'response %{public}d %{public}s bytes=%{public}d', code, path, data.length);
      if (code < 200 || code >= 300) {
        return failure<string>(`network error: ${code}`, code, data);
      }
      return success(data, code);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      hilog.error(DOMAIN, TAG, 'request failed %{public}s: %{public}s', path, message);
      return failure<string>(message);
    } finally {
      request.destroy();
    }
  }

  private async parseEncryptedResponse<T>(body: string): Promise<ApiResult<T>> {
    try {
      const json = JSON.parse(body) as ResponseWrapper<string>;
      if (json.code === 200 && json.data !== undefined && json.data !== null) {
        const token = await this.tokenPromise;
        const decrypted = await aesEcbPkcs5DecryptBase64(String(json.data), token);
        hilog.info(DOMAIN, TAG, 'decrypt ok bytes=%{public}d', decrypted.length);
        return success(JSON.parse(decrypted) as T, json.code);
      }
      hilog.error(DOMAIN, TAG, 'api error code=%{public}d msg=%{public}s', json.code, json.errorMsg ?? '');
      return failure<T>(json.errorMsg ?? 'api returned an error', json.code);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      hilog.error(DOMAIN, TAG, 'parse/decrypt failed: %{public}s body=%{public}s', message, body.substring(0, Math.min(180, body.length)));
      return failure<T>(message, -1, body);
    }
  }

  private buildUrl(path: string, query?: QueryParams): string {
    const cleanPath = path.startsWith('/') ? path.slice(1) : path;
    const search: string[] = [];
    if (query) {
      query.forEach((value: ParamValue, key: string) => {
        if (value !== undefined && value !== null) {
          search.push(`${encodeURIComponent(key)}=${encodeURIComponent(String(value))}`);
        }
      });
    }
    const suffix = search.length > 0 ? `?${search.join('&')}` : '';
    return `${this.baseUrl}/${cleanPath}${suffix}`;
  }

  private buildMultipartBody(parts: FormParts): RequestBody {
    const boundary = `----JmMobileHarmony${Date.now().toString(16)}`;
    const values: string[] = [];
    parts.forEach((value: ParamValue, key: string) => {
      if (value !== undefined && value !== null) {
        values.push(`--${boundary}\r\n`);
        values.push(`Content-Disposition: form-data; name="${key}"\r\n\r\n`);
        values.push(`${String(value)}\r\n`);
      }
    });
    values.push(`--${boundary}--\r\n`);
    return {
      contentType: `multipart/form-data; boundary=${boundary}`,
      data: values.join('')
    };
  }

  private buildHeaders(token: string, cookie: string, body?: RequestBody): HeaderMap {
    if (body !== undefined) {
      return {
        tokenparam: `${this.apiTs},${API_VERSION}`,
        token: token,
        Cookie: cookie,
        'Content-Type': body.contentType
      };
    }
    return {
      tokenparam: `${this.apiTs},${API_VERSION}`,
      token: token,
      Cookie: cookie
    };
  }
}
