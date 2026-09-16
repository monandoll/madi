import fs from 'node:fs';
import path from 'node:path';
import { EventEmitter } from 'node:events';
import type { Reference, ReferenceStats, StyleResponse } from '@madi/shared';
import { parseScenes, parseSilences, sceneDetectArgs, silenceDetectArgs } from '@madi/ffmpeg-presets';
import type { StyleProfile } from '../agent/style.js';
import type { EngineConfig } from '../config.js';
import type { EventLog } from '../events.js';
import type { Library } from '../library.js';
import type { Logger } from '../log.js';
import type { JobQueue } from '../queue/index.js';
import type { SettingsStore } from '../settings.js';
import type { VideoStore } from '../videos.js';
import type { Ffmpeg } from '../workers/ffmpeg.js';
import { run } from '../workers/spawn.js';
import type { Whisper } from '../workers/whisper.js';
import { aggregate, aspectOf, learnedRuleLines, looksLikeSameVideo, pairDiff } from './learn.js';
import type { ReferenceStore } from './references.js';
import { scanReferenceFolders } from './scan.js';

export interface StyleServiceDeps {
  cfg: EngineConfig;
  settings: SettingsStore;
  refs: ReferenceStore;
  queue: JobQueue;
  videos: VideoStore;
  library: Library;
  style: StyleProfile;
  ffmpeg: Ffmpeg;
  ffmpegBin: string;
  whisper: () => Promise<Whisper>;
  events: EventLog;
  log: Logger;
}

export interface StyleServiceEvents {
  'style.updated': [];
}

/**
 * 5단계 스타일 학습.
 * 완성본 폴더 → 파일 등록 → analyze 잡(길이·비율·남은 무음·장면 전환, 짝이 있으면 자막 diff) → 합쳐서 style.md 학습 블록 + params.
 */
export class StyleService extends EventEmitter<StyleServiceEvents> {
  constructor(private readonly d: StyleServiceDeps) {
    super();
  }

  /** 설정의 완성본 폴더를 훑어 새 파일은 분석에 넣고, 사라진 것은 missing. 끝에 다시 배운다. */
  refresh(opts: { retryFailed?: boolean } = {}): void {
    const folders = this.d.settings.get().referenceFolders;
    const files = scanReferenceFolders(folders);
    const present = new Set(files);
    for (const file of files) {
      const { ref, changed } = this.d.refs.upsertFromFile(file);
      if (changed || (opts.retryFailed && ref.status === 'failed')) {
        if (ref.status !== 'queued') this.d.refs.update(ref.id, { status: 'queued', error: null });
        this.d.queue.enqueue({ type: 'analyze', referenceId: ref.id });
      }
    }
    this.d.refs.markMissingExcept(present);
    this.relearn();
  }

  /** 분석이 끝난 완성본들을 합쳐 style.md 의 학습 블록과 params 를 갱신한다. */
  relearn(): void {
    const stats = this.d.refs
      .list()
      .filter((r) => r.status === 'done' && r.stats)
      .map((r) => r.stats!);
    const learned = aggregate(stats);
    const before = JSON.stringify(this.d.style.params().learned);
    this.d.style.setLearned(learned, learned ? learnedRuleLines(learned) : []);
    if (JSON.stringify(learned) !== before) this.d.events.record('style.learned', { count: learned?.count ?? 0 });
    this.emit('style.updated');
  }

  response(): StyleResponse {
    const p = this.d.style.params();
    return {
      rules: this.d.style.rulesList(),
      learned: p.learned,
      references: this.d.refs.list().filter((r) => r.status !== 'missing'),
      subtitleStyle: p.subtitleStyle,
      silenceMinSec: p.silenceMinSec,
    };
  }

  registerWorker(): void {
    this.d.queue.register('analyze', async ({ job, signal }) => {
      const payload = job.payload as { type: 'analyze'; referenceId: string };
      const ref = this.d.refs.get(payload.referenceId);
      if (!ref || ref.status === 'missing') return;
      if (!fs.existsSync(ref.path)) {
        this.d.refs.update(ref.id, { status: 'missing' });
        return;
      }
      this.d.refs.update(ref.id, { status: 'analyzing', error: null });
      const started = Date.now();
      try {
        const stats = await this.analyze(ref, signal);
        this.d.refs.update(ref.id, { status: 'done', stats, error: null });
        this.d.events.record('reference.analyzed', { aspect: stats.aspect, durationSec: stats.durationSec, paired: !!stats.pair }, Date.now() - started);
        this.relearn();
      } catch (err) {
        this.d.refs.update(ref.id, { status: 'failed', error: (err instanceof Error ? err.message : String(err)).slice(0, 200) });
        throw err;
      }
    });
  }

  private async analyze(ref: Reference, signal: AbortSignal): Promise<ReferenceStats> {
    const meta = await this.d.ffmpeg.probe(ref.path, signal);
    let silences: { start: number; end: number }[] = [];
    if (meta.hasAudio) {
      const { stderr } = await run(this.d.ffmpegBin, silenceDetectArgs(ref.path, { minSec: 0.3 }), { signal });
      silences = parseSilences(stderr, meta.durationSec);
    }
    const scenes = parseScenes((await run(this.d.ffmpegBin, sceneDetectArgs(ref.path, 0.4), { signal })).stderr);
    const minutes = Math.max(meta.durationSec / 60, 1 / 60);
    const pair = await this.pairWithSource(ref, meta.hasAudio, signal);
    return {
      durationSec: meta.durationSec,
      width: meta.width,
      height: meta.height,
      hasAudio: meta.hasAudio,
      aspect: aspectOf(meta.width, meta.height),
      silenceCount: silences.length,
      maxSilenceSec: Math.round(Math.max(0, ...silences.map((s) => s.end - s.start)) * 100) / 100,
      sceneCount: scenes.length,
      cutsPerMin: Math.round((scenes.length / minutes) * 10) / 10,
      pair,
    };
  }

  /**
   * 제목이 같은 원본이 갤러리에 있고 그 원본에 자막이 있으면, 완성본도 자막을 만들어 맞춰 본다.
   * whisper 가 없거나 짝이 없으면 null — 실패로 치지 않는다.
   */
  private async pairWithSource(ref: Reference, hasAudio: boolean, signal: AbortSignal) {
    if (!hasAudio) return null;
    const source = this.d.videos.listVisible().find((v) => v.status === 'ready' && looksLikeSameVideo(ref.title, v.title));
    if (!source) return null;
    const transcript = this.d.library.transcriptOf(source.id);
    if (!transcript) return null;
    try {
      let segments = this.d.refs.segmentsOf(ref.id);
      if (!segments) {
        const whisper = await this.d.whisper();
        const work = path.join(this.d.cfg.workDir, 'analyze', ref.id);
        const result = await whisper.transcribe(ref.path, work, { signal });
        fs.rmSync(work, { recursive: true, force: true });
        segments = result.segments;
        this.d.refs.update(ref.id, { segments });
      }
      return pairDiff(transcript.segments, segments, source.durationSec ?? 0, source.id);
    } catch (err) {
      this.d.log.debug({ ref: ref.id, err: String(err) }, 'pair skipped');
      return null;
    }
  }
}
