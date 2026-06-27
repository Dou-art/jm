import { ApiResult } from '../ApiResult';
import { JmHttpClient } from '../HttpClient';
import { CacheStore, TTL_SETTING } from '../CacheStore';
import { RemoteSettingResponse } from '../models/Responses';

export class RemoteSettingApi {
  private readonly http: JmHttpClient;
  private readonly cache: CacheStore;

  constructor(http: JmHttpClient, cache: CacheStore) {
    this.http = http;
    this.cache = cache;
  }

  getRemoteSetting(): Promise<ApiResult<RemoteSettingResponse>> {
    return this.cache.getOrFetch<RemoteSettingResponse>('setting', TTL_SETTING, () => {
      return this.http.getJson<RemoteSettingResponse>('setting');
    });
  }
}
