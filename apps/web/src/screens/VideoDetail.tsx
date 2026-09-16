import { useEffect, useRef, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { type ActionRequest, isStreaming, LONGFORM_MIN_SEC, type OutputCard } from '@madi/shared';
import { type ActionKey, ActionBar } from '../components/ActionBar.js';
import { ChatBar } from '../components/ChatBar.js';
import { ChatFeed } from '../components/ChatFeed.js';
import { CloseIcon, PlayIcon } from '../components/Icons.js';
import { OutputView } from '../components/OutputView.js';
import { ShortPicker } from '../components/ShortPicker.js';
import { Thumb } from '../components/Thumb.js';
import { HeaderButton, TopBar } from '../components/TopBar.js';
import { copy, errorMessage } from '../copy.js';
import { ApiError, api, queryKeys } from '../lib/api.js';
import { formatDate, formatDuration } from '../lib/format.js';
import { go } from '../lib/route.js';
import { useIsPc, useUi } from '../store.js';

interface Props {
  id: string;
  /** PC: 옆 패널에 열 결과물 (#/outputs/:id 로 들어왔을 때) */
  panelOutputId?: string | undefined;
}

/**
 * design/v2 영상 상세 = 채팅.
 * 위: 영상 카드(썸네일 · 길이/촬영일/결과물 · 프리뷰 보기). 가운데: 피드. 아래: AI 연결이면 칩 + 입력창, 아니면 버튼 4개.
 * PC 는 오른쪽에 380px 결과물 패널이 겹쳐 열린다. 오류는 피드 안에 AI 말투로.
 */
export function VideoDetail({ id, panelOutputId }: Props) {
  const pc = useIsPc();
  const qc = useQueryClient();
  const q = useQuery({ queryKey: queryKeys.video(id), queryFn: () => api.video(id) });
  const health = useQuery({ queryKey: queryKeys.health, queryFn: api.health, refetchInterval: 15_000 });
  const [open, setOpen] = useState(false);
  const [picking, setPicking] = useState(false);
  const [localError, setLocalError] = useState<string | null>(null);
  const [prefill, setPrefill] = useState<{ text: string; at: number } | undefined>(undefined);
  const panel = panelOutputId ?? null;
  const feedEnd = useRef<HTMLDivElement>(null);
  const storePrefill = useUi((s) => s.prefill);

  // 결과물 화면에서 "이 문장 고쳐줘" 로 넘어온 말
  useEffect(() => {
    if (storePrefill && storePrefill.videoId === id) setPrefill({ text: storePrefill.text, at: storePrefill.at });
  }, [storePrefill, id]);

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
  const { video, outputs, messages, jobs, aiBusy, chapters, transcript } = q.data;
  const aiOn = health.data?.ai.connected ?? false;
  const busy = jobs.length > 0;
  const chatBusy = aiBusy || messages.some(isStreaming) || chat.isPending;
  const hasAudio = video.hasAudio !== false;
  const longform = (video.durationSec ?? 0) >= LONGFORM_MIN_SEC;
  const latest = outputs[outputs.length - 1];

  const onAction = (key: ActionKey) => {
    if (key === 'short') {
      setPicking(true);
      return;
    }
    if (key === 'auto_shorts') {
      act.mutate({ type: 'auto_shorts', max: 3 });
      return;
    }
    act.mutate({ type: key });
  };
  // 챕터 카드의 숏폼은 되묻지 않는다: 자막이 이미 있으면 넣고, 없으면 자막 없이 (자막을 새로 만들지 않는다)
  const onShortFromChapter = (range: { start: number; end: number }) => act.mutate({ type: 'short', range, subtitles: hasAudio && !!transcript });
  const ask = (text: string) => setPrefill({ text, at: Date.now() });
  const onRevise = (o: OutputCard) => ask(copy.detail.outputCard.revisePrefill(o.title));
  const openOutput = (o: OutputCard) => go({ screen: 'output', id: o.id });
  const closePanel = () => go({ screen: 'video', id });
  const meta = `${formatDuration(video.durationSec)} · ${formatDate(video.recordedAt)}`;
  const outputsLabel = outputs.length ? copy.detail.outputs(outputs.length) : copy.detail.noOutputs;

  return (
    <div className="relative flex h-full min-h-0 flex-col bg-surface" data-testid="video-detail" data-ai={aiOn ? 'on' : 'off'}>
      {pc ? (
        <TopBar
          title={video.title}
          meta={`${meta} · ${outputsLabel}`}
          actions={
            <>
              {latest && (
                <HeaderButton outlined onClick={() => (panel ? closePanel() : openOutput(latest))} testId="panel-toggle">
                  {panel ? copy.header.panelClose : copy.header.panelOpen}
                </HeaderButton>
              )}
              <HeaderButton onClick={() => go({ screen: 'gallery' })}>{copy.header.gallery}</HeaderButton>
            </>
          }
        />
      ) : (
        <TopBar
          title={video.title}
          meta={meta}
          showBack
          aside={
            latest && (
              <button type="button" onClick={() => go({ screen: 'output', id: latest.id })} className="flex-none rounded-thumb px-2 py-[5px] text-13 text-accent hover:bg-accent-faint">
                {copy.header.outputs}
              </button>
            )
          }
        />
      )}

      <main className="flex min-h-0 w-full flex-1 flex-col gap-1 overflow-x-hidden overflow-y-auto px-3.5 pt-3 pb-3.5 pc:gap-1.5 pc:px-6 pc:pt-[18px]">
        {/* 영상 카드: 썸네일 · 메타 · 프리뷰 보기 */}
        <div className="mb-1.5 flex flex-col overflow-hidden rounded-panel border border-line bg-surface-2">
          <button type="button" onClick={() => setOpen((v) => !v)} className="flex w-full items-center gap-2.5 px-2.5 py-[9px] text-left pc:items-start pc:gap-3.5 pc:p-3" data-testid="preview-toggle">
            <Thumb src={video.thumbnailUrl} ratio="16/9" className="w-[72px] flex-none rounded-[6px] pc:w-[150px]">
              <span className="absolute top-1/2 left-1/2 flex h-[22px] w-[22px] -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-pill bg-[rgba(255,255,255,0.92)] text-text pc:h-[30px] pc:w-[30px]">
                <PlayIcon size={pc ? 11 : 9} />
              </span>
            </Thumb>
            <span className="flex min-w-0 flex-1 flex-col gap-0.5 pc:hidden">
              <span className="text-12 text-text-3">
                {formatDuration(video.durationSec)} · {outputsLabel}
              </span>
              <span className="text-13 text-text-2">{open ? copy.detail.previewClose : copy.detail.previewOpen}</span>
            </span>
            <span className="hidden min-w-0 flex-1 flex-col gap-[5px] pc:flex">
              <Prop k={copy.detail.props.duration} v={formatDuration(video.durationSec)} />
              <Prop k={copy.detail.props.recorded} v={formatDate(video.recordedAt)} />
              <Prop k={copy.detail.props.outputs} v={outputs.length ? copy.detail.props.count(outputs.length) : copy.detail.props.none} />
              <span className="pt-0.5 text-12 text-accent">{open ? copy.detail.previewClose : copy.detail.previewOpen}</span>
            </span>
          </button>
          {open && video.proxyUrl && (
            <div className="px-2.5 pb-2.5 pc:px-3 pc:pb-3">
              <video src={video.proxyUrl} poster={video.thumbnailUrl ?? undefined} controls playsInline className="w-full max-w-[560px] rounded-thumb bg-thumb" style={{ aspectRatio: '16/9' }} data-testid="preview-video" />
            </div>
          )}
        </div>

        <ChatFeed messages={messages} outputs={outputs} jobs={jobs} onRevise={aiOn ? onRevise : undefined} chapters={chapters} onShortFromChapter={busy || act.isPending ? undefined : onShortFromChapter} onOpenOutput={openOutput} />
        {localError && (
          <div className="rounded-thumb bg-accent-faint px-3 py-2 text-13 leading-normal" data-testid="chat-error">
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
        <ChatBar busy={chatBusy} disabled={video.status !== 'ready'} prefill={prefill} longform={longform} onSend={(t) => chat.mutate(t)} onStop={() => stop.mutate()} />
      ) : (
        <ActionBar hasAudio={hasAudio} busy={busy || act.isPending} disabled={video.status !== 'ready'} longform={longform} onAction={onAction} />
      )}

      {pc && panel && <OutputPanel outputId={panel} onClose={closePanel} onAsk={aiOn ? ask : undefined} />}
    </div>
  );
}

function Prop({ k, v }: { k: string; v: string }) {
  return (
    <span className="flex items-baseline gap-2.5">
      <span className="w-16 flex-none text-12 text-text-3">{k}</span>
      <span className="min-w-0 flex-1 truncate text-13">{v}</span>
    </span>
  );
}

/** PC 오른쪽 결과물 패널 (380px, 1px 왼선). 제목 · 메타 · 닫기 + OutputView. */
function OutputPanel({ outputId, onClose, onAsk }: { outputId: string; onClose(): void; onAsk?: ((text: string) => void) | undefined }) {
  const q = useQuery({ queryKey: queryKeys.output(outputId), queryFn: () => api.output(outputId) });
  const o = q.data?.output;
  const vertical = o ? o.width < o.height : true;
  return (
    <aside className="absolute inset-y-0 right-0 z-10 flex w-[380px] max-w-[94%] flex-col overflow-hidden border-l border-line bg-surface" data-testid="output-detail">
      <header className="flex min-h-[50px] flex-none items-center gap-2.5 border-b border-line-2 px-3.5 py-2">
        <div className="flex min-w-0 flex-1 flex-col gap-px">
          <h2 className="truncate text-14 font-semibold">{o?.title ?? ''}</h2>
          <div className="text-12 text-text-3">{o ? `${formatDuration(o.durationSec)} · ${vertical ? '9:16' : '16:9'}` : ''}</div>
        </div>
        <button type="button" onClick={onClose} aria-label={copy.output.close} className="flex h-[26px] w-[26px] flex-none items-center justify-center rounded-row text-text-2 hover:bg-hover" data-testid="panel-close">
          <CloseIcon />
        </button>
      </header>
      {q.data ? <OutputView data={q.data} onAsk={onAsk} /> : <div className="flex flex-1 items-center justify-center p-4 text-13 text-text-3">{q.isError ? copy.output.notFound : copy.empty.loading}</div>}
    </aside>
  );
}

function Shell({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="flex h-full flex-col bg-surface">
      <TopBar title={title} showBack />
      <main className="flex flex-1 items-center justify-center p-4 text-13 text-text-3">{children}</main>
    </div>
  );
}
