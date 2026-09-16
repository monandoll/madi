import { useEffect, useRef, useState } from 'react';
import { keepSegments, type OutputDetailResponse, type Segment } from '@madi/shared';
import { remapRange } from '@madi/shared';
import { copy } from '../copy.js';
import { formatDuration } from '../lib/format.js';
import { PauseIcon, PlayIcon } from './Icons.js';

interface Props {
  data: OutputDetailResponse;
  /** 결과물 화면(모바일)이면 true — 프리뷰가 176px, PC 패널은 168px */
  wide?: boolean;
  /** AI 연결 시 "이 문장 고쳐줘 / 이 부분 살려줘" 와 수정 요청 */
  onAsk?: ((text: string) => void) | undefined;
}

/**
 * design/v2 결과물: 세로 프리뷰(자막 오버레이) · 4px 진행 바 · 재생 · 시각 · 자막 N문장/잘린 구간 N곳 · 자막 목록 · 다운로드/수정 요청.
 * 잘린 문장은 취소선 + 'N초 잘림'. 고른 줄은 EEF5FA 배경에 "이 문장 고쳐줘/이 부분 살려줘".
 * 모바일 결과물 화면과 PC 옆 패널이 같은 컴포넌트를 쓴다.
 */
export function OutputView({ data, wide = false, onAsk }: Props) {
  const { output, edit, transcript, video } = data;
  const videoRef = useRef<HTMLVideoElement>(null);
  const [t, setT] = useState(0);
  const [playing, setPlaying] = useState(false);
  const [sel, setSel] = useState<string | null>(null);

  useEffect(() => {
    const v = videoRef.current;
    if (!v) return;
    const onTime = () => setT(v.currentTime);
    const onPlay = () => setPlaying(true);
    const onPause = () => setPlaying(false);
    v.addEventListener('timeupdate', onTime);
    v.addEventListener('play', onPlay);
    v.addEventListener('pause', onPause);
    v.addEventListener('ended', onPause);
    return () => {
      v.removeEventListener('timeupdate', onTime);
      v.removeEventListener('play', onPlay);
      v.removeEventListener('pause', onPause);
      v.removeEventListener('ended', onPause);
    };
  }, [output.id]);

  const vertical = output.width < output.height;
  const keep = keepSegments(edit, video.durationSec ?? output.durationSec);
  const rows = transcript ? rowsFor(transcript.segments, keep) : [];
  const current = rows.find((r) => r.at !== null && t >= r.at && t < r.end!);
  const cuts = rows.filter((r) => r.at === null).length;
  const selected = rows.find((r) => r.id === sel) ?? null;

  const toggle = () => {
    const v = videoRef.current;
    if (!v) return;
    if (v.paused) void v.play();
    else v.pause();
  };

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <div className="flex flex-none flex-col gap-2.5 px-3.5 pt-3.5 pb-2.5">
        <div className="flex justify-center">
          <div
            className="relative overflow-hidden rounded-panel bg-thumb"
            style={{ width: vertical ? (wide ? 176 : 168) : '100%', maxWidth: vertical ? undefined : 340, aspectRatio: vertical ? '9/16' : '16/9' }}
          >
            <video ref={videoRef} src={output.url} poster={output.thumbnailUrl ?? undefined} playsInline preload="metadata" className="absolute inset-0 h-full w-full object-cover" data-testid="output-video" onClick={toggle} />
            {current && edit.subtitles && (
              <div className="pointer-events-none absolute inset-x-3 flex justify-center" style={{ bottom: '13%' }}>
                <span className="rounded-[4px] bg-overlay-2 px-[7px] py-[3px] text-center text-12 leading-[1.45] font-semibold text-white">{current.text}</span>
              </div>
            )}
          </div>
        </div>
        <div className="relative h-1 rounded-pill bg-track">
          <div className="absolute inset-y-0 left-0 rounded-pill bg-accent" style={{ width: `${Math.min(100, (t / Math.max(0.01, output.durationSec)) * 100)}%` }} />
        </div>
        <div className="flex items-center gap-2.5">
          <button
            type="button"
            onClick={toggle}
            aria-label={playing ? 'pause' : 'play'}
            className={`flex flex-none items-center justify-center border border-line hover:bg-hover ${wide ? 'h-8 w-8 rounded-pill' : 'h-7 w-7 rounded-thumb'}`}
          >
            {playing ? <PauseIcon size={wide ? 11 : 10} /> : <PlayIcon size={wide ? 11 : 10} />}
          </button>
          <span className="text-12 text-text-2">
            {formatDuration(t)} / {formatDuration(output.durationSec)}
          </span>
          <span className="flex-1" />
          <span className="text-12 text-text-3">{rows.length ? (wide ? copy.output.lines(rows.length - cuts) : copy.output.cuts(cuts)) : ''}</span>
        </div>
      </div>

      <div className="min-h-0 flex-1 overflow-y-auto border-t border-line-soft" data-testid="subtitle-rows">
        {rows.length === 0 ? (
          <p className="px-3.5 py-6 text-center text-13 text-text-3">{copy.output.noSubtitles}</p>
        ) : (
          rows.map((r) => {
            const cut = r.at === null;
            const on = r.id === sel;
            return (
              <div
                key={r.id}
                role="button"
                tabIndex={0}
                onClick={() => {
                  setSel(r.id);
                  if (videoRef.current && r.at !== null) videoRef.current.currentTime = r.at;
                }}
                onKeyDown={(e) => {
                  if (e.key === 'Enter') setSel(r.id);
                }}
                className={`flex w-full cursor-pointer items-baseline gap-2.5 border-b border-line-faint px-3.5 text-left hover:bg-surface-2 ${wide ? 'py-[11px]' : 'py-[9px]'} ${on ? 'bg-accent-faint' : ''}`}
                data-testid="subtitle-row"
                data-cut={cut}
              >
                <span className="w-7 flex-none text-11 text-text-3">{cut ? formatDuration(r.srcStart) : formatDuration(r.at ?? 0)}</span>
                <span className={`min-w-0 flex-1 text-13 leading-[1.55] ${cut ? 'text-muted line-through' : ''}`} style={{ textWrap: 'pretty' }}>
                  {r.text}
                </span>
                {cut && !on && <span className="flex-none text-11 text-text-3">{copy.output.cutMeta(Math.round(r.srcEnd - r.srcStart))}</span>}
                {on && onAsk && (
                  <button
                    type="button"
                    onClick={(e) => {
                      e.stopPropagation();
                      onAsk(cut ? copy.output.restorePrefill(r.text) : copy.output.fixPrefill(r.text));
                    }}
                    className="flex-none text-12 font-medium text-accent"
                    data-testid="subtitle-ask"
                  >
                    {cut ? copy.output.restoreLine : copy.output.fixLine}
                  </button>
                )}
              </div>
            );
          })
        )}
      </div>

      <div className="flex flex-none gap-2 border-t border-line-soft px-3.5 pt-2.5 pb-3.5">
        <a
          href={output.downloadUrl}
          download
          className={`flex flex-1 items-center justify-center rounded-thumb bg-accent font-semibold text-white hover:bg-accent-hover ${wide ? 'min-h-[46px] rounded-panel text-14' : 'py-[9px] text-13'}`}
          data-testid="download"
        >
          {copy.output.download}
        </a>
        <button
          type="button"
          disabled={!onAsk}
          title={onAsk ? undefined : copy.detail.outputCard.reviseHint}
          onClick={() => onAsk?.(copy.detail.outputCard.revisePrefill(output.title))}
          className={`flex flex-1 items-center justify-center rounded-thumb border border-line hover:bg-hover disabled:text-text-3 ${wide ? 'min-h-[46px] rounded-panel text-14' : 'py-[9px] text-13'}`}
          data-testid="output-revise"
        >
          {copy.output.revise}
        </button>
      </div>
      {selected && null}
    </div>
  );
}

interface Row {
  id: string;
  text: string;
  srcStart: number;
  srcEnd: number;
  /** 결과물 시각. 잘린 문장은 null */
  at: number | null;
  end: number | null;
}

/** 문장 → 결과물 시각으로 옮긴 줄. 잘린 문장도 목록에 남긴다(취소선). */
function rowsFor(segments: Segment[], keep: { start: number; end: number }[]): Row[] {
  return segments.map((s) => {
    const r = remapRange({ start: s.start, end: s.end }, keep);
    return { id: s.id, text: s.text, srcStart: s.start, srcEnd: s.end, at: r?.start ?? null, end: r?.end ?? null };
  });
}
