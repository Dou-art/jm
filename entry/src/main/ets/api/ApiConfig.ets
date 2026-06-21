export const API_VERSION: string = '1.8.2';
export const API_TOKEN_SECRET: string = '185Hcomic3PAPP7R';

export const DEFAULT_API_LIST: string[] = [
  'https://www.cdnhth.club',
  'https://www.cdnmhwscc.vip',
  'https://www.jmapiproxyxxx.vip',
  'https://www.cdnxxx-proxy.xyz',
  'https://www.jmeadpoolcdn.life'
];

export interface JmApiClientOptions {
  baseUrl?: string;
  timeoutMs?: number;
}

export function normalizeBaseUrl(baseUrl: string): string {
  return baseUrl.endsWith('/') ? baseUrl.slice(0, -1) : baseUrl;
}

