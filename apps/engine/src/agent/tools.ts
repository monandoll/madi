import { z } from 'zod';
import { DEFAULT_SUBTITLE_STYLE, type Edit, type Output, type TimeRange, type Video } from '@madi/shared';
import { parseScenes, parseSilences, sceneDetectArgs, scenesToRanges, silenceDetectArgs, silencesToCuts } from '@madi/ffmpeg-presets';
import type { EngineConfig } from '../config.js';
import type { EventLog } from '../events.js';
import type { Library } from '../library.js';
import type { Logger } from '../log.js';
import type { JobQueue } from '../queue/index.js';
import type { VideoStore } from '../videos.js';
import { run } from '../workers/spawn.js';
import { splitByMotion } from '../workers/edit.js';
import { TOOL_DEFS, type ToolInput, type ToolName } from '../mcp/tools.js';
import type { ToolOutcome } from '../mcp/server.js';
import type { ChapterStore } from '../chapters/store.js';
import { computeChapters } from '../workers/chapters.js';
import type { StyleProfile } from './style.js';
import type { MemoryStore } from '../style/memory.js';
import { mergeSubtitleLines } from './subtitles.js';

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
  /** 범위(주제 · 이 영상만)가 있는 규칙은 style.md 대신 여기에 */
  memory: MemoryStore;
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
    if (!parsed.success) return { ok: false, error: `입력이 잘못됐습니다: ${z.prettifyError(parsed.error).slice(0, 300)}` };
    const video = this.d.videos.get(ctx.videoId);
    if (!video) return { ok: false, error: '영상을 찾지 못했습니다.' };
    const started = Date.now();
    try {
      const result = await this.dispatch(name, video, ctx, parsed.data);
      this.d.events.record('ai.tool', { name, ok: true }, Date.now() - started);
      return { ok: true, result };
    } catch (err) {
      this.d.events.record('ai.tool', { name, ok: false }, Date.now() - started);
      const msg = err instanceof ToolError ? err.message : err instanceof Error ? `문제가 생겼습니다: ${err.message.slice(0, 200)}` : String(err);
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
      case 'set_subtitle_text':
        return Promise.resolve(this.setSubtitleText(video, input as ToolInput<'set_subtitle_text'>));
      case 'get_chapters':
        return this.getChapters(video, ctx, input as ToolInput<'get_chapters'>);
      case 'update_style_rule':
        return Promise.resolve(this.updateStyleRule(video, input as ToolInput<'update_style_rule'>));
    }
  }

  /** 자막 문장 고치기. 자막이 없으면 준 줄들로 새로 만든다 (model=manual). */
  private setSubtitleText(video: Video, input: ToolInput<'set_subtitle_text'>) {
    const existing = this.d.library.transcriptOf(video.id);
    const segments = mergeSubtitleLines(existing?.segments ?? [], input.lines, input.replaceAll ?? false);
    if (segments.length === 0) throw new ToolError('넣을 문장이 없습니다.');
    const t = this.d.library.setTranscript(video.id, { language: existing?.language ?? 'ko', model: existing ? existing.model : 'manual', segments });
    this.d.events.record('transcript.edited', { lines: input.lines.length, replaceAll: !!input.replaceAll, total: segments.length });
    return { segments: t.segments.map((s, i) => ({ i, start: r2(s.start), end: r2(s.end), text: s.text })) };
  }

  private async getChapters(video: Video, ctx: ToolContext, input: ToolInput<'get_chapters'>) {
    let ch = input.refresh ? null : this.d.chapters.get(video.id);
    if (!ch) {
      if ((video.durationSec ?? 0) < 30) throw new ToolError('영상이 짧아 나눌 챕터가 없습니다.');
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
      if (video.hasAudio === false) throw new ToolError('소리가 없어 자막을 자동으로 만들 수 없습니다. 넣을 문장과 시각을 알면 set_subtitle_text 로 넣을 수 있습니다.');
      const job = this.d.queue.enqueue({ type: 'transcribe', videoId: video.id });
      if (!this.d.library.messageForJob(job.id)) {
        this.d.library.say({ videoId: video.id, role: 'assistant', kind: 'progress', code: 'progress.transcribe', jobId: job.id, params: { step: 'transcribe', action: 'ai', durationSec: Math.round(video.durationSec ?? 0) } });
      }
      await this.waitJob(job.id, ctx.signal);
      t = this.d.library.transcriptOf(video.id);
      if (!t) throw new ToolError('자막을 만들지 못했습니다.');
    }
    return {
      language: t.language,
      durationSec: r2(video.durationSec ?? 0),
      segments: t.segments.map((s, i) => ({ i, start: r2(s.start), end: r2(s.end), text: s.text })),
    };
  }

  private async findSilences(video: Video, ctx: ToolContext, input: ToolInput<'find_silences'>) {
    if (video.hasAudio === false) throw new ToolError('이 영상은 소리가 없습니다.');
    const duration = video.durationSec ?? 0;
    const { stderr } = await run(this.d.ffmpegBin, silenceDetectArgs(video.path, { minSec: input.minSec ?? this.d.style.params().silenceMinSec }), { signal: ctx.signal });
    const silences = parseSilences(stderr, duration);
    const { kept } = await splitByMotion(this.d, video.path, silences, duration, ctx.signal);
    const moving = new Set(kept);
    return {
      silences: silences.map((s) => ({ start: r2(s.start), end: r2(s.end), moving: moving.has(s) })),
      totalSec: r2(silences.reduce((a, s) => a + s.end - s.start, 0)),
      note: kept.length ? `moving=true 인 ${kept.length}곳은 말은 없지만 동작이 이어진다 (시범). 자르지 않는다.` : undefined,
    };
  }

  private async findScenes(video: Video, ctx: ToolContext, input: ToolInput<'find_scenes'>) {
    const { stderr } = await run(this.d.ffmpegBin, sceneDetectArgs(video.path, input.threshold ?? 0.4), { signal: ctx.signal });
    const scenes = parseScenes(stderr);
    return { scenes: scenes.map(r2), ranges: scenesToRanges(scenes, video.durationSec ?? 0).map((r) => ({ start: r2(r.start), end: r2(r.end) })) };
  }

  private async proposeCuts(video: Video, ctx: ToolContext, input: ToolInput<'propose_cuts'>) {
    if (video.hasAudio === false) throw new ToolError('소리가 없어 쉬는 구간을 찾을 수 없습니다.');
    const duration = video.durationSec ?? 0;
    const { stderr } = await run(this.d.ffmpegBin, silenceDetectArgs(video.path, { minSec: input.minSilenceSec ?? this.d.style.params().silenceMinSec }), { signal: ctx.signal });
    const silences = parseSilences(stderr, duration);
    // 동작이 이어지는 침묵(시범)은 제안에서 뺀다 — 에이전트가 따로 판단할 필요 없이 kept 로 알려 준다
    const { cut, kept } = await splitByMotion(this.d, video.path, silences, duration, ctx.signal);
    const cuts = silencesToCuts(cut, duration, input.padSec ?? 0.2);
    return {
      cuts: cuts.map((c) => ({ start: r2(c.start), end: r2(c.end), reason: c.reason })),
      removedSec: r2(cuts.reduce((a, c) => a + c.end - c.start, 0)),
      kept: kept.map((k) => ({ start: r2(k.start), end: r2(k.end), why: '말은 없지만 동작이 이어진다 (시범)' })),
    };
  }

  // ---- 편집 ----

  private applyEdit(video: Video, input: ToolInput<'apply_edit'>) {
    const transcript = this.d.library.transcriptOf(video.id);
    const clamp = (t: number) => Math.max(0, Math.min(video.durationSec ?? t, t));
    const cuts = input.cuts?.map((c) => ({ start: clamp(Math.min(c.start, c.end)), end: clamp(Math.max(c.start, c.end)), reason: c.reason ?? ('ai' as const) })).filter((c) => c.end > c.start);
    const keep = input.keep === undefined ? undefined : input.keep === null ? null : { start: clamp(Math.min(input.keep.start, input.keep.end)), end: clamp(Math.max(input.keep.start, input.keep.end)) };
    if (keep && keep.end - keep.start < 1) throw new ToolError('구간이 너무 짧습니다. 1초보다 길게 정하세요.');
    const parts = input.parts === undefined ? undefined : this.cleanParts(video, input.parts);
    if (input.subtitles && video.hasAudio === false && !transcript) throw new ToolError('소리가 없어 자막을 자동으로 만들 수 없습니다. set_subtitle_text 로 문장을 먼저 넣으세요.');
    const cropFocus = input.focus === undefined ? undefined : focusValue(input.focus);

    let edit: Edit;
    if (input.editId) {
      const existing = this.d.library.edit(input.editId);
      if (!existing || existing.videoId !== video.id) throw new ToolError('그 편집을 찾지 못했습니다.');
      edit = this.d.library.updateEdit(existing.id, {
        ...(input.title !== undefined ? { title: input.title } : {}),
        ...(keep !== undefined ? { keep } : {}),
        ...(parts !== undefined ? { parts } : {}),
        ...(cuts !== undefined ? { cuts } : {}),
        ...(input.crop !== undefined ? { crop: input.crop } : {}),
        ...(cropFocus !== undefined ? { cropFocus } : {}),
        ...(input.subtitles !== undefined ? { subtitles: input.subtitles } : {}),
        ...(transcript ? { transcriptId: transcript.id } : {}),
      });
    } else {
      const crop = input.crop ?? (keep || parts?.length ? 'vertical' : 'none');
      edit = this.d.library.createEdit({
        videoId: video.id,
        title: input.title ?? `${video.title} · 편집`,
        keep: keep ?? null,
        parts: parts ?? [],
        cuts: cuts ?? [],
        crop,
        cropFocus: cropFocus ?? null,
        subtitles: input.subtitles ?? false,
        transcriptId: transcript?.id ?? null,
        subtitleStyle: this.d.style.params().subtitleStyle,
        speed: [],
      });
    }
    return summarizeEdit(edit);
  }

  /** 조각 목록 정리: 뒤집힌 건 바로, 길이 밖은 잘라, 1초 미만은 오류. 순서는 그대로 (그게 구성이다). */
  private cleanParts(video: Video, parts: TimeRange[]): TimeRange[] {
    const clamp = (t: number) => Math.max(0, Math.min(video.durationSec ?? t, t));
    return parts.map((p) => {
      const start = clamp(Math.min(p.start, p.end));
      const end = clamp(Math.max(p.start, p.end));
      if (end - start < 1) throw new ToolError(`${r2(p.start)}~${r2(p.end)} 조각이 너무 짧아요. 1초보다 길게 정하세요.`);
      return { start, end };
    });
  }

  private async render(video: Video, ctx: ToolContext, input: ToolInput<'render'>) {
    const edit = this.d.library.edit(input.editId);
    if (!edit || edit.videoId !== video.id) throw new ToolError('그 편집을 찾지 못했습니다. apply_edit 로 먼저 만드세요.');
    const output = await this.renderEdit(video, edit, ctx);
    return summarizeOutput(output);
  }

  private async extractShorts(video: Video, ctx: ToolContext, input: ToolInput<'extract_shorts'>) {
    const wantSubs = (input.subtitles ?? true) && (video.hasAudio !== false || !!this.d.library.transcriptOf(video.id));
    if (wantSubs && !this.d.library.transcriptOf(video.id)) await this.getTranscript(video, ctx);
    const transcript = this.d.library.transcriptOf(video.id);
    const outputs: ReturnType<typeof summarizeOutput>[] = [];
    let n = this.d.library.shortEditCount(video.id);
    for (const clip of input.clips) {
      const parts = clip.parts?.length ? this.cleanParts(video, clip.parts) : [];
      const start = parts.length ? Math.min(...parts.map((p) => p.start)) : Math.max(0, Math.min(clip.start, clip.end));
      const end = parts.length ? Math.max(...parts.map((p) => p.end)) : Math.min(video.durationSec ?? clip.end, Math.max(clip.start, clip.end));
      if (end - start < 1) throw new ToolError(`${r2(clip.start)}~${r2(clip.end)} 구간이 너무 짧아요.`);
      n += 1;
      const edit = this.d.library.createEdit({
        videoId: video.id,
        title: clip.title ?? `${video.title} · 숏폼 ${n}`,
        keep: { start, end },
        parts,
        cuts: [],
        crop: 'vertical',
        cropFocus: clip.focus === undefined ? null : focusValue(clip.focus),
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
      if (!edit || edit.videoId !== video.id) throw new ToolError('그 편집을 찾지 못했습니다.');
      style = { ...edit.subtitleStyle, ...patch };
      // 여백을 직접 정했으면 렌더가 자동으로 위로 올리지 않는다
      this.d.library.updateEdit(edit.id, { subtitleStyle: style, ...(input.bottom !== undefined ? { subtitleAuto: false } : {}) });
    }
    if (input.remember) this.d.style.writeParams({ ...this.d.style.params(), subtitleStyle: { ...DEFAULT_SUBTITLE_STYLE, ...style } });
    return { subtitleStyle: style, remembered: !!input.remember };
  }

  /**
   * "앞으로도 이렇게": 모든 영상이면 style.md 에 한 줄 (설정의 규칙 목록에 보인다),
   * 주제 · 이 영상만이면 기억(memory)에 범위와 함께 (설정의 기억 목록에 보인다). 둘 다 사용자가 지울 수 있다.
   */
  private updateStyleRule(video: Video, input: ToolInput<'update_style_rule'>) {
    const scope = input.scope ?? 'all';
    const kind = input.kind ?? 'style';
    if (scope === 'all' && kind === 'style') {
      const rules = this.d.style.appendRule(input.rule);
      this.d.events.record('style.rule', { rules, scope });
      return { ok: true, rules, scope };
    }
    const item = this.d.memory.add({ text: input.rule, kind, scope, topics: input.topics ?? [], videoId: video.id, source: 'feedback' });
    this.d.events.record('style.rule', { scope, kind, topics: item.topics.length });
    return { ok: true, scope, kind, memoryId: item.id };
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
    if (!output) throw new ToolError('결과 파일을 만들지 못했습니다.');
    return output;
  }

  private async waitJob(jobId: string, signal?: AbortSignal): Promise<void> {
    const timeout = Date.now() + 30 * 60_000;
    while (Date.now() < timeout) {
      if (signal?.aborted) throw new ToolError('취소했습니다.');
      const j = this.d.queue.get(jobId);
      if (!j) throw new ToolError('작업을 찾지 못했습니다.');
      if (j.status === 'done') return;
      if (j.status === 'failed' || j.status === 'canceled') throw new ToolError(jobFailureText(j.error));
      await new Promise((r) => setTimeout(r, 250));
    }
    throw new ToolError('시간이 너무 오래 걸려 중단했습니다.');
  }
}

function jobFailureText(error: string | null): string {
  const e = error ?? '';
  if (/no audio/i.test(e)) return '이 영상은 소리가 없습니다.';
  if (/whisper.*ENOENT|ENOENT.*whisper|whisper-cli/i.test(e)) return '자막 도구가 아직 설치되지 않았습니다.';
  if (/model download failed|fetch failed/i.test(e)) return '자막 모델을 내려받지 못했습니다. 인터넷 연결을 확인하세요.';
  if (/nothing to render/i.test(e)) return '잘라내고 나면 남는 구간이 없습니다.';
  return `만드는 중에 문제가 생겼습니다${e ? ` (${e.slice(0, 120)})` : ''}.`;
}

/** focus 입력 → cropFocus. auto 는 null (렌더할 때 고른다). */
export function focusValue(f: 'auto' | 'left' | 'center' | 'right'): number | null {
  return f === 'auto' ? null : f === 'left' ? 0 : f === 'right' ? 1 : 0.5;
}

export function summarizeEdit(e: Edit) {
  return {
    editId: e.id,
    title: e.title,
    keep: e.keep ? { start: r2(e.keep.start), end: r2(e.keep.end) } : null,
    ...(e.parts.length ? { parts: e.parts.map((p) => ({ start: r2(p.start), end: r2(p.end) })) } : {}),
    cuts: e.cuts.map((c) => ({ start: r2(c.start), end: r2(c.end) })),
    crop: e.crop,
    ...(e.crop === 'vertical' ? { focus: e.cropFocus === null ? 'auto' : e.cropFocus < 0.25 ? 'left' : e.cropFocus > 0.75 ? 'right' : 'center' } : {}),
    subtitles: e.subtitles,
  };
}

export function summarizeOutput(o: Output) {
  return { outputId: o.id, title: o.title, durationSec: r2(o.durationSec), aspect: o.width < o.height ? '9:16' : '16:9' };
}
