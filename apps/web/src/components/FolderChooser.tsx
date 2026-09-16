import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import type { FolderSuggestion } from '@madi/shared';
import { copy } from '../copy.js';
import { ApiError, api, queryKeys } from '../lib/api.js';

interface Props {
  /** 지금 고른 폴더들 */
  value: string[];
  onChange(next: string[]): void;
  /** true 면 하나만 고른다 (첫 실행). false 면 여러 개 (설정). */
  single?: boolean;
  /** 이미 고른 폴더는 목록에서 뺀다 (설정의 '폴더 추가') */
  hideSelected?: boolean;
}

/**
 * 엔진이 찾아 준 폴더 후보에서 고른다. 경로 타이핑 없음.
 * design/v2/Desktop.dc.html 첫 실행 카드의 라디오 줄 (16px 원, 이름 14/500 · 경로 12 · 개수 12).
 * 마지막 줄 '다른 폴더 고르기…' 는 시스템 선택창 — 브라우저만 뜬 상태면 안내 문구.
 */
export function FolderChooser({ value, onChange, single = false, hideSelected = false }: Props) {
  const qc = useQueryClient();
  const suggest = useQuery({ queryKey: queryKeys.folders, queryFn: api.suggestFolders });
  const [extra, setExtra] = useState<FolderSuggestion[]>([]);
  const [pickerHint, setPickerHint] = useState(false);

  const pick = useMutation({
    mutationFn: api.pickFolder,
    onSuccess: ({ folder }) => {
      if (!folder) return;
      if (!all.some((f) => f.path === folder.path)) setExtra((xs) => [...xs, folder]);
      select(folder.path);
      void qc.invalidateQueries({ queryKey: queryKeys.folders });
    },
    onError: (err) => {
      if (err instanceof ApiError && err.status === 501) setPickerHint(true);
    },
  });

  const all = [...(suggest.data?.folders ?? []), ...extra.filter((e) => !suggest.data?.folders.some((f) => f.path === e.path))];
  const rows = hideSelected ? all.filter((f) => !value.includes(f.path)) : all;

  const select = (p: string) => {
    if (single) onChange([p]);
    else onChange(value.includes(p) ? value.filter((x) => x !== p) : [...value, p]);
  };

  return (
    <div className="flex flex-col overflow-hidden rounded-thumb border border-line" data-testid="folder-chooser">
      {suggest.isPending && <Row muted>{copy.folders.loading}</Row>}
      {suggest.isSuccess && rows.length === 0 && <Row muted>{copy.folders.noneFound}</Row>}
      {rows.map((f, i) => {
        const on = value.includes(f.path);
        return (
          <button
            key={f.path}
            type="button"
            role={single ? 'radio' : 'checkbox'}
            aria-checked={on}
            onClick={() => select(f.path)}
            className={`flex items-center gap-2.5 px-3 py-[11px] text-left hover:bg-surface-2 ${i > 0 || suggest.isPending ? 'border-t border-line-soft' : ''} ${on ? 'bg-[#F4F9FC]' : ''}`}
          >
            <span className={`flex h-4 w-4 flex-none items-center justify-center rounded-pill border-[1.5px] ${on ? 'border-accent' : 'border-off'}`}>
              <span className={`h-2 w-2 rounded-pill ${on ? 'bg-accent' : 'bg-transparent'}`} />
            </span>
            <span className="flex min-w-0 flex-1 flex-col gap-px">
              <span className="text-14 font-medium">{f.label}</span>
              <span className="truncate text-12 text-text-3">{f.path}</span>
            </span>
            <span className="flex-none text-12 text-text-3">{copy.folders.count(f.videoCount)}</span>
          </button>
        );
      })}
      <button
        type="button"
        onClick={() => pick.mutate()}
        disabled={pick.isPending}
        className={`flex min-h-11 items-center px-3 text-left text-13 font-medium text-accent hover:bg-surface-2 ${rows.length > 0 || suggest.isPending ? 'border-t border-line-soft' : ''}`}
      >
        {hideSelected ? copy.folders.add : copy.folders.pickOther}
      </button>
      {pickerHint && <Row muted>{copy.folders.noPicker}</Row>}
    </div>
  );
}

function Row({ children, muted }: { children: React.ReactNode; muted?: boolean }) {
  return <div className={`flex min-h-11 items-center px-3 py-2 text-12 leading-snug ${muted ? 'text-text-3' : ''}`}>{children}</div>;
}
