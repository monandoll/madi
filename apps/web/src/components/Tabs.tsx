import { copy } from '../copy.js';
import { type GalleryTab, useUi } from '../store.js';

const TABS: { id: GalleryTab; label: string }[] = [
  { id: 'videos', label: copy.tabs.videos },
  { id: 'outputs', label: copy.tabs.outputs },
  { id: 'inProgress', label: copy.tabs.inProgress },
];

/** 칩 탭. 활성: accent-soft 배경 + accent 글자, 600. */
export function Tabs() {
  const tab = useUi((s) => s.tab);
  const setTab = useUi((s) => s.setTab);
  return (
    <nav className="flex flex-none gap-1 px-3.5 pt-2.5 pb-2" role="tablist">
      {TABS.map((t) => {
        const active = t.id === tab;
        return (
          <button
            key={t.id}
            type="button"
            role="tab"
            aria-selected={active}
            onClick={() => setTab(t.id)}
            className={
              active
                ? 'rounded-pill bg-accent-soft px-3 py-1.5 text-13 font-semibold text-accent'
                : 'rounded-pill px-3 py-1.5 text-13 text-text-2'
            }
          >
            {t.label}
          </button>
        );
      })}
    </nav>
  );
}
