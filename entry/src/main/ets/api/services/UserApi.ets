import { ApiResult } from '../ApiResult';
import { JmHttpClient } from '../HttpClient';
import {
  LoginResponse,
  SignInDataResponse,
  SignInResponse,
  UserCollectComicListResponse,
  UserHistoryComicListResponse,
  UserHistoryCommentListResponse
} from '../models/Responses';

export class UserApi {
  private readonly http: JmHttpClient;

  constructor(http: JmHttpClient) {
    this.http = http;
  }

  login(username: string, password: string): Promise<ApiResult<LoginResponse>> {
    const parts = new Map<string, string | number | boolean | undefined | null>();
    parts.set('username', username);
    parts.set('password', password);
    return this.http.postMultipartJson<LoginResponse>('login', parts);
  }

  getCollectComicList(
    page: number,
    order: string,
    folderId: number = 0
  ): Promise<ApiResult<UserCollectComicListResponse>> {
    const query = new Map<string, string | number | boolean | undefined | null>();
    query.set('page', page);
    query.set('o', order);
    query.set('folder_id', folderId);
    return this.http.getJson<UserCollectComicListResponse>('favorite', query);
  }

  getHistoryComicList(page: number): Promise<ApiResult<UserHistoryComicListResponse>> {
    const query = new Map<string, string | number | boolean | undefined | null>();
    query.set('page', page);
    return this.http.getJson<UserHistoryComicListResponse>('watch_list', query);
  }

  getHistoryCommentList(page: number, userId: number): Promise<ApiResult<UserHistoryCommentListResponse>> {
    const query = new Map<string, string | number | boolean | undefined | null>();
    query.set('page', page);
    query.set('uid', userId);
    return this.http.getJson<UserHistoryCommentListResponse>('forum', query);
  }

  getSignInData(userId: number): Promise<ApiResult<SignInDataResponse>> {
    const query = new Map<string, string | number | boolean | undefined | null>();
    query.set('user_id', userId);
    return this.http.getJson<SignInDataResponse>('daily', query);
  }

  signIn(userId: number, dailyId: number): Promise<ApiResult<SignInResponse>> {
    const parts = new Map<string, string | number | boolean | undefined | null>();
    parts.set('user_id', userId);
    parts.set('daily_id', dailyId);
    return this.http.postMultipartJson<SignInResponse>('daily_chk', parts);
  }
}
