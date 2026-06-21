import { ApiResult } from '../ApiResult';
import { JmHttpClient } from '../HttpClient';
import { RemoteSettingResponse } from '../models/Responses';

export class RemoteSettingApi {
  private readonly http: JmHttpClient;

  constructor(http: JmHttpClient) {
    this.http = http;
  }

  getRemoteSetting(): Promise<ApiResult<RemoteSettingResponse>> {
    return this.http.getJson<RemoteSettingResponse>('setting');
  }
}
