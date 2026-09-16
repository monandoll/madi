import type { ChatMessage, Job, OutputCard } from '@madi/shared';
import { chatText, copy, errorMessage } from '../copy.js';
import { formatDuration } from '../lib/format.js';
import { go } from '../lib/route.js';
import { Thumb } from './Thumb.js';

interface Props {
  messages: ChatMessage[];
  outputs: OutputCard[];
  jobs: Job[];
}

/**
 * design/Mobile.dc.html '영상 상세' 가운데 피드.
 * 말풍선(assistant 왼쪽 F7F3EE / user 오른쪽 F1EAE2), 결과물 카드, 진행 카드. 오류도 말풍선.
 */
export function ChatFeed({ messages, outputs, jobs }: Props) {
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
              {o && <OutputRow output={o} />}
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
        return (
          <Bubble key={m.id} role={m.role}>
            {chatText(m.code, m.params)}
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
export function OutputRow({ output, first = true }: { output: OutputCard; first?: boolean }) {
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
          <button type="button" title={copy.detail.outputCard.reviseHint} className="text-text-2" disabled>
            {copy.detail.outputCard.revise}
          </button>
          <button type="button" onClick={() => go({ screen: 'output', id: output.id })}>
            {copy.detail.outputCard.more}
          </button>
        </div>
      </div>
    </div>
  );
}

/** 결과물 여러 개를 한 카드에 (시안의 clips 카드). */
export function OutputList({ outputs }: { outputs: OutputCard[] }) {
  return (
    <div className="flex w-full flex-col overflow-hidden rounded-panel border border-line" data-testid="output-list">
      {outputs.map((o, i) => (
        <OutputRow key={o.id} output={o} first={i === 0} />
      ))}
    </div>
  );
}
