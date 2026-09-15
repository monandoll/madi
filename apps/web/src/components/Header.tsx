import { useEffect, useRef, useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { Settings } from '@madi/shared';
import { copy } from '../copy.js';
import { api, queryKeys } from '../lib/api.js';

interface Props {
  workspaceName: string;
  aiConnected: boolean;
  engineOk: boolean;
}

/**
 * design/Mobile.dc.html 갤러리 헤더: 48px, 상태 점 · 스튜디오 이름 · AI 상태.
 * 이름을 탭하면 같은 자리에서 고친다 (Enter 저장, Esc 취소). 설정 화면이 따로 없어서 여기서.
 */
export function Header({ workspaceName, aiConnected, engineOk }: Props) {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(workspaceName);
  const inputRef = useRef<HTMLInputElement>(null);
  const qc = useQueryClient();

  const rename = useMutation({
    mutationFn: (name: string) => api.patchSettings({ workspaceName: name }),
    onSuccess: (data) => qc.setQueryData(queryKeys.settings, data),
  });

  useEffect(() => {
    if (editing) inputRef.current?.select();
  }, [editing]);

  const start = () => {
    setDraft(workspaceName);
    setEditing(true);
  };
  const cancel = () => setEditing(false);
  const commit = () => {
    setEditing(false);
    const parsed = Settings.shape.workspaceName.safeParse(draft);
    if (parsed.success && parsed.data !== workspaceName) rename.mutate(parsed.data);
  };

  return (
    <header className="flex h-12 flex-none items-center gap-2 border-b border-line bg-surface px-3.5">
      <span
        data-testid="engine-dot"
        className="h-[7px] w-[7px] rounded-pill"
        style={{ background: engineOk ? 'var(--color-ok)' : 'var(--color-line)' }}
      />
      {editing ? (
        <input
          ref={inputRef}
          data-testid="workspace-name-input"
          className="min-w-0 flex-1 bg-transparent text-15 font-semibold tracking-[-0.01em] outline-none placeholder:font-normal placeholder:text-text-2"
          value={draft}
          maxLength={40}
          placeholder={copy.header.namePlaceholder}
          onChange={(e) => setDraft(e.target.value)}
          onBlur={commit}
          onKeyDown={(e) => {
            if (e.key === 'Enter') commit();
            else if (e.key === 'Escape') cancel();
          }}
        />
      ) : (
        <h1 className="min-w-0 flex-1">
          <button
            type="button"
            title={copy.header.renameHint}
            onClick={start}
            className="block max-w-full truncate text-left text-15 font-semibold tracking-[-0.01em]"
          >
            {workspaceName}
          </button>
        </h1>
      )}
      <span className="text-12 text-text-2">{aiConnected ? copy.header.aiOn : copy.header.aiOff}</span>
    </header>
  );
}
