import fs from 'node:fs';
import path from 'node:path';
import { contactSheetArgs, frameSheets, pickFrameTimes } from '@madi/ffmpeg-presets';
import type { Logger } from '../log.js';
import { run } from './spawn.js';

/** 시트 한 장: 파일(절대 경로) · cwd 기준 상대 경로 · 칸 순서대로 시각. */
export interface FrameSheet {
  file: string;
  rel: string;
  times: number[];
}

/**
 * 대표 프레임 시트 만들기 (기획안 §10). dir 은 분석 cwd 아래 `sheets/` — Claude 는 그 폴더만 Read 로 열 수 있다.
 * 못 만들면(ffmpeg 오류 · 너무 짧은 영상) 빈 목록 — 화면 없이 간다, 실패로 치지 않는다.
 */
export async function makeFrameSheets(
  d: { ffmpegBin: string; log: Logger },
  input: string,
  opts: { durationSec: number; scenes: number[]; dir: string; signal?: AbortSignal | undefined },
): Promise<FrameSheet[]> {
  const times = pickFrameTimes(opts.durationSec, opts.scenes);
  if (!times.length) return [];
  fs.mkdirSync(opts.dir, { recursive: true });
  const out: FrameSheet[] = [];
  try {
    for (const [i, chunk] of frameSheets(times).entries()) {
      const file = path.join(opts.dir, `sheet-${i + 1}.jpg`);
      await run(d.ffmpegBin, contactSheetArgs({ input, output: file, times: chunk }), opts.signal ? { signal: opts.signal } : {});
      if (!fs.existsSync(file)) throw new Error('sheet not written');
      out.push({ file, rel: `./${path.basename(opts.dir)}/sheet-${i + 1}.jpg`, times: chunk });
    }
    return out;
  } catch (err) {
    if (opts.signal?.aborted) throw err;
    d.log.warn({ err: String(err) }, 'frame sheets failed; going without frames');
    return [];
  }
}
