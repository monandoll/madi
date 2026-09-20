import { parseScenes, parseSilences, sceneDetectArgs, silenceDetectArgs } from '@madi/ffmpeg-presets';
import type { Chapters, Video } from '@madi/shared';
import type { StyleProfile } from '../agent/style.js';
import type { ChapterStore } from '../chapters/store.js';
import { pickShorts, splitChapters, transcriptUsable } from '../chapters/split.js';
import type { EventLog } from '../events.js';
import type { Library } from '../library.js';
import type { Logger } from '../log.js';
import type { JobQueue } from '../queue/index.js';
import type { VideoStore } from '../videos.js';
import { runAnalysis } from './spawn.js';

export interface ChapterWorkerDeps {
  queue: JobQueue;
  videos: VideoStore;
  library: Library;
  chapters: ChapterStore;
  style: StyleProfile;
  ffmpegBin: string;
  events: EventLog;
  log: Logger;
}

/**
 * 6단계 롱폼 워커: chapters 잡.
 * 자막이 없고 소리가 있으면 먼저 자막을 만들고(기다림), 무음·장면과 합쳐 챕터를 나눈다.
 * then='shorts' 면 챕터마다 하이라이트 구간으로 세로 숏폼 렌더를 건다 (카드는 렌더 워커가 붙인다).
 */
export function registerChapterWorkers(d: ChapterWorkerDeps): void {
  d.queue.register('chapters', async ({ job, signal, setProgress }) => {
    const video = d.videos.mustGet(job.videoId!);
    const payload = job.payload as { type: 'chapters'; videoId: string; then: 'none' | 'shorts'; max: number };
    const started = Date.now();
    try {
      const chapters = await computeChapters(d, video, signal, setProgress);
      const m = d.library.messageForJob(job.id);
      if (payload.then === 'shorts') {
        const picks = pickShorts(chapters.items, payload.max);
        if (picks.length === 0) throw new Error('nothing to render');
        const transcript = d.library.transcriptOf(video.id);
        let n = d.library.shortEditCount(video.id);
        if (m) d.library.updateMessage(m.id, { kind: 'chapters', code: 'chapters.shorts', params: { ...m.params, count: chapters.items.length, shorts: picks.length } });
        for (const pick of picks) {
          n += 1;
          const edit = d.library.createEdit({
            videoId: video.id,
            title: `${video.title} · 숏폼 ${n} · ${pick.title}`,
            keep: pick.range,
            cuts: [],
            crop: 'vertical',
            subtitles: !!transcript,
            transcriptId: transcript?.id ?? null,
            subtitleStyle: d.style.params().subtitleStyle,
            speed: [],
          });
          const render = d.queue.enqueue({ type: 'render', videoId: video.id, editId: edit.id });
          d.library.say({ videoId: video.id, role: 'assistant', kind: 'progress', code: 'progress.render', jobId: render.id, params: { step: 'render', action: 'short', title: pick.title } });
        }
      } else if (m) {
        d.library.updateMessage(m.id, { kind: 'chapters', code: 'chapters.ready', params: { ...m.params, count: chapters.items.length } });
      }
      d.events.record('chapters.made', { count: chapters.items.length, fromTranscript: chapters.fromTranscript, then: payload.then, durationSec: video.durationSec }, Date.now() - started);
    } catch (err) {
      const m = d.library.messageForJob(job.id);
      if (m) d.library.updateMessage(m.id, { kind: 'error', code: chapterErrorCode(err), params: { ...m.params, detail: String(err).slice(0, 200) } });
      throw err;
    }
  });
}

export function chapterErrorCode(err: unknown): string {
  const msg = err instanceof Error ? err.message : String(err);
  if (/nothing to render/i.test(msg)) return 'nothing_left';
  if (/too short/i.test(msg)) return 'too_short_for_chapters';
  return 'edit_failed';
}

/** 챕터 계산 (자막 있으면 자막까지 기다린 뒤). 저장하고 돌려준다. */
export async function computeChapters(d: ChapterWorkerDeps, video: Video, signal: AbortSignal, setProgress?: (r: number) => void): Promise<Chapters> {
  const duration = video.durationSec ?? 0;
  if (duration < 30) throw new Error('too short');
  let transcript = d.library.transcriptOf(video.id);
  if (!transcript && video.hasAudio !== false) {
    const t = d.queue.enqueue({ type: 'transcribe', videoId: video.id });
    await waitJob(d.queue, t.id, signal);
    transcript = d.library.transcriptOf(video.id);
  }
  setProgress?.(0.4);
  let silences: { start: number; end: number }[] = [];
  if (video.hasAudio !== false) {
    const { stderr } = await runAnalysis(d.ffmpegBin, silenceDetectArgs(video.path, { minSec: Math.max(1, d.style.params().silenceMinSec) }), { signal });
    silences = parseSilences(stderr, duration);
  }
  setProgress?.(0.6);
  const scenes = parseScenes((await runAnalysis(d.ffmpegBin, sceneDetectArgs(video.path, 0.4), { signal })).stderr);
  setProgress?.(0.9);
  const segments = transcript?.segments ?? [];
  const items = splitChapters({ segments, silences, scenes, durationSec: duration });
  return d.chapters.set(video.id, items, transcriptUsable(segments, duration));
}

async function waitJob(queue: JobQueue, jobId: string, signal: AbortSignal): Promise<void> {
  const until = Date.now() + 30 * 60_000;
  while (Date.now() < until) {
    if (signal.aborted) throw new Error('aborted');
    const j = queue.get(jobId);
    if (!j) throw new Error('job vanished');
    if (j.status === 'done') return;
    if (j.status === 'failed' || j.status === 'canceled') {
      // 자막을 못 만들어도 챕터는 장면·무음으로 나눈다
      return;
    }
    await new Promise((r) => setTimeout(r, 250));
  }
  throw new Error('timeout');
}
