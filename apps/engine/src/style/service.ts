import fs from 'node:fs';
import path from 'node:path';
import { EventEmitter } from 'node:events';
import { linkSiteLabel, normalizeVideoUrl, type Reference, type ReferenceStats, type StyleResponse } from '@madi/shared';
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
import { run, SpawnError } from '../workers/spawn.js';
import type { Whisper } from '../workers/whisper.js';
import { aggregate, aspectOf, learnedRuleLines, looksLikeSameVideo, pairDiff } from './learn.js';
import { classifyLinkError, parseYtdlpOutput, ytdlpArgs } from './link.js';
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
  /** yt-dlp. 없는 PC(개발)면 링크로 배우기가 꺼진다. */
  ytdlpBin: string;
  whisper: () => Promise<Whisper>;
  events: EventLog;
  log: Logger;
}

export class LinkError extends Error {
  constructor(readonly code: 'bad_link' | 'no_downloader') {
    super(code);
  }
}

export interface StyleServiceEvents {
  'style.updated': [];
}

/**
 * 5단계 스타일 학습.
 * 완성본 폴더 → 파일 등록 → analyze 잡(길이·비율·남은 무음·장면 전환, 짝이 있으면 자막 diff) → 합쳐서 style.md 학습 블록 + params.
 */
export class StyleService extends EventEmitter<StyleServiceEvents> {
  /** yt-dlp 가 이 PC 에 있는지. detectDownloader() 가 채운다. */
  private linkImport = false;

  constructor(private readonly d: StyleServiceDeps) {
    super();
  }

  /** yt-dlp --version 이 되면 링크로 배우기를 켠다. 기동 때 한 번 (몇 초 걸릴 수 있어 기다리지 않는다). */
  async detectDownloader(): Promise<boolean> {
    try {
      const { stdout } = await run(this.d.ytdlpBin, ['--version']);
      this.linkImport = stdout.trim().length > 0;
    } catch (err) {
      this.linkImport = false;
      this.d.log.debug({ err: String(err) }, 'yt-dlp not found');
    }
    this.emit('style.updated');
    return this.linkImport;
  }

  /** 설정의 완성본 폴더를 훑어 새 파일은 분석에 넣고, 사라진 것은 missing. 끝에 다시 배운다. 링크 완성본은 실패한 것만 다시. */
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
    if (opts.retryFailed) {
      for (const ref of this.d.refs.list()) {
        if (ref.source !== 'link' || ref.status !== 'failed') continue;
        this.d.refs.update(ref.id, { status: 'queued', error: null });
        this.d.queue.enqueue(fs.existsSync(ref.path) ? { type: 'analyze', referenceId: ref.id } : { type: 'download', referenceId: ref.id });
      }
    }
    this.relearn();
  }

  /**
   * 링크로 배우기: 주소를 등록하고 download 잡을 건다. 받고 나면 analyze 로 이어진다.
   * 주소가 아니면 bad_link, yt-dlp 가 없으면 no_downloader.
   */
  addLink(input: string): Reference {
    const url = normalizeVideoUrl(input);
    if (!url) throw new LinkError('bad_link');
    if (!this.linkImport) throw new LinkError('no_downloader');
    const { ref, changed } = this.d.refs.upsertFromLink(url, this.d.cfg.referencesDir);
    if (changed) {
      this.d.queue.enqueue({ type: 'download', referenceId: ref.id });
      this.d.events.record('reference.linked', { site: linkSiteLabel(url) });
    }
    return ref;
  }

  /** 완성본 하나 빼기 (링크 완성본은 받은 파일도). 배운 값을 다시 계산한다. */
  removeReference(id: string): boolean {
    const ref = this.d.refs.remove(id);
    if (!ref) return false;
    this.relearn();
    return true;
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
      linkImport: this.linkImport,
    };
  }

  registerWorker(): void {
    this.d.queue.register('download', async ({ job, signal }) => {
      const payload = job.payload as { type: 'download'; referenceId: string };
      const ref = this.d.refs.get(payload.referenceId);
      if (!ref || ref.source !== 'link' || !ref.url) return;
      this.d.refs.update(ref.id, { status: 'downloading', error: null });
      const started = Date.now();
      fs.mkdirSync(this.d.cfg.referencesDir, { recursive: true });
      const outBase = path.join(this.d.cfg.referencesDir, ref.id);
      try {
        const { stdout } = await run(this.d.ytdlpBin, ytdlpArgs({ url: ref.url, outBase, ffmpeg: this.d.ffmpegBin }), { signal, stderrTail: 2000 });
        const got = parseYtdlpOutput(stdout);
        if (!got || !fs.existsSync(got.filePath)) throw new Error('yt-dlp finished without a file');
        const size = fs.statSync(got.filePath).size;
        this.d.refs.update(ref.id, { path: got.filePath, fileName: path.basename(got.filePath), title: got.title.slice(0, 120), sizeBytes: size, status: 'queued', error: null });
        this.d.events.record('reference.downloaded', { site: linkSiteLabel(ref.url), bytes: size }, Date.now() - started);
        this.d.queue.enqueue({ type: 'analyze', referenceId: ref.id });
      } catch (err) {
        if (signal.aborted) return;
        const stderr = err instanceof SpawnError ? err.stderr : err instanceof Error ? err.message : String(err);
        const code = classifyLinkError(stderr);
        this.d.log.warn({ ref: ref.id, url: ref.url, code, err: stderr.slice(-600) }, 'link download failed');
        this.d.refs.update(ref.id, { status: 'failed', error: code });
        this.d.events.record('reference.download_failed', { site: linkSiteLabel(ref.url), code }, Date.now() - started);
        // 잡은 성공으로 끝낸다 — 큐의 재시도 대신 사용자가 "다시 배우기"로 다시 건다.
      }
    });

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
