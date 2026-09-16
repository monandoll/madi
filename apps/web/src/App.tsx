import { useQuery } from '@tanstack/react-query';
import { Sidebar } from './components/Sidebar.js';
import { TabBar } from './components/TabBar.js';
import { copy } from './copy.js';
import { api, queryKeys } from './lib/api.js';
import { useRoute } from './lib/route.js';
import { useSettings } from './lib/settings.js';
import { useEngineEvents } from './lib/ws.js';
import { FirstRun } from './screens/FirstRun.js';
import { Gallery } from './screens/Gallery.js';
import { OutputDetail } from './screens/OutputDetail.js';
import { OutputsScreen } from './screens/Outputs.js';
import { RunningScreen } from './screens/Running.js';
import { SettingsScreen } from './screens/Settings.js';
import { VideoDetail } from './screens/VideoDetail.js';
import { useIsPc } from './store.js';

/**
 * 앱 틀.
 * - 설정 전(setupDone=false)이면 첫 실행 화면만.
 * - PC(900px+): design/v2/Desktop — 왼쪽 사이드바 + 화면.
 * - 모바일: design/v2/Mobile — 화면 + 아래 탭 3개.
 */
export function App() {
  useEngineEvents();
  const route = useRoute();
  const pc = useIsPc();
  const settings = useSettings();
  const health = useQuery({ queryKey: queryKeys.health, queryFn: api.health, refetchInterval: 15_000 });
  const videos = useQuery({ queryKey: queryKeys.videos, queryFn: api.videos, enabled: pc });
  const outputs = useQuery({ queryKey: queryKeys.outputs, queryFn: api.outputs, enabled: pc });
  const providers = useQuery({ queryKey: queryKeys.aiProviders, queryFn: () => api.aiProviders(), enabled: pc, staleTime: 60_000 });
  const ws = settings.settings;

  if (settings.isSuccess && !ws.setupDone) return <FirstRun initialName={ws.workspaceName} initialFolders={ws.watchFolders} />;

  const screen = (() => {
    switch (route.screen) {
      case 'settings':
        return <SettingsScreen />;
      case 'outputs':
        return <OutputsScreen />;
      case 'running':
        return <RunningScreen />;
      case 'video':
        return <VideoDetail id={route.id} />;
      case 'output':
        return <OutputDetail id={route.id} />;
      default:
        return <Gallery />;
    }
  })();

  if (!pc) {
    return (
      <div className="flex h-full flex-col bg-surface">
        <div className="min-h-0 flex-1">{screen}</div>
        <TabBar route={route} />
      </div>
    );
  }

  const list = videos.data?.videos ?? [];
  const running = list.filter((v) => v.activeJob || v.status === 'preparing' || v.status === 'registered').length;
  const ai = health.data?.ai;
  const aiLabel = ai?.connected ? copy.header.aiOn(providers.data?.providers.find((p) => p.id === ai.provider)?.label ?? ai.provider) : copy.header.aiOff;
  return (
    <div className="flex h-full overflow-hidden bg-surface">
      <Sidebar route={route} workspaceName={ws.workspaceName} engineOk={health.isSuccess} aiLabel={aiLabel} videos={list} outputCount={outputs.data?.outputs.length ?? 0} runningCount={running} />
      <div className="flex min-w-0 flex-1 flex-col overflow-hidden">{screen}</div>
    </div>
  );
}
