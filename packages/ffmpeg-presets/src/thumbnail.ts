export const THUMBNAIL_WIDTH = 640;

export interface ThumbnailOptions {
  input: string;
  output: string;
  /** 캡처 시점(초). 영상 길이의 10% 근처가 무난. */
  atSec: number;
  width?: number;
}

/** 썸네일 한 장(JPEG). 원본이 작으면 키우지 않는다. */
export function thumbnailArgs({ input, output, atSec, width = THUMBNAIL_WIDTH }: ThumbnailOptions): string[] {
  return [
    '-hide_banner',
    '-nostdin',
    '-y',
    '-ss', atSec.toFixed(3),
    '-i', input,
    '-frames:v', '1',
    '-vf', `scale=w='min(${width},iw)':h=-2`,
    '-q:v', '3',
    '-loglevel', 'error',
    output,
  ];
}

/** 썸네일 캡처 시점: 길이의 10%, 단 0.5초 이상, 끝에서 0.5초 전 이하. */
export function thumbnailTime(durationSec: number): number {
  const t = durationSec * 0.1;
  return Math.max(0, Math.min(Math.max(0.5, t), Math.max(0, durationSec - 0.5)));
}
