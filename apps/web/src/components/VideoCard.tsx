import type { VideoCard as VideoCardData } from '@madi/shared';
import { copy } from '../copy.js';
import { formatDate, formatDuration } from '../lib/format.js';
import { hrefOf } from '../lib/route.js';
import { Thumb } from './Thumb.js';

/** 갤러리 카드 상태 문구 (날짜 옆). 없으면 null. */
export function statusLabel(v: VideoCardData): string | null {
  if (v.status === 'registered' || v.status === 'preparing') return copy.status.preparing;
  if (v.status === 'failed') return copy.status.failed;
  if (v.status === 'missing') return copy.status.missing;
  if (v.activeJob && v.activeJob.type !== 'probe' && v.activeJob.type !== 'proxy' && v.activeJob.type !== 'thumbnail') return copy.status.working;
  if (v.outputCount > 0) return copy.status.outputs(v.outputCount);
  return null;
}

/**
 * design/v2 갤러리 카드: 16:9 썸네일(1px 선, 8px 모서리) · 길이 배지 · 결과물 있으면 겹친 사각형 · 제목 · 날짜 + 상태.
 * pc 변형은 글자가 한 단계 크다 (14/12 vs 13/11).
 */
export function VideoCard({ video }: { video: VideoCardData }) {
  const tag = statusLabel(video);
  const duration = formatDuration(video.durationSec);
  return (
    <a href={hrefOf({ screen: 'video', id: video.id })} className="flex flex-col gap-1.5 text-text pc:gap-[7px]" data-testid="video-card" data-status={video.status}>
      <Thumb src={video.thumbnailUrl} ratio="16/9" className="rounded-thumb border border-line">
        {duration && (
          <span className="absolute right-[5px] bottom-[5px] rounded-[3px] bg-overlay px-1 py-px text-10 font-medium text-white pc:right-1.5 pc:bottom-1.5 pc:rounded-[4px] pc:px-[5px] pc:text-11">
            {duration}
          </span>
        )}
        {video.outputCount > 0 && (
          <span className="absolute top-1.5 right-1.5 h-3.5 w-4 pc:top-[7px] pc:right-[7px] pc:h-[15px] pc:w-[17px]" aria-hidden="true">
            <span className="absolute top-0 right-0 h-[9px] w-[11px] rounded-[2px] border border-white pc:h-2.5 pc:w-3" />
            <span className="absolute bottom-0 left-0 h-[9px] w-[11px] rounded-[2px] border border-white bg-[rgba(22,26,31,0.3)] pc:h-2.5 pc:w-3" />
          </span>
        )}
        {video.activeJob && video.activeJob.type === 'proxy' && (
          <span className="absolute inset-x-0 bottom-0 h-[3px] bg-accent" style={{ width: `${Math.round(video.activeJob.progress * 100)}%` }} />
        )}
      </Thumb>
      <div className="flex flex-col gap-0.5 pc:gap-[3px]">
        <div className="truncate text-13 font-medium tracking-[-0.01em] pc:text-14">{video.title}</div>
        <div className="flex items-center gap-[7px] text-11 text-text-3 pc:text-12">
          <span>{formatDate(video.recordedAt)}</span>
          {tag && <span className="text-text-2">{tag}</span>}
        </div>
      </div>
    </a>
  );
}
