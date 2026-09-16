import { type ActionRequest, type ActionResponse, DEFAULT_SUBTITLE_STYLE, type Edit, type Video } from '@madi/shared';
import type { EventLog } from './events.js';
import type { Library } from './library.js';
import type { JobQueue } from './queue/index.js';
import type { VideoStore } from './videos.js';

export interface ActionDeps {
  queue: JobQueue;
  videos: VideoStore;
  library: Library;
  events: EventLog;
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
  const baseEdit = (title: string): Omit<Edit, 'id' | 'createdAt'> => ({
    videoId: video.id,
    title,
    keep: null,
    cuts: [],
    crop: 'none',
    subtitles: false,
    transcriptId: transcript?.id ?? null,
    subtitleStyle: DEFAULT_SUBTITLE_STYLE,
    speed: [],
  });
  const messages: ActionResponse['messages'] = [];
  const user = (code: string, params: Record<string, string | number | boolean | null> = {}) =>
    messages.push(d.library.say({ videoId: video.id, role: 'user', kind: 'text', code, params }));
  const progress = (jobId: string, code: string, params: Record<string, string | number | boolean | null> = {}) =>
    messages.push(d.library.say({ videoId: video.id, role: 'assistant', kind: 'progress', code, jobId, params }));

  d.events.record('action', { type: req.type, kind: video.kind });

  switch (req.type) {
    case 'subtitle': {
      if (video.hasAudio === false) throw new ActionError('no_audio');
      user('action.subtitle');
      const edit = d.library.createEdit({ ...baseEdit(`${video.title} · 자막`), subtitles: true });
      if (transcript) {
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
      const n = d.library.outputsOf(video.id).filter((o) => o.kind === 'short').length + 1;
      const wantSubs = req.subtitles && video.hasAudio !== false;
      const edit = d.library.createEdit({ ...baseEdit(`${video.title} · 숏폼 ${n}`), keep: { start, end }, crop: 'vertical', subtitles: wantSubs });
      if (wantSubs && !transcript) {
        const job = d.queue.enqueue({ type: 'transcribe', videoId: video.id, renderEditId: edit.id });
        progress(job.id, 'progress.transcribe', { step: 'transcribe', action: 'short', durationSec: Math.round(duration) });
        return { messages, job };
      }
      const job = d.queue.enqueue({ type: 'render', videoId: video.id, editId: edit.id });
      progress(job.id, 'progress.render', { step: 'render', action: 'short' });
      return { messages, job };
    }
  }
}

/** 상세 화면을 처음 열 때 인사. 한 번만. */
export function greetIfEmpty(library: Library, video: Video): void {
  if (library.messagesOf(video.id).length > 0) return;
  library.say({
    videoId: video.id,
    role: 'assistant',
    kind: 'text',
    code: 'greeting',
    params: { durationSec: Math.round(video.durationSec ?? 0), hasAudio: video.hasAudio ?? true },
  });
}
