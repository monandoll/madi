import fs from 'node:fs';
import path from 'node:path';
import { nanoid } from 'nanoid';
import { kindFromDuration, keepSegments, type Video } from '@madi/shared';
import { buildAss, parseSilences, renderPlan, silenceDetectArgs, silencesToCuts, ProgressParser } from '@madi/ffmpeg-presets';
import type { EngineConfig } from '../config.js';
import type { EventLog } from '../events.js';
import type { Library } from '../library.js';
import type { Logger } from '../log.js';
import type { JobQueue } from '../queue/index.js';
import type { VideoStore } from '../videos.js';
import type { Ffmpeg } from './ffmpeg.js';
import { run } from './spawn.js';
import type { Whisper } from './whisper.js';
import { WhisperMissingError } from './whisper.js';

export interface EditWorkerDeps {
  cfg: EngineConfig;
  queue: JobQueue;
  videos: VideoStore;
  library: Library;
  ffmpeg: Ffmpeg;
  ffmpegBin: string;
  whisper: () => Promise<Whisper>;
  events: EventLog;
  log: Logger;
}

/** UI 문구는 copy.ts 가 코드로 고른다. */
export function editErrorCode(err: unknown): string {
  if (err instanceof WhisperMissingError) return err.message.includes('model') ? 'whisper_model_missing' : 'whisper_missing';
  const msg = err instanceof Error ? err.message : String(err);
  if (/model download failed|fetch failed/i.test(msg)) return 'whisper_model_missing';
  if (/whisper-cli.*ENOENT|ENOENT.*whisper/i.test(msg)) return 'whisper_missing';
  if (/nothing to render/i.test(msg)) return 'nothing_left';
  if (/no audio|Output file is empty|does not contain any stream/i.test(msg)) return 'no_audio';
  if (/ENOENT/.test(msg) && /ffmpeg/.test(msg)) return 'ffmpeg_missing';
  return 'edit_failed';
}

/**
 * 2단계 워커: transcribe(whisper) · silence(ffmpeg) · render(ffmpeg).
 * 각 잡은 progress 메시지를 갱신하고, 끝나면 output / error 메시지로 바꾼다.
 */
export function registerEditWorkers(d: EditWorkerDeps): void {
  const { cfg, queue, videos, library, ffmpeg, log } = d;

  const fail = (jobId: string, err: unknown) => {
    const code = editErrorCode(err);
    const m = library.messageForJob(jobId);
    if (m) library.updateMessage(m.id, { kind: 'error', code, params: { ...m.params, detail: err instanceof Error ? err.message.slice(0, 200) : String(err) } });
  };

  queue.register('transcribe', async ({ job, signal, setProgress }) => {
    const video = videos.mustGet(job.videoId!);
    const started = Date.now();
    try {
      if (video.hasAudio === false) throw new Error('no audio');
      const whisper = await d.whisper();
      const work = path.join(cfg.dataDir, 'work', job.id);
      const result = await whisper.transcribe(video.path, work, { signal, onProgress: setProgress });
      fs.rmSync(work, { recursive: true, force: true });
      const transcript = library.setTranscript(video.id, { ...result, model: whisper.model });
      d.events.record('transcript.made', { segments: transcript.segments.length, durationSec: video.durationSec }, Date.now() - started);
      const m = library.messageForJob(job.id);
      const payload = job.payload as { type: 'transcribe'; videoId: string; renderEditId?: string | null };
      if (payload.renderEditId) {
        // 자막을 쓰는 렌더가 기다리고 있다 → 같은 메시지를 렌더 잡으로 넘긴다
        library.updateEdit(payload.renderEditId, { transcriptId: transcript.id });
        const render = queue.enqueue({ type: 'render', videoId: video.id, editId: payload.renderEditId });
        if (m) library.updateMessage(m.id, { jobId: render.id, code: 'progress.render', params: { ...m.params, step: 'render' } });
      } else if (m) {
        library.updateMessage(m.id, { kind: 'text', code: 'transcript.ready', params: { segments: transcript.segments.length } });
      }
    } catch (err) {
      fail(job.id, err);
      throw err;
    }
  });

  queue.register('silence', async ({ job, signal }) => {
    const video = videos.mustGet(job.videoId!);
    try {
      if (video.hasAudio === false) throw new Error('no audio');
      const { stderr } = await run(d.ffmpegBin, silenceDetectArgs(video.path), { signal });
      const silences = parseSilences(stderr, video.durationSec ?? 0);
      const cuts = silencesToCuts(silences, video.durationSec ?? 0);
      const payload = job.payload as { type: 'silence'; videoId: string; editId?: string };
      const editId = payload.editId!;
      library.updateEdit(editId, { cuts });
      const m = library.messageForJob(job.id);
      if (cuts.length === 0) {
        if (m) library.updateMessage(m.id, { kind: 'text', code: 'silence.none', params: {} });
        return;
      }
      const removed = cuts.reduce((a, c) => a + (c.end - c.start), 0);
      const render = queue.enqueue({ type: 'render', videoId: video.id, editId });
      if (m) library.updateMessage(m.id, { jobId: render.id, code: 'progress.render', params: { ...m.params, step: 'render', cuts: cuts.length, removedSec: Math.round(removed) } });
    } catch (err) {
      fail(job.id, err);
      throw err;
    }
  });

  queue.register('render', async ({ job, signal, setProgress }) => {
    const video = videos.mustGet(job.videoId!);
    const payload = job.payload as { type: 'render'; videoId: string; editId: string };
    const edit = library.edit(payload.editId);
    if (!edit) throw new Error(`edit not found: ${payload.editId}`);
    const outDir = path.join(cfg.dataDir, 'outputs');
    fs.mkdirSync(outDir, { recursive: true });
    const outId = nanoid(); // 결과물 id = 파일 이름. 미리 정해 둔다.
    const outPath = path.join(outDir, `${outId}.mp4`);
    const tmp = `${outPath}.part.mp4`;
    const assPath = path.join(outDir, `${outId}.ass`);
    const started = Date.now();
    try {
      const encoder = await ffmpeg.detectEncoder();
      const duration = video.durationSec ?? 0;
      const segments = keepSegments(edit, duration);
      let subtitleFile: string | undefined;
      if (edit.subtitles) {
        const transcript = (edit.transcriptId && library.transcript(edit.transcriptId)) || library.transcriptOf(video.id);
        if (transcript) {
          const vertical = edit.crop === 'vertical';
          const frame = vertical ? { width: 1080, height: 1920 } : { width: video.width ?? 1920, height: video.height ?? 1080 };
          fs.writeFileSync(assPath, buildAss(transcript.segments, segments, edit.subtitleStyle, frame), 'utf8');
          subtitleFile = assPath;
        }
      }
      const plan = renderPlan({
        input: video.path,
        output: tmp,
        edit,
        durationSec: duration,
        width: video.width ?? 1920,
        height: video.height ?? 1080,
        hasAudio: video.hasAudio ?? true,
        encoder,
        subtitleFile,
      });
      const parser = new ProgressParser(plan.durationSec, setProgress);
      await run(d.ffmpegBin, plan.args, { signal, onStdout: (c) => parser.feed(c) });
      fs.renameSync(tmp, outPath);
      const meta = await ffmpeg.probe(outPath);
      const output = library.addOutput(
        {
        videoId: video.id,
        editId: edit.id,
        title: edit.title,
        kind: edit.crop === 'vertical' || edit.keep ? 'short' : kindFromDuration(meta.durationSec),
        path: outPath,
        durationSec: meta.durationSec,
        width: meta.width,
        height: meta.height,
        sizeBytes: fs.statSync(outPath).size,
        },
        outId,
      );
      await ffmpeg.thumbnail({ input: outPath, output: path.join(outDir, `${output.id}.jpg`), durationSec: meta.durationSec }).catch(() => {});
      d.events.record('output.made', { crop: edit.crop, subtitles: edit.subtitles, cuts: edit.cuts.length, durationSec: meta.durationSec }, Date.now() - started);
      const m = library.messageForJob(job.id);
      if (m) library.updateMessage(m.id, { kind: 'output', code: 'output.ready', outputId: output.id, params: { ...m.params, title: output.title, durationSec: Math.round(output.durationSec) } });
      log.info({ output: output.id, ms: Date.now() - started }, 'output ready');
    } catch (err) {
      fs.rmSync(tmp, { force: true });
      fail(job.id, err);
      throw err;
    } finally {
      fs.rmSync(assPath, { force: true });
    }
  });
}

/** 결과물 파일 위치. Library 는 path 를 저장하지만 썸네일은 규칙으로 찾는다. */
export function outputThumbnailPath(cfg: EngineConfig, outputId: string): string {
  return path.join(cfg.dataDir, 'outputs', `${outputId}.jpg`);
}

export function videoLabel(v: Video): string {
  return v.title;
}
