import { JmApiClientOptions } from './ApiConfig';
import { JmHttpClient } from './HttpClient';
import { CacheStore } from './CacheStore';
import { ComicApi } from './services/ComicApi';
import { RemoteSettingApi } from './services/RemoteSettingApi';
import { UserApi } from './services/UserApi';

export { DEFAULT_API_LIST } from './ApiConfig';
export { ApiResult, ApiSuccess, ApiFailure } from './ApiResult';
export { CookieJar, StoredCookie } from './CookieJar';
export { JmHttpClient } from './HttpClient';
export { CacheStore } from './CacheStore';
export { PrefStore } from './PrefStore';
export * from './models/Responses';

export interface JmApiClient {
  http: JmHttpClient;
  cache: CacheStore;
  comic: ComicApi;
  user: UserApi;
  remoteSetting: RemoteSettingApi;
}

export function createJmApiClient(options: JmApiClientOptions = {}): JmApiClient {
  const http = new JmHttpClient(options);
  const cache = new CacheStore();
  return {
    http,
    cache,
    comic: new ComicApi(http, cache),
    user: new UserApi(http),
    remoteSetting: new RemoteSettingApi(http, cache)
  };
}

