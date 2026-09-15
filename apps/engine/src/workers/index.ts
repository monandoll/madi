import fs from 'node:fs';
import path from 'node:path';
import { kindFromDuration } from '@madi/shared';
import type { EngineConfig } from '../config.js';
import type { EventLog } from '../events.js';
import type { Logger } from '../log.js';
import type { JobQueue } from '../queue/index.js';
import type { VideoStore } from '../videos.js';
import type { Ffmpeg } from './ffmpeg.js';

export interface WorkerDeps {
  cfg: EngineConfig;
  queue: JobQueue;
  videos: VideoStore;
  ffmpeg: Ffmpeg;
  events: EventLog;
  log: Logger;
}

/**
 * probe → (thumbnail, proxy) → ready.
 * 각 핸들러는 파일을 만들고 VideoStore 로 상태를 갱신한다.
 */
export function registerMediaWorkers({ cfg, queue, videos, ffmpeg, events, log }: WorkerDeps): void {
  queue.register('probe', async ({ job, signal }) => {
    const video = videos.mustGet(job.videoId!);
    const started = Date.now();
    try {
      const meta = await ffmpeg.probe(video.path, signal);
      videos.update(video.id, {
        durationSec: meta.durationSec,
        width: meta.width,
        height: meta.height,
        fps: meta.fps,
        hasAudio: meta.hasAudio,
        kind: kindFromDuration(meta.durationSec),
        status: 'preparing',
        error: null,
      });
      events.record('video.probed', { kind: kindFromDuration(meta.durationSec), durationSec: meta.durationSec }, Date.now() - started);
      queue.enqueue({ type: 'thumbnail', videoId: video.id });
      queue.enqueue({ type: 'proxy', videoId: video.id });
    } catch (err) {
      videos.update(video.id, { status: 'failed', error: errorCode(err) });
      throw err;
    }
  });

  queue.register('thumbnail', async ({ job, signal }) => {
    const video = videos.mustGet(job.videoId!);
    const output = path.join(cfg.thumbsDir, `${video.id}.jpg`);
    await ffmpeg.thumbnail({ input: video.path, output, durationSec: video.durationSec ?? 0 }, signal);
    videos.update(video.id, { thumbnailPath: output });
    videos.markReadyIfComplete(video.id);
  });

  queue.register('proxy', async ({ job, signal, setProgress }) => {
    const video = videos.mustGet(job.videoId!);
    const output = path.join(cfg.proxiesDir, `${video.id}.mp4`);
    const started = Date.now();
    try {
      await ffmpeg.proxy(
        { input: video.path, output, durationSec: video.durationSec ?? 0, hasAudio: video.hasAudio ?? true },
        setProgress,
        signal,
      );
      const meta = await ffmpeg.probe(output);
      videos.setProxy(video.id, { path: output, width: meta.width, height: meta.height });
      videos.markReadyIfComplete(video.id);
      events.record('proxy.made', { durationSec: video.durationSec }, Date.now() - started);
      log.info({ video: video.id, ms: Date.now() - started }, 'proxy ready');
    } catch (err) {
      fs.rmSync(output, { force: true });
      videos.update(video.id, { status: 'failed', error: errorCode(err) });
      throw err;
    }
  });
}

/** UI 문구는 copy.ts 가 코드로 고른다. 여기서는 코드만 남긴다. */
function errorCode(err: unknown): string {
  const msg = err instanceof Error ? err.message : String(err);
  if (/no video stream/i.test(msg)) return 'no_video_stream';
  if (/no duration/i.test(msg)) return 'no_duration';
  if (/ENOENT/.test(msg) && /ffmpeg|ffprobe/.test(msg)) return 'ffmpeg_missing';
  if (/Invalid data found|moov atom not found/i.test(msg)) return 'unreadable';
  return 'media_failed';
}
