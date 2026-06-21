import { JmApiClientOptions } from './ApiConfig';
import { JmHttpClient } from './HttpClient';
import { ComicApi } from './services/ComicApi';
import { RemoteSettingApi } from './services/RemoteSettingApi';
import { UserApi } from './services/UserApi';

export { DEFAULT_API_LIST } from './ApiConfig';
export { ApiResult, ApiSuccess, ApiFailure } from './ApiResult';
export { CookieJar, StoredCookie } from './CookieJar';
export { JmHttpClient } from './HttpClient';
export * from './models/Responses';

export interface JmApiClient {
  http: JmHttpClient;
  comic: ComicApi;
  user: UserApi;
  remoteSetting: RemoteSettingApi;
}

export function createJmApiClient(options: JmApiClientOptions = {}): JmApiClient {
  const http = new JmHttpClient(options);
  return {
    http,
    comic: new ComicApi(http),
    user: new UserApi(http),
    remoteSetting: new RemoteSettingApi(http)
  };
}

