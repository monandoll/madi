import fs from 'node:fs';
import path from 'node:path';
import { EventEmitter } from 'node:events';
import { createHash } from 'node:crypto';
import { type AiProvider, linkSiteLabel, normalizeVideoUrl, type Reference, type ReferenceStats, type Segment, type StyleResponse, type Video } from '@madi/shared';
import type { AgentProvider } from '../agent/provider.js';
import { insightPrompt, memoryBlock, memoryPrompt, parseInsight, parseMemory, retrieve } from './insight.js';
import { makeFrameSheets } from '../workers/frames.js';
import { SHEETS_DIR } from '../agent/claude.js';
import { applyCorrections, type CorrectionStore } from './corrections.js';
import type { MemoryStore } from './memory.js';
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
import { run, runAnalysis, SpawnError } from '../workers/spawn.js';
import { termsPrompt, type Whisper } from '../workers/whisper.js';
import { aggregate, aspectOf, learnedRuleLines, looksLikeSameVideo, pairDiff } from './learn.js';
import { withKnownDirs } from '../agent/detect.js';
import { classifyAnalyzeError, classifyLinkError, parseYtdlpOutput, ytdlpArgs, ytdlpEnv } from './link.js';
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
  resolveYtdlp?: () => string;
  whisper: () => Promise<Whisper>;
  events: EventLog;
  log: Logger;
  /** 제작자 기억 */
  memory: MemoryStore;
  /** 자막에서 고친 말 — whisper 에 알려 주고, 반복된 것은 결과에서 바로 바꾼다 */
  corrections: CorrectionStore;
  /** 완성본의 뜻을 읽을 AI (채팅과 같은 도구). 설정의 provider 로 고른다. */
  providers: Record<Exclude<AiProvider, 'none'>, AgentProvider>;
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
  private downloaderBin: string;
  /** 기억 정리는 완성본 메모가 바뀔 때마다 하되, 연달아 끝나면 한 번만 (AI 한 턴이라 비싸다). */
  private rememoryTimer: ReturnType<typeof setTimeout> | null = null;
  private rememoryRunning = false;
  private rememoryDirty = false;

  constructor(private readonly d: StyleServiceDeps) {
    super();
    this.downloaderBin = d.ytdlpBin;
  }

  /** yt-dlp --version 이 되면 링크로 배우기를 켠다. 기동 때 한 번 (몇 초 걸릴 수 있어 기다리지 않는다). */
  async detectDownloader(): Promise<boolean> {
    try {
      this.downloaderBin = this.d.resolveYtdlp?.() ?? this.d.ytdlpBin;
      const { stdout } = await run(this.downloaderBin, ['--version'], { signal: AbortSignal.timeout(10_000) });
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
    // 폴더를 빼서 메모 있는 완성본이 사라지면 제작자 기억도 다시 정리해야 한다
    const insightBefore = this.d.refs.withInsight().map((r) => r.id).join(',');
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
    // AI 를 나중에 연결한 경우: 숫자만 배운 완성본의 뜻을 이제 읽는다 (학습에서 뺀 것은 말고)
    if (this.insightOn()) {
      for (const ref of this.d.refs.learnable()) {
        if (ref.status === 'done' && !ref.insight && this.canInspect(ref)) this.d.queue.enqueue({ type: 'insight', referenceId: ref.id });
      }
    }
    if (opts.retryFailed) {
      for (const ref of this.d.refs.list()) {
        if (ref.source !== 'link' || ref.status !== 'failed') continue;
        this.d.refs.update(ref.id, { status: 'queued', error: null });
        this.d.queue.enqueue(fs.existsSync(ref.path) ? { type: 'analyze', referenceId: ref.id } : { type: 'download', referenceId: ref.id });
      }
    }
    this.relearn();
    if (this.d.refs.withInsight().map((r) => r.id).join(',') !== insightBefore) this.scheduleRememory();
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
    if (ref.insight) this.scheduleRememory();
    return true;
  }

  /**
   * 완성본 하나를 학습에서 빼거나 다시 넣는다 (기획안 §12). 파일 · 메모는 그대로 두고 숫자 · 기억에서만 뺀다.
   * 다시 넣을 때 메모가 없으면(뺀 채로 AI 를 연결한 경우) 그때 읽는다.
   */
  setExcluded(id: string, excluded: boolean): Reference | null {
    const ref = this.d.refs.get(id);
    if (!ref) return null;
    if (ref.excluded === excluded) return ref;
    const next = this.d.refs.update(id, { excluded });
    this.relearn();
    if (next.insight) this.scheduleRememory();
    else if (!excluded && this.insightOn() && next.status === 'done' && this.canInspect(next)) this.d.queue.enqueue({ type: 'insight', referenceId: id });
    this.d.events.record('reference.excluded', { excluded });
    return next;
  }

  /** AI 가 연결돼 있어 완성본의 뜻까지 읽는지. (설치 여부는 잡이 돌 때 다시 본다.) */
  insightOn(): boolean {
    return this.d.settings.get().ai.provider !== 'none';
  }

  private canInspect(ref: Reference): boolean {
    return (this.d.refs.segmentsOf(ref.id)?.length ?? 0) > 0 || (this.d.settings.get().ai.frames && fs.existsSync(ref.path));
  }

  /** 새 영상을 편집할 때 붙일 "# 기억" 블록. 없으면 빈 문자열. */
  recall(video: Pick<Video, 'id' | 'title'>): string {
    const transcript = this.d.library.transcriptOf(video.id);
    // 사용자가 확인한 기억만 (제안은 설정 화면에만 보인다)
    const r = retrieve({ videoId: video.id, title: video.title, transcript: transcript?.segments ?? null }, this.d.memory.listApproved(), this.d.refs.withInsight());
    return memoryBlock(r);
  }

  contextKey(video: Pick<Video, 'id' | 'title'>): string {
    const transcript = this.d.library.transcriptOf(video.id);
    const relevant = retrieve({ videoId: video.id, title: video.title, transcript: transcript?.segments ?? null }, this.d.memory.listApproved(), this.d.refs.withInsight()).items;
    const memories = relevant.map(({ text, kind, scope, topics }) => ({ text, kind, scope, topics })).sort((a, b) => a.text.localeCompare(b.text));
    return createHash('sha256').update(JSON.stringify({ rules: this.d.style.rules(), subtitleStyle: this.d.style.params().subtitleStyle, memories })).digest('hex');
  }

  /** 분석이 끝난 완성본들을 합쳐 style.md 의 학습 블록과 params 를 갱신한다. */
  relearn(): void {
    const stats = this.d.refs
      .learnable()
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
      memory: this.d.memory.list(),
      insightOn: this.insightOn(),
      corrections: this.d.corrections.list(),
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
        // 유튜브는 JS 런타임이 있어야 한다. 트레이 앱엔 PATH 가 없으니 알려진 폴더를 붙이고, 우리 node(Electron 을 node 로) 를 직접 준다.
        const env = ytdlpEnv(withKnownDirs(process.env));
        const { stdout } = await run(this.downloaderBin, ytdlpArgs({ url: ref.url, outBase, ffmpeg: this.d.ffmpegBin, nodeBin: process.execPath }), { signal, stderrTail: 2000, env });
        const got = parseYtdlpOutput(stdout);
        if (!got || !fs.existsSync(got.filePath)) throw new Error('yt-dlp finished without a file');
        const size = fs.statSync(got.filePath).size;
        // 제목이 깨져 있으면(cleanTitle 이 비움 → 파일 이름) 원래 이름("유튜브 영상")을 둔다
        const title = /^[A-Za-z0-9_-]{16,}$/.test(got.title) ? ref.title : got.title.slice(0, 120);
        this.d.refs.update(ref.id, { path: got.filePath, fileName: path.basename(got.filePath), title, sizeBytes: size, status: 'queued', error: null });
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

    this.registerInsightWorker();
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
        // 자막이 있고 AI 가 연결돼 있으면 뜻까지 읽는다 (기획안 §7 · §10). 학습에서 뺀 것은 읽지 않는다.
        if (this.insightOn() && !ref.excluded && this.canInspect(ref)) this.d.queue.enqueue({ type: 'insight', referenceId: ref.id });
      } catch (err) {
        // 사용자에겐 코드(쉬운 말)만, 원문은 로그에
        const message = err instanceof Error ? err.message : String(err);
        this.d.log.warn({ ref: ref.id, source: ref.source, err: message.slice(-600) }, 'reference analyze failed');
        this.d.refs.update(ref.id, { status: 'failed', error: ref.source === 'link' ? classifyAnalyzeError(message) : message.slice(0, 200) });
        throw err;
      }
    });
  }

  /** insight 잡: AI 가 자막을 읽고 메모를 남긴다. 실패해도 완성본은 done 그대로 (숫자는 배웠다). */
  registerInsightWorker(): void {
    this.d.queue.register('insight', async ({ job, signal }) => {
      const payload = job.payload as { type: 'insight'; referenceId: string };
      const ref = this.d.refs.get(payload.referenceId);
      const segments = (ref ? this.d.refs.segmentsOf(ref.id) : null) ?? [];
      if (!ref || ref.status !== 'done' || ref.excluded || !this.canInspect(ref)) return;
      const providerId = this.d.settings.get().ai.provider;
      if (providerId === 'none') return;
      const provider = this.d.providers[providerId];
      const started = Date.now();
      const cwd = path.join(this.d.cfg.workDir, 'insight', ref.id);
      fs.mkdirSync(cwd, { recursive: true });
      try {
        // 화면도 보여 준다 (기획안 §10) — 장면 전환 시각은 숫자 분석 때 재 두었다
        const sheets = this.d.settings.get().ai.frames && fs.existsSync(ref.path) ? await makeFrameSheets(this.d, ref.path, { durationSec: ref.stats?.durationSec ?? 0, scenes: ref.stats?.sceneTimes ?? [], dir: path.join(cwd, SHEETS_DIR), signal }) : [];
        if (!segments.length && !sheets.length) throw new Error('no reference evidence');
        const { system, prompt } = insightPrompt(ref, segments, sheets.length ? { sheets: sheets.map((s) => ({ rel: s.rel, times: s.times })), attached: providerId === 'codex' } : undefined);
        const res = await provider.analyze({ system, prompt, cwd, images: sheets.map((s) => s.file), bin: provider.bin(this.d.settings.get().ai.paths?.[providerId] ?? null), signal });
        if (!res.ok) throw new Error(res.error ?? 'analyze failed');
        const insight = parseInsight(res.text, { provider: providerId, durationSec: ref.stats?.durationSec ?? 0, frameTimes: sheets.flatMap((s) => s.times), hasSpeech: segments.length > 0 });
        if (!insight) throw new Error('no insight in answer');
        this.d.refs.update(ref.id, { insight });
        this.d.events.record('reference.insight', { provider: providerId, tags: insight.tags.length, shorts: insight.shortCandidates.length, frames: insight.frameTimes.length }, Date.now() - started);
        this.emit('style.updated');
        this.scheduleRememory();
      } catch (err) {
        if (signal.aborted) return;
        this.d.log.warn({ ref: ref.id, err: err instanceof Error ? err.message : String(err) }, 'insight failed');
        this.d.events.record('reference.insight_failed', { provider: providerId }, Date.now() - started);
        // 잡은 성공으로 끝낸다 — "다시 배우기"가 다시 건다
      } finally {
        fs.rmSync(cwd, { recursive: true, force: true });
      }
    });
  }

  /** 완성본 메모들이 바뀌면 2초 뒤 한 번 제작자 기억을 다시 정리한다. 돌고 있으면 끝난 뒤 한 번 더. */
  scheduleRememory(): void {
    if (this.rememoryRunning) {
      this.rememoryDirty = true;
      return;
    }
    if (this.rememoryTimer) clearTimeout(this.rememoryTimer);
    this.rememoryTimer = setTimeout(() => {
      this.rememoryTimer = null;
      void this.rememory();
    }, 2_000);
  }

  /** 완성본 메모 전부 → AI 한 턴 → 반복되는 것만 제작자 기억(source=reference)으로. 메모가 없으면 비운다. */
  async rememory(): Promise<void> {
    const refs = this.d.refs.withInsight();
    const providerId = this.d.settings.get().ai.provider;
    if (refs.length < 2) {
      this.d.memory.replaceFromReferences([]);
      this.emit('style.updated');
      return;
    }
    if (providerId === 'none') return;
    this.rememoryRunning = true;
    const started = Date.now();
    const cwd = path.join(this.d.cfg.workDir, 'insight', 'memory');
    fs.mkdirSync(cwd, { recursive: true });
    try {
      const provider = this.d.providers[providerId];
      const { system, prompt } = memoryPrompt(refs);
      const res = await provider.analyze({ system, prompt, cwd, bin: provider.bin(this.d.settings.get().ai.paths?.[providerId] ?? null) });
      if (!res.ok) throw new Error(res.error ?? 'analyze failed');
      const items = parseMemory(res.text, new Set(refs.map((r) => r.id)));
      this.d.memory.replaceFromReferences(items);
      this.d.events.record('memory.learned', { items: items.length, references: refs.length }, Date.now() - started);
      this.emit('style.updated');
    } catch (err) {
      this.d.log.warn({ err: err instanceof Error ? err.message : String(err) }, 'rememory failed');
    } finally {
      fs.rmSync(cwd, { recursive: true, force: true });
      this.rememoryRunning = false;
      if (this.rememoryDirty) {
        this.rememoryDirty = false;
        this.scheduleRememory();
      }
    }
  }

  /** 기다리지 않고 멈춘다 (엔진 종료). */
  stop(): void {
    if (this.rememoryTimer) clearTimeout(this.rememoryTimer);
    this.rememoryTimer = null;
  }

  private async analyze(ref: Reference, signal: AbortSignal): Promise<ReferenceStats> {
    const meta = await this.d.ffmpeg.probe(ref.path, signal);
    let silences: { start: number; end: number }[] = [];
    if (meta.hasAudio) {
      const { stderr } = await runAnalysis(this.d.ffmpegBin, silenceDetectArgs(ref.path, { minSec: 0.3 }), { signal });
      silences = parseSilences(stderr, meta.durationSec);
    }
    const scenes = parseScenes((await runAnalysis(this.d.ffmpegBin, sceneDetectArgs(ref.path, 0.4), { signal })).stderr);
    const minutes = Math.max(meta.durationSec / 60, 1 / 60);
    // 자막은 뜻을 읽는 재료라 소리가 있으면 항상 뜬다. whisper 가 없으면 건너뛴다 (숫자는 배운다).
    if (meta.hasAudio && !this.d.refs.segmentsOf(ref.id)) await this.transcribe(ref, signal);
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
      sceneTimes: scenes.slice(0, 200).map((t) => Math.round(t * 10) / 10),
      pair,
    };
  }

  /**
   * 제목이 같은 원본이 갤러리에 있고 그 원본에 자막이 있으면, 완성본도 자막을 만들어 맞춰 본다.
   * whisper 가 없거나 짝이 없으면 null — 실패로 치지 않는다.
   */
  /** 완성본 자막 뜨기 → 저장. 실패는 삼킨다 (whisper 가 없는 PC 도 숫자는 배워야 한다). */
  private async transcribe(ref: Reference, signal: AbortSignal): Promise<Segment[] | null> {
    try {
      const whisper = await this.d.whisper();
      const work = path.join(this.d.cfg.workDir, 'analyze', ref.id);
      // 사용자가 확인한 용어 기억을 알려 주고 듣는다 (기획안 §5.2)
      const terms = [...this.d.memory.listApproved().filter((m) => m.kind === 'term').map((m) => m.text), ...this.d.corrections.rights()];
      const result = await whisper.transcribe(ref.path, work, { signal, prompt: termsPrompt(terms) });
      fs.rmSync(work, { recursive: true, force: true });
      const { segments } = applyCorrections(result.segments, this.d.corrections.active());
      this.d.refs.update(ref.id, { segments });
      return segments;
    } catch (err) {
      if (signal.aborted) throw err;
      this.d.log.debug({ ref: ref.id, err: String(err) }, 'reference transcript skipped');
      return null;
    }
  }

  private async pairWithSource(ref: Reference, hasAudio: boolean, signal: AbortSignal) {
    if (!hasAudio) return null;
    const source = this.d.videos.listVisible().find((v) => v.status === 'ready' && looksLikeSameVideo(ref.title, v.title));
    if (!source) return null;
    const transcript = this.d.library.transcriptOf(source.id);
    if (!transcript) return null;
    try {
      const segments = this.d.refs.segmentsOf(ref.id) ?? (await this.transcribe(ref, signal));
      if (!segments) return null;
      return pairDiff(transcript.segments, segments, source.durationSec ?? 0, source.id);
    } catch (err) {
      this.d.log.debug({ ref: ref.id, err: String(err) }, 'pair skipped');
      return null;
    }
  }
}
