import type { VideoCard } from '@madi/shared';
import { copy } from '../copy.js';
import { go, hrefOf, type Route } from '../lib/route.js';
import { ClockIcon, FolderIcon, GearIcon, VideoIcon } from './Icons.js';

interface Props {
  route: Route;
  workspaceName: string;
  engineOk: boolean;
  aiLabel: string;
  videos: VideoCard[];
  outputCount: number;
  runningCount: number;
}

/**
 * design/v2/Desktop.dc.html 왼쪽 사이드바 (252px, #F3F5F7).
 * 스튜디오 이름 · 엔진 상태 · 레일(영상/결과물/진행 중) · 영상 목록 · 아래 설정.
 */
export function Sidebar({ route, workspaceName, engineOk, aiLabel, videos, outputCount, runningCount }: Props) {
  const inVideo = route.screen === 'video' || route.screen === 'output';
  const rail: { id: Route['screen']; label: string; icon: React.ReactNode; badge: number; on: boolean; to: Route }[] = [
    { id: 'gallery', label: copy.tabs.videos, icon: <VideoIcon />, badge: videos.length, on: route.screen === 'gallery' || inVideo, to: { screen: 'gallery' } },
    { id: 'outputs', label: copy.tabs.outputs, icon: <FolderIcon />, badge: outputCount, on: route.screen === 'outputs', to: { screen: 'outputs' } },
    { id: 'running', label: copy.tabs.inProgress, icon: <ClockIcon />, badge: runningCount, on: route.screen === 'running', to: { screen: 'running' } },
  ];
  const currentVideo = route.screen === 'video' ? route.id : null;
  const engineLabel = !engineOk ? copy.header.engineOff : runningCount > 0 ? copy.header.engineBusy(runningCount) : copy.header.engineOk;

  return (
    <aside className="flex w-[252px] flex-none flex-col overflow-hidden border-r border-line bg-side" data-testid="sidebar">
      <div className="flex flex-none flex-col gap-1 px-3.5 pt-3.5 pb-3">
        <h1 className="cursor-pointer truncate text-15 font-semibold tracking-[-0.01em]" onClick={() => go({ screen: 'gallery' })}>
          {workspaceName}
        </h1>
        <div className="flex items-center gap-1.5">
          <span className="h-[7px] w-[7px] rounded-pill" style={{ background: engineOk ? 'var(--color-ok)' : 'var(--color-off)' }} data-testid="engine-dot" />
          <span className="text-12 text-text-2">{engineLabel}</span>
        </div>
      </div>

      <nav className="flex flex-none flex-col gap-px px-2 pb-2" role="tablist">
        {rail.map((r) => (
          <a
            key={r.id}
            href={hrefOf(r.to)}
            role="tab"
            aria-selected={r.on}
            className={`flex items-center gap-[9px] rounded-row px-2 py-1.5 text-text hover:bg-line-2 ${r.on ? 'bg-select' : ''}`}
          >
            <span className="flex-none text-[#7D8791]">{r.icon}</span>
            <span className={`min-w-0 flex-1 text-14 ${r.on ? 'font-semibold' : ''}`}>{r.label}</span>
            <span className="flex-none text-12 text-text-3">{r.badge}</span>
          </a>
        ))}
      </nav>

      <div className="flex-none px-3.5 pt-2.5 pb-[5px] text-12 font-semibold text-text-3">{copy.tabs.videos}</div>
      <div className="flex min-h-0 flex-1 flex-col gap-px overflow-y-auto px-2 pb-3.5" data-testid="sidebar-videos">
        {videos.map((v) => {
          const on = v.id === currentVideo;
          return (
            <a key={v.id} href={hrefOf({ screen: 'video', id: v.id })} className={`flex items-center gap-2 rounded-row px-2 py-1.5 text-text hover:bg-line-2 ${on ? 'bg-select' : ''}`}>
              <span className={`min-w-0 flex-1 truncate text-14 ${on ? 'font-semibold' : ''}`}>{v.title}</span>
              {v.outputCount > 0 && <span className="flex-none text-12 text-text-3">{v.outputCount}</span>}
            </a>
          );
        })}
      </div>

      <div className="flex flex-none items-center gap-[9px] border-t border-line-2 px-3 py-[9px]">
        <span className="flex h-[26px] w-[26px] flex-none items-center justify-center rounded-thumb bg-avatar-me text-11 font-semibold text-text-4">{workspaceName.trim().charAt(0) || '마'}</span>
        <span className="flex min-w-0 flex-1 flex-col">
          <span className="text-13 font-medium">{copy.header.thisComputer}</span>
          <span className="truncate text-11 text-text-3">{aiLabel}</span>
        </span>
        <button
          type="button"
          aria-label={copy.header.settings}
          title={copy.header.settings}
          onClick={() => go({ screen: 'settings' })}
          className={`flex h-7 w-7 flex-none items-center justify-center rounded-thumb text-text-2 hover:bg-line-2 ${route.screen === 'settings' ? 'bg-select-2' : ''}`}
        >
          <GearIcon />
        </button>
      </div>
    </aside>
  );
}
