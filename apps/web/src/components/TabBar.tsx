import { copy } from '../copy.js';
import { hrefOf, type Route } from '../lib/route.js';
import { FolderIcon, GearIcon, VideoIcon } from './Icons.js';

/** design/v2/Mobile.dc.html 아래 탭 3개: 영상 · 결과물 · 설정. 활성은 accent, 600. */
export function TabBar({ route }: { route: Route }) {
  const tabs: { id: string; label: string; icon: React.ReactNode; on: boolean; to: Route }[] = [
    { id: 'videos', label: copy.tabs.videos, icon: <VideoIcon size={20} />, on: route.screen === 'gallery' || route.screen === 'video' || route.screen === 'running', to: { screen: 'gallery' } },
    { id: 'outputs', label: copy.tabs.outputs, icon: <FolderIcon size={20} />, on: route.screen === 'outputs' || route.screen === 'output', to: { screen: 'outputs' } },
    { id: 'settings', label: copy.tabs.settings, icon: <GearIcon size={20} />, on: route.screen === 'settings', to: { screen: 'settings' } },
  ];
  return (
    <nav className="flex flex-none border-t border-line-soft bg-surface px-2 pt-1.5 pb-[calc(10px+env(safe-area-inset-bottom))]" role="tablist" data-testid="tab-bar">
      {tabs.map((t) => (
        <a
          key={t.id}
          href={hrefOf(t.to)}
          role="tab"
          aria-selected={t.on}
          className={`flex min-h-12 flex-1 flex-col items-center justify-center gap-[3px] rounded-panel ${t.on ? 'text-accent' : 'text-text-3'}`}
        >
          {t.icon}
          <span className={`text-11 ${t.on ? 'font-semibold' : ''}`}>{t.label}</span>
        </a>
      ))}
    </nav>
  );
}
