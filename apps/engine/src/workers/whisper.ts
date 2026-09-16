import fs from 'node:fs';
import path from 'node:path';
import { nanoid } from 'nanoid';
import { z } from 'zod';
import { parseSilences, silenceDetectArgs } from '@madi/ffmpeg-presets';
import type { Segment, TimeRange, Word } from '@madi/shared';
import { run } from './spawn.js';

/**
 * whisper.cpp 의 `-ojf`(full json) 출력. 토큰에 시각이 붙어 있어 단어를 만들 수 있다.
 * 버전에 따라 필드가 조금씩 달라서 느슨하게 받는다.
 *
 * 글자 깨짐 주의: whisper 토큰은 바이트 단위라 한글 한 글자(3바이트)가 토큰 두 개에 걸쳐 잘린다.
 * 파일을 utf8 로 읽으면 그 자리가 � 가 되므로, latin1(바이트 그대로)로 읽어 어절 단위로 바이트를 합친 뒤 utf8 로 푼다.
 */
const WhisperToken = z.object({
  text: z.string(),
  offsets: z.object({ from: z.number(), to: z.number() }),
  p: z.number().optional(),
  id: z.number().optional(),
});
const WhisperSegment = z.object({
  offsets: z.object({ from: z.number(), to: z.number() }),
  text: z.string(),
  tokens: z.array(WhisperToken).optional(),
});
export const WhisperJson = z.object({
  result: z.object({ language: z.string().optional() }).optional(),
  transcription: z.array(WhisperSegment).default([]),
});
export type WhisperJson = z.infer<typeof WhisperJson>;

/** whisper 특수 토큰: [_BEG_], [_TT_123], <|ko|> 같은 것 */
function isSpecial(text: string): boolean {
  return /^\s*(\[_[A-Z_]+_?\d*\]|<\|[^|]*\|>)\s*$/.test(text);
}

/** ASCII 공백만 뗀다. String.trim 은 0xA0(NBSP) 도 떼는데, latin1 로 읽은 바이트 문자열에선 그게 한글의 일부일 수 있다. */
function trimAscii(s: string): string {
  return s.replace(/^[ \t\r\n]+|[ \t\r\n]+$/g, '');
}

/** latin1 로 읽은 바이트 문자열 → 진짜 utf8 글자. (utf8 로 읽은 문자열이면 그대로.) */
function decode(s: string, bytes: boolean): string {
  return bytes ? Buffer.from(s, 'latin1').toString('utf8') : s;
}

/**
 * 토큰 → 단어. whisper 토큰은 서브워드라서 공백으로 시작하는 토큰이 새 단어.
 * 한국어는 공백 단위(어절)로 묶는다. bytes=true 면 토큰 글자가 바이트 문자열이라 어절을 다 모은 뒤 utf8 로 푼다.
 */
export function tokensToWords(tokens: z.infer<typeof WhisperToken>[], bytes = false): Word[] {
  const words: Word[] = [];
  let cur: Word | null = null;
  const flush = () => {
    if (!cur) return;
    cur.text = decode(cur.text, bytes);
    if (cur.text && !cur.text.includes('�')) words.push(cur);
    cur = null;
  };
  for (const t of tokens) {
    if (isSpecial(t.text)) continue;
    const startsWord = /^[ \t\r\n]/.test(t.text) || cur === null;
    const piece = trimAscii(t.text);
    if (!piece) continue;
    if (startsWord) {
      flush();
      cur = { start: t.offsets.from / 1000, end: t.offsets.to / 1000, text: piece, p: t.p ?? null };
    } else if (cur) {
      cur.text += piece;
      cur.end = Math.max(cur.end, t.offsets.to / 1000);
      if (t.p !== undefined) cur.p = cur.p === null ? t.p : Math.min(cur.p, t.p);
    }
  }
  flush();
  return words;
}

/**
 * whisper JSON → 문장 단위 Segment[]. 빈 문장·특수 토큰만 있는 문장은 버린다.
 * Buffer 를 주면 바이트 그대로 해석해 잘린 한글을 되살린다 (파일에서 읽을 땐 항상 Buffer 로).
 * 문장 글은 whisper 의 문장 텍스트를 쓴다 (토큰을 이어 붙인 것보다 안전). 단어는 시각용.
 */
export function parseWhisperJson(raw: string | Buffer): { language: string; segments: Segment[] } {
  const bytes = Buffer.isBuffer(raw);
  const json = WhisperJson.parse(JSON.parse(bytes ? raw.toString('latin1') : raw));
  const segments: Segment[] = [];
  for (const s of json.transcription) {
    const text = decode(trimAscii(s.text), bytes).replace(/�/g, '').replace(/\s+/g, ' ').trim();
    if (!text || isSpecial(text)) continue;
    const words = s.tokens ? tokensToWords(s.tokens, bytes) : [];
    segments.push({
      id: nanoid(8),
      start: s.offsets.from / 1000,
      end: s.offsets.to / 1000,
      text,
      words,
    });
  }
  return { language: decode(json.result?.language ?? 'ko', bytes), segments };
}

/**
 * whisper 가 무음에서 지어낸 문장 걸러내기.
 * - 문장 구간의 대부분(기본 80%)이 무음이면 버린다.
 * - "[음악]", "(박수)", "..." 처럼 괄호·기호뿐인 문장, 같은 글자만 반복되는 문장도 버린다.
 */
export function dropHallucinations(segments: Segment[], silences: TimeRange[], opts: { silentRatio?: number } = {}): Segment[] {
  const ratio = opts.silentRatio ?? 0.8;
  return segments.filter((s) => {
    if (isNoiseText(s.text)) return false;
    const len = s.end - s.start;
    if (len <= 0) return silentAt(s.start, silences);
    let silent = 0;
    for (const r of silences) silent += Math.max(0, Math.min(s.end, r.end) - Math.max(s.start, r.start));
    return silent / len < ratio;
  });
}

function silentAt(t: number, silences: TimeRange[]): boolean {
  return silences.some((r) => t >= r.start && t <= r.end);
}

/** 괄호 태그만 있거나, 글자가 거의 없거나, 한 덩어리가 계속 반복되는 글 */
export function isNoiseText(text: string): boolean {
  const t = text.trim();
  if (!t) return true;
  if (/^[\[(（【][^\])）】]*[\])）】]$/.test(t)) return true; // [음악] (박수) 【字幕】
  const letters = t.replace(/[^\p{L}\p{N}]/gu, '');
  if (letters.length === 0) return true; // "..." "♪♪"
  const chunk = /^(.{1,6}?)\1{3,}$/su.exec(t.replace(/\s+/g, ''));
  if (chunk) return true; // "네네네네네네" "감사합니다감사합니다감사합니다감사합니다"
  return false;
}

export interface WhisperBins {
  ffmpeg: string;
  whisper: string;
}

export class WhisperMissingError extends Error {
  constructor(what: 'binary' | 'model') {
    super(what === 'binary' ? 'whisper binary missing' : 'whisper model missing');
    this.name = 'WhisperMissingError';
  }
}

/** 순수 스폰 래퍼. 16k mono wav 로 바꾼 뒤 whisper-cli 를 돌리고, 무음에서 지어낸 문장을 걸러낸다. */
export class Whisper {
  constructor(
    private readonly bins: WhisperBins,
    private readonly modelPath: string,
  ) {}

  get model(): string {
    return path.basename(this.modelPath);
  }

  async transcribe(
    input: string,
    workDir: string,
    opts: { language?: string; signal?: AbortSignal | undefined; onProgress?: (ratio: number) => void } = {},
  ): Promise<{ language: string; segments: Segment[] }> {
    if (!fs.existsSync(this.modelPath)) throw new WhisperMissingError('model');
    fs.mkdirSync(workDir, { recursive: true });
    const wav = path.join(workDir, 'audio.wav');
    const prefix = path.join(workDir, 'whisper');
    try {
      await run(this.bins.ffmpeg, ['-hide_banner', '-nostdin', '-y', '-i', input, '-vn', '-ac', '1', '-ar', '16000', '-c:a', 'pcm_s16le', '-loglevel', 'error', wav], {
        signal: opts.signal,
      });
      opts.onProgress?.(0.1);
      const threads = String(Math.max(1, Math.min(8, (await import('node:os')).cpus().length - 1)));
      // -sns: "[음악]" 같은 비음성 토큰을 애초에 내지 않는다
      await run(
        this.bins.whisper,
        ['-m', this.modelPath, '-f', wav, '-l', opts.language ?? 'ko', '-t', threads, '-ojf', '-of', prefix, '-np', '-pp', '-sns'],
        {
          signal: opts.signal,
          onStdout: (chunk) => {
            // -pp 는 "whisper_print_progress_callback: progress = 42%" 를 낸다 (stderr 일 수도 있어 stdout 만 본다)
            const m = /progress\s*=\s*(\d+)%/.exec(chunk);
            if (m) opts.onProgress?.(0.1 + 0.85 * (Number(m[1]) / 100));
          },
        },
      ).catch((err: Error) => {
        if (/ENOENT/.test(err.message)) throw new WhisperMissingError('binary');
        throw err;
      });
      const parsed = parseWhisperJson(fs.readFileSync(`${prefix}.json`));
      // 무음 구간(0.5초 이상)을 재서 그 안에서 지어낸 문장을 버린다. 실패해도 자막은 살린다.
      let silences: TimeRange[] = [];
      try {
        const { stderr } = await run(this.bins.ffmpeg, silenceDetectArgs(wav, { minSec: 0.5 }), { signal: opts.signal });
        silences = parseSilences(stderr, Number.MAX_SAFE_INTEGER);
      } catch {
        /* 무음 측정 실패 → 걸러내지 않음 */
      }
      opts.onProgress?.(1);
      return { language: parsed.language, segments: dropHallucinations(parsed.segments, silences) };
    } finally {
      fs.rmSync(wav, { force: true });
    }
  }
}
