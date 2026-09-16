import fs from 'node:fs';
import path from 'node:path';
import { nanoid } from 'nanoid';
import { z } from 'zod';
import type { Segment, Word } from '@madi/shared';
import { run } from './spawn.js';

/**
 * whisper.cpp 의 `-ojf`(full json) 출력. 토큰에 시각이 붙어 있어 단어를 만들 수 있다.
 * 버전에 따라 필드가 조금씩 달라서 느슨하게 받는다.
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

/**
 * 토큰 → 단어. whisper 토큰은 서브워드라서 공백으로 시작하는 토큰이 새 단어.
 * 한국어는 공백 단위(어절)로 묶는다.
 */
export function tokensToWords(tokens: z.infer<typeof WhisperToken>[]): Word[] {
  const words: Word[] = [];
  let cur: Word | null = null;
  for (const t of tokens) {
    if (isSpecial(t.text)) continue;
    const startsWord = /^\s/.test(t.text) || cur === null;
    const piece = t.text.trim();
    if (!piece) continue;
    if (startsWord) {
      if (cur) words.push(cur);
      cur = { start: t.offsets.from / 1000, end: t.offsets.to / 1000, text: piece, p: t.p ?? null };
    } else if (cur) {
      cur.text += piece;
      cur.end = Math.max(cur.end, t.offsets.to / 1000);
      if (t.p !== undefined) cur.p = cur.p === null ? t.p : Math.min(cur.p, t.p);
    }
  }
  if (cur) words.push(cur);
  return words;
}

/** whisper JSON → 문장 단위 Segment[]. 빈 문장·특수 토큰만 있는 문장은 버린다. */
export function parseWhisperJson(raw: string): { language: string; segments: Segment[] } {
  const json = WhisperJson.parse(JSON.parse(raw));
  const segments: Segment[] = [];
  for (const s of json.transcription) {
    const text = s.text.trim();
    if (!text || isSpecial(text)) continue;
    const words = s.tokens ? tokensToWords(s.tokens) : [];
    segments.push({
      id: nanoid(8),
      start: s.offsets.from / 1000,
      end: s.offsets.to / 1000,
      text: words.length ? words.map((w) => w.text).join(' ') : text,
      words,
    });
  }
  return { language: json.result?.language ?? 'ko', segments };
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

/** 순수 스폰 래퍼. 16k mono wav 로 바꾼 뒤 whisper-cli 를 돌린다. */
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
      await run(
        this.bins.whisper,
        ['-m', this.modelPath, '-f', wav, '-l', opts.language ?? 'ko', '-t', threads, '-ojf', '-of', prefix, '-np', '-pp'],
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
      const raw = fs.readFileSync(`${prefix}.json`, 'utf8');
      opts.onProgress?.(1);
      return parseWhisperJson(raw);
    } finally {
      fs.rmSync(wav, { force: true });
    }
  }
}
