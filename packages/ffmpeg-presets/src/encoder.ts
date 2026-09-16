/**
 * H.264 인코더 선택. GPU가 있으면 하드웨어 인코더, 없으면 libx264.
 * 실제 사용 가능 여부는 엔진이 `ffmpeg -encoders` 로 한 번 확인해서 넘긴다.
 */
export type Encoder = 'h264_nvenc' | 'h264_videotoolbox' | 'libx264';

export interface EncoderHints {
  platform: string;
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

/**
 * 하드웨어 인코더가 실제로 도는지 확인하는 인자. 합성 검은 화면 2프레임을 인코딩해서 버린다.
 * 인코더 이름이 목록에 있어도 GPU 가 없거나(VM, 헤드리스) 드라이버가 막혀 있으면 여기서 실패한다.
 * 실패하면 엔진은 libx264 로 내려간다.
 */
export function encoderSmokeArgs(encoder: Encoder): string[] {
  return [
    '-hide_banner',
    '-nostdin',
    '-f', 'lavfi',
    '-i', 'color=c=black:s=128x128:r=30:d=0.1',
    '-frames:v', '2',
    ...proxyEncoderArgs(encoder),
    '-f', 'null',
    '-',
  ];
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

/** h264_nvenc 프리셋 확인용 인자. 출력에 p1~p7 이 있어야 `proxyEncoderArgs` 의 `-preset p4` 가 통한다. */
export function nvencHelpArgs(): string[] {
  return ['-hide_banner', '-h', 'encoder=h264_nvenc'];
}

/**
 * `ffmpeg -h encoder=h264_nvenc` 출력에 p1~p7 프리셋이 있는지.
 * 2018년 이전 빌드(@ffmpeg-installer 폴백 등)는 slow/medium/fast 같은 옛 프리셋만 알아서 p4 를 거부한다.
 */
export function supportsNvencPresets(helpOutput: string): boolean {
  return /^\s+p4\s/m.test(helpOutput);
}
