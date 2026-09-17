import { useEffect, useRef, useState } from 'react';
import { useMutation } from '@tanstack/react-query';
import { copy } from '../copy.js';
import { api, ApiError } from '../lib/api.js';

/**
 * 폰이 밖에서 처음 들어왔을 때. PC 화면의 6자리 숫자를 한 번 넣으면 그 기기는 기억된다.
 * QR 로 들어오면 주소에 숫자가 실려 있어 이 화면은 스쳐 지나간다.
 */
export function Pair({ onDone }: { onDone(): void }) {
  const [pin, setPin] = useState('');
  const [error, setError] = useState<string | null>(null);
  const input = useRef<HTMLInputElement>(null);
  const pair = useMutation({
    mutationFn: (value: string) => api.pair(value),
    onSuccess: () => {
      setError(null);
      onDone();
    },
    onError: (err) => {
      setPin('');
      setError(err instanceof ApiError && err.code === 'remote_off' ? copy.pair.off : copy.pair.wrong);
      input.current?.focus();
    },
  });

  // 주소에 숫자가 실려 오면(QR) 바로 넣어 본다
  useEffect(() => {
    const url = new URL(window.location.href);
    const fromQr = url.searchParams.get('pin');
    if (!fromQr) return;
    url.searchParams.delete('pin');
    window.history.replaceState(null, '', url.toString());
    pair.mutate(fromQr);
    // 한 번만
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const submit = () => {
    const value = pin.trim();
    if (value.length < 4 || pair.isPending) return;
    pair.mutate(value);
  };

  return (
    <div className="flex h-full flex-col items-center justify-center bg-side px-5" data-testid="pair-screen">
      <div className="flex w-full max-w-[380px] flex-col gap-3.5 rounded-card border border-line bg-surface px-5 py-6">
        <h1 className="text-20 font-semibold tracking-[-0.02em]">{copy.pair.title}</h1>
        <p className="text-14 leading-[1.65] text-text-2" style={{ textWrap: 'pretty' }}>
          {copy.pair.help}
        </p>
        <input
          ref={input}
          autoFocus
          value={pin}
          inputMode="numeric"
          autoComplete="one-time-code"
          maxLength={6}
          placeholder={copy.pair.placeholder}
          onChange={(e) => {
            setPin(e.target.value.replace(/\D/g, ''));
            setError(null);
          }}
          onKeyDown={(e) => {
            if (e.key === 'Enter') submit();
          }}
          className="w-full rounded-thumb border border-input bg-surface px-3.5 py-3 text-center text-20 tracking-[0.3em] outline-none placeholder:text-14 placeholder:tracking-normal placeholder:text-text-3 focus:border-accent"
          data-testid="pair-input"
        />
        {error && (
          <p className="text-13 text-error" data-testid="pair-error">
            {error}
          </p>
        )}
        <button
          type="button"
          onClick={submit}
          disabled={pin.trim().length < 4 || pair.isPending}
          className="min-h-11 rounded-thumb bg-accent text-14 font-semibold text-white hover:bg-accent-hover disabled:opacity-60"
          data-testid="pair-submit"
        >
          {pair.isPending ? copy.pair.checking : copy.pair.submit}
        </button>
      </div>
    </div>
  );
}
