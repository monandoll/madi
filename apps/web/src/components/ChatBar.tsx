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
  onSend(text: string): void;
  onStop(): void;
}

/**
 * design/Mobile.dc.html 영상 상세 하단: 추천 칩 한 줄 + 둥근 입력(44px, bg) + accent 원형 보내기.
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
    onSend(t);
    setText('');
  };

  return (
    <div className="flex flex-none flex-col gap-2 border-t border-line px-3 pt-2.5 pb-3" data-testid="chat-bar">
      <div className="flex gap-1.5 overflow-x-auto">
        {(longform ? copy.detail.chat.chipsLong : copy.detail.chat.chips).map((chip) => (
          <button
            key={chip}
            type="button"
            disabled={busy || disabled}
            onClick={() => onSend(chip)}
            className="h-11 shrink-0 rounded-pill border border-line px-[11px] text-12 whitespace-nowrap disabled:text-text-2"
            data-testid="chat-chip"
          >
            {chip}
          </button>
        ))}
      </div>
      <form
        className="flex items-center gap-2"
        onSubmit={(e) => {
          e.preventDefault();
          submit();
        }}
      >
        <input
          ref={input}
          data-testid="chat-input"
          className="h-11 min-w-0 flex-1 rounded-pill bg-bg px-4 text-14 outline-none placeholder:text-text-2"
          placeholder={copy.detail.chat.placeholder}
          value={text}
          disabled={disabled}
          maxLength={2000}
          autoComplete="off"
          onChange={(e) => setText(e.target.value)}
        />
        {busy ? (
          <button type="button" aria-label={copy.detail.chat.stop} title={copy.detail.chat.stop} onClick={onStop} className="flex h-11 w-11 flex-none items-center justify-center rounded-pill bg-accent text-white" data-testid="chat-stop">
            <StopIcon />
          </button>
        ) : (
          <button type="submit" aria-label={copy.detail.chat.send} title={copy.detail.chat.send} disabled={disabled || !text.trim()} className="flex h-11 w-11 flex-none items-center justify-center rounded-pill bg-accent text-white disabled:opacity-60" data-testid="chat-send">
            <ArrowUpIcon />
          </button>
        )}
      </form>
    </div>
  );
}
