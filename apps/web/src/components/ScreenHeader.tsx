import { copy } from '../copy.js';
import { back, type Route } from '../lib/route.js';

interface Props {
  title: string;
  /** 오른쪽 끝의 작은 글자 (길이 등) */
  aside?: string | undefined;
  fallback?: Route;
  /** '← 뒤로' 처럼 글자를 붙일지, 화살표만 둘지 */
  backLabel?: boolean;
}

/** 상세·결과물 화면 헤더. 48px, 1px 선. design/Mobile.dc.html. */
export function ScreenHeader({ title, aside, fallback, backLabel = false }: Props) {
  return (
    <header className="flex h-12 flex-none items-center gap-2.5 border-b border-line bg-surface px-3.5">
      <button type="button" onClick={() => back(fallback)} className="-ml-1 flex h-11 items-center px-1 text-13 text-text-3" aria-label={copy.detail.back}>
        ←{backLabel ? ` ${copy.detail.back}` : ''}
      </button>
      <h1 className="min-w-0 flex-1 truncate text-14 font-semibold">{title}</h1>
      {aside && <span className="text-12 text-text-2">{aside}</span>}
    </header>
  );
}
