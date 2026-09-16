import { copy } from '../copy.js';
import { back, type Route } from '../lib/route.js';
import { useIsPc } from '../store.js';
import { BackIcon } from './Icons.js';

interface Props {
  title: string;
  /** 제목 아래 작은 글자 (길이 · 날짜, 상태 등) */
  meta?: string | undefined;
  /** 모바일 갤러리처럼 제목 아래에 초록 점 */
  dot?: boolean;
  /** 모바일에서 ← 를 보일지 */
  showBack?: boolean;
  backFallback?: Route;
  /** 오른쪽 끝 버튼들 */
  actions?: React.ReactNode;
  /** 오른쪽 끝의 accent 글자 링크 (모바일 상세의 "결과물") */
  aside?: React.ReactNode;
}

/**
 * 화면 위 제목 줄.
 * - 모바일: design/v2/Mobile.dc.html 46px (← · 제목/부제 · 오른쪽 링크)
 * - PC: design/v2/Desktop.dc.html 50px (제목/메타 · 오른쪽 버튼들)
 */
export function TopBar({ title, meta, dot = false, showBack = false, backFallback, actions, aside }: Props) {
  const pc = useIsPc();
  if (pc) {
    return (
      <header className="flex min-h-[50px] flex-none items-center gap-2.5 border-b border-line-2 px-4 py-2">
        <div className="flex min-w-0 flex-col gap-px">
          <h1 className="truncate text-15 font-semibold tracking-[-0.01em]">{title}</h1>
          {meta && <div className="truncate text-12 text-text-3">{meta}</div>}
        </div>
        <div className="flex-1" />
        {aside}
        {actions}
      </header>
    );
  }
  return (
    <header className="flex min-h-[46px] flex-none items-center gap-2.5 border-b border-line-soft px-3.5 pt-1 pb-2.5">
      {showBack && (
        <button type="button" onClick={() => back(backFallback)} aria-label={copy.detail.back} className="-ml-1.5 flex h-8 w-8 flex-none items-center justify-center rounded-thumb text-text-2 hover:bg-hover">
          <BackIcon />
        </button>
      )}
      <div className="flex min-w-0 flex-1 flex-col gap-px">
        <h1 className="truncate text-16 font-semibold tracking-[-0.01em]">{title}</h1>
        {(meta || dot) && (
          <div className="flex min-w-0 items-center gap-1.5">
            {dot && <span className="h-1.5 w-1.5 flex-none rounded-pill bg-ok" data-testid="engine-dot" />}
            <span className="truncate text-12 text-text-3">{meta}</span>
          </div>
        )}
      </div>
      {aside}
      {actions}
    </header>
  );
}

/** PC 헤더의 작은 테두리 버튼 ("결과물 보기") 과 글자 버튼 ("갤러리") */
export function HeaderButton({ children, onClick, outlined = false, testId }: { children: React.ReactNode; onClick(): void; outlined?: boolean; testId?: string }) {
  return (
    <button
      type="button"
      onClick={onClick}
      data-testid={testId}
      className={`flex-none rounded-row px-2.5 py-[5px] text-13 whitespace-nowrap text-text-2 hover:bg-hover ${outlined ? 'border border-line' : ''}`}
    >
      {children}
    </button>
  );
}
