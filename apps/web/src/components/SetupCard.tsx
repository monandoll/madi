import { useState } from 'react';
import { Settings } from '@madi/shared';
import { copy } from '../copy.js';
import { usePatchSettings } from '../lib/settings.js';
import { FolderChooser } from './FolderChooser.js';

interface Props {
  initialName: string;
  initialFolders: string[];
}

/** design/Setup.dc.html 왼쪽. 처음 켰을 때 갤러리 위에 한 번만. */
export function SetupCard({ initialName, initialFolders }: Props) {
  const [name, setName] = useState(initialName);
  const [folders, setFolders] = useState<string[]>(initialFolders);
  const patch = usePatchSettings();
  const nameOk = Settings.shape.workspaceName.safeParse(name).success;

  return (
    <section className="flex flex-col gap-3.5 rounded-panel border border-line bg-surface p-3.5" data-testid="setup-card">
      <div className="flex flex-col gap-[3px]">
        <h2 className="text-14 font-semibold">{copy.setup.title}</h2>
        <p className="text-12 leading-normal text-text-2">{copy.setup.subtitle}</p>
      </div>

      <label className="flex flex-col gap-1.5">
        <span className="text-12 text-text-3">{copy.setup.nameLabel}</span>
        <input
          data-testid="setup-name"
          className="h-11 rounded-thumb border border-line bg-surface px-3 text-14 outline-none placeholder:text-text-2 focus:border-accent"
          value={name}
          maxLength={40}
          placeholder={copy.setup.namePlaceholder}
          onChange={(e) => setName(e.target.value)}
        />
      </label>

      <div className="flex flex-col gap-1.5">
        <span className="text-12 text-text-3">{copy.setup.folderLabel}</span>
        <FolderChooser value={folders} onChange={setFolders} single />
      </div>

      <button
        type="button"
        data-testid="setup-start"
        disabled={!nameOk || patch.isPending}
        onClick={() => patch.mutate({ workspaceName: name.trim(), watchFolders: folders, setupDone: true })}
        className="h-11 rounded-thumb bg-accent text-14 font-semibold text-white disabled:opacity-50"
      >
        {copy.setup.start}
      </button>
    </section>
  );
}
