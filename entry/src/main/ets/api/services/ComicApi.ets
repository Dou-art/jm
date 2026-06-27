import { ApiResult, failure, success } from '../ApiResult';
import { parseChapterImages } from '../DataDecode';
import { JmHttpClient } from '../HttpClient';
import { CacheStore, TTL_DETAIL, TTL_HOME } from '../CacheStore';
import {
  CollectComicResponse,
  ComicDetailResponse,
  ComicListResponse,
  ComicPicListResponse,
  CommentComicResponse,
  CommentListResponse,
  HomeSwiperComicListItemResponse,
  LikeComicResponse,
  WeekRecommendComicResponse,
  WeekResponse
} from '../models/Responses';

export class ComicApi {
  private readonly http: JmHttpClient;
  private readonly cache: CacheStore;

  constructor(http: JmHttpClient, cache: CacheStore) {
    this.http = http;
    this.cache = cache;
  }

  getComicDetail(id: number): Promise<ApiResult<ComicDetailResponse>> {
    return this.cache.getOrFetch<ComicDetailResponse>(`detail:${id}`, TTL_DETAIL, () => {
      const query = new Map<string, string | number | boolean | undefined | null>();
      query.set('id', id);
      return this.http.getJson<ComicDetailResponse>('album', query);
    });
  }

  likeComic(id: number): Promise<ApiResult<LikeComicResponse>> {
    const parts = new Map<string, string | number | boolean | undefined | null>();
    parts.set('id', id);
    return this.http.postMultipartJson<LikeComicResponse>('like', parts);
  }

  collectComic(id: number): Promise<ApiResult<CollectComicResponse>> {
    const parts = new Map<string, string | number | boolean | undefined | null>();
    parts.set('aid', id);
    return this.http.postMultipartJson<CollectComicResponse>('favorite', parts);
  }

  unCollectComic(id: number): Promise<ApiResult<CollectComicResponse>> {
    return this.collectComic(id);
  }

  getHomeSwiperComicList(): Promise<ApiResult<HomeSwiperComicListItemResponse[]>> {
    return this.cache.getOrFetch<HomeSwiperComicListItemResponse[]>('home', TTL_HOME, () => {
      return this.http.getJson<HomeSwiperComicListItemResponse[]>('promote');
    });
  }

  async getComicPicList(id: number, shunt: string): Promise<ApiResult<ComicPicListResponse>> {
    const query = new Map<string, string | number | boolean | undefined | null>();
    query.set('id', id);
    query.set('app_img_shunt', shunt);
    query.set('mode', 'vertical');
    query.set('page', 0);
    query.set('express', 'off');
    query.set('v', Math.floor(Date.now() / 1000));
    const html = await this.http.getText('chapter_view_template', query);
    if (!html.ok) {
      return failure<ComicPicListResponse>(html.message ?? 'request failed', html.code, html.cause);
    }
    const parsed = parseChapterImages(html.data ?? '');
    if (parsed.list.length === 0) {
      return failure<ComicPicListResponse>('failed to parse comic image list');
    }
    return success(parsed);
  }

  getComicList(page: number, order: string, searchContent: string): Promise<ApiResult<ComicListResponse>> {
    const query = new Map<string, string | number | boolean | undefined | null>();
    query.set('page', page);
    query.set('o', order);
    query.set('search_query', searchContent);
    return this.http.getJson<ComicListResponse>('search', query);
  }

  getWeekData(): Promise<ApiResult<WeekResponse>> {
    return this.http.getJson<WeekResponse>('week');
  }

  getWeekRecommendComicList(
    page: number,
    categoryId: string,
    typeId: string
  ): Promise<ApiResult<WeekRecommendComicResponse>> {
    const query = new Map<string, string | number | boolean | undefined | null>();
    query.set('page', page);
    query.set('id', categoryId);
    query.set('type', typeId);
    return this.http.getJson<WeekRecommendComicResponse>('week/filter', query);
  }

  getCommentList(page: number, comicId: number): Promise<ApiResult<CommentListResponse>> {
    const query = new Map<string, string | number | boolean | undefined | null>();
    query.set('page', page);
    query.set('aid', comicId);
    query.set('mode', 'manhua');
    return this.http.getJson<CommentListResponse>('forum', query);
  }

  comment(content: string, comicId: number, commentId?: number): Promise<ApiResult<CommentComicResponse>> {
    const parts = new Map<string, string | number | boolean | undefined | null>();
    parts.set('comment', content);
    parts.set('aid', comicId);
    parts.set('status', '1');
    parts.set('comment_id', commentId);
    return this.http.postMultipartJson<CommentComicResponse>('comment', parts);
  }
}
