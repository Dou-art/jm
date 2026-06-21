export interface CategoryResponse {
  id?: string;
  title?: string;
}

export interface ListComicItemResponse {
  id: string;
  author: string;
  description?: string;
  name: string;
  image: string;
  category: CategoryResponse;
  category_sub: CategoryResponse;
  liked?: boolean;
  is_favorite?: boolean;
  update_at?: number;
}

export interface CollectComicResponse {
  msg: string;
  status: string;
  type: string;
}

export interface LikeComicResponse {
  code: number;
  msg: string;
  status: string;
}

export interface ComicDetailRelatedListItemResponse {
  id: string;
  name: string;
  author: string;
  image: string;
}

export interface ComicDetailSeriesListItemResponse {
  id: string;
  name: string;
  sort: string;
}

export interface ComicDetailResponse {
  id: number;
  name: string;
  description: string;
  author: string[];
  total_views: number;
  likes: number;
  comment_total: number;
  tags: string[];
  actors: string[];
  works: string[];
  is_favorite: boolean;
  liked: boolean;
  related_list: ComicDetailRelatedListItemResponse[];
  series: ComicDetailSeriesListItemResponse[];
  series_id: string;
  price: string;
  purchased: boolean;
}

export interface ComicListResponse {
  search_query: string;
  total: string;
  redirect_aid?: string;
  content: ListComicItemResponse[];
}

export interface HomeSwiperComicListItemResponse {
  id: string;
  title: string;
  slug: string;
  type: string;
  filter_val: string;
  content: ListComicItemResponse[];
}

export interface ComicPicListResponse {
  list: string[];
  __aId: number;
  __scrambleId: number;
  __speed: string;
}

export interface WeekResponse {
  categories: WeekCategoryItemResponse[];
  type: WeekTypeItemResponse[];
}

export interface WeekCategoryItemResponse {
  id: string;
  time: string;
  title: string;
}

export interface WeekTypeItemResponse {
  id: string;
  title: string;
}

export interface WeekRecommendComicResponse {
  total: number;
  list: ListComicItemResponse[];
}

export interface CommentListItemResponse {
  AID?: string;
  BID: string;
  CID: string;
  UID: string;
  username: string;
  nickname: string;
  likes: string;
  gender: string;
  update_at: string;
  addtime: string;
  parent_CID: string;
  name: string;
  content: string;
  photo: string;
  spoiler: string;
  replys?: CommentListItemResponse[];
}

export interface CommentListResponse {
  list: CommentListItemResponse[];
  total: string;
}

export interface CommentComicResponse {
  msg: string;
  status: string;
  aid: number;
  cid: number;
  spoiler: string;
}

export interface LoginResponse {
  uid: number;
  username: string;
  email: string;
  photo: string;
  coin: string;
  album_favorites: number;
  level_name: string;
  level: number;
  nextLevelExp: number;
  exp: number;
  expPercent: number;
  album_favorites_max: number;
}

export interface UserCollectComicListResponse {
  count: number;
  list: ListComicItemResponse[];
  total: number;
}

export interface UserHistoryComicListResponse {
  list: ListComicItemResponse[];
  total: number;
}

export interface UserHistoryCommentListResponse {
  list: CommentListItemResponse[];
  total: number;
}

export interface SignInDataRecordItemResponse {
  date: string;
  signed: boolean;
  bonus: boolean;
}

export interface SignInDataResponse {
  daily_id: number;
  three_days_coin: string;
  three_days_exp: string;
  seven_days_coin: string;
  seven_days_exp: string;
  event_name: string;
  background_pc: string;
  background_phone: string;
  currentProgress: string;
  record: SignInDataRecordItemResponse[][];
}

export interface SignInResponse {
  msg: string;
}

export interface RemoteSettingResponse {
  img_host: string;
  app_shunts: RemoteSettingShuntResponse[];
}

export interface RemoteSettingShuntResponse {
  title: string;
  key: string;
}
