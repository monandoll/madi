import fs from 'node:fs';
import path from 'node:path';
import { keepSegments, type Edit, type Video, type VideoFramesRequest, type VideoFramesSummary } from '@madi/shared';
import { contactSheetArgs } from '@madi/ffmpeg-presets';
import { run } from './spawn.js';

/** 표본 시각을 결과물의 남는 구간 위에서 고르게 고른다. 원본·결과 시각을 함께 유지한다. */
export function inspectionSamples(duration: number, edit: Edit | null, request: VideoFramesRequest) {
  const kept = edit ? keepSegments(edit, duration) : [{ start: 0, end: duration }];
  let outputStart = 0;
  const spans = kept.map(span => {
    const offset = outputStart;
    outputStart += span.end - span.start;
    const start = Math.max(span.start, request.range?.start ?? 0);
    const end = Math.min(span.end, request.range?.end ?? duration);
    return { start, end, outputStart: offset + start - span.start };
  }).filter(span => span.end > span.start);
  const total = spans.reduce((sum, span) => sum + span.end - span.start, 0);
  if (!total) throw new Error('선택한 범위에 남는 영상이 없습니다.');
  const pad = Math.min(0.05, total / 4);
  return Array.from({ length: request.count }, (_, i) => {
    let at = pad + i * (total - pad * 2) / (request.count - 1);
    for (const span of spans) {
      const length = span.end - span.start;
      if (at < length) return { sourceTime: span.start + at, outputTime: span.outputStart + at };
      at -= length;
    }
    throw new Error('화면 시각을 정하지 못했습니다.');
  });
}

export async function inspectVideoFrames(opts: { ffmpegBin: string; workDir: string; video: Video; edit: Edit | null; request: VideoFramesRequest; signal?: AbortSignal | undefined }) {
  const duration = opts.video.durationSec ?? 0;
  if (duration <= 0 || (opts.request.range && opts.request.range.end > duration)) throw new Error('영상 길이 안에서 확인할 구간을 정하세요.');
  const samples = inspectionSamples(duration, opts.edit, opts.request);
  fs.mkdirSync(opts.workDir, { recursive: true });
  const dir = fs.mkdtempSync(path.join(opts.workDir, 'vision-'));
  const sheets: VideoFramesSummary['sheets'] = [];
  const images: { data: string; mimeType: 'image/jpeg' }[] = [];
  const timeout = AbortSignal.timeout(90_000);
  const signal = opts.signal ? AbortSignal.any([opts.signal, timeout]) : timeout;
  try {
    for (let i = 0; i < samples.length; i += 4) {
      signal.throwIfAborted();
      const frames = samples.slice(i, i + 4);
      const output = path.join(dir, `sheet-${i}.jpg`);
      await run(opts.ffmpegBin, contactSheetArgs({ input: opts.video.path, output, times: frames.map(f => f.sourceTime), cols: 2, tileWidth: 512 }), { signal });
      images.push({ data: fs.readFileSync(output).toString('base64'), mimeType: 'image/jpeg' });
      sheets.push({ columns: 2, frames });
    }
    const summary: VideoFramesSummary = {
      videoId: opts.video.id, editId: opts.edit?.id ?? null, sourceDurationSec: duration, sheets,
      note: '이미지는 원본 화면 표본이며 새로 생성한 자막이나 크롭을 덧씌우지 않았다. 각 이미지의 칸은 왼쪽→오른쪽, 위→아래 순서다. 보이는 움직임만 설명하고 운동 이름·목적·효과·횟수·주의사항은 화면만으로 단정하지 않는다. 불명확한 전환은 좁은 원본 range로 재확인한다. set_subtitle_text에는 sourceTime 기준을 사용한다.',
    };
    return { summary, images };
  } finally {
    await fs.promises.rm(dir, { recursive: true, force: true, maxRetries: 3, retryDelay: 100 });
  }
}
