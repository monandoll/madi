import { copy } from '../copy.js';
import { go } from '../lib/route.js';

export type ActionKey = 'subtitle' | 'silence' | 'vertical' | 'short' | 'chapters' | 'auto_shorts';

interface Props {
  disabled?: boolean;
  hasAudio: boolean;
  busy: boolean;
  /** 긴 영상(2분 이상)이면 챕터·자동 숏폼 버튼이 더 보인다 */
  longform?: boolean;
  onAction(key: ActionKey): void;
}

/**
 * design/v2 AI 미연결 상태: 2열 버튼(46px, 1px 선, 10px 모서리) + "AI를 연결하면 말로 편집할 수 있어요. 연결하기".
 * PC 는 버튼 오른쪽에 힌트 글자. 입력창은 없다 — 러너를 스폰하지 않는 상태라서.
 */
export function ActionBar({ disabled = false, hasAudio, busy, longform = false, onAction }: Props) {
  const items: { key: ActionKey; label: string; needsAudio: boolean }[] = [
    { key: 'subtitle', label: copy.detail.actions.subtitle, needsAudio: true },
    { key: 'silence', label: copy.detail.actions.silence, needsAudio: true },
    { key: 'vertical', label: copy.detail.actions.vertical, needsAudio: false },
    { key: 'short', label: copy.detail.actions.short, needsAudio: false },
    ...(longform
      ? [
          { key: 'chapters' as const, label: copy.detail.actions.chapters, needsAudio: false },
          { key: 'auto_shorts' as const, label: copy.detail.actions.autoShorts, needsAudio: false },
        ]
      : []),
  ];
  return (
    <div className="flex flex-none flex-col gap-2 border-t border-line-soft bg-surface px-3 pt-2.5 pb-3.5 pc:gap-2.5 pc:border-line-2 pc:px-6 pc:pb-4" data-testid="action-bar">
      <div className="grid grid-cols-2 gap-[7px] pc:grid-cols-[repeat(auto-fit,minmax(170px,1fr))] pc:gap-2">
        {items.map((it) => {
          const off = disabled || busy || (it.needsAudio && !hasAudio);
          return (
            <button
              key={it.key}
              type="button"
              data-action={it.key}
              disabled={off}
              onClick={() => onAction(it.key)}
              className={`flex min-h-[46px] items-center gap-2 rounded-panel border border-line px-3 py-2.5 text-left text-14 font-medium hover:border-accent disabled:text-text-3 disabled:hover:border-line pc:min-h-0 pc:rounded-thumb pc:py-[11px] ${off ? 'text-text-3' : ''}`}
            >
              <span className="flex-1">{it.label}</span>
              <span className="hidden text-12 font-normal text-text-3 pc:inline">{copy.detail.actionHints[it.key]}</span>
            </button>
          );
        })}
      </div>
      <p className="text-12 text-text-2 pc:text-13">
        {copy.detail.aiOffHint}{' '}
        <a
          href="#/settings"
          onClick={(e) => {
            e.preventDefault();
            go({ screen: 'settings' });
          }}
        >
          {copy.detail.aiOffLink}
        </a>
      </p>
    </div>
  );
}
