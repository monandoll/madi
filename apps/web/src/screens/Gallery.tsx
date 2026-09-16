import { useQuery } from '@tanstack/react-query';
import { Header } from '../components/Header.js';
import { SetupCard } from '../components/SetupCard.js';
import { Tabs } from '../components/Tabs.js';
import { VideoCard } from '../components/VideoCard.js';
import { copy } from '../copy.js';
import { api, queryKeys } from '../lib/api.js';
import { useSettings } from '../lib/settings.js';
import { useUi } from '../store.js';

/**
 * 첫 화면. design/Mobile.dc.html "갤러리 · 375".
 * 375 에서 2열(카드 폭 ≈169px). 더 넓으면 같은 카드 폭으로 열이 늘어난다.
 */
export function Gallery() {
  const tab = useUi((s) => s.tab);
  const health = useQuery({ queryKey: queryKeys.health, queryFn: api.health, refetchInterval: 15_000 });
  const settings = useSettings();
  const videos = useQuery({ queryKey: queryKeys.videos, queryFn: api.videos, refetchInterval: health.isError ? 3_000 : false });

  const ws = settings.settings;
  const showSetup = settings.isSuccess && !ws.setupDone;
  const list = videos.data?.videos ?? [];
  const inProgress = list.filter((v) => v.activeJob || v.status === 'preparing' || v.status === 'registered');

  return (
    <div className="flex h-full flex-col bg-bg">
      <Header workspaceName={ws.workspaceName} aiConnected={health.data?.ai.connected ?? false} engineOk={health.isSuccess} />
      <Tabs />
      <main className="min-h-0 flex-1 overflow-y-auto px-3.5 pb-5">
        {tab === 'videos' && showSetup && (
          <div className="pt-0.5 pb-3">
            <SetupCard initialName={ws.workspaceName} initialFolders={ws.watchFolders} />
          </div>
        )}
        {tab === 'videos' && (
          <Grid>
            {videos.isPending ? (
              <Empty>{copy.empty.loading}</Empty>
            ) : videos.isError ? (
              <Empty>{copy.empty.disconnected}</Empty>
            ) : list.length === 0 ? (
              <Empty>{showSetup ? copy.setup.belowCard : ws.watchFolders.length === 0 ? copy.empty.noFolder : copy.empty.noVideos}</Empty>
            ) : (
              list.map((v) => <VideoCard key={v.id} video={v} />)
            )}
          </Grid>
        )}
        {tab === 'outputs' && <Empty>{copy.empty.noOutputs}</Empty>}
        {tab === 'inProgress' && (
          <Grid>
            {inProgress.length === 0 ? <Empty>{copy.empty.nothingInProgress}</Empty> : inProgress.map((v) => <VideoCard key={v.id} video={v} />)}
          </Grid>
        )}
      </main>
    </div>
  );
}

function Grid({ children }: { children: React.ReactNode }) {
  return <div className="grid grid-cols-[repeat(auto-fill,minmax(168px,1fr))] gap-2">{children}</div>;
}

function Empty({ children }: { children: React.ReactNode }) {
  return (
    <p className="col-span-full pt-9 text-center text-13 leading-relaxed whitespace-pre-line text-text-2" data-testid="empty">
      {children}
    </p>
  );
}
