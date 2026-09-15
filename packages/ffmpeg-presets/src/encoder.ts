/**
 * H.264 인코더 선택. GPU가 있으면 하드웨어 인코더, 없으면 libx264.
 * 실제 사용 가능 여부는 엔진이 `ffmpeg -encoders` 로 한 번 확인해서 넘긴다.
 */
export type Encoder = 'h264_nvenc' | 'h264_videotoolbox' | 'libx264';

export interface EncoderHints {
  platform: NodeJS.Platform | string;
  /** ffmpeg -encoders 출력에 들어 있는 인코더 이름들 */
  available: ReadonlySet<string>;
}

export function pickEncoder({ platform, available }: EncoderHints): Encoder {
  if (platform === 'darwin' && available.has('h264_videotoolbox')) return 'h264_videotoolbox';
  if (available.has('h264_nvenc')) return 'h264_nvenc';
  return 'libx264';
}

/** 인코더별 품질/속도 옵션. 프록시용(빠르게, 적당한 화질). */
export function proxyEncoderArgs(encoder: Encoder): string[] {
  switch (encoder) {
    case 'h264_nvenc':
      return ['-c:v', 'h264_nvenc', '-preset', 'p4', '-rc', 'vbr', '-cq', '28', '-b:v', '0'];
    case 'h264_videotoolbox':
      return ['-c:v', 'h264_videotoolbox', '-q:v', '55', '-realtime', '1'];
    case 'libx264':
      return ['-c:v', 'libx264', '-preset', 'veryfast', '-crf', '26'];
  }
}

/** `ffmpeg -hide_banner -encoders` 출력에서 인코더 이름만 뽑는다. */
export function parseEncoderList(stdout: string): Set<string> {
  const names = new Set<string>();
  for (const line of stdout.split('\n')) {
    // 형식: " V....D h264_nvenc           NVIDIA NVENC H.264 encoder (codec h264)"
    const m = /^\s*[VAS][A-Z.]{5}\s+(\S+)\s/.exec(line);
    if (m?.[1]) names.add(m[1]);
  }
  return names;
}
