import fs from 'node:fs';
import path from 'node:path';
import { nanoid } from 'nanoid';
import { kindFromDuration, keepSegments, type Edit, type TimeRange, type Video } from '@madi/shared';
import {
  buildAss,
  chooseCropFocus,
  chooseSubtitleSide,
  motionDetectArgs,
  motionLevelIn,
  motionRegionsArgs,
  parseMotion,
  parseSilences,
  regionsFor,
  renderPlan,
  silenceDetectArgs,
  silencesToCuts,
  splitSilencesByMotion,
  SUBTITLE_TOP_MARGIN,
  ProgressParser,
  type MotionSample,
} from '@madi/ffmpeg-presets';
import type { EngineConfig } from '../config.js';
import type { EventLog } from '../events.js';
import type { Library } from '../library.js';
import type { Logger } from '../log.js';
import type { JobQueue } from '../queue/index.js';
import type { VideoStore } from '../videos.js';
import type { StyleProfile } from '../agent/style.js';
import type { Ffmpeg } from './ffmpeg.js';
import { run } from './spawn.js';
import type { Whisper } from './whisper.js';
import { termsPrompt, WhisperMissingError } from './whisper.js';
import { applyCorrections, type CorrectionPair } from '../style/corrections.js';

export interface EditWorkerDeps {
  cfg: EngineConfig;
  queue: JobQueue;
  videos: VideoStore;
  library: Library;
  ffmpeg: Ffmpeg;
  ffmpegBin: string;
  whisper: () => Promise<Whisper>;
  /** 무음 기준(초)은 완성본에서 배운 값을 따른다 */
  style: StyleProfile;
  /** 자막을 만들 때 whisper 에 알려 줄 운동 · 해부학 용어 (기억 · 완성본 · 편집안 · 고친 말에서). 없으면 빈 목록. */
  terms?: (videoId: string) => string[];
  /** 반복해서 고친 말 — whisper 결과에서 바로 바꾼다 (기획안 §5.2). 없으면 안 바꾼다. */
  corrections?: () => CorrectionPair[];
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
      const result = await whisper.transcribe(video.path, work, { signal, onProgress: setProgress, prompt: termsPrompt(d.terms?.(video.id) ?? []) });
      fs.rmSync(work, { recursive: true, force: true });
      // 전에 두 번 이상 고친 말은 바로 바꿔 쓴다
      const fixed = applyCorrections(result.segments, d.corrections?.() ?? []);
      const transcript = library.setTranscript(video.id, { language: result.language, segments: fixed.segments, model: whisper.model });
      d.events.record('transcript.made', { segments: transcript.segments.length, corrected: fixed.replaced, durationSec: video.durationSec }, Date.now() - started);
      const m = library.messageForJob(job.id);
      const payload = job.payload as { type: 'transcribe'; videoId: string; renderEditId?: string | null };
      if (payload.renderEditId) {
        // 자막을 쓰는 렌더가 기다리고 있다 → 같은 메시지를 렌더 잡으로 넘긴다
        library.updateEdit(payload.renderEditId, { transcriptId: transcript.id });
        const render = queue.enqueue({ type: 'render', videoId: video.id, editId: payload.renderEditId });
        if (m) library.updateMessage(m.id, { jobId: render.id, code: 'progress.render', params: { ...m.params, step: 'render' } });
      } else if (m) {
        library.updateMessage(m.id, { kind: 'text', code: transcript.segments.length ? 'transcript.ready' : 'transcript.empty', params: { segments: transcript.segments.length } });
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
      const duration = video.durationSec ?? 0;
      const { stderr } = await run(d.ffmpegBin, silenceDetectArgs(video.path, { minSec: d.style.params().silenceMinSec }), { signal });
      const silences = parseSilences(stderr, duration);
      // 말은 없지만 동작이 이어지는 침묵(시범)은 남긴다 — 기획안 §5.1
      const { cut, kept } = await splitByMotion(d, video.path, silences, duration, signal);
      const cuts = silencesToCuts(cut, duration);
      const payload = job.payload as { type: 'silence'; videoId: string; editId?: string };
      const editId = payload.editId!;
      library.updateEdit(editId, { cuts });
      const m = library.messageForJob(job.id);
      if (cuts.length === 0) {
        if (m) library.updateMessage(m.id, { kind: 'text', code: 'silence.none', params: { kept: kept.length } });
        return;
      }
      const removed = cuts.reduce((a, c) => a + (c.end - c.start), 0);
      const render = queue.enqueue({ type: 'render', videoId: video.id, editId });
      if (m) library.updateMessage(m.id, { jobId: render.id, code: 'progress.render', params: { ...m.params, step: 'render', cuts: cuts.length, removedSec: Math.round(removed), kept: kept.length } });
    } catch (err) {
      fail(job.id, err);
      throw err;
    }
  });

  queue.register('render', async ({ job, signal, setProgress }) => {
    const video = videos.mustGet(job.videoId!);
    const payload = job.payload as { type: 'render'; videoId: string; editId: string };
    let edit = library.edit(payload.editId);
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
      const transcript = edit.subtitles ? (edit.transcriptId && library.transcript(edit.transcriptId)) || library.transcriptOf(video.id) : null;
      // 세로 초점 · 자막 위치를 아직 안 정했으면 화면의 어느 쪽이 움직이는지 보고 정해 Edit 에 적는다 (기획안 §5.4 · §5.5)
      const placed = await placeEdit(d, video, edit, segments, !!transcript, path.join(cfg.dataDir, 'work', job.id), signal);
      edit = placed.edit;
      let subtitleFile: string | undefined;
      if (transcript) {
        const vertical = edit.crop === 'vertical';
        const frame = vertical ? { width: 1080, height: 1920 } : { width: video.width ?? 1920, height: video.height ?? 1080 };
        fs.writeFileSync(assPath, buildAss(transcript.segments, segments, edit.subtitleStyle, frame, edit.emphasis), 'utf8');
        subtitleFile = assPath;
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
        fontsDir: fs.existsSync(cfg.fontsDir) ? cfg.fontsDir : undefined,
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
      d.events.record(
        'output.made',
        { crop: edit.crop, subtitles: edit.subtitles, cuts: edit.cuts.length, parts: edit.parts.length, focus: placed.focus, subtitleTop: placed.subtitleTop, durationSec: meta.durationSec },
        Date.now() - started,
      );
      const m = library.messageForJob(job.id);
      if (m)
        library.updateMessage(m.id, {
          kind: 'output',
          code: 'output.ready',
          outputId: output.id,
          params: { ...m.params, title: output.title, durationSec: Math.round(output.durationSec), ...(placed.focus ? { focus: placed.focus } : {}), ...(placed.subtitleTop ? { subtitleTop: true } : {}) },
        });
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

/**
 * 무음 구간을 "가만히 있던 침묵"과 "동작이 이어지는 침묵"으로 나눈다.
 * 화면을 못 읽으면(ffmpeg 오류) 전부 자르는 쪽으로 — 전과 같은 동작이고, 자르기 자체는 막지 않는다.
 */
export async function splitByMotion(
  d: Pick<EditWorkerDeps, 'ffmpegBin' | 'log'>,
  input: string,
  silences: { start: number; end: number }[],
  durationSec: number,
  signal?: AbortSignal,
): Promise<{ cut: { start: number; end: number }[]; kept: { start: number; end: number }[] }> {
  if (silences.length === 0) return { cut: [], kept: [] };
  try {
    const { stderr } = await run(d.ffmpegBin, motionDetectArgs(input), signal ? { signal } : {});
    const r = splitSilencesByMotion(silences, parseMotion(stderr), durationSec);
    if (r.kept.length) d.log.info({ kept: r.kept.length, speechLevel: r.speechLevel }, 'silences kept for motion');
    return { cut: r.cut, kept: r.kept };
  } catch (err) {
    if (signal?.aborted) throw err;
    d.log.warn({ err: String(err) }, 'motion pass failed; cutting all silences');
    return { cut: silences, kept: [] };
  }
}

export type FocusSide = 'left' | 'center' | 'right';

export interface Placement {
  edit: Edit;
  /** 이번 렌더에서 자동으로 고른 세로 초점 (가운데면 null — 말할 게 없다) */
  focus: FocusSide | null;
  /** 자막을 위로 올렸는지 */
  subtitleTop: boolean;
}

const focusSide = (f: number): FocusSide => (f < 0.25 ? 'left' : f > 0.75 ? 'right' : 'center');

/**
 * 세로 초점(cropFocus 가 null) · 자막 위치(subtitleAuto) 를 화면의 움직임으로 정한다 — 한 번 훑는다.
 * 정한 값은 Edit 에 적는다: 다음에 같은 Edit 로 렌더해도 같은 결과가 나와야 하니까.
 * 화면을 못 읽으면(ffmpeg 오류) 가운데 · 아래 — 전과 같은 동작이고, 그것도 적는다.
 */
export async function placeEdit(
  d: Pick<EditWorkerDeps, 'ffmpegBin' | 'log' | 'library'>,
  video: Pick<Video, 'path' | 'width' | 'height'>,
  edit: Edit,
  segments: TimeRange[],
  hasTranscript: boolean,
  workDir: string,
  signal?: AbortSignal,
): Promise<Placement> {
  const width = video.width ?? 1920;
  const height = video.height ?? 1080;
  const horizontal = width > height;
  const needFocus = edit.crop === 'vertical' && horizontal && edit.cropFocus === null;
  const needSide = edit.subtitles && hasTranscript && edit.subtitleAuto;
  if (!needFocus && !needSide) return { edit, focus: null, subtitleTop: false };

  const levels = await measureRegions(d, video.path, width, height, segments, workDir, signal);
  const at = (name: string) => levels.get(name) ?? null;
  const col = (c: string) => avg([at(`${c}.top`), at(`${c}.bottom`)]);

  const patch: Partial<Pick<Edit, 'cropFocus' | 'subtitleAuto' | 'subtitleStyle'>> = {};
  let focus: FocusSide | null = null;
  let cropFocus = edit.cropFocus;
  if (needFocus) {
    cropFocus = levels.size ? chooseCropFocus({ left: col('left'), center: col('center'), right: col('right') }) : 0.5;
    patch.cropFocus = cropFocus;
    if (cropFocus !== 0.5) focus = focusSide(cropFocus);
  }
  let subtitleTop = false;
  if (needSide) {
    // 세로로 자르면 잡히는 기둥만, 아니면 화면 전체(기둥 평균)
    let bands: { top: number | null; bottom: number | null };
    if (!horizontal) bands = { top: at('top'), bottom: at('bottom') };
    else if (edit.crop === 'vertical' && cropFocus !== null) {
      const c = focusSide(cropFocus);
      bands = { top: at(`${c}.top`), bottom: at(`${c}.bottom`) };
    } else bands = { top: avg([at('left.top'), at('center.top'), at('right.top')]), bottom: avg([at('left.bottom'), at('center.bottom'), at('right.bottom')]) };
    subtitleTop = levels.size ? chooseSubtitleSide(bands) === 'top' : false;
    patch.subtitleAuto = false;
    if (subtitleTop) patch.subtitleStyle = { ...edit.subtitleStyle, bottom: SUBTITLE_TOP_MARGIN };
  }
  const updated = d.library.updateEdit(edit.id, patch);
  if (focus || subtitleTop) d.log.info({ edit: edit.id, focus, subtitleTop }, 'placement chosen');
  return { edit: updated, focus, subtitleTop };
}

function avg(xs: (number | null)[]): number | null {
  const v = xs.filter((x): x is number => x !== null);
  return v.length ? v.reduce((a, b) => a + b, 0) / v.length : null;
}

/** 조각(기둥 × 띠)마다 남는 구간 안의 평균 움직임. 못 읽으면 빈 맵. */
async function measureRegions(
  d: Pick<EditWorkerDeps, 'ffmpegBin' | 'log'>,
  input: string,
  width: number,
  height: number,
  segments: TimeRange[],
  workDir: string,
  signal?: AbortSignal,
): Promise<Map<string, number | null>> {
  const regions = regionsFor(width, height);
  const files = regions.map((r) => path.join(workDir, `motion-${r.name}.txt`));
  const out = new Map<string, number | null>();
  try {
    fs.mkdirSync(workDir, { recursive: true });
    await run(d.ffmpegBin, motionRegionsArgs(input, regions, files), signal ? { signal } : {});
    regions.forEach((r, i) => {
      const samples: MotionSample[] = fs.existsSync(files[i]!) ? parseMotion(fs.readFileSync(files[i]!, 'utf8')) : [];
      out.set(r.name, motionLevelIn(samples, segments));
    });
  } catch (err) {
    if (signal?.aborted) throw err;
    d.log.warn({ err: String(err) }, 'region motion pass failed; center / bottom');
    out.clear();
  } finally {
    fs.rmSync(workDir, { recursive: true, force: true });
  }
  return out;
}
