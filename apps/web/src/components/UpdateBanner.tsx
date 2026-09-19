import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { copy } from '../copy.js';
import { api, queryKeys } from '../lib/api.js';

/**
 * 새 버전 한 줄 (조용하게 — 붉은색 없음). 받아 두었으면 "새 버전 x · 지금 업데이트", 받는 중이면 "새 버전 x 받는 중".
 * 최신이면 아무것도 안 그린다. 사이드바(PC) 와 갤러리 위(모바일) 가 같이 쓴다.
 */
export function UpdateBanner({ className = '' }: { className?: string }) {
  const qc = useQueryClient();
  const health = useQuery({ queryKey: queryKeys.health, queryFn: api.health, refetchInterval: 15_000 });
  const [installing, setInstalling] = useState(false);
  const install = useMutation({
    mutationFn: api.installUpdate,
    onSuccess: () => {
      setInstalling(true);
      void qc.invalidateQueries({ queryKey: queryKeys.health });
    },
  });
  const u = health.data?.update;
  if (installing) {
    return (
      <div className={`text-12 text-text-3 ${className}`} data-testid="update-banner" data-state="installing">
        {copy.update.installing}
      </div>
    );
  }
  if (!u?.available) return null;
  return (
    <div className={`flex items-center gap-1.5 text-12 ${className}`} data-testid="update-banner" data-state={u.canInstall ? 'ready' : 'downloading'}>
      <span className="text-text-2">{u.canInstall ? copy.update.ready(u.available) : copy.update.downloading(u.available)}</span>
      {u.canInstall && (
        <button type="button" onClick={() => install.mutate()} disabled={install.isPending} className="font-medium text-accent hover:text-accent-hover disabled:text-text-3" data-testid="update-install">
          {copy.update.installNow}
        </button>
      )}
    </div>
  );
}
