import { useQuery } from '@tanstack/react-query';
import { HeaderButton, TopBar } from '../components/TopBar.js';
import { VideoCard } from '../components/VideoCard.js';
import { copy } from '../copy.js';
import { api, queryKeys } from '../lib/api.js';
import { go } from '../lib/route.js';
import { useSettings } from '../lib/settings.js';
import { useIsPc } from '../store.js';

/**
 * 첫 화면. design/v2 갤러리.
 * 모바일: 제목 = 스튜디오 이름, 부제 "연결됨 · 영상 N개", 2열. PC: 헤더 "영상", 226px 이상 카드가 자동으로 늘어난다.
 */
export function Gallery() {
  const pc = useIsPc();
  const health = useQuery({ queryKey: queryKeys.health, queryFn: api.health, refetchInterval: 15_000 });
  const settings = useSettings();
  const videos = useQuery({ queryKey: queryKeys.videos, queryFn: api.videos, refetchInterval: health.isError ? 3_000 : false });
  const ws = settings.settings;
  const list = videos.data?.videos ?? [];
  const engineOk = health.isSuccess;

  return (
    <div className="flex h-full min-h-0 flex-col bg-surface">
      {pc ? (
        <TopBar title={copy.tabs.videos} meta={copy.header.sectionMeta['videos']} actions={<HeaderButton onClick={() => go({ screen: 'settings' })}>{copy.header.galleryActions.openFolder}</HeaderButton>} />
      ) : (
        <TopBar title={ws.workspaceName} dot={engineOk} meta={`${engineOk ? copy.header.engineOk : copy.header.engineOff} · ${copy.header.videoCount(list.length)}`} />
      )}
      <main className="min-h-0 flex-1 overflow-x-hidden overflow-y-auto px-3.5 pt-3 pb-5 pc:px-6 pc:pt-5 pc:pb-10">
        {videos.isPending ? (
          <Empty>{copy.empty.loading}</Empty>
        ) : videos.isError ? (
          <Empty>{copy.empty.disconnected}</Empty>
        ) : list.length === 0 ? (
          <Empty>{ws.watchFolders.length === 0 ? copy.empty.noFolder : copy.empty.noVideos}</Empty>
        ) : (
          <div className="grid grid-cols-2 gap-x-2 gap-y-2.5 pc:grid-cols-[repeat(auto-fill,minmax(226px,1fr))] pc:gap-3.5">
            {list.map((v) => (
              <VideoCard key={v.id} video={v} />
            ))}
          </div>
        )}
      </main>
    </div>
  );
}

export function Empty({ children }: { children: React.ReactNode }) {
  return (
    <p className="py-[60px] text-center text-14 leading-relaxed whitespace-pre-line text-text-3" data-testid="empty">
      {children}
    </p>
  );
}
