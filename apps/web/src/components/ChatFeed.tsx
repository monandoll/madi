import { type Chapters, type ChatMessage, type EditPlan, isStreaming, type Job, type OutputCard, type TimeRange } from '@madi/shared';
import { chatText, copy, errorMessage } from '../copy.js';
import { formatDuration, formatTime } from '../lib/format.js';
import { go } from '../lib/route.js';
import { PlanCard } from './PlanCard.js';
import { Thumb } from './Thumb.js';

interface Props {
  messages: ChatMessage[];
  outputs: OutputCard[];
  jobs: Job[];
  /** AI 연결 시 결과물 카드의 "수정 요청"이 산다 */
  onRevise?: ((output: OutputCard) => void) | undefined;
  /** 롱폼 챕터 (chapters 카드가 읽는다) */
  chapters?: Chapters | null | undefined;
  /** 챕터 카드의 "숏폼으로" */
  onShortFromChapter?: ((range: TimeRange, title: string) => void) | undefined;
  /** 결과물 카드 "자세히" — PC 는 옆 패널, 모바일은 결과물 화면 */
  onOpenOutput?: ((output: OutputCard) => void) | undefined;
  /** 편집안 (plan 카드가 읽는다) */
  plan?: EditPlan | null | undefined;
  /** 편집안 카드의 숏폼 후보 "만들기" */
  onShortFromPlan?: ((range: TimeRange, title: string) => void) | undefined;
  /** 편집안 카드의 "롱폼 만들기" */
  onApplyPlan?: (() => void) | undefined;
}

/**
 * design/v2 영상 상세 피드: 아바타(마/나) · 이름 · 시각 · 글. 결과물 카드(왼쪽 3px accent 선), 챕터 카드, 진행 카드가 글 아래에 붙는다.
 * 에이전트가 쓰는 중이면 "마디가 보고 있어요…" 줄.
 */
export function ChatFeed({ messages, outputs, jobs, onRevise, chapters, onShortFromChapter, onOpenOutput, plan, onShortFromPlan, onApplyPlan }: Props) {
  const outputById = new Map(outputs.map((o) => [o.id, o]));
  const jobById = new Map(jobs.map((j) => [j.id, j]));
  return (
    <div className="flex flex-col gap-1 pc:gap-1.5" data-testid="chat-feed">
      {messages.map((m) => {
        if (m.kind === 'output') {
          const o = m.outputId ? outputById.get(m.outputId) : undefined;
          return (
            <Row key={m.id} role="assistant" at={m.createdAt} text={chatText(m.code, m.params)}>
              {o && <OutputRow output={o} onRevise={onRevise} onOpen={onOpenOutput} />}
            </Row>
          );
        }
        if (m.kind === 'progress') {
          const job = m.jobId ? jobById.get(m.jobId) : undefined;
          return (
            <Row key={m.id} role="assistant" at={m.createdAt}>
              <ProgressCard label={chatText(m.code, m.params)} progress={job?.progress ?? 0} durationSec={Number(m.params['durationSec'] ?? 0)} />
            </Row>
          );
        }
        if (m.kind === 'error') {
          const detail = typeof m.params['detail'] === 'string' && m.params['detail'] ? String(m.params['detail']) : null;
          return (
            <Row key={m.id} role="assistant" at={m.createdAt} text={errorMessage(m.code)} testId="chat-error">
              {detail && (
                <div className="truncate text-12 text-text-3" title={detail} data-testid="chat-error-detail">
                  {copy.detail.chat.errorDetail(detail)}
                </div>
              )}
            </Row>
          );
        }
        if (m.kind === 'plan') {
          return (
            <Row key={m.id} role="assistant" at={m.createdAt} text={chatText(m.code, m.params)}>
              {plan && <PlanCard plan={plan} onShort={onShortFromPlan} onApply={onApplyPlan} />}
            </Row>
          );
        }
        if (m.kind === 'chapters') {
          return (
            <Row key={m.id} role="assistant" at={m.createdAt} text={chatText(m.code, m.params)}>
              {chapters && chapters.items.length > 0 && <ChaptersCard chapters={chapters} onShort={onShortFromChapter} />}
            </Row>
          );
        }
        if (isStreaming(m)) {
          const text = String(m.params['text'] ?? '');
          const hint = m.params['status'] === 'working' ? copy.detail.chat.working : copy.detail.chat.thinking;
          return (
            <Row key={m.id} role="assistant" at={m.createdAt} testId="bubble-streaming" thinking={!text} thinkingText={hint} text={text || undefined} />
          );
        }
        return <Row key={m.id} role={m.role} at={m.createdAt} text={chatText(m.code, m.params)} />;
      })}
    </div>
  );
}

/** 메시지 한 줄: 26px 아바타(PC 30) · 이름 12/600 · 시각 11 · 글 14/1.6 (PC 15). testid 는 글 부분에 (카드는 밖). */
function Row({
  role,
  at,
  text,
  testId,
  thinking = false,
  thinkingText,
  children,
}: {
  role: 'assistant' | 'user';
  at: number;
  text?: React.ReactNode;
  testId?: string;
  thinking?: boolean;
  thinkingText?: string;
  children?: React.ReactNode;
}) {
  const me = role === 'user';
  return (
    <div className="-mx-2.5 flex gap-[9px] rounded-thumb px-2.5 py-[7px] pc:-mx-3 pc:gap-[11px] pc:px-3 pc:py-2 pc:hover:bg-[#F6FAFC]" data-role={role}>
      <span
        className={`flex h-[26px] w-[26px] flex-none items-center justify-center rounded-thumb text-10 font-bold pc:h-[30px] pc:w-[30px] pc:rounded-[9px] pc:text-11 ${me ? 'bg-avatar-me text-text-4' : 'bg-accent-soft text-accent-hover'}`}
        aria-hidden="true"
      >
        {me ? copy.detail.me : copy.detail.ai.charAt(0)}
      </span>
      <div className="flex min-w-0 flex-1 flex-col gap-[5px] pc:gap-1.5">
        <div className="flex items-baseline gap-[7px]">
          <span className="text-12 font-semibold pc:text-13">{me ? copy.detail.me : copy.detail.ai}</span>
          <span className="text-11 text-text-3">{formatTime(at)}</span>
        </div>
        {thinking ? (
          <div className="text-13 text-text-3 pc:text-14" data-testid={testId ?? `bubble-${role}`}>
            {thinkingText}
          </div>
        ) : (
          text !== undefined && (
            <div className="text-14 leading-[1.6] whitespace-pre-wrap pc:text-15" style={{ textWrap: 'pretty' }} data-testid={testId ?? `bubble-${role}`}>
              {text}
            </div>
          )
        )}
        {children}
      </div>
    </div>
  );
}

/** 진행 카드: 제목 14/500 · 남은 시간 12 · 4px 바. */
export function ProgressCard({ label, progress, durationSec }: { label: string; progress: number; durationSec: number }) {
  const pct = Math.round(Math.max(0.03, Math.min(1, progress)) * 100);
  return (
    <div className="flex w-full flex-col gap-2 rounded-thumb border border-line px-3 py-2.5" data-testid="progress-card">
      <div className="flex items-baseline justify-between gap-2">
        <span className="text-14 font-medium">{label}</span>
        <span className="text-12 text-text-3">{copy.detail.progressEta(durationSec * (1 - progress) * 0.5)}</span>
      </div>
      <div className="relative h-1 rounded-pill bg-track">
        <div className="absolute inset-y-0 left-0 rounded-pill bg-accent" style={{ width: `${pct}%` }} />
      </div>
    </div>
  );
}

/** 결과물 카드: 왼쪽 3px accent 선 · 썸네일 · 제목 · 메타 · 다운로드 / 수정 요청 / 자세히. */
export function OutputRow({ output, onRevise, onOpen }: { output: OutputCard; onRevise?: ((o: OutputCard) => void) | undefined; onOpen?: ((o: OutputCard) => void) | undefined }) {
  const vertical = output.width < output.height;
  const open = () => (onOpen ? onOpen(output) : go({ screen: 'output', id: output.id }));
  return (
    <div className="flex items-center gap-2.5 rounded-thumb border border-line border-l-[3px] border-l-accent bg-surface py-[9px] pr-2.5 pl-2.5 pc:gap-3 pc:py-2.5 pc:pr-3 pc:pl-3 pc:hover:bg-surface-2" data-testid="output-row">
      <div onClick={open} className="flex-none cursor-pointer">
        <Thumb src={output.thumbnailUrl} ratio={vertical ? '9/16' : '16/9'} className={`rounded-[5px] ${vertical ? 'w-[30px] pc:w-[34px]' : 'w-14 pc:w-16'}`} />
      </div>
      <div className="flex min-w-0 flex-1 flex-col gap-0.5">
        <div className="truncate text-13 font-medium pc:text-14">{output.title}</div>
        <div className="truncate text-11 text-text-3 pc:text-12">
          {formatDuration(output.durationSec)} · {vertical ? '9:16' : '16:9'}
        </div>
      </div>
      <div className="flex flex-none items-center gap-2.5 text-12 whitespace-nowrap pc:text-13">
        <a href={output.downloadUrl} download className="hidden text-text-2 hover:text-accent pc:inline">
          {copy.detail.outputCard.download}
        </a>
        {onRevise && (
          <button type="button" onClick={() => onRevise(output)} className="text-text-2 hover:text-accent" data-testid="output-revise">
            {copy.detail.outputCard.revise}
          </button>
        )}
        <button type="button" onClick={open} className="text-accent">
          {copy.detail.outputCard.more}
        </button>
      </div>
    </div>
  );
}

/** 결과물 목록 (결과물 탭): 제목 · 길이 · 비율. 누르면 결과물 화면/패널. */
export function OutputList({ outputs, onOpen }: { outputs: OutputCard[]; onOpen?: ((o: OutputCard) => void) | undefined }) {
  return (
    <div className="flex w-full flex-col overflow-hidden rounded-thumb border border-line" data-testid="output-list">
      {outputs.map((o, i) => {
        const vertical = o.width < o.height;
        return (
          <button
            key={o.id}
            type="button"
            onClick={() => (onOpen ? onOpen(o) : go({ screen: 'output', id: o.id }))}
            className={`flex items-center gap-2.5 px-3 py-2.5 text-left hover:bg-surface-2 ${i > 0 ? 'border-t border-line-soft' : ''}`}
            data-testid="output-row"
          >
            <Thumb src={o.thumbnailUrl} ratio={vertical ? '9/16' : '16/9'} className={`flex-none rounded-[5px] ${vertical ? 'w-[30px]' : 'w-14'}`} />
            <span className="flex min-w-0 flex-1 flex-col gap-0.5">
              <span className="truncate text-14 font-medium">{o.title}</span>
              <span className="text-12 text-text-3">
                {formatDuration(o.durationSec)} · {vertical ? '9:16' : '16:9'}
              </span>
            </span>
            <span className="flex-none text-13 text-accent">{copy.detail.outputCard.more}</span>
          </button>
        );
      })}
    </div>
  );
}

/** 챕터 카드: 번호 · 제목 · 구간 · 숏폼으로. */
export function ChaptersCard({ chapters, onShort }: { chapters: Chapters; onShort?: ((range: TimeRange, title: string) => void) | undefined }) {
  return (
    <div className="flex w-full flex-col overflow-hidden rounded-thumb border border-line" data-testid="chapters-card">
      <div className="flex items-baseline justify-between px-3 pt-2.5 pb-1">
        <span className="text-13 font-medium pc:text-14">{copy.detail.chaptersCard.title(chapters.items.length)}</span>
        <span className="text-11 text-text-3 pc:text-12">{formatDuration(chapters.items[chapters.items.length - 1]?.end ?? 0)}</span>
      </div>
      {chapters.items.map((c) => (
        <div key={c.index} className="flex items-center gap-2.5 border-t border-line-soft px-3 py-[9px] pc:gap-3 pc:hover:bg-surface-2" data-testid="chapter-row">
          <span className="w-3.5 flex-none text-12 text-text-3">{c.index + 1}</span>
          <span className="min-w-0 flex-1 truncate text-13 font-medium pc:text-14">{c.title}</span>
          <span className="flex-none text-11 text-text-3 pc:text-12">
            {formatDuration(c.start)} – {formatDuration(c.end)}
          </span>
          {c.highlight && onShort ? (
            <button type="button" onClick={() => onShort(c.highlight!, c.title)} className="flex-none text-12 text-accent pc:text-13" data-testid="chapter-short">
              {copy.detail.chaptersCard.makeShort}
            </button>
          ) : (
            <span className="flex-none text-11 text-text-3">{c.highlight ? '' : copy.detail.chaptersCard.noHighlight}</span>
          )}
        </div>
      ))}
    </div>
  );
}
