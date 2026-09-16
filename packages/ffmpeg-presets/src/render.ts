import { type Edit, type Segment, type TimeRange, keepSegments, remapRange, type SubtitleStyle } from '@madi/shared';
import { type Encoder, proxyEncoderArgs } from './encoder.js';

export const SHORT_WIDTH = 1080;
export const SHORT_HEIGHT = 1920;

export interface RenderPlan {
  args: string[];
  /** 결과 길이(초) */
  durationSec: number;
  /** 결과 크기 */
  width: number;
  height: number;
  segments: TimeRange[];
}

export interface RenderInput {
  input: string;
  output: string;
  edit: Pick<Edit, 'keep' | 'cuts' | 'crop' | 'subtitles' | 'subtitleStyle'>;
  durationSec: number;
  width: number;
  height: number;
  hasAudio: boolean;
  encoder: Encoder;
  /** 자막을 번인할 때 미리 써 둔 .ass 파일 */
  subtitleFile?: string | undefined;
  /** 동봉 폰트 폴더 (Pretendard). 없으면 시스템 폰트. */
  fontsDir?: string | undefined;
}

/** 인코더별 결과물 품질 옵션. 프록시보다 좋게. */
function outputEncoderArgs(encoder: Encoder): string[] {
  switch (encoder) {
    case 'h264_nvenc':
      return ['-c:v', 'h264_nvenc', '-preset', 'p5', '-rc', 'vbr', '-cq', '22', '-b:v', '0'];
    case 'h264_videotoolbox':
      return ['-c:v', 'h264_videotoolbox', '-q:v', '70'];
    case 'libx264':
      return ['-c:v', 'libx264', '-preset', 'medium', '-crf', '20'];
  }
}

/** libass 의 subtitles 필터에 넣을 경로 이스케이프 (':' '\\' ''' 등). */
export function escapeFilterPath(p: string): string {
  return p.replace(/\\/g, '/').replace(/:/g, '\\:').replace(/'/g, "\\'").replace(/,/g, '\\,').replace(/\[/g, '\\[').replace(/\]/g, '\\]');
}

/**
 * Edit → ffmpeg 인자. 구간 트림 + 이어붙이기 → (세로 크롭) → (자막 번인).
 * 항상 재인코딩. 렌더는 Edit 로부터 재현 가능하다.
 */
export function renderPlan(r: RenderInput): RenderPlan {
  const segs = keepSegments(r.edit, r.durationSec);
  if (segs.length === 0) throw new Error('nothing to render');
  const vertical = r.edit.crop === 'vertical';
  const outW = vertical ? SHORT_WIDTH : r.width - (r.width % 2);
  const outH = vertical ? SHORT_HEIGHT : r.height - (r.height % 2);

  const parts: string[] = [];
  const vLabels: string[] = [];
  const aLabels: string[] = [];
  segs.forEach((s, i) => {
    parts.push(`[0:v]trim=start=${fmt(s.start)}:end=${fmt(s.end)},setpts=PTS-STARTPTS[v${i}]`);
    vLabels.push(`[v${i}]`);
    if (r.hasAudio) {
      parts.push(`[0:a]atrim=start=${fmt(s.start)}:end=${fmt(s.end)},asetpts=PTS-STARTPTS[a${i}]`);
      aLabels.push(`[a${i}]`);
    }
  });
  const n = segs.length;
  if (r.hasAudio) {
    parts.push(`${vLabels.map((v, i) => v + aLabels[i]).join('')}concat=n=${n}:v=1:a=1[vc][ac]`);
  } else {
    parts.push(`${vLabels.join('')}concat=n=${n}:v=1:a=0[vc]`);
  }

  const post: string[] = [];
  if (vertical) {
    // 가운데 9:16 만큼 잘라서 1080x1920 으로. 원본이 이미 세로면 그냥 맞춘다.
    post.push(`crop=w='min(iw,ih*9/16)':h='min(ih,iw*16/9)'`, `scale=${SHORT_WIDTH}:${SHORT_HEIGHT}:flags=lanczos`);
  }
  if (r.edit.subtitles && r.subtitleFile) {
    const fonts = r.fontsDir ? `:fontsdir='${escapeFilterPath(r.fontsDir)}'` : '';
    post.push(`subtitles='${escapeFilterPath(r.subtitleFile)}'${fonts}`);
  }
  post.push('format=yuv420p');
  parts.push(`[vc]${post.join(',')}[vout]`);

  const args = [
    '-hide_banner',
    '-nostdin',
    '-y',
    '-i', r.input,
    '-filter_complex', parts.join(';'),
    '-map', '[vout]',
    ...(r.hasAudio ? ['-map', '[ac]', '-c:a', 'aac', '-b:a', '160k', '-ac', '2'] : ['-an']),
    ...outputEncoderArgs(r.encoder),
    '-movflags', '+faststart',
    '-progress', 'pipe:1',
    '-loglevel', 'error',
    r.output,
  ];
  return { args, durationSec: segs.reduce((a, s) => a + (s.end - s.start), 0), width: outW, height: outH, segments: segs };
}

function fmt(n: number): string {
  return n.toFixed(3);
}

/** #RRGGBB → ASS 의 &HAABBGGRR& */
export function assColor(hex: string, alpha = 0): string {
  const m = /^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(hex);
  if (!m) return '&H00FFFFFF&';
  const [, r, g, b] = m;
  return `&H${alpha.toString(16).padStart(2, '0').toUpperCase()}${b!.toUpperCase()}${g!.toUpperCase()}${r!.toUpperCase()}&`;
}

function assTime(sec: number): string {
  const cs = Math.round(sec * 100);
  const h = Math.floor(cs / 360000);
  const m = Math.floor((cs % 360000) / 6000);
  const s = Math.floor((cs % 6000) / 100);
  const c = cs % 100;
  return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}.${String(c).padStart(2, '0')}`;
}

/**
 * 문장 자막 → ASS. 잘린 구간은 빠지고 시각은 결과물 기준으로 옮긴다.
 * BorderStyle=3: 글자 뒤에 박스 (디자인의 노란 박스).
 */
export function buildAss(
  segments: Segment[],
  keep: TimeRange[],
  style: SubtitleStyle,
  frame: { width: number; height: number },
): string {
  const marginV = Math.round(frame.height * style.bottom);
  const header = [
    '[Script Info]',
    'ScriptType: v4.00+',
    `PlayResX: ${frame.width}`,
    `PlayResY: ${frame.height}`,
    'WrapStyle: 0',
    'ScaledBorderAndShadow: yes',
    '',
    '[V4+ Styles]',
    'Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding',
    `Style: Madi,${style.fontFamily},${style.fontSize},${assColor(style.color)},${assColor(style.color)},${assColor(style.boxColor)},${assColor(style.boxColor)},1,0,0,0,100,100,0,0,3,${Math.round(style.fontSize * 0.22)},0,2,40,40,${marginV},1`,
    '',
    '[Events]',
    'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text',
  ];
  const lines: string[] = [];
  for (const seg of segments) {
    // 구간 안에 남는 단어들만 모아서 문장을 다시 만든다
    const words = seg.words.length ? seg.words : [{ start: seg.start, end: seg.end, text: seg.text, p: null }];
    let cur: { start: number; end: number; text: string[] } | null = null;
    const flush = () => {
      if (cur && cur.text.length) lines.push(`Dialogue: 0,${assTime(cur.start)},${assTime(cur.end)},Madi,,0,0,0,,${escapeAss(cur.text.join(' '))}`);
      cur = null;
    };
    for (const w of words) {
      const r = remapRange({ start: w.start, end: Math.max(w.start, Math.min(w.end, seg.end)) }, keep);
      if (!r) {
        flush();
        continue;
      }
      if (!cur) cur = { start: r.start, end: r.end, text: [] };
      cur.end = Math.max(cur.end, r.end);
      cur.text.push(w.text.trim());
    }
    flush();
  }
  return [...header, ...lines, ''].join('\n');
}

function escapeAss(text: string): string {
  return text.replace(/\\/g, '\\\\').replace(/\{/g, '(').replace(/\}/g, ')').replace(/\n/g, '\\N');
}
