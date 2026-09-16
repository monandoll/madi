import { useEffect, useRef, useState } from 'react';
import { copy } from '../copy.js';
import { formatDuration } from '../lib/format.js';
import { CheckIcon } from './Icons.js';

interface Props {
  proxyUrl: string | null;
  posterUrl: string | null;
  durationSec: number;
  hasAudio: boolean;
  onCancel(): void;
  onMake(range: { start: number; end: number }, subtitles: boolean): void;
}

/**
 * 수동 숏폼 구간 고르기. 프리뷰 + 시작/끝 슬라이더 두 개. 카드 틀은 결과물 카드와 같다 (1px 선, 8px).
 * 타임라인 편집기는 아니다 — 구간 하나만.
 */
export function ShortPicker({ proxyUrl, posterUrl, durationSec, hasAudio, onCancel, onMake }: Props) {
  const total = Math.max(1, durationSec);
  const [start, setStart] = useState(0);
  const [end, setEnd] = useState(Math.min(total, 30));
  const [subs, setSubs] = useState(hasAudio);
  const video = useRef<HTMLVideoElement>(null);

  const seek = (t: number) => {
    if (video.current) video.current.currentTime = t;
  };
  useEffect(() => seek(start), [start]);
  const ok = end - start >= 1;

  return (
    <div className="flex flex-col gap-3 rounded-panel border border-line bg-surface p-3.5" data-testid="short-picker">
      <div className="text-14 font-semibold">{copy.detail.shortPicker.title}</div>
      {proxyUrl && <video ref={video} src={proxyUrl} poster={posterUrl ?? undefined} className="w-full rounded-thumb bg-thumb" style={{ aspectRatio: '16/9' }} muted playsInline preload="metadata" />}
      <Slider label={copy.detail.shortPicker.start} value={start} max={total} onChange={(v) => setStart(Math.min(v, end - 1))} testId="short-start" />
      <Slider
        label={copy.detail.shortPicker.end}
        value={end}
        max={total}
        onChange={(v) => {
          setEnd(Math.max(v, start + 1));
          seek(v);
        }}
        testId="short-end"
      />
      {hasAudio && (
        <label className="flex items-center gap-2 text-13">
          <span className={`flex h-4 w-4 items-center justify-center rounded-[4px] border ${subs ? 'border-accent bg-accent text-white' : 'border-off'}`}>{subs && <CheckIcon />}</span>
          <input type="checkbox" className="sr-only" checked={subs} onChange={(e) => setSubs(e.target.checked)} />
          {copy.detail.shortPicker.withSubtitles}
        </label>
      )}
      {!ok && <p className="text-12 text-text-3">{copy.detail.shortPicker.tooShort}</p>}
      <div className="flex gap-2">
        <button type="button" onClick={onCancel} className="min-h-[42px] flex-1 rounded-thumb border border-line text-14 hover:bg-hover">
          {copy.detail.shortPicker.cancel}
        </button>
        <button
          type="button"
          data-testid="short-make"
          disabled={!ok}
          onClick={() => onMake({ start, end }, subs)}
          className="min-h-[42px] flex-1 rounded-thumb bg-accent text-14 font-semibold text-white hover:bg-accent-hover disabled:opacity-50"
        >
          {copy.detail.shortPicker.make}
        </button>
      </div>
    </div>
  );
}

function Slider({ label, value, max, onChange, testId }: { label: string; value: number; max: number; onChange(v: number): void; testId: string }) {
  return (
    <label className="flex items-center gap-3 text-12 text-text-2">
      <span className="w-6 flex-none">{label}</span>
      <input type="range" data-testid={testId} min={0} max={max} step={0.1} value={value} onChange={(e) => onChange(Number(e.target.value))} className="h-1 flex-1 accent-[var(--color-accent)]" />
      <span className="w-12 flex-none text-right text-12 text-text">{formatDuration(value)}</span>
    </label>
  );
}
