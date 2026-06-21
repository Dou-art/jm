export interface ResponseWrapper<T> {
  code: number;
  data?: T;
  errorMsg?: string;
}

export interface ApiResult<T> {
  ok: boolean;
  code: number;
  data?: T;
  message?: string;
  cause?: string;
}

export type ApiSuccess<T> = ApiResult<T>;
export type ApiFailure<T> = ApiResult<T>;

export function success<T>(data: T, code: number = 200): ApiResult<T> {
  return { ok: true, data, code };
}

export function failure<T>(message: string, code: number = -1, cause?: string): ApiResult<T> {
  return { ok: false, message, code, cause };
}
