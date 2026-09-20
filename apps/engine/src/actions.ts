import type { z } from 'zod';
import { type ActionRequest, type ActionResponse, DEFAULT_SUBTITLE_STYLE, Edit, mergeSubtitleStyle, type EditPlan, type SubtitleStyle, type TimeRange, type Video } from '@madi/shared';
import type { EventLog } from './events.js';
import type { Library } from './library.js';
import type { PlanStore } from './plan/store.js';
import { planCuts } from './plan/prompt.js';
import { recipeForRange, parseRecipe } from './plan/execution.js';
import { mergeSubtitleLines } from './agent/subtitles.js';
import type { JobQueue } from './queue/index.js';
import type { VideoStore } from './videos.js';

export interface ActionDeps {
  queue: JobQueue;
  videos: VideoStore;
  library: Library;
  events: EventLog;
  plans: PlanStore;
  /** AI 가 골라져 있는지 (편집안은 AI 한 턴이라 없으면 못 한다) */
  aiOn: () => boolean;
  contextKey?: (video: Video) => string;
  subtitleStyle?: () => SubtitleStyle;
}

export class ActionError extends Error {
  constructor(readonly code: string) {
    super(code);
  }
}

/**
 * AI 미연결 상태의 버튼 4개. 러너를 스폰하지 않고 워커를 직접 부른다.
 * 각 액션은 (사용자 말풍선) + (진행 카드) 두 메시지를 남기고 잡을 하나 건다.
 */
export function runAction(d: ActionDeps, video: Video, req: ActionRequest): ActionResponse {
  if (video.status !== 'ready') throw new ActionError('video_not_ready');
  const duration = video.durationSec ?? 0;
  const transcript = d.library.transcriptOf(video.id);
  const baseEdit = (title: string): Omit<z.input<typeof Edit>, 'id' | 'createdAt'> => ({
    videoId: video.id,
    title,
    keep: null,
    cuts: [],
    crop: 'none',
    subtitles: false,
    transcriptId: transcript?.id ?? null,
    subtitleStyle: d.subtitleStyle?.() ?? DEFAULT_SUBTITLE_STYLE,
    speed: [],
  });
  const planSettings = (plan: EditPlan, range?: TimeRange): Partial<z.input<typeof Edit>> => {
    if (plan.styleContextKey && d.contextKey && plan.styleContextKey !== d.contextKey(video)) throw new ActionError('plan_outdated');
    const recipe = recipeForRange(plan, range);
    if (!recipe) return {};
    const protectedRanges = [...plan.keepRanges, ...plan.cutCandidates.filter((_, i) => plan.feedback.some((f) => f.kind === 'cut' && f.index === i && f.verdict === 'rejected'))];
    if (!range && !parseRecipe(recipe, duration, protectedRanges)) throw new ActionError('plan_outdated');
    const caption = recipe.captions.length ? d.library.setTranscript(video.id, { language: transcript?.language ?? 'ko', model: 'ai-plan', segments: mergeSubtitleLines([], recipe.captions, true) }, { source: false }) : null;
    return {
      parts: recipe.parts,
      subtitleStyle: mergeSubtitleStyle(d.subtitleStyle?.() ?? DEFAULT_SUBTITLE_STYLE, recipe.subtitleStyle),
      subtitleAuto: recipe.subtitleStyle.bottom === undefined,
      ...(caption ? { transcriptId: caption.id, subtitles: true } : {}),
    };
  };
  const messages: ActionResponse['messages'] = [];
  const user = (code: string, params: Record<string, string | number | boolean | null> = {}) =>
    messages.push(d.library.say({ videoId: video.id, role: 'user', kind: 'text', code, params }));
  const progress = (jobId: string, code: string, params: Record<string, string | number | boolean | null> = {}) =>
    messages.push(d.library.say({ videoId: video.id, role: 'assistant', kind: 'progress', code, jobId, params }));

  d.events.record('action', { type: req.type, kind: video.kind, ...(req.type === 'short' ? { from: req.from } : {}) });

  switch (req.type) {
    case 'subtitle': {
      const existing = req.editId ? d.library.edit(req.editId) : null;
      if (req.editId && (!existing || existing.videoId !== video.id)) throw new ActionError('not_found');
      const selected = req.transcriptId ? d.library.transcript(req.transcriptId) : existing ? d.library.transcriptForEdit(existing) : transcript;
      if (req.transcriptId && (!selected || selected.videoId !== video.id)) throw new ActionError('not_found');
      // 소리가 없어도 직접 쓴 자막(transcript)이 있으면 넣는다
      if (video.hasAudio === false && !selected) throw new ActionError('no_audio');
      user('action.subtitle');
      const patch = { subtitles: selected ? selected.segments.length > 0 : true, transcriptId: selected?.id ?? null };
      const edit = existing ? d.library.reviseEdit(existing, patch) : d.library.createEdit({ ...baseEdit(`${video.title} · 자막`), ...patch });
      if (selected) {
        const job = d.queue.enqueue({ type: 'render', videoId: video.id, editId: edit.id });
        progress(job.id, 'progress.render', { step: 'render', action: 'subtitle' });
        return { messages, job };
      }
      const job = d.queue.enqueue({ type: 'transcribe', videoId: video.id, renderEditId: edit.id });
      progress(job.id, 'progress.transcribe', { step: 'transcribe', action: 'subtitle', durationSec: Math.round(duration) });
      return { messages, job };
    }
    case 'silence': {
      if (video.hasAudio === false) throw new ActionError('no_audio');
      user('action.silence');
      const edit = d.library.createEdit({ ...baseEdit(`${video.title} · 쉬는 구간 제거`), subtitles: !!transcript });
      const job = d.queue.enqueue({ type: 'silence', videoId: video.id, editId: edit.id });
      progress(job.id, 'progress.silence', { step: 'silence', action: 'silence' });
      return { messages, job };
    }
    case 'vertical': {
      user('action.vertical');
      const edit = d.library.createEdit({ ...baseEdit(`${video.title} · 세로`), crop: 'vertical', subtitles: !!transcript });
      const job = d.queue.enqueue({ type: 'render', videoId: video.id, editId: edit.id });
      progress(job.id, 'progress.render', { step: 'render', action: 'vertical' });
      return { messages, job };
    }
    case 'short': {
      const start = Math.max(0, Math.min(req.range.start, req.range.end));
      const end = Math.min(duration, Math.max(req.range.start, req.range.end));
      if (end - start < 1) throw new ActionError('range_too_short');
      user('action.short', { start: Math.round(start), end: Math.round(end) });
      const n = d.library.shortEditCount(video.id) + 1;
      let wantSubs = req.subtitles && (video.hasAudio !== false || !!transcript);
      // 편집안의 숏폼 후보를 눌러 만든 거면 "골랐다"로 남기고, 화면을 보고 안 사람 위치가 있으면 그쪽을 잡는다 (기획안 §9 · §5.4)
      let cropFocus: number | null = null;
      let recipePatch: Partial<z.input<typeof Edit>> = {};
      if (req.from === 'plan') {
        const plan = d.plans.get(video.id);
        if (plan) recipePatch = planSettings(plan, { start, end });
        const idx = plan?.shortCandidates.findIndex((s) => Math.abs(s.start - start) < 0.5 && Math.abs(s.end - end) < 0.5) ?? -1;
        if (idx >= 0) d.plans.setFeedback(video.id, { kind: 'short', index: idx, verdict: 'accepted' });
        const side = plan?.framing?.side;
        cropFocus = side === 'left' ? 0 : side === 'right' ? 1 : null;
      }
      wantSubs = req.subtitles && (wantSubs || !!recipePatch.transcriptId);
      const edit = d.library.createEdit({ ...baseEdit(`${video.title} · 숏폼 ${n}`), ...recipePatch, keep: { start, end }, crop: 'vertical', cropFocus, subtitles: wantSubs });
      if (wantSubs && !transcript && !recipePatch.transcriptId) {
        const job = d.queue.enqueue({ type: 'transcribe', videoId: video.id, renderEditId: edit.id });
        progress(job.id, 'progress.transcribe', { step: 'transcribe', action: 'short', durationSec: Math.round(duration) });
        return { messages, job };
      }
      const job = d.queue.enqueue({ type: 'render', videoId: video.id, editId: edit.id });
      progress(job.id, 'progress.render', { step: 'render', action: 'short' });
      return { messages, job };
    }
    case 'chapters': {
      if (duration < 30) throw new ActionError('too_short_for_chapters');
      user('action.chapters');
      const job = d.queue.enqueue({ type: 'chapters', videoId: video.id, then: 'none', max: 3 });
      progress(job.id, 'progress.chapters', { step: 'chapters', action: 'chapters', durationSec: Math.round(duration), hasAudio: video.hasAudio !== false });
      return { messages, job };
    }
    case 'auto_shorts': {
      if (duration < 30) throw new ActionError('too_short_for_chapters');
      user('action.auto_shorts', { max: req.max });
      const job = d.queue.enqueue({ type: 'chapters', videoId: video.id, then: 'shorts', max: req.max });
      progress(job.id, 'progress.chapters', { step: 'chapters', action: 'auto_shorts', durationSec: Math.round(duration), hasAudio: video.hasAudio !== false, max: req.max });
      return { messages, job };
    }
    case 'plan': {
      if (!d.aiOn()) throw new ActionError('ai_off');
      const job = enqueuePlan(d, video, messages, 'user');
      return { messages, job };
    }
    case 'apply_plan': {
      const plan = d.plans.get(video.id);
      if (!plan) throw new ActionError('plan_missing');
      const recipePatch = planSettings(plan);
      const cuts = planCuts(plan, duration);
      user('action.apply_plan', { cuts: cuts.length });
      const edit = d.library.createEdit({ ...baseEdit(`${video.title} · 편집안`), cuts, subtitles: !!transcript, ...recipePatch });
      const job = d.queue.enqueue({ type: 'render', videoId: video.id, editId: edit.id });
      const removed = Math.round(cuts.reduce((a, c) => a + (c.end - c.start), 0));
      progress(job.id, 'progress.render', { step: 'render', action: 'plan', cuts: cuts.length, removedSec: removed, title: edit.title });
      return { messages, job };
    }
  }
}

/**
 * 편집안 잡 걸기. who='auto' 는 상세를 처음 열 때 (사용자 말풍선 없이 진행 카드만), 'user' 는 버튼.
 * 이미 걸려 있으면 다시 걸지 않는다.
 */
export function enqueuePlan(d: Pick<ActionDeps, 'queue' | 'library' | 'events'>, video: Video, messages: ActionResponse['messages'], who: 'auto' | 'user') {
  const running = d.queue.list(['queued', 'running']).find((j) => j.type === 'plan' && j.videoId === video.id);
  if (running) return running;
  if (who === 'user') messages.push(d.library.say({ videoId: video.id, role: 'user', kind: 'text', code: 'action.plan', params: {} }));
  const job = d.queue.enqueue({ type: 'plan', videoId: video.id });
  messages.push(
    d.library.say({
      videoId: video.id,
      role: 'assistant',
      kind: 'progress',
      code: 'progress.plan',
      jobId: job.id,
      params: { step: 'plan', action: 'plan', durationSec: Math.round(video.durationSec ?? 0), hasAudio: video.hasAudio !== false, auto: who === 'auto' },
    }),
  );
  d.events.record('action', { type: 'plan', kind: video.kind, auto: who === 'auto' });
  return job;
}

/**
 * 상세 화면을 처음 열 때 인사. 한 번만.
 * AI 가 골라져 있으면 그 자리에서 편집안도 읽기 시작한다 (기획안 §4: 넣으면 편집안이 나온다). 안 골라져 있으면 인사만.
 */
export function greetIfEmpty(d: Pick<ActionDeps, 'queue' | 'library' | 'events' | 'plans' | 'aiOn'>, video: Video): void {
  if (d.library.messagesOf(video.id).length > 0) return;
  d.library.say({
    videoId: video.id,
    role: 'assistant',
    kind: 'text',
    code: 'greeting',
    params: { durationSec: Math.round(video.durationSec ?? 0), hasAudio: video.hasAudio ?? true, plan: d.aiOn() },
  });
  if (d.aiOn() && !d.plans.get(video.id)) enqueuePlan(d, video, [], 'auto');
}
