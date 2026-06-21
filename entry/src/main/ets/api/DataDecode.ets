import { hilog } from '@kit.PerformanceAnalysisKit';

export interface ParsedChapterImages {
  list: string[];
  __aId: number;
  __scrambleId: number;
  __speed: string;
}

const DOMAIN = 0x0000;
const TAG = 'JMApi';

function parseQuotedList(source: string): string[] {
  const values: string[] = [];
  const regex = /['"]([^'"]+)['"]/g;
  let match = regex.exec(source);
  while (match !== null) {
    values.push(match[1]);
    match = regex.exec(source);
  }
  return values;
}

function parseJsStringField(source: string, key: string): string {
  const regex = new RegExp(`${key}\\s*:\\s*['"]([^'"]*)['"]`);
  const match = regex.exec(source);
  return match !== null && match.length > 1 ? match[1] : '';
}

export function parseHtml(html: string): string[] {
  const imagesMatch = /images\s*:\s*\[([\s\S]*?)\]/.exec(html);
  const configMatch = /(?:const|let|var)\s+config\s*=\s*(\{[\s\S]*?\})\s*;/.exec(html);
  const images = imagesMatch !== null && imagesMatch.length > 1 ? parseQuotedList(imagesMatch[1]) : [];
  const configSource = configMatch !== null && configMatch.length > 1 ? configMatch[1] : '';
  const imgHost = parseJsStringField(configSource, 'imghost');
  const jmId = parseJsStringField(configSource, 'jmid');
  const cache = parseJsStringField(configSource, 'cache');
  if (images.length === 0 || imgHost.length === 0 || jmId.length === 0) {
    hilog.error(
      DOMAIN,
      TAG,
      'chapter image parse failed images=%{public}d host=%{public}d jmid=%{public}d html=%{public}d',
      images.length,
      imgHost.length,
      jmId.length,
      html.length
    );
    return [];
  }
  hilog.info(DOMAIN, TAG, 'chapter image parse ok images=%{public}d host=%{public}s jmid=%{public}s', images.length, imgHost, jmId);
  return images.map((item: string) => `${imgHost}/media/photos/${jmId}/${item}${cache}`);
}

export function parseRange(html: string): [number, number] {
  const aidMatch = /var aid\s*=\s*(\d+);/.exec(html);
  const scrambleMatch = /var scramble_id\s*=\s*(\d+);/.exec(html);
  const aid = aidMatch ? Number.parseInt(aidMatch[1], 10) : 0;
  const scrambleId = scrambleMatch ? Number.parseInt(scrambleMatch[1], 10) : 0;
  return [Number.isNaN(aid) ? 0 : aid, Number.isNaN(scrambleId) ? 0 : scrambleId];
}

export function parseSpeed(html: string): string {
  const match = /var speed\s*=\s*'(.*)';/.exec(html);
  return match ? match[1] : '';
}

export function parseChapterImages(html: string): ParsedChapterImages {
  const range = parseRange(html);
  return {
    list: parseHtml(html),
    __aId: range[0],
    __scrambleId: range[1],
    __speed: parseSpeed(html)
  };
}
