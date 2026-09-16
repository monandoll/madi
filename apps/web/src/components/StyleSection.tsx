import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import type { StyleResponse } from '@madi/shared';
import { copy } from '../copy.js';
import { api, queryKeys } from '../lib/api.js';
import { usePatchSettings, useSettings } from '../lib/settings.js';
import { FolderChooser } from './FolderChooser.js';

/**
 * 설정 · 편집 스타일 (5단계). 설정 화면의 다른 섹션과 같은 틀(라벨 12 · 44px 줄 · 1px 선).
 * - 규칙 목록: 사용자 줄은 빼기, 배운 줄은 '배움' 표시만
 * - 규칙 추가 한 줄
 * - 완성본 폴더: 추가/빼기, 배운 상태
 */
export function StyleSection() {
  const qc = useQueryClient();
  const { settings } = useSettings();
  const patch = usePatchSettings();
  const style = useQuery({ queryKey: queryKeys.style, queryFn: api.style });
  const [draft, setDraft] = useState('');
  const [adding, setAdding] = useState(false);
  const put = (data: StyleResponse) => qc.setQueryData(queryKeys.style, data);
  const add = useMutation({ mutationFn: (rule: string) => api.addRule(rule), onSuccess: put });
  const remove = useMutation({ mutationFn: (i: number) => api.removeRule(i), onSuccess: put });
  const relearn = useMutation({ mutationFn: api.relearn, onSuccess: put });

  const rules = style.data?.rules ?? [];
  const refs = style.data?.references ?? [];
  const done = refs.filter((r) => r.status === 'done').length;
  const busy = refs.filter((r) => r.status === 'queued' || r.status === 'analyzing').length;
  const failed = refs.filter((r) => r.status === 'failed').length;
  const folders = settings.referenceFolders;
  const setFolders = (next: string[]) => patch.mutate({ referenceFolders: next });

  return (
    <>
      <section className="flex flex-col gap-1.5 border-b border-line bg-surface px-3.5 pt-4 pb-3.5" data-testid="style-section">
        <span className="text-12 text-text-3">{copy.settings.styleLabel}</span>
        <div className="flex flex-col overflow-hidden rounded-thumb border border-line" data-testid="style-rules">
          {rules.length === 0 && <div className="flex h-11 items-center px-3 text-13 text-text-2">{style.isPending ? copy.empty.loading : copy.settings.styleNoRules}</div>}
          {rules.map((r, i) => (
            <div key={`${i}-${r.text}`} className={`flex min-h-11 items-center gap-2.5 px-3 py-2 ${i > 0 ? 'border-t border-line-soft' : ''}`} data-testid="style-rule" data-learned={r.learned ? 'true' : 'false'}>
              <span className={`min-w-0 flex-1 text-13 leading-snug ${r.learned ? 'text-text-3' : ''}`}>{r.text}</span>
              {r.learned ? (
                <span className="flex-none rounded-pill bg-accent-soft px-2 py-0.5 text-11 text-accent">{copy.settings.styleLearnedTag}</span>
              ) : (
                <button type="button" onClick={() => remove.mutate(i)} disabled={remove.isPending} className="flex-none text-12 text-text-3">
                  {copy.settings.styleRemove}
                </button>
              )}
            </div>
          ))}
        </div>
        <form
          className="flex gap-2"
          onSubmit={(e) => {
            e.preventDefault();
            const t = draft.trim();
            if (t.length < 2) return;
            add.mutate(t);
            setDraft('');
          }}
        >
          <input
            data-testid="style-rule-input"
            className="h-11 min-w-0 flex-1 rounded-thumb border border-line bg-surface px-3 text-14 outline-none placeholder:text-text-2 focus:border-accent"
            value={draft}
            maxLength={200}
            placeholder={copy.settings.styleAddPlaceholder}
            onChange={(e) => setDraft(e.target.value)}
          />
          <button type="submit" disabled={draft.trim().length < 2 || add.isPending} className="h-11 rounded-thumb border border-line px-3.5 text-14 disabled:text-text-2">
            {copy.settings.styleAdd}
          </button>
        </form>
        <p className="text-11 leading-normal text-text-2">{copy.settings.styleHelp}</p>
      </section>

      <section className="flex flex-col gap-2 border-b border-line bg-surface px-3.5 pt-4 pb-3.5" data-testid="references-section">
        <div className="flex items-baseline justify-between">
          <span className="text-12 text-text-3">{copy.settings.referencesLabel}</span>
          <span className="text-11 text-text-2" data-testid="references-status">
            {refs.length ? copy.settings.referencesCount(done, busy, failed) : ''}
          </span>
        </div>
        <div className="flex flex-col overflow-hidden rounded-thumb border border-line" data-testid="reference-folders">
          {folders.map((p, i) => (
            <div key={p} className={`flex h-11 items-center gap-2.5 px-3 ${i > 0 ? 'border-t border-line-soft' : ''}`}>
              <span className="flex min-w-0 flex-1 flex-col gap-px">
                <span className="text-13 font-medium">{baseName(p)}</span>
                <span className="truncate text-11 text-text-2">{p}</span>
              </span>
              <button type="button" onClick={() => setFolders(folders.filter((x) => x !== p))} className="flex-none text-12 text-text-3">
                {copy.folders.remove}
              </button>
            </div>
          ))}
          {!adding && (
            <button type="button" onClick={() => setAdding(true)} className={`flex h-11 items-center px-3 text-left text-13 font-medium text-accent ${folders.length > 0 ? 'border-t border-line-soft' : ''}`}>
              {copy.folders.add}
            </button>
          )}
        </div>
        {adding && (
          <FolderChooser
            value={folders}
            onChange={(next) => {
              setFolders(next);
              setAdding(false);
            }}
            hideSelected
          />
        )}
        <div className="flex items-baseline justify-between gap-2">
          <p className="text-11 leading-normal text-text-2">{copy.settings.referencesHelp}</p>
          {folders.length > 0 && (
            <button type="button" onClick={() => relearn.mutate()} disabled={relearn.isPending} className="flex-none text-12 text-text-3" data-testid="relearn">
              {copy.settings.referencesRelearn}
            </button>
          )}
        </div>
      </section>
    </>
  );
}

function baseName(p: string): string {
  const parts = p.split(/[\\/]/).filter(Boolean);
  return parts[parts.length - 1] ?? p;
}
