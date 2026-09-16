import { useQuery } from '@tanstack/react-query';
import { TopBar } from '../components/TopBar.js';
import { copy } from '../copy.js';
import { api, queryKeys } from '../lib/api.js';
import { hrefOf } from '../lib/route.js';
import { Empty } from './Gallery.js';

/** 진행 중 (PC 레일). 영상마다 지금 돌고 있는 잡을 카드로: 제목 · 남은 시간 · 영상 이름 · 4px 바. */
export function RunningScreen() {
  const videos = useQuery({ queryKey: queryKeys.videos, queryFn: api.videos, refetchInterval: 3_000 });
  const jobs = (videos.data?.videos ?? []).filter((v) => v.activeJob || v.status === 'preparing' || v.status === 'registered');
  return (
    <div className="flex h-full min-h-0 flex-col bg-surface">
      <TopBar title={copy.tabs.inProgress} meta={copy.header.sectionMeta['running']} />
      <main className="min-h-0 flex-1 overflow-y-auto px-3.5 pt-3 pb-5 pc:px-6 pc:pt-[22px] pc:pb-[60px]">
        {jobs.length === 0 ? (
          <Empty>{copy.empty.nothingInProgress}</Empty>
        ) : (
          <div className="grid grid-cols-1 gap-2.5 pc:grid-cols-[repeat(auto-fit,minmax(300px,1fr))]">
            {jobs.map((v) => {
              const type = v.activeJob?.type ?? 'probe';
              const progress = v.activeJob?.progress ?? 0;
              return (
                <a key={v.id} href={hrefOf({ screen: 'video', id: v.id })} className="flex flex-col gap-2 rounded-thumb border border-line p-3 text-text hover:bg-surface-2" data-testid="job-card">
                  <div className="flex items-baseline gap-2.5">
                    <span className="min-w-0 flex-1 text-14 font-medium">{copy.running[type] ?? copy.status.working}</span>
                    <span className="text-12 text-text-3">{copy.detail.progressEta((v.durationSec ?? 60) * (1 - progress) * 0.5)}</span>
                  </div>
                  <div className="truncate text-12 text-text-3">{v.title}</div>
                  <div className="relative h-1 rounded-pill bg-track">
                    <div className="absolute inset-y-0 left-0 rounded-pill bg-accent" style={{ width: `${Math.round(Math.max(0.03, progress) * 100)}%` }} />
                  </div>
                </a>
              );
            })}
          </div>
        )}
      </main>
    </div>
  );
}
