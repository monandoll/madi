import { copy } from '../copy.js';

export type ActionKey = 'subtitle' | 'silence' | 'vertical' | 'short';

interface Props {
  disabled?: boolean;
  hasAudio: boolean;
  busy: boolean;
  onAction(key: ActionKey): void;
}

/**
 * AI 미연결 상태의 버튼 4개. 시안의 추천 칩 자리(하단, 1px 윗선)에 칩 모양 그대로.
 * 입력창은 없다 — 러너를 스폰하지 않는 상태라서.
 */
export function ActionBar({ disabled = false, hasAudio, busy, onAction }: Props) {
  const items: { key: ActionKey; label: string; needsAudio: boolean }[] = [
    { key: 'subtitle', label: copy.detail.actions.subtitle, needsAudio: true },
    { key: 'silence', label: copy.detail.actions.silence, needsAudio: true },
    { key: 'vertical', label: copy.detail.actions.vertical, needsAudio: false },
    { key: 'short', label: copy.detail.actions.short, needsAudio: false },
  ];
  return (
    <div className="flex flex-none flex-col gap-2 border-t border-line px-3 pt-2.5 pb-3" data-testid="action-bar">
      <div className="flex flex-wrap gap-1.5">
        {items.map((it) => {
          const off = disabled || busy || (it.needsAudio && !hasAudio);
          return (
            <button
              key={it.key}
              type="button"
              data-action={it.key}
              disabled={off}
              onClick={() => onAction(it.key)}
              className={`h-11 rounded-pill border border-line px-[11px] text-12 whitespace-nowrap ${off ? 'text-text-2' : ''}`}
            >
              {it.label}
            </button>
          );
        })}
      </div>
    </div>
  );
}
