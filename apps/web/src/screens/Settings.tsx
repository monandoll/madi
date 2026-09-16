import { useEffect, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Settings as SettingsSchema } from '@madi/shared';
import { FolderChooser } from '../components/FolderChooser.js';
import { copy } from '../copy.js';
import { api, queryKeys } from '../lib/api.js';
import { go } from '../lib/route.js';
import { usePatchSettings, useSettings } from '../lib/settings.js';

/** design/Setup.dc.html 오른쪽. 이름 · 영상 폴더 · AI · 버전. 저장 버튼 없이 바로 반영. */
export function SettingsScreen() {
  const { settings } = useSettings();
  const patch = usePatchSettings();
  const health = useQuery({ queryKey: queryKeys.health, queryFn: api.health });
  const [name, setName] = useState(settings.workspaceName);
  const [adding, setAdding] = useState(false);
  useEffect(() => setName(settings.workspaceName), [settings.workspaceName]);

  const commitName = () => {
    const parsed = SettingsSchema.shape.workspaceName.safeParse(name);
    if (!parsed.success) {
      setName(settings.workspaceName);
      return;
    }
    if (parsed.data !== settings.workspaceName) patch.mutate({ workspaceName: parsed.data });
  };

  const setFolders = (next: string[]) => patch.mutate({ watchFolders: next, setupDone: true });

  return (
    <div className="flex h-full flex-col bg-bg" data-testid="settings-screen">
      <header className="flex h-12 flex-none items-center gap-2.5 border-b border-line bg-surface px-3.5">
        <button type="button" onClick={() => go('gallery')} className="-ml-1 flex h-11 items-center px-1 text-13 text-text-3">
          ← {copy.settings.back}
        </button>
        <h1 className="flex-1 text-14 font-semibold">{copy.settings.title}</h1>
      </header>

      <main className="flex min-h-0 flex-1 flex-col overflow-y-auto">
        <section className="flex flex-col gap-1.5 border-b border-line bg-surface px-3.5 pt-4 pb-3.5">
          <label className="text-12 text-text-3" htmlFor="settings-name">
            {copy.settings.nameLabel}
          </label>
          <input
            id="settings-name"
            data-testid="settings-name"
            className="h-11 rounded-thumb border border-line bg-surface px-3 text-14 outline-none focus:border-accent"
            value={name}
            maxLength={40}
            onChange={(e) => setName(e.target.value)}
            onBlur={commitName}
            onKeyDown={(e) => {
              if (e.key === 'Enter') (e.target as HTMLInputElement).blur();
            }}
          />
          <p className="text-11 text-text-2">{copy.settings.nameHelp}</p>
        </section>

        <section className="flex flex-col gap-2 border-b border-line bg-surface px-3.5 pt-4 pb-3.5">
          <div className="flex items-baseline justify-between">
            <span className="text-12 text-text-3">{copy.settings.foldersLabel}</span>
            <span className="text-11 text-text-2">{copy.settings.foldersHelp}</span>
          </div>
          <div className="flex flex-col overflow-hidden rounded-thumb border border-line" data-testid="folder-list">
            {settings.watchFolders.map((p, i) => (
              <div key={p} className={`flex h-11 items-center gap-2.5 px-3 ${i > 0 ? 'border-t border-line-soft' : ''}`}>
                <span className="flex min-w-0 flex-1 flex-col gap-px">
                  <span className="text-13 font-medium">{baseName(p)}</span>
                  <span className="truncate text-11 text-text-2">{p}</span>
                </span>
                <button type="button" onClick={() => setFolders(settings.watchFolders.filter((x) => x !== p))} className="flex-none text-12 text-text-3">
                  {copy.folders.remove}
                </button>
              </div>
            ))}
            {!adding && (
              <button
                type="button"
                onClick={() => setAdding(true)}
                className={`flex h-11 items-center px-3 text-left text-13 font-medium text-accent ${settings.watchFolders.length > 0 ? 'border-t border-line-soft' : ''}`}
              >
                {copy.folders.add}
              </button>
            )}
          </div>
          {adding && (
            <FolderChooser
              value={settings.watchFolders}
              onChange={(next) => {
                setFolders(next);
                setAdding(false);
              }}
              hideSelected
            />
          )}
        </section>

        <section className="flex flex-col gap-1.5 border-b border-line bg-surface px-3.5 pt-4 pb-3.5">
          <span className="text-12 text-text-3">{copy.settings.aiLabel}</span>
          <div className="flex h-11 items-center gap-2">
            <span className="h-[7px] w-[7px] rounded-pill" style={{ background: health.data?.ai.connected ? 'var(--color-ok)' : 'var(--color-line)' }} />
            <span className="flex-1 text-14">{health.data?.ai.connected ? copy.header.aiOn : copy.settings.aiOff}</span>
            {!health.data?.ai.connected && <span className="text-12 text-text-2">{copy.settings.aiSoon}</span>}
          </div>
          <p className="text-11 leading-normal text-text-2">{copy.settings.aiHelp}</p>
        </section>

        <p className="p-3.5 text-11 text-text-2">{health.data ? copy.settings.version(health.data.version) : ''}</p>
      </main>
    </div>
  );
}

function baseName(p: string): string {
  const parts = p.split(/[\\/]/).filter(Boolean);
  return parts[parts.length - 1] ?? p;
}
