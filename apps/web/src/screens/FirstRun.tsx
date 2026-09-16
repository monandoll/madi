import { useState } from 'react';
import { Settings } from '@madi/shared';
import { FolderChooser } from '../components/FolderChooser.js';
import { copy } from '../copy.js';
import { usePatchSettings } from '../lib/settings.js';

interface Props {
  initialName: string;
  initialFolders: string[];
}

/**
 * design/v2/Desktop.dc.html 첫 실행: #F3F5F7 배경 가운데 460px 카드.
 * 스튜디오 이름 · 영상 폴더(라디오) · 시작하기 · 안내 한 줄. 모바일도 같은 카드를 전체 폭으로.
 */
export function FirstRun({ initialName, initialFolders }: Props) {
  const [name, setName] = useState(initialName);
  const [folders, setFolders] = useState<string[]>(initialFolders);
  const patch = usePatchSettings();
  const nameOk = Settings.shape.workspaceName.safeParse(name).success;

  return (
    <div className="flex h-full items-center justify-center overflow-y-auto bg-side p-4 pc:p-8" data-testid="first-run">
      <section className="flex w-full max-w-[460px] flex-col gap-[18px] rounded-card border border-line bg-surface px-5 pt-6 pb-5 pc:px-7 pc:pt-7 pc:pb-6" data-testid="setup-card">
        <div className="flex flex-col gap-1.5">
          <h2 className="text-20 font-semibold tracking-[-0.02em]">{copy.setup.title}</h2>
          <p className="text-14 text-text-2">{copy.setup.subtitle}</p>
        </div>

        <label className="flex flex-col gap-[7px]">
          <span className="text-13 text-text-2">{copy.setup.nameLabel}</span>
          <span className="flex rounded-thumb border border-input px-3 py-[9px] focus-within:border-accent">
            <input
              data-testid="setup-name"
              className="w-full bg-transparent text-15 outline-none placeholder:text-text-3"
              value={name}
              maxLength={40}
              placeholder={copy.setup.namePlaceholder}
              onChange={(e) => setName(e.target.value)}
            />
          </span>
        </label>

        <div className="flex flex-col gap-[7px]">
          <span className="text-13 text-text-2">{copy.setup.folderLabel}</span>
          <FolderChooser value={folders} onChange={setFolders} single />
        </div>

        <button
          type="button"
          data-testid="setup-start"
          disabled={!nameOk || patch.isPending}
          onClick={() => patch.mutate({ workspaceName: name.trim(), watchFolders: folders, setupDone: true })}
          className="rounded-thumb bg-accent px-4 py-[11px] text-center text-14 font-semibold text-white hover:bg-accent-hover disabled:opacity-50"
        >
          {copy.setup.start}
        </button>
        <p className="text-center text-12 text-text-3">{copy.setup.hint}</p>
      </section>
    </div>
  );
}
