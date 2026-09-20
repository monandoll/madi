import { useEffect, useRef, useState } from 'react';
import { copy } from '../copy.js';
import { ArrowUpIcon, StopIcon } from './Icons.js';

interface Props {
  busy: boolean;
  disabled?: boolean;
  /** 밖에서 채워 넣는 말 (결과물 카드의 수정 요청). 바뀔 때마다 입력창에 들어간다. */
  prefill?: { text: string; at: number } | undefined;
  /** 긴 영상이면 챕터·숏폼 여러 개 칩 */
  longform?: boolean;
  onSend(text: string, fromInput?: boolean): void;
  onStop(): void;
}

/**
 * design/v2 영상 상세 아래: 추천 칩 한 줄(999px) + 입력(모바일 999px 테두리 / PC 10px 카드) + accent 보내기.
 * AI 가 연결됐을 때만 보인다. 답하는 동안은 보내기 대신 멈추기.
 */
export function ChatBar({ busy, disabled = false, prefill, longform = false, onSend, onStop }: Props) {
  const [text, setText] = useState('');
  const input = useRef<HTMLInputElement>(null);
  useEffect(() => {
    if (!prefill) return;
    setText(prefill.text);
    input.current?.focus();
  }, [prefill]);

  const submit = () => {
    const t = text.trim();
    if (!t || busy || disabled) return;
    onSend(t, true);
    setText('');
  };
  const canSend = !!text.trim() && !disabled;

  return (
    <div className="flex flex-none flex-col gap-2 border-t border-line-soft bg-surface px-3 pt-[9px] pb-3.5 pc:border-line-2 pc:px-6 pc:pt-2.5 pc:pb-4" data-testid="chat-bar">
      <div className="flex gap-1.5 overflow-x-auto pc:flex-wrap">
        {(longform ? copy.detail.chat.chipsLong : copy.detail.chat.chips).map((chip) => (
          <button
            key={chip}
            type="button"
            disabled={busy || disabled}
            onClick={() => onSend(chip)}
            className="shrink-0 rounded-pill border border-line px-3 py-1.5 text-13 whitespace-nowrap text-text-4 hover:border-accent hover:text-accent disabled:text-text-3 disabled:hover:border-line pc:px-[11px] pc:py-[5px]"
            data-testid="chat-chip"
          >
            {chip}
          </button>
        ))}
      </div>
      <form
        className="flex items-center gap-2 rounded-pill border border-input py-[5px] pr-[5px] pl-4 pc:gap-2.5 pc:rounded-panel pc:py-2.5 pc:pr-2.5 pc:pl-3.5"
        onSubmit={(e) => {
          e.preventDefault();
          submit();
        }}
      >
        <input
          ref={input}
          data-testid="chat-input"
          className="h-[34px] min-w-0 flex-1 bg-transparent text-15 outline-none placeholder:text-text-3 pc:h-[30px]"
          placeholder={copy.detail.chat.placeholder}
          value={text}
          disabled={disabled}
          maxLength={2000}
          autoComplete="off"
          onChange={(e) => setText(e.target.value)}
        />
        {busy ? (
          <button
            type="button"
            aria-label={copy.detail.chat.stop}
            title={copy.detail.chat.stop}
            onClick={onStop}
            className="flex h-[34px] w-[34px] flex-none items-center justify-center rounded-pill bg-accent text-white hover:bg-accent-hover pc:h-[30px] pc:w-[30px] pc:rounded-thumb"
            data-testid="chat-stop"
          >
            <StopIcon />
          </button>
        ) : (
          <button
            type="submit"
            aria-label={copy.detail.chat.send}
            title={copy.detail.chat.send}
            disabled={!canSend}
            className={`flex h-[34px] w-[34px] flex-none items-center justify-center rounded-pill pc:h-[30px] pc:w-[30px] pc:rounded-thumb ${canSend ? 'bg-accent text-white hover:bg-accent-hover' : 'bg-track text-muted'}`}
            data-testid="chat-send"
          >
            <ArrowUpIcon />
          </button>
        )}
      </form>
    </div>
  );
}
