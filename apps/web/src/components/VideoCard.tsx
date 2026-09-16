import type { VideoCard as VideoCardData } from '@madi/shared';
import { copy } from '../copy.js';
import { formatDate, formatDuration } from '../lib/format.js';
import { hrefOf } from '../lib/route.js';

/** 갤러리 카드 상태 배지 문구. 없으면 null (배지 없음). */
export function statusLabel(v: VideoCardData): string | null {
  if (v.status === 'registered' || v.status === 'preparing') return copy.status.preparing;
  if (v.status === 'failed') return copy.status.failed;
  if (v.status === 'missing') return copy.status.missing;
  if (v.activeJob && v.activeJob.type !== 'probe' && v.activeJob.type !== 'proxy' && v.activeJob.type !== 'thumbnail') return copy.status.working;
  if (v.outputCount > 0) return copy.status.outputs(v.outputCount);
  return null;
}

export function VideoCard({ video }: { video: VideoCardData }) {
  const badge = statusLabel(video);
  const duration = formatDuration(video.durationSec);
  return (
    <a href={hrefOf({ screen: 'video', id: video.id })} className="block text-text" data-testid="video-card" data-status={video.status}>
      <div className="relative aspect-video overflow-hidden rounded-thumb bg-thumb">
        {video.thumbnailUrl ? (
          <img src={video.thumbnailUrl} alt="" className="absolute inset-0 h-full w-full object-cover" loading="lazy" />
        ) : (
          <Placeholder />
        )}
        {badge && (
          <span className="absolute top-[5px] left-1.5 rounded-pill bg-bg px-[5px] py-0.5 text-[10px] font-medium text-text">
            {badge}
          </span>
        )}
        {duration && (
          <span className="absolute right-1.5 bottom-[5px] rounded-[3px] bg-text px-1 py-px text-[10px] font-medium text-white">
            {duration}
          </span>
        )}
        {video.activeJob && video.activeJob.type === 'proxy' && (
          <span
            className="absolute inset-x-0 bottom-0 h-[3px] bg-accent"
            style={{ width: `${Math.round(video.activeJob.progress * 100)}%` }}
          />
        )}
      </div>
      <div className="flex flex-col gap-0.5 px-px pt-[5px]">
        <div className="truncate text-12 font-medium">{video.title}</div>
        <div className="text-11 text-text-2">{formatDate(video.recordedAt)}</div>
      </div>
    </a>
  );
}

/** 썸네일 없을 때 시안의 회색 실루엣. */
function Placeholder() {
  return (
    <>
      <div className="absolute inset-x-0 bottom-0 h-[34%] bg-thumb-2" />
      <div className="absolute bottom-[18%] left-1/2 h-[30%] w-[38%] -translate-x-1/2 rounded-[6px] bg-thumb-3" />
    </>
  );
}
