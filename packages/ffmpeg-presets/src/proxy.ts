import { type Encoder, proxyEncoderArgs } from './encoder.js';

export const PROXY_HEIGHT = 720;

export interface ProxyOptions {
  input: string;
  output: string;
  encoder: Encoder;
  hasAudio: boolean;
}

/**
 * 720p 프리뷰 프록시. 원본이 720p보다 작으면 키우지 않는다.
 * 브라우저 스트리밍용으로 faststart, yuv420p.
 * 진행률은 `-progress pipe:1` 로 stdout에 key=value 로 나온다.
 */
export function proxyArgs({ input, output, encoder, hasAudio }: ProxyOptions): string[] {
  return [
    '-hide_banner',
    '-nostdin',
    '-y',
    '-i', input,
    '-vf', `scale=w=-2:h='min(${PROXY_HEIGHT},ih)'`,
    '-pix_fmt', 'yuv420p',
    ...proxyEncoderArgs(encoder),
    ...(hasAudio ? ['-c:a', 'aac', '-b:a', '128k', '-ac', '2'] : ['-an']),
    '-movflags', '+faststart',
    '-progress', 'pipe:1',
    '-loglevel', 'error',
    output,
  ];
}
