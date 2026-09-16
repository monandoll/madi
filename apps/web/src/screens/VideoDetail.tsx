import { useEffect, useRef, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { type ActionRequest, isStreaming, type OutputCard } from '@madi/shared';
import { type ActionKey, ActionBar } from '../components/ActionBar.js';
import { ChatBar } from '../components/ChatBar.js';
import { ChatFeed } from '../components/ChatFeed.js';
import { ChevronIcon } from '../components/Icons.js';
import { ScreenHeader } from '../components/ScreenHeader.js';
import { ShortPicker } from '../components/ShortPicker.js';
import { Thumb } from '../components/Thumb.js';
import { copy, errorMessage } from '../copy.js';
import { ApiError, api, queryKeys } from '../lib/api.js';
import { formatDate, formatDuration } from '../lib/format.js';

/**
 * design/Mobile.dc.html '영상 상세 · 채팅 위, 프리뷰 접힘'.
 * AI 연결: 추천 칩 + 입력창(ChatBar). 미연결: 버튼 4개(ActionBar). 오류는 피드 안에 AI 말투로.
 */
export function VideoDetail({ id }: { id: string }) {
  const qc = useQueryClient();
  const q = useQuery({ queryKey: queryKeys.video(id), queryFn: () => api.video(id) });
  const health = useQuery({ queryKey: queryKeys.health, queryFn: api.health, refetchInterval: 15_000 });
  const [open, setOpen] = useState(false);
  const [picking, setPicking] = useState(false);
  const [localError, setLocalError] = useState<string | null>(null);
  const [prefill, setPrefill] = useState<{ text: string; at: number } | undefined>(undefined);
  const feedEnd = useRef<HTMLDivElement>(null);

  const invalidate = () => void qc.invalidateQueries({ queryKey: queryKeys.video(id) });
  const onError = (err: unknown) => setLocalError(errorMessage(err instanceof ApiError ? err.code : 'edit_failed'));
  const act = useMutation({
    mutationFn: (body: ActionRequest) => api.act(id, body),
    onSuccess: () => {
      setLocalError(null);
      invalidate();
    },
    onError,
  });
  const chat = useMutation({
    mutationFn: (text: string) => api.chat(id, text),
    onSuccess: () => {
      setLocalError(null);
      invalidate();
    },
    onError,
  });
  const stop = useMutation({ mutationFn: () => api.cancelChat(id), onSuccess: invalidate });

  const messageCount = q.data?.messages.length ?? 0;
  const lastUpdated = q.data?.messages.at(-1)?.updatedAt ?? 0;
  useEffect(() => {
    feedEnd.current?.scrollIntoView({ block: 'end' });
  }, [messageCount, lastUpdated]);

  if (q.isPending) return <Shell title="">{null}</Shell>;
  if (q.isError || !q.data) return <Shell title="">{copy.empty.disconnected}</Shell>;
  const { video, outputs, messages, jobs, aiBusy } = q.data;
  const aiOn = health.data?.ai.connected ?? false;
  const busy = jobs.length > 0;
  const chatBusy = aiBusy || messages.some(isStreaming) || chat.isPending;
  const hasAudio = video.hasAudio !== false;

  const onAction = (key: ActionKey) => {
    if (key === 'short') {
      setPicking(true);
      return;
    }
    act.mutate({ type: key });
  };
  const onRevise = (o: OutputCard) => setPrefill({ text: copy.detail.outputCard.revisePrefill(o.title), at: Date.now() });

  return (
    <div className="flex h-full flex-col bg-surface" data-testid="video-detail" data-ai={aiOn ? 'on' : 'off'}>
      <ScreenHeader title={video.title} />

      {/* 프리뷰: 접힘(썸네일 + 메타) / 펼침(플레이어) */}
      <div className="flex-none border-b border-line">
        <button type="button" onClick={() => setOpen((v) => !v)} className="flex w-full items-center gap-2.5 px-3.5 py-2.5 text-left" data-testid="preview-toggle">
          {!open && <Thumb src={video.thumbnailUrl} ratio="16/9" className="w-16 flex-none rounded-[6px]" />}
          <div className="flex min-w-0 flex-1 flex-col gap-0.5">
            <div className="text-12 text-text-2">
              {formatDuration(video.durationSec)} · {formatDate(video.recordedAt)} · {outputs.length ? copy.detail.outputs(outputs.length) : copy.detail.noOutputs}
            </div>
            <div className="text-13 text-text-3">{open ? copy.detail.previewClose : copy.detail.previewOpen}</div>
          </div>
          <span className="text-text-2">
            <ChevronIcon up={open} />
          </span>
        </button>
        {open && video.proxyUrl && (
          <div className="px-3.5 pb-3">
            <video src={video.proxyUrl} poster={video.thumbnailUrl ?? undefined} controls playsInline className="w-full rounded-thumb bg-thumb" style={{ aspectRatio: '16/9' }} data-testid="preview-video" />
          </div>
        )}
      </div>

      <main className="mx-auto flex min-h-0 w-full max-w-[560px] flex-1 flex-col gap-2 overflow-y-auto px-3.5 py-3">
        <ChatFeed messages={messages} outputs={outputs} jobs={jobs} onRevise={aiOn ? onRevise : undefined} />
        {localError && (
          <div className="max-w-[80%] self-start rounded-[12px_12px_12px_4px] bg-bg px-[11px] py-2 text-13 leading-[1.55]" data-testid="chat-error">
            {localError}
          </div>
        )}
        {picking && (
          <ShortPicker
            proxyUrl={video.proxyUrl}
            posterUrl={video.thumbnailUrl}
            durationSec={video.durationSec ?? 0}
            hasAudio={hasAudio}
            onCancel={() => setPicking(false)}
            onMake={(range, subtitles) => {
              setPicking(false);
              act.mutate({ type: 'short', range, subtitles });
            }}
          />
        )}
        <div ref={feedEnd} />
      </main>

      {aiOn ? (
        <ChatBar busy={chatBusy} disabled={video.status !== 'ready'} prefill={prefill} onSend={(t) => chat.mutate(t)} onStop={() => stop.mutate()} />
      ) : (
        <ActionBar hasAudio={hasAudio} busy={busy || act.isPending} disabled={video.status !== 'ready'} onAction={onAction} />
      )}
    </div>
  );
}

function Shell({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="flex h-full flex-col bg-surface">
      <ScreenHeader title={title} />
      <main className="flex flex-1 items-center justify-center p-4 text-13 text-text-2">{children}</main>
    </div>
  );
}
