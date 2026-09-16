import { useEffect, useRef, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { keepSegments, remapRange, type Segment } from '@madi/shared';
import { PauseIcon, PlayIcon } from '../components/Icons.js';
import { ScreenHeader } from '../components/ScreenHeader.js';
import { copy } from '../copy.js';
import { api, queryKeys } from '../lib/api.js';
import { formatDuration } from '../lib/format.js';

/**
 * design/Mobile.dc.html '결과물 자세히 · 전체 화면'.
 * 세로 프리뷰 + 진행 바 + 재생 + 자막 목록(잘린 문장은 취소선과 'N초 잘림') + 다운로드.
 */
export function OutputDetail({ id }: { id: string }) {
  const q = useQuery({ queryKey: queryKeys.output(id), queryFn: () => api.output(id) });
  const videoRef = useRef<HTMLVideoElement>(null);
  const [t, setT] = useState(0);
  const [playing, setPlaying] = useState(false);

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
  }, [q.data?.output.id]);

  if (q.isPending) return <Frame title="">{null}</Frame>;
  if (q.isError || !q.data) return <Frame title="">{copy.output.notFound}</Frame>;
  const { output, edit, transcript, video } = q.data;
  const vertical = output.width < output.height;
  const keep = keepSegments(edit, video.durationSec ?? output.durationSec);
  const rows = transcript ? rowsFor(transcript.segments, keep) : [];
  const current = rows.find((r) => r.at !== null && t >= r.at && t < r.end!);

  const toggle = () => {
    const v = videoRef.current;
    if (!v) return;
    if (v.paused) void v.play();
    else v.pause();
  };

  return (
    <div className="flex h-full flex-col bg-surface" data-testid="output-detail">
      <ScreenHeader title={output.title} aside={formatDuration(output.durationSec)} backLabel />

      <div className="mx-auto flex w-full max-w-[560px] flex-none flex-col gap-2.5 px-3.5 pt-3 pb-2.5">
        <div className="flex justify-center">
          <div className="relative overflow-hidden rounded-thumb bg-thumb" style={{ width: vertical ? 186 : '100%', aspectRatio: vertical ? '9/16' : '16/9' }}>
            <video
              ref={videoRef}
              src={output.url}
              poster={output.thumbnailUrl ?? undefined}
              playsInline
              preload="metadata"
              className="absolute inset-0 h-full w-full object-cover"
              data-testid="output-video"
              onClick={toggle}
            />
            {current && edit.subtitles && (
              <div className="pointer-events-none absolute inset-x-2.5 flex justify-center" style={{ bottom: '14%' }}>
                <span className="rounded-[4px] bg-subtitle px-[5px] py-0.5 text-center text-12 leading-[1.4] font-semibold text-text">{current.text}</span>
              </div>
            )}
          </div>
        </div>
        <div className="relative h-1 rounded-pill bg-track">
          <div className="absolute inset-y-0 left-0 rounded-pill bg-accent" style={{ width: `${Math.min(100, (t / Math.max(0.01, output.durationSec)) * 100)}%` }} />
        </div>
        <div className="flex items-center gap-2.5">
          <button type="button" onClick={toggle} aria-label={playing ? 'pause' : 'play'} className="flex h-8 w-8 flex-none items-center justify-center rounded-pill border border-line">
            {playing ? <PauseIcon /> : <PlayIcon />}
          </button>
          <span className="text-12 text-text-2">
            {formatDuration(t)} / {formatDuration(output.durationSec)}
          </span>
        </div>
      </div>

      <main className="mx-auto min-h-0 w-full max-w-[560px] flex-1 overflow-y-auto border-t border-line" data-testid="subtitle-rows">
        {rows.length === 0 ? (
          <p className="px-3.5 py-6 text-center text-13 text-text-2">{copy.output.noSubtitles}</p>
        ) : (
          rows.map((r) => (
            <button
              key={r.id}
              type="button"
              disabled={r.at === null}
              onClick={() => {
                if (videoRef.current && r.at !== null) videoRef.current.currentTime = r.at;
              }}
              className={`flex w-full items-baseline gap-2.5 border-b border-line-soft px-3.5 py-[11px] text-left ${r === current ? 'bg-accent-soft' : ''}`}
              data-testid="subtitle-row"
              data-cut={r.at === null}
            >
              <span className="w-[30px] flex-none text-11 text-text-2">{r.at === null ? formatDuration(r.srcStart) : formatDuration(r.at)}</span>
              <span className={`min-w-0 flex-1 text-13 leading-normal ${r.at === null ? 'text-[#A79C93] line-through' : ''}`} style={{ textWrap: 'pretty' }}>
                {r.text}
              </span>
              {r.at === null && <span className="flex-none text-11 text-text-2">{copy.output.cutMeta(Math.round(r.srcEnd - r.srcStart))}</span>}
            </button>
          ))
        )}
      </main>

      <div className="mx-auto flex w-full max-w-[560px] flex-none gap-2 border-t border-line px-3.5 pt-2.5 pb-3">
        <a href={output.downloadUrl} download className="flex h-11 flex-1 items-center justify-center rounded-thumb bg-accent text-14 font-semibold text-white" data-testid="download">
          {copy.output.download}
        </a>
        <button type="button" disabled title={copy.detail.outputCard.reviseHint} className="h-11 flex-1 rounded-thumb border border-line text-14 text-text-2">
          {copy.output.revise}
        </button>
      </div>
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

function Frame({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="flex h-full flex-col bg-surface">
      <ScreenHeader title={title} backLabel />
      <main className="flex flex-1 items-center justify-center p-4 text-13 text-text-2">{children}</main>
    </div>
  );
}
