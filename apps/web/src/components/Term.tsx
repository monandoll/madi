import { useEffect, useRef, useState } from 'react';
import { FitAddon } from '@xterm/addon-fit';
import { Terminal } from '@xterm/xterm';
import { TermOut, type TermKind } from '@madi/shared';
import '@xterm/xterm/css/xterm.css';
import { copy } from '../copy.js';

/**
 * 화면 안 터미널. 로그인·깔기를 이 자리에서 끝낸다 (검은 창을 따로 찾지 않게, 폰에서도 되게).
 * 엔진이 열어 주는 것은 정해진 몇 개뿐이라 여기서 아무 명령이나 칠 수는 없다.
 * 색은 디자인 토큰을 그대로 쓴다.
 */
export function Term({ kind, onClose, onFallback }: { kind: TermKind; onClose(): void; onFallback?: (() => void) | undefined }) {
  const box = useRef<HTMLDivElement>(null);
  const [title, setTitle] = useState<string | null>(null);
  const [line, setLine] = useState<string | null>(null);
  const [done, setDone] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const el = box.current;
    if (!el) return;
    const term = new Terminal({
      fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace',
      fontSize: 12,
      cursorBlink: true,
      convertEol: true,
      theme: { background: '#1C2127', foreground: '#EDF2F6', cursor: '#EDF2F6', selectionBackground: '#3E6B8A' },
    });
    const fit = new FitAddon();
    term.loadAddon(fit);
    term.open(el);
    fit.fit();

    const url = `${location.protocol === 'https:' ? 'wss' : 'ws'}://${location.host}/api/term`;
    const ws = new WebSocket(url);
    const send = (msg: unknown) => ws.readyState === WebSocket.OPEN && ws.send(JSON.stringify(msg));

    ws.onopen = () => send({ t: 'open', kind, cols: term.cols, rows: term.rows });
    ws.onmessage = (evt) => {
      const parsed = TermOut.safeParse(safeJson(String(evt.data)));
      if (!parsed.success) return;
      const msg = parsed.data;
      if (msg.t === 'ready') {
        setTitle(msg.title);
        setLine(msg.line);
      } else if (msg.t === 'out') term.write(msg.d);
      else if (msg.t === 'exit') setDone(msg.code);
      else if (msg.t === 'error') {
        if (msg.line) setLine(msg.line);
        setError(
          msg.code === 'busy'
            ? copy.settings.termBusy
            : msg.code === 'no_pty'
              ? copy.settings.termNoPty
              : msg.code === 'bad_kind'
                ? copy.settings.termFailed
                : copy.settings.termMissing,
        );
      }
    };
    ws.onclose = () => setDone((d) => d ?? 0);
    ws.onerror = () => setError(copy.settings.termFailed);

    const typed = term.onData((d) => send({ t: 'in', d }));
    const resize = () => {
      fit.fit();
      send({ t: 'size', cols: term.cols, rows: term.rows });
    };
    window.addEventListener('resize', resize);
    term.focus();

    return () => {
      window.removeEventListener('resize', resize);
      typed.dispose();
      try {
        send({ t: 'kill' });
        ws.close();
      } catch {
        /* 이미 닫혔다 */
      }
      term.dispose();
    };
  }, [kind]);

  return (
    <div className="flex flex-col gap-2 rounded-thumb border border-line px-3 py-2.5" data-testid="term">
      <div className="flex items-baseline justify-between gap-3">
        <span className="text-13 font-medium" data-testid="term-title">
          {title ?? copy.settings.termOpening}
        </span>
        <button type="button" onClick={onClose} className="text-13 text-text-3 hover:text-accent" data-testid="term-close">
          {copy.settings.termClose}
        </button>
      </div>
      <p className="text-12 leading-normal text-text-3">{copy.settings.termHelp}</p>
      {error ? (
        <p className="flex flex-wrap items-center gap-x-2 text-12 text-error" data-testid="term-error">
          {error}
          {onFallback && (
            <button type="button" className="text-accent hover:text-accent-hover" onClick={onFallback} data-testid="term-fallback">
              {copy.settings.termNative}
            </button>
          )}
        </p>
      ) : (
        <div className="overflow-hidden rounded-row bg-[#1C2127] px-2 py-2" style={{ height: 260 }}>
          <div ref={box} className="h-full w-full" />
        </div>
      )}
      {done !== null && (
        <p className="text-12 text-text-2" data-testid="term-done">
          {done === 0 ? copy.settings.termDone : copy.settings.termStopped}
        </p>
      )}
      {line && <p className="text-12 text-text-3">{copy.settings.termLine(line)}</p>}
    </div>
  );
}

function safeJson(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}
