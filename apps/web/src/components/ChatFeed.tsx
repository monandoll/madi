import { type Chapters, type ChatMessage, isStreaming, type Job, type OutputCard, type TimeRange } from '@madi/shared';
import { chatText, copy, errorMessage } from '../copy.js';
import { formatDuration } from '../lib/format.js';
import { go } from '../lib/route.js';
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
}

/**
 * design/Mobile.dc.html '영상 상세' 가운데 피드.
 * 말풍선(assistant 왼쪽 F7F3EE / user 오른쪽 F1EAE2), 결과물 카드, 진행 카드. 오류도 말풍선.
 * 에이전트가 쓰는 중인 말풍선은 글자가 차오르고, 비어 있으면 "생각하는 중 / 만드는 중".
 */
export function ChatFeed({ messages, outputs, jobs, onRevise, chapters, onShortFromChapter }: Props) {
  const outputById = new Map(outputs.map((o) => [o.id, o]));
  const jobById = new Map(jobs.map((j) => [j.id, j]));
  return (
    <div className="flex flex-col gap-2" data-testid="chat-feed">
      {messages.map((m) => {
        if (m.kind === 'output') {
          const o = m.outputId ? outputById.get(m.outputId) : undefined;
          return (
            <div key={m.id} className="flex flex-col gap-2">
              <Bubble role="assistant">{chatText(m.code, m.params)}</Bubble>
              {o && <OutputRow output={o} onRevise={onRevise} />}
            </div>
          );
        }
        if (m.kind === 'progress') {
          const job = m.jobId ? jobById.get(m.jobId) : undefined;
          return <ProgressCard key={m.id} label={chatText(m.code, m.params)} progress={job?.progress ?? 0} durationSec={Number(m.params['durationSec'] ?? 0)} />;
        }
        if (m.kind === 'error') {
          return (
            <Bubble key={m.id} role="assistant" testId="chat-error">
              {errorMessage(m.code)}
            </Bubble>
          );
        }
        if (m.kind === 'chapters') {
          return (
            <div key={m.id} className="flex flex-col gap-2">
              <Bubble role="assistant">{chatText(m.code, m.params)}</Bubble>
              {chapters && chapters.items.length > 0 && <ChaptersCard chapters={chapters} onShort={onShortFromChapter} />}
            </div>
          );
        }
        if (isStreaming(m)) {
          const text = String(m.params['text'] ?? '');
          const hint = m.params['status'] === 'working' ? copy.detail.chat.working : copy.detail.chat.thinking;
          return (
            <Bubble key={m.id} role="assistant" testId="bubble-streaming">
              {text ? <span className="whitespace-pre-wrap">{text}</span> : <span className="text-text-2">{hint}</span>}
              <Dots />
            </Bubble>
          );
        }
        return (
          <Bubble key={m.id} role={m.role}>
            <span className="whitespace-pre-wrap">{chatText(m.code, m.params)}</span>
          </Bubble>
        );
      })}
    </div>
  );
}

function Bubble({ role, children, testId }: { role: 'assistant' | 'user'; children: React.ReactNode; testId?: string }) {
  return (
    <div
      data-testid={testId ?? `bubble-${role}`}
      className={`max-w-[80%] px-[11px] py-2 text-13 leading-[1.55] ${
        role === 'user' ? 'self-end rounded-[12px_12px_4px_12px] bg-line-soft' : 'self-start rounded-[12px_12px_12px_4px] bg-bg'
      }`}
    >
      {children}
    </div>
  );
}

/** 쓰는 중 표시: 점 세 개가 차례로 진해진다. 붉은색·스피너 없음. */
function Dots() {
  return (
    <span className="ml-1 inline-flex gap-[3px] align-middle" aria-hidden="true">
      {[0, 1, 2].map((i) => (
        <span key={i} className="h-[4px] w-[4px] rounded-pill bg-text-2 animate-pulse" style={{ animationDelay: `${i * 200}ms` }} />
      ))}
    </span>
  );
}

/** 진행 카드: 제목 · 남은 시간 · 4px 바. */
export function ProgressCard({ label, progress, durationSec }: { label: string; progress: number; durationSec: number }) {
  const pct = Math.round(Math.max(0.03, Math.min(1, progress)) * 100);
  return (
    <div className="flex w-full flex-col gap-2 self-start rounded-panel border border-line px-3 py-[11px]" data-testid="progress-card">
      <div className="flex items-baseline justify-between">
        <span className="text-13 font-medium">{label}</span>
        <span className="text-11 text-text-2">{copy.detail.progressEta(durationSec * (1 - progress) * 0.5)}</span>
      </div>
      <div className="relative h-1 rounded-pill bg-track">
        <div className="absolute inset-y-0 left-0 rounded-pill bg-accent" style={{ width: `${pct}%` }} />
      </div>
    </div>
  );
}

/** 결과물 한 줄: 세로 썸네일 · 제목 · 메타 · 다운로드/수정 요청/자세히. */
export function OutputRow({ output, first = true, onRevise }: { output: OutputCard; first?: boolean; onRevise?: ((o: OutputCard) => void) | undefined }) {
  return (
    <div className={`flex items-center gap-2.5 px-2.5 py-[9px] ${first ? '' : 'border-t border-line-soft'}`} data-testid="output-row">
      <Thumb src={output.thumbnailUrl} ratio={output.width < output.height ? '9/16' : '16/9'} className={`flex-none rounded-[5px] ${output.width < output.height ? 'w-[42px]' : 'w-[64px]'}`} />
      <div className="flex min-w-0 flex-1 flex-col gap-[3px]">
        <div className="truncate text-13 font-medium">{output.title}</div>
        <div className="text-11 text-text-2">
          {formatDuration(output.durationSec)} · {output.width < output.height ? '9:16' : '16:9'}
        </div>
        <div className="flex gap-2.5 text-12 text-text-3">
          <a href={output.downloadUrl} download className="text-text-3">
            {copy.detail.outputCard.download}
          </a>
          {onRevise ? (
            <button type="button" onClick={() => onRevise(output)} data-testid="output-revise">
              {copy.detail.outputCard.revise}
            </button>
          ) : (
            <button type="button" title={copy.detail.outputCard.reviseHint} className="text-text-2" disabled>
              {copy.detail.outputCard.revise}
            </button>
          )}
          <button type="button" onClick={() => go({ screen: 'output', id: output.id })}>
            {copy.detail.outputCard.more}
          </button>
        </div>
      </div>
    </div>
  );
}

/** 결과물 여러 개를 한 카드에 (시안의 clips 카드). */
export function OutputList({ outputs, onRevise }: { outputs: OutputCard[]; onRevise?: ((o: OutputCard) => void) | undefined }) {
  return (
    <div className="flex w-full flex-col overflow-hidden rounded-panel border border-line" data-testid="output-list">
      {outputs.map((o, i) => (
        <OutputRow key={o.id} output={o} first={i === 0} onRevise={onRevise} />
      ))}
    </div>
  );
}

/** 챕터 목록 카드: 번호 · 제목 · 구간 · 숏폼으로. 결과물 카드와 같은 틀(1px 선, 12px 모서리). */
export function ChaptersCard({ chapters, onShort }: { chapters: Chapters; onShort?: ((range: TimeRange, title: string) => void) | undefined }) {
  return (
    <div className="flex w-full flex-col overflow-hidden rounded-panel border border-line" data-testid="chapters-card">
      <div className="flex items-baseline justify-between px-3 pt-[10px] pb-1">
        <span className="text-13 font-medium">{copy.detail.chaptersCard.title(chapters.items.length)}</span>
        <span className="text-11 text-text-2">{formatDuration(chapters.items[chapters.items.length - 1]?.end ?? 0)}</span>
      </div>
      {chapters.items.map((c) => (
        <div key={c.index} className="flex items-center gap-2.5 border-t border-line-soft px-3 py-[9px]" data-testid="chapter-row">
          <span className="w-5 flex-none text-11 text-text-2">{c.index + 1}</span>
          <div className="flex min-w-0 flex-1 flex-col gap-[2px]">
            <div className="truncate text-13 font-medium">{c.title}</div>
            <div className="text-11 text-text-2">
              {formatDuration(c.start)} – {formatDuration(c.end)} · {formatDuration(c.end - c.start)}
            </div>
          </div>
          {c.highlight && onShort ? (
            <button type="button" onClick={() => onShort(c.highlight!, c.title)} className="flex-none text-12 text-text-3" data-testid="chapter-short">
              {copy.detail.chaptersCard.makeShort}
            </button>
          ) : (
            <span className="flex-none text-11 text-text-2">{c.highlight ? '' : copy.detail.chaptersCard.noHighlight}</span>
          )}
        </div>
      ))}
    </div>
  );
}
