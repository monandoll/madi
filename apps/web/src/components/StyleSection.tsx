import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import type { StyleResponse } from '@madi/shared';
import { copy } from '../copy.js';
import { api, queryKeys } from '../lib/api.js';
import { usePatchSettings, useSettings } from '../lib/settings.js';
import { FolderChooser } from './FolderChooser.js';
import { SectionTitle, Card, CardRow } from './Settings.js';

/**
 * 설정 · 내 편집 스타일 (design/v2 Desktop 설정 카드).
 * - 규칙 목록: 사용자 줄은 빼기, 배운 줄은 '배움' 표시만
 * - 규칙 추가 한 줄
 * - "샘플 영상 더 넣어서 다시 배우기" → 완성본 폴더 (추가/빼기, 배운 상태, 다시 배우기)
 */
export function StyleSection({ aiOn }: { aiOn: boolean }) {
  const qc = useQueryClient();
  const { settings } = useSettings();
  const patch = usePatchSettings();
  const style = useQuery({ queryKey: queryKeys.style, queryFn: api.style });
  const [draft, setDraft] = useState('');
  const [adding, setAdding] = useState(false);
  const [refsOpen, setRefsOpen] = useState(false);
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
  const showRefs = refsOpen || folders.length > 0;

  return (
    <section className="flex flex-col gap-[9px] pc:col-span-full" data-testid="style-section">
      <SectionTitle>{copy.settings.styleLabel}</SectionTitle>
      {!aiOn && <p className="text-14 text-text-2">{copy.settings.styleOff}</p>}
      <Card testId="style-rules">
        {rules.length === 0 && <CardRow first>{<span className="text-13 text-text-3">{style.isPending ? copy.empty.loading : copy.settings.styleNoRules}</span>}</CardRow>}
        {rules.map((r, i) => (
          <CardRow key={`${i}-${r.text}`} first={i === 0} testId="style-rule" data-learned={r.learned ? 'true' : 'false'}>
            <span className="min-w-0 flex-1 text-13 leading-normal pc:text-14" style={{ textWrap: 'pretty' }}>
              {r.text}
            </span>
            {r.learned ? (
              <span className="flex-none rounded-pill bg-track px-[7px] py-0.5 text-11 text-text-2">{copy.settings.styleLearnedTag}</span>
            ) : (
              <button type="button" onClick={() => remove.mutate(i)} disabled={remove.isPending} className="flex-none text-13 text-text-2 hover:text-accent">
                {copy.settings.styleRemove}
              </button>
            )}
          </CardRow>
        ))}
      </Card>
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
          className="min-w-0 flex-1 rounded-thumb border border-input bg-surface px-3 py-[9px] text-14 outline-none placeholder:text-text-3 focus:border-accent"
          value={draft}
          maxLength={200}
          placeholder={copy.settings.styleAddPlaceholder}
          onChange={(e) => setDraft(e.target.value)}
        />
        <button type="submit" disabled={draft.trim().length < 2 || add.isPending} className="rounded-thumb border border-line px-3.5 text-13 font-medium hover:bg-hover disabled:text-text-3">
          {copy.settings.styleAdd}
        </button>
      </form>
      <p className="text-12 text-text-3">{copy.settings.styleHelp}</p>

      <div className="flex flex-col gap-2.5 pt-1" data-testid="references-section">
        <div className="flex items-center gap-2.5">
          <button type="button" onClick={() => setRefsOpen((v) => !v)} className="self-start rounded-thumb border border-line px-3.5 py-2 text-13 font-medium hover:border-accent hover:text-accent">
            {copy.settings.referencesLabel}
          </button>
          <span className="text-12 text-text-3" data-testid="references-status">
            {refs.length ? copy.settings.referencesCount(done, busy, failed) : ''}
          </span>
        </div>
        {showRefs && (
          <>
            <Card testId="reference-folders">
              {folders.map((p, i) => (
                <CardRow key={p} first={i === 0}>
                  <span className="flex min-w-0 flex-1 flex-col gap-px">
                    <span className="text-14 font-medium">{baseName(p)}</span>
                    <span className="truncate text-12 text-text-3">{p}</span>
                  </span>
                  <button type="button" onClick={() => setFolders(folders.filter((x) => x !== p))} className="flex-none text-13 text-text-2 hover:text-accent">
                    {copy.folders.remove}
                  </button>
                </CardRow>
              ))}
              {!adding && (
                <button type="button" onClick={() => setAdding(true)} className={`flex min-h-11 items-center px-3 text-left text-13 font-medium text-accent hover:bg-surface-2 ${folders.length > 0 ? 'border-t border-line-soft' : ''}`}>
                  {copy.folders.add}
                </button>
              )}
            </Card>
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
              <p className="text-12 text-text-3">{copy.settings.referencesHelp}</p>
              {folders.length > 0 && (
                <button type="button" onClick={() => relearn.mutate()} disabled={relearn.isPending} className="flex-none text-13 text-text-2 hover:text-accent" data-testid="relearn">
                  {copy.settings.referencesRelearn}
                </button>
              )}
            </div>
          </>
        )}
      </div>
    </section>
  );
}

function baseName(p: string): string {
  const parts = p.split(/[\\/]/).filter(Boolean);
  return parts[parts.length - 1] ?? p;
}
