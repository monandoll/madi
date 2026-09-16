import { copy } from '../copy.js';
import { go } from '../lib/route.js';
import { GearIcon } from './Icons.js';

interface Props {
  workspaceName: string;
  aiConnected: boolean;
  engineOk: boolean;
}

/** design/Setup.dc.html 갤러리 헤더: 48px, 상태 점 · 스튜디오 이름 · AI 상태 · 설정 톱니. */
export function Header({ workspaceName, aiConnected, engineOk }: Props) {
  return (
    <header className="flex h-12 flex-none items-center gap-2 border-b border-line bg-surface px-3.5">
      <span
        data-testid="engine-dot"
        className="h-[7px] w-[7px] rounded-pill"
        style={{ background: engineOk ? 'var(--color-ok)' : 'var(--color-line)' }}
      />
      <h1 className="min-w-0 flex-1 truncate text-15 font-semibold tracking-[-0.01em]">{workspaceName}</h1>
      <span className="text-12 text-text-2">{aiConnected ? copy.header.aiOn : copy.header.aiOff}</span>
      <button
        type="button"
        aria-label={copy.header.settings}
        title={copy.header.settings}
        onClick={() => go('settings')}
        className="-mr-1 flex h-11 w-9 items-center justify-center text-text-2"
      >
        <GearIcon />
      </button>
    </header>
  );
}
