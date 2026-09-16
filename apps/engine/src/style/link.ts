import path from 'node:path';

/**
 * 링크로 배우기 — yt-dlp 호출 조립·결과 해석 (순수 함수).
 * 유튜브·틱톡·인스타 릴스 등 yt-dlp 가 읽는 공개 영상을 ~/.madi/references/<id>.mp4 로 받는다.
 */

const FILE_TAG = 'MADI_FILE\t';
const TITLE_TAG = 'MADI_TITLE\t';

export interface YtdlpArgsOptions {
  url: string;
  /** 받을 파일의 확장자 앞부분. yt-dlp 가 %(ext)s 를 채운다. */
  outBase: string;
  /** ffmpeg 바이너리 경로 (합치기·mp4 변환에 쓴다). 없으면 PATH. */
  ffmpeg?: string | undefined;
  /** 최대 세로 해상도. 분석용이라 720 이면 충분하다. */
  maxHeight?: number;
}

/** 재생목록은 안 받고, 720p 이하 mp4 하나로. 끝나면 파일 경로·제목을 표시 줄로 찍게 한다. */
export function ytdlpArgs(o: YtdlpArgsOptions): string[] {
  const h = o.maxHeight ?? 720;
  const args = [
    '--no-playlist',
    '--no-warnings',
    '--no-progress',
    '--no-mtime',
    '-f',
    `bv*[height<=${h}]+ba/b[height<=${h}]/b`,
    '--merge-output-format',
    'mp4',
    '--remux-video',
    'mp4',
    '-o',
    `${o.outBase}.%(ext)s`,
    '--no-simulate',
    '--print',
    `after_move:${FILE_TAG}%(filepath)s`,
    '--print',
    `after_move:${TITLE_TAG}%(title)s`,
  ];
  if (o.ffmpeg) args.push('--ffmpeg-location', o.ffmpeg);
  args.push('--', o.url);
  return args;
}

export interface YtdlpResult {
  filePath: string;
  title: string;
}

/** stdout 에서 표시 줄을 찾는다. 파일 줄이 없으면 null (받다 만 것). */
export function parseYtdlpOutput(stdout: string): YtdlpResult | null {
  let filePath: string | null = null;
  let title = '';
  for (const raw of stdout.split(/\r?\n/)) {
    const line = raw.trim();
    if (line.startsWith(FILE_TAG)) filePath = line.slice(FILE_TAG.length).trim();
    else if (line.startsWith(TITLE_TAG)) title = line.slice(TITLE_TAG.length).trim();
  }
  if (!filePath) return null;
  return { filePath, title: title || path.basename(filePath).replace(/\.[^.]+$/, '') };
}

export type LinkErrorCode = 'link_private' | 'link_unsupported' | 'link_unavailable' | 'link_network' | 'link_failed';

/** yt-dlp 오류 글을 사용자에게 보일 수 있는 코드로. 원문은 로그에만. */
export function classifyLinkError(stderr: string): LinkErrorCode {
  const s = stderr.toLowerCase();
  if (/login|sign in|cookies|private video|rate-limit|rate limit|429|age-restricted|confirm your age/.test(s)) return 'link_private';
  if (/unsupported url|is not a valid url|no video formats|requested format is not available/.test(s)) return 'link_unsupported';
  if (/video unavailable|not available|removed|does not exist|404|has been deleted|blocked/.test(s)) return 'link_unavailable';
  if (/unable to download|connection|timed out|network|resolve host|ssl|getaddrinfo|econn/.test(s)) return 'link_network';
  return 'link_failed';
}

export function isLinkErrorCode(s: string | null | undefined): s is LinkErrorCode {
  return s === 'link_private' || s === 'link_unsupported' || s === 'link_unavailable' || s === 'link_network' || s === 'link_failed';
}
