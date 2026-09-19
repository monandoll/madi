import { useEffect, useRef, useState } from 'react';
import { useMutation, useQuery } from '@tanstack/react-query';
import { Qr } from '../components/Qr.js';
import { HeaderButton, TopBar } from '../components/TopBar.js';
import { UpdateBanner } from '../components/UpdateBanner.js';
import { VideoCard } from '../components/VideoCard.js';
import { copy } from '../copy.js';
import { api, queryKeys } from '../lib/api.js';
import { go } from '../lib/route.js';
import { useSettings } from '../lib/settings.js';
import { percent, type UploadItem, useUploads } from '../lib/uploads.js';
import { useIsPc } from '../store.js';

/**
 * 첫 화면. design/v2 갤러리.
 * 모바일: 제목 = 스튜디오 이름, 부제 "연결됨 · 영상 N개", 오른쪽 "올리기", 2열.
 * PC: 헤더 "영상" · "폴더 열기"(탐색기) · "폰에서 업로드"(안내 패널), 226px 이상 카드가 자동으로 늘어난다.
 */
export function Gallery() {
  const pc = useIsPc();
  const health = useQuery({ queryKey: queryKeys.health, queryFn: api.health, refetchInterval: 15_000 });
  const settings = useSettings();
  const videos = useQuery({ queryKey: queryKeys.videos, queryFn: api.videos, refetchInterval: health.isError ? 3_000 : false });
  const ws = settings.settings;
  const list = videos.data?.videos ?? [];
  const engineOk = health.isSuccess;
  const [help, setHelp] = useState(false);
  // 맥·윈도우에서 가장 자연스러운 가져오기: Finder/탐색기에서 갤러리로 끌어다 놓기
  const [dropping, setDropping] = useState(false);
  const fileInput = useRef<HTMLInputElement>(null);
  const uploads = useUploads();
  // PC 헤더 "폴더 열기": 이 PC 의 영상 폴더를 탐색기/Finder 로. 폴더가 아직 없으면 설정으로 보낸다.
  const openFolder = useMutation({
    mutationFn: api.openFolder,
    onSuccess: (r) => {
      if (!r.opened) go({ screen: 'settings' });
    },
  });

  // 다 올라간 영상이 갤러리에 나타나면 진행 줄을 치운다
  useEffect(() => {
    for (const it of uploads.items) {
      if (it.status === 'done' && list.some((v) => v.fileName === it.name || v.fileName.startsWith(it.name.replace(/\.[^.]+$/, '')))) uploads.remove(it.id);
    }
  }, [list, uploads]);

  const pick = () => fileInput.current?.click();
  const picker = (
    <input
      ref={fileInput}
      type="file"
      accept="video/*,.mp4,.mov,.m4v,.mkv,.webm"
      multiple
      className="hidden"
      data-testid="upload-input"
      onChange={(e) => {
        if (e.target.files?.length) uploads.start(e.target.files);
        e.target.value = '';
      }}
    />
  );

  return (
    <div className="flex h-full min-h-0 flex-col bg-surface">
      {pc ? (
        <TopBar
          title={copy.tabs.videos}
          meta={copy.header.sectionMeta['videos']}
          actions={
            <>
              <HeaderButton onClick={() => openFolder.mutate()} testId="open-folder">
                {copy.header.galleryActions.openFolder}
              </HeaderButton>
              <button type="button" onClick={() => setHelp((v) => !v)} className="flex-none rounded-row px-2.5 py-[5px] text-13 font-medium whitespace-nowrap text-accent hover:bg-accent-soft" data-testid="upload-help-toggle">
                {copy.header.galleryActions.upload}
              </button>
            </>
          }
        />
      ) : (
        <TopBar
          title={ws.workspaceName}
          dot={engineOk}
          meta={`${engineOk ? copy.header.engineOk : copy.header.engineOff} · ${copy.header.videoCount(list.length)}`}
          aside={
            <button type="button" onClick={pick} className="flex-none rounded-row px-2 py-1 text-13 font-medium text-accent hover:bg-accent-soft" data-testid="upload-button">
              {copy.upload.button}
            </button>
          }
        />
      )}
      {picker}
      <main
        className="relative min-h-0 flex-1 overflow-x-hidden overflow-y-auto px-3.5 pt-3 pb-5 pc:px-6 pc:pt-5 pc:pb-10"
        onDragOver={(e) => {
          if (!e.dataTransfer.types.includes('Files')) return;
          e.preventDefault();
          setDropping(true);
        }}
        onDragLeave={(e) => {
          // 자식 위로 지나갈 때도 leave 가 뜬다. 진짜로 밖으로 나갔을 때만 끈다.
          if (e.currentTarget.contains(e.relatedTarget as Node | null)) return;
          setDropping(false);
        }}
        onDrop={(e) => {
          if (!e.dataTransfer.files.length) return;
          e.preventDefault();
          setDropping(false);
          uploads.start(e.dataTransfer.files);
        }}
        data-testid="gallery-main"
      >
        {dropping && (
          <div className="pointer-events-none absolute inset-2 z-10 flex items-center justify-center rounded-panel border-2 border-dashed border-accent bg-accent-faint/90 text-14 font-medium text-accent" data-testid="drop-hint">
            {copy.upload.dropping}
          </div>
        )}
        {!pc && <UpdateBanner className="mb-2.5" />}
        {pc && help && <UploadHelp onPick={pick} onClose={() => setHelp(false)} />}
        {uploads.items.length > 0 && (
          <div className="mb-3 flex flex-col overflow-hidden rounded-thumb border border-line pc:mb-4" data-testid="upload-list">
            {uploads.items.map((it, i) => (
              <UploadRow key={it.id} item={it} first={i === 0} onRemove={() => uploads.remove(it.id)} onRetry={() => uploads.retry(it.id)} />
            ))}
          </div>
        )}
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

/** PC "폰에서 업로드" 안내 카드: QR · 밖에서 접속 상태 · 이 브라우저에서 바로 고르기. */
function UploadHelp({ onPick, onClose }: { onPick(): void; onClose(): void }) {
  const remote = useQuery({ queryKey: queryKeys.remote, queryFn: api.remote, refetchInterval: 3_000 });
  const url = remote.data?.url ?? null;
  const pin = remote.data?.pin ?? null;
  const qrUrl = url && pin ? `${url}/?pin=${pin}` : url;
  const on = !!url;
  return (
    <div className="mb-4 flex flex-col gap-2 rounded-thumb border border-line px-4 py-3" data-testid="upload-help">
      <div className="flex items-baseline justify-between gap-3">
        <span className="text-14 font-semibold">{copy.upload.pcTitle}</span>
        <button type="button" onClick={onClose} className="text-13 text-text-3 hover:text-accent">
          {copy.upload.close}
        </button>
      </div>
      <div className="flex flex-wrap items-center gap-x-3 gap-y-1.5">
        <button type="button" onClick={onPick} className="rounded-thumb bg-accent px-3 py-1.5 text-13 font-medium text-white hover:bg-accent-hover" data-testid="upload-pick-here">
          {copy.upload.pickHere}
        </button>
        <span className="text-13 text-text-3">{copy.upload.dropHint}</span>
      </div>
      <div className="flex items-start gap-3.5 border-t border-line-faint pt-2.5">
        {qrUrl && <Qr value={qrUrl} size={132} />}
        <div className="flex min-w-0 flex-1 flex-col gap-1.5">
          <p className="text-14 leading-[1.6] text-text-2" style={{ textWrap: 'pretty' }}>
            {on ? copy.settings.remoteQrHelp : copy.upload.pcHelp}
          </p>
          <span className="flex items-center gap-1.5 text-13 text-text-3" data-testid="upload-remote">
            <span className="h-1.5 w-1.5 flex-none rounded-pill" style={{ background: on ? 'var(--color-ok)' : 'var(--color-off)' }} />
            {on ? copy.upload.pcRemoteOn : copy.upload.pcRemoteOff}
          </span>
          {pin && (
            <span className="text-13 font-semibold tracking-[0.12em]" data-testid="upload-pin">
              {copy.settings.remotePin(pin)}
            </span>
          )}
        </div>
      </div>
      <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-13">
        {!on && (
          <button type="button" onClick={() => go({ screen: 'settings' })} className="text-accent hover:text-accent-hover">
            {copy.upload.pcSettings}
          </button>
        )}
        <span className="flex-1" />
      </div>
    </div>
  );
}

/** 올리기 한 줄: 이름 · 진행 바 · 상태(AI 말투) · 빼기/다시. */
function UploadRow({ item: it, first, onRemove, onRetry }: { item: UploadItem; first: boolean; onRemove(): void; onRetry(): void }) {
  const pct = percent(it);
  const text =
    it.status === 'uploading'
      ? copy.upload.uploading(pct)
      : it.status === 'done'
        ? copy.upload.done
        : it.error === 'no_folder'
          ? copy.upload.noFolder
          : it.error === 'not_video'
            ? copy.upload.notVideo
            : copy.upload.failed;
  return (
    <div className={`flex flex-col gap-1.5 px-3 py-2.5 ${first ? '' : 'border-t border-line-soft'}`} data-testid="upload-row" data-status={it.status}>
      <div className="flex items-baseline gap-2.5">
        <span className="min-w-0 flex-1 truncate text-14 font-medium">{it.name}</span>
        <span className="flex-none text-12 text-text-3" data-testid="upload-status">
          {text}
        </span>
        {it.status === 'failed' && it.error === 'network' && (
          <button type="button" onClick={onRetry} className="flex-none text-13 text-accent" data-testid="upload-retry">
            {copy.upload.retry}
          </button>
        )}
        {it.status !== 'uploading' && (
          <button type="button" onClick={onRemove} className="flex-none text-13 text-text-2 hover:text-accent" data-testid="upload-remove">
            {copy.upload.remove}
          </button>
        )}
      </div>
      {it.status === 'uploading' && (
        <div className="relative h-1 rounded-pill bg-track">
          <div className="absolute inset-y-0 left-0 rounded-pill bg-accent" style={{ width: `${Math.max(3, pct)}%` }} />
        </div>
      )}
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
