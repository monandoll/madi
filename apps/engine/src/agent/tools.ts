import { z } from 'zod';
import { DEFAULT_SUBTITLE_STYLE, type Edit, type Output, type Video } from '@madi/shared';
import { parseScenes, parseSilences, sceneDetectArgs, scenesToRanges, silenceDetectArgs, silencesToCuts } from '@madi/ffmpeg-presets';
import type { EngineConfig } from '../config.js';
import type { EventLog } from '../events.js';
import type { Library } from '../library.js';
import type { Logger } from '../log.js';
import type { JobQueue } from '../queue/index.js';
import type { VideoStore } from '../videos.js';
import { run } from '../workers/spawn.js';
import { TOOL_DEFS, type ToolInput, type ToolName } from '../mcp/tools.js';
import type { ToolOutcome } from '../mcp/server.js';
import type { ChapterStore } from '../chapters/store.js';
import { computeChapters } from '../workers/chapters.js';
import type { StyleProfile } from './style.js';

export interface AgentToolDeps {
  cfg: EngineConfig;
  library: Library;
  videos: VideoStore;
  queue: JobQueue;
  ffmpegBin: string;
  style: StyleProfile;
  chapters: ChapterStore;
  events: EventLog;
  log: Logger;
}

export interface ToolContext {
  videoId: string;
  runId: string;
  signal?: AbortSignal | undefined;
}

/** 도구 실행 실패. message 는 모델이 읽고 사용자에게 옮길 수 있는 쉬운 말. */
export class ToolError extends Error {}

const r2 = (n: number) => Math.round(n * 100) / 100;

/**
 * MCP 도구의 실제 구현. 엔진 안에서 돈다 (MCP 서버 프로세스가 HTTP 로 여기를 부른다).
 * 결과 파일을 만드는 도구는 잡을 걸고 끝날 때까지 기다린다. 카드(메시지)는 워커가 붙인다.
 */
export class AgentTools {
  constructor(private readonly d: AgentToolDeps) {}

  async call(name: ToolName, ctx: ToolContext, rawInput: unknown): Promise<ToolOutcome> {
    const def = TOOL_DEFS[name];
    const parsed = def.input.safeParse(rawInput ?? {});
    if (!parsed.success) return { ok: false, error: `입력이 잘못됐어요: ${z.prettifyError(parsed.error).slice(0, 300)}` };
    const video = this.d.videos.get(ctx.videoId);
    if (!video) return { ok: false, error: '영상을 찾지 못했어요.' };
    const started = Date.now();
    try {
      const result = await this.dispatch(name, video, ctx, parsed.data);
      this.d.events.record('ai.tool', { name, ok: true }, Date.now() - started);
      return { ok: true, result };
    } catch (err) {
      this.d.events.record('ai.tool', { name, ok: false }, Date.now() - started);
      const msg = err instanceof ToolError ? err.message : err instanceof Error ? `문제가 생겼어요: ${err.message.slice(0, 200)}` : String(err);
      this.d.log.warn({ tool: name, err: String(err) }, 'agent tool failed');
      return { ok: false, error: msg };
    }
  }

  private dispatch(name: ToolName, video: Video, ctx: ToolContext, input: unknown): Promise<unknown> {
    switch (name) {
      case 'get_transcript':
        return this.getTranscript(video, ctx);
      case 'find_silences':
        return this.findSilences(video, ctx, input as ToolInput<'find_silences'>);
      case 'find_scenes':
        return this.findScenes(video, ctx, input as ToolInput<'find_scenes'>);
      case 'propose_cuts':
        return this.proposeCuts(video, ctx, input as ToolInput<'propose_cuts'>);
      case 'apply_edit':
        return Promise.resolve(this.applyEdit(video, input as ToolInput<'apply_edit'>));
      case 'render':
        return this.render(video, ctx, input as ToolInput<'render'>);
      case 'extract_shorts':
        return this.extractShorts(video, ctx, input as ToolInput<'extract_shorts'>);
      case 'set_subtitle_style':
        return Promise.resolve(this.setSubtitleStyle(video, input as ToolInput<'set_subtitle_style'>));
      case 'get_chapters':
        return this.getChapters(video, ctx, input as ToolInput<'get_chapters'>);
      case 'update_style_rule':
        return Promise.resolve(this.updateStyleRule(input as ToolInput<'update_style_rule'>));
    }
  }

  private async getChapters(video: Video, ctx: ToolContext, input: ToolInput<'get_chapters'>) {
    let ch = input.refresh ? null : this.d.chapters.get(video.id);
    if (!ch) {
      if ((video.durationSec ?? 0) < 30) throw new ToolError('이 영상은 너무 짧아서 챕터로 나눌 게 없어요.');
      const controller = new AbortController();
      ctx.signal?.addEventListener('abort', () => controller.abort(), { once: true });
      ch = await computeChapters({ queue: this.d.queue, videos: this.d.videos, library: this.d.library, chapters: this.d.chapters, style: this.d.style, ffmpegBin: this.d.ffmpegBin, events: this.d.events, log: this.d.log }, video, controller.signal);
      this.d.library.say({ videoId: video.id, role: 'assistant', kind: 'chapters', code: 'chapters.ready', params: { count: ch.items.length, action: 'ai' } });
    }
    return {
      fromTranscript: ch.fromTranscript,
      chapters: ch.items.map((c) => ({ index: c.index, title: c.title, start: r2(c.start), end: r2(c.end), highlight: c.highlight ? { start: r2(c.highlight.start), end: r2(c.highlight.end) } : null })),
    };
  }

  // ---- 읽기 ----

  private async getTranscript(video: Video, ctx: ToolContext) {
    let t = this.d.library.transcriptOf(video.id);
    if (!t) {
      if (video.hasAudio === false) throw new ToolError('이 영상은 소리가 없어서 자막을 만들 수 없어요.');
      const job = this.d.queue.enqueue({ type: 'transcribe', videoId: video.id });
      if (!this.d.library.messageForJob(job.id)) {
        this.d.library.say({ videoId: video.id, role: 'assistant', kind: 'progress', code: 'progress.transcribe', jobId: job.id, params: { step: 'transcribe', action: 'ai', durationSec: Math.round(video.durationSec ?? 0) } });
      }
      await this.waitJob(job.id, ctx.signal);
      t = this.d.library.transcriptOf(video.id);
      if (!t) throw new ToolError('자막을 만들지 못했어요.');
    }
    return {
      language: t.language,
      durationSec: r2(video.durationSec ?? 0),
      segments: t.segments.map((s, i) => ({ i, start: r2(s.start), end: r2(s.end), text: s.text })),
    };
  }

  private async findSilences(video: Video, ctx: ToolContext, input: ToolInput<'find_silences'>) {
    if (video.hasAudio === false) throw new ToolError('이 영상은 소리가 없어요.');
    const { stderr } = await run(this.d.ffmpegBin, silenceDetectArgs(video.path, { minSec: input.minSec ?? this.d.style.params().silenceMinSec }), { signal: ctx.signal });
    const silences = parseSilences(stderr, video.durationSec ?? 0);
    return { silences: silences.map((s) => ({ start: r2(s.start), end: r2(s.end) })), totalSec: r2(silences.reduce((a, s) => a + s.end - s.start, 0)) };
  }

  private async findScenes(video: Video, ctx: ToolContext, input: ToolInput<'find_scenes'>) {
    const { stderr } = await run(this.d.ffmpegBin, sceneDetectArgs(video.path, input.threshold ?? 0.4), { signal: ctx.signal });
    const scenes = parseScenes(stderr);
    return { scenes: scenes.map(r2), ranges: scenesToRanges(scenes, video.durationSec ?? 0).map((r) => ({ start: r2(r.start), end: r2(r.end) })) };
  }

  private async proposeCuts(video: Video, ctx: ToolContext, input: ToolInput<'propose_cuts'>) {
    if (video.hasAudio === false) throw new ToolError('이 영상은 소리가 없어서 쉬는 구간을 찾을 수 없어요.');
    const { stderr } = await run(this.d.ffmpegBin, silenceDetectArgs(video.path, { minSec: input.minSilenceSec ?? this.d.style.params().silenceMinSec }), { signal: ctx.signal });
    const silences = parseSilences(stderr, video.durationSec ?? 0);
    const cuts = silencesToCuts(silences, video.durationSec ?? 0, input.padSec ?? 0.2);
    return { cuts: cuts.map((c) => ({ start: r2(c.start), end: r2(c.end), reason: c.reason })), removedSec: r2(cuts.reduce((a, c) => a + c.end - c.start, 0)) };
  }

  // ---- 편집 ----

  private applyEdit(video: Video, input: ToolInput<'apply_edit'>) {
    const transcript = this.d.library.transcriptOf(video.id);
    const clamp = (t: number) => Math.max(0, Math.min(video.durationSec ?? t, t));
    const cuts = input.cuts?.map((c) => ({ start: clamp(Math.min(c.start, c.end)), end: clamp(Math.max(c.start, c.end)), reason: c.reason ?? ('ai' as const) })).filter((c) => c.end > c.start);
    const keep = input.keep === undefined ? undefined : input.keep === null ? null : { start: clamp(Math.min(input.keep.start, input.keep.end)), end: clamp(Math.max(input.keep.start, input.keep.end)) };
    if (keep && keep.end - keep.start < 1) throw new ToolError('구간이 너무 짧아요. 1초보다 길게 잡아 주세요.');
    if (input.subtitles && video.hasAudio === false) throw new ToolError('이 영상은 소리가 없어서 자막을 넣을 수 없어요.');

    let edit: Edit;
    if (input.editId) {
      const existing = this.d.library.edit(input.editId);
      if (!existing || existing.videoId !== video.id) throw new ToolError('그 편집을 찾지 못했어요.');
      edit = this.d.library.updateEdit(existing.id, {
        ...(input.title !== undefined ? { title: input.title } : {}),
        ...(keep !== undefined ? { keep } : {}),
        ...(cuts !== undefined ? { cuts } : {}),
        ...(input.crop !== undefined ? { crop: input.crop } : {}),
        ...(input.subtitles !== undefined ? { subtitles: input.subtitles } : {}),
        ...(transcript ? { transcriptId: transcript.id } : {}),
      });
    } else {
      const crop = input.crop ?? (keep ? 'vertical' : 'none');
      edit = this.d.library.createEdit({
        videoId: video.id,
        title: input.title ?? `${video.title} · 편집`,
        keep: keep ?? null,
        cuts: cuts ?? [],
        crop,
        subtitles: input.subtitles ?? false,
        transcriptId: transcript?.id ?? null,
        subtitleStyle: this.d.style.params().subtitleStyle,
        speed: [],
      });
    }
    return summarizeEdit(edit);
  }

  private async render(video: Video, ctx: ToolContext, input: ToolInput<'render'>) {
    const edit = this.d.library.edit(input.editId);
    if (!edit || edit.videoId !== video.id) throw new ToolError('그 편집을 찾지 못했어요. apply_edit 로 먼저 만들어 주세요.');
    const output = await this.renderEdit(video, edit, ctx);
    return summarizeOutput(output);
  }

  private async extractShorts(video: Video, ctx: ToolContext, input: ToolInput<'extract_shorts'>) {
    const wantSubs = (input.subtitles ?? true) && video.hasAudio !== false;
    if (wantSubs && !this.d.library.transcriptOf(video.id)) await this.getTranscript(video, ctx);
    const transcript = this.d.library.transcriptOf(video.id);
    const outputs: ReturnType<typeof summarizeOutput>[] = [];
    let n = this.d.library.shortEditCount(video.id);
    for (const clip of input.clips) {
      const start = Math.max(0, Math.min(clip.start, clip.end));
      const end = Math.min(video.durationSec ?? clip.end, Math.max(clip.start, clip.end));
      if (end - start < 1) throw new ToolError(`${r2(clip.start)}~${r2(clip.end)} 구간이 너무 짧아요.`);
      n += 1;
      const edit = this.d.library.createEdit({
        videoId: video.id,
        title: clip.title ?? `${video.title} · 숏폼 ${n}`,
        keep: { start, end },
        cuts: [],
        crop: 'vertical',
        subtitles: wantSubs,
        transcriptId: transcript?.id ?? null,
        subtitleStyle: this.d.style.params().subtitleStyle,
        speed: [],
      });
      outputs.push(summarizeOutput(await this.renderEdit(video, edit, ctx)));
    }
    return { outputs };
  }

  private setSubtitleStyle(video: Video, input: ToolInput<'set_subtitle_style'>) {
    const patch = {
      ...(input.fontSize !== undefined ? { fontSize: input.fontSize } : {}),
      ...(input.color !== undefined ? { color: input.color } : {}),
      ...(input.boxColor !== undefined ? { boxColor: input.boxColor } : {}),
      ...(input.bottom !== undefined ? { bottom: input.bottom } : {}),
    };
    let style = { ...this.d.style.params().subtitleStyle, ...patch };
    if (input.editId) {
      const edit = this.d.library.edit(input.editId);
      if (!edit || edit.videoId !== video.id) throw new ToolError('그 편집을 찾지 못했어요.');
      style = { ...edit.subtitleStyle, ...patch };
      this.d.library.updateEdit(edit.id, { subtitleStyle: style });
    }
    if (input.remember) this.d.style.writeParams({ ...this.d.style.params(), subtitleStyle: { ...DEFAULT_SUBTITLE_STYLE, ...style } });
    return { subtitleStyle: style, remembered: !!input.remember };
  }

  private updateStyleRule(input: ToolInput<'update_style_rule'>) {
    const rules = this.d.style.appendRule(input.rule);
    this.d.events.record('style.rule', { rules });
    return { ok: true, rules };
  }

  // ---- 공통 ----

  /** 렌더 잡을 걸고 끝날 때까지. 진행 카드는 워커가 결과 카드로 바꾼다. */
  private async renderEdit(video: Video, edit: Edit, ctx: ToolContext): Promise<Output> {
    const job = this.d.queue.enqueue({ type: 'render', videoId: video.id, editId: edit.id });
    if (!this.d.library.messageForJob(job.id)) {
      this.d.library.say({ videoId: video.id, role: 'assistant', kind: 'progress', code: 'progress.render', jobId: job.id, params: { step: 'render', action: 'ai', title: edit.title } });
    }
    await this.waitJob(job.id, ctx.signal);
    const m = this.d.library.messageForJob(job.id);
    const output = m?.outputId ? this.d.library.output(m.outputId) : null;
    if (!output) throw new ToolError('결과 파일을 만들지 못했어요.');
    return output;
  }

  private async waitJob(jobId: string, signal?: AbortSignal): Promise<void> {
    const timeout = Date.now() + 30 * 60_000;
    while (Date.now() < timeout) {
      if (signal?.aborted) throw new ToolError('취소됐어요.');
      const j = this.d.queue.get(jobId);
      if (!j) throw new ToolError('작업을 찾지 못했어요.');
      if (j.status === 'done') return;
      if (j.status === 'failed' || j.status === 'canceled') throw new ToolError(jobFailureText(j.error));
      await new Promise((r) => setTimeout(r, 250));
    }
    throw new ToolError('너무 오래 걸려서 멈췄어요.');
  }
}

function jobFailureText(error: string | null): string {
  const e = error ?? '';
  if (/no audio/i.test(e)) return '이 영상은 소리가 없어요.';
  if (/whisper.*ENOENT|ENOENT.*whisper|whisper-cli/i.test(e)) return '자막 도구가 아직 설치되지 않았어요.';
  if (/model download failed|fetch failed/i.test(e)) return '자막 모델을 받지 못했어요. 인터넷 연결을 봐 주세요.';
  if (/nothing to render/i.test(e)) return '잘라내고 나니 남는 게 없어요.';
  return `만들다가 문제가 생겼어요${e ? ` (${e.slice(0, 120)})` : ''}.`;
}

export function summarizeEdit(e: Edit) {
  return {
    editId: e.id,
    title: e.title,
    keep: e.keep ? { start: r2(e.keep.start), end: r2(e.keep.end) } : null,
    cuts: e.cuts.map((c) => ({ start: r2(c.start), end: r2(c.end) })),
    crop: e.crop,
    subtitles: e.subtitles,
  };
}

export function summarizeOutput(o: Output) {
  return { outputId: o.id, title: o.title, durationSec: r2(o.durationSec), aspect: o.width < o.height ? '9:16' : '16:9' };
}
