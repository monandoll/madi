import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { linkSiteLabel, normalizeVideoUrl, type Reference, type StyleResponse } from '@madi/shared';
import { copy } from '../copy.js';
import { api, ApiError, queryKeys } from '../lib/api.js';
import { usePatchSettings, useSettings } from '../lib/settings.js';
import { FolderChooser } from './FolderChooser.js';
import { SectionTitle, Card, CardRow, Status } from './Settings.js';

/**
 * 설정 · 내 편집 스타일 (design/v2 Desktop 설정 카드).
 * - 규칙 목록: 사용자 줄은 빼기, 배운 줄은 '배움' 표시만
 * - 규칙 추가 한 줄
 * - 기존 영상으로 배우기: 완성본 폴더 (추가/빼기) + 링크로 배우기 (유튜브·틱톡·릴스 붙여넣기 → 받아서 배움) + 다시 배우기
 */
export function StyleSection({ aiOn }: { aiOn: boolean }) {
  const qc = useQueryClient();
  const { settings } = useSettings();
  const patch = usePatchSettings();
  const style = useQuery({ queryKey: queryKeys.style, queryFn: api.style });
  const [draft, setDraft] = useState('');
  const [adding, setAdding] = useState(false);
  const [link, setLink] = useState('');
  const [linkError, setLinkError] = useState<string | null>(null);
  const put = (data: StyleResponse) => qc.setQueryData(queryKeys.style, data);
  const add = useMutation({ mutationFn: (rule: string) => api.addRule(rule), onSuccess: put });
  const remove = useMutation({ mutationFn: (i: number) => api.removeRule(i), onSuccess: put });
  const relearn = useMutation({ mutationFn: api.relearn, onSuccess: put });
  const addLink = useMutation({
    mutationFn: (url: string) => api.addLink(url),
    onSuccess: (data) => {
      put(data);
      setLink('');
      setLinkError(null);
    },
    onError: (err) => setLinkError(err instanceof ApiError && err.code === 'no_downloader' ? copy.settings.linksOff : copy.settings.linkBad),
  });
  const removeRef = useMutation({ mutationFn: (id: string) => api.removeReference(id), onSuccess: put });

  const rules = style.data?.rules ?? [];
  const refs = style.data?.references ?? [];
  const links = refs.filter((r) => r.source === 'link');
  const done = refs.filter((r) => r.status === 'done').length;
  const busy = refs.filter((r) => r.status === 'queued' || r.status === 'downloading' || r.status === 'analyzing').length;
  const failed = refs.filter((r) => r.status === 'failed').length;
  const folders = settings.referenceFolders;
  const setFolders = (next: string[]) => patch.mutate({ referenceFolders: next });
  const linkImport = style.data?.linkImport ?? true;
  const linkOk = normalizeVideoUrl(link) !== null;

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

      {/* 기존 영상으로 배우기 */}
      <div className="flex flex-col gap-[9px] pt-3" data-testid="references-section">
        <SectionTitle
          aside={
            <span data-testid="references-status">
              {refs.length ? copy.settings.referencesCount(done, busy, failed) : ''}
            </span>
          }
        >
          {copy.settings.referencesLabel}
        </SectionTitle>
        <p className="text-12 text-text-3">{copy.settings.referencesIntro}</p>

        <Card testId="reference-folders">
          {folders.map((p, i) => (
            <CardRow key={p} first={i === 0}>
              <span className="flex min-w-0 flex-1 flex-col gap-px">
                <span className="text-14 font-medium">
                  <span className="text-text-3">{copy.settings.referencesFoldersLabel} · </span>
                  {baseName(p)}
                </span>
                <span className="truncate text-12 text-text-3">{p}</span>
              </span>
              <button type="button" onClick={() => setFolders(folders.filter((x) => x !== p))} className="flex-none text-13 text-text-2 hover:text-accent">
                {copy.folders.remove}
              </button>
            </CardRow>
          ))}
          {folders.length === 0 && (
            <CardRow first>
              <span className="flex-1 text-14 font-medium">{copy.settings.referencesFoldersLabel}</span>
              <span className="text-12 text-text-3">{copy.settings.referencesEmpty}</span>
            </CardRow>
          )}
          {!adding && (
            <button type="button" onClick={() => setAdding(true)} className="flex min-h-11 items-center border-t border-line-soft px-3 text-left text-13 font-medium text-accent hover:bg-surface-2">
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

        {/* 링크로 배우기 */}
        <form
          className="flex gap-2 pt-1"
          data-testid="link-form"
          onSubmit={(e) => {
            e.preventDefault();
            if (!linkOk || addLink.isPending) return;
            addLink.mutate(link.trim());
          }}
        >
          <input
            data-testid="link-input"
            className="min-w-0 flex-1 rounded-thumb border border-input bg-surface px-3 py-[9px] text-14 outline-none placeholder:text-text-3 focus:border-accent"
            value={link}
            inputMode="url"
            autoComplete="off"
            spellCheck={false}
            placeholder={copy.settings.linksPlaceholder}
            onChange={(e) => {
              setLink(e.target.value);
              setLinkError(null);
            }}
          />
          <button type="submit" disabled={!linkOk || addLink.isPending} className="rounded-thumb border border-line px-3.5 text-13 font-medium hover:bg-hover disabled:text-text-3" data-testid="link-add">
            {copy.settings.linksAdd}
          </button>
        </form>
        {links.length > 0 && (
          <Card testId="link-list">
            {links.map((r, i) => (
              <LinkRow key={r.id} reference={r} first={i === 0} onRemove={() => removeRef.mutate(r.id)} removing={removeRef.isPending} />
            ))}
          </Card>
        )}
        <div className="flex items-baseline justify-between gap-2">
          <p className="text-12 text-text-3" data-testid="link-help">
            {linkError ?? (!linkImport ? copy.settings.linksOff : copy.settings.linksHelp)}
          </p>
          {(folders.length > 0 || links.length > 0) && (
            <button type="button" onClick={() => relearn.mutate()} disabled={relearn.isPending} className="flex-none text-13 text-text-2 hover:text-accent" data-testid="relearn">
              {copy.settings.referencesRelearn}
            </button>
          )}
        </div>
      </div>
    </section>
  );
}

/** 링크 완성본 한 줄: 출처 · 제목 · 상태 점 · 빼기. 못 읽었으면 이유를 AI 말투로. */
function LinkRow({ reference: r, first, onRemove, removing }: { reference: Reference; first: boolean; onRemove(): void; removing: boolean }) {
  const failedText = r.status === 'failed' ? (copy.settings.linkErrors[r.error ?? ''] ?? copy.settings.linkErrors['link_failed']) : null;
  return (
    <CardRow first={first} testId="link-row">
      <span className="flex min-w-0 flex-1 flex-col gap-px">
        <span className="truncate text-14 font-medium">
          <span className="text-text-3">{linkSiteLabel(r.url ?? '')} · </span>
          {r.title}
        </span>
        <span className="truncate text-12 text-text-3">{failedText ?? r.url}</span>
      </span>
      <Status on={r.status === 'done'} busy={r.status === 'queued' || r.status === 'downloading' || r.status === 'analyzing'} testId="link-status">
        {copy.settings.linkStatus[r.status] ?? r.status}
      </Status>
      <button type="button" onClick={onRemove} disabled={removing} className="flex-none text-13 text-text-2 hover:text-accent" data-testid="link-remove">
        {copy.folders.remove}
      </button>
    </CardRow>
  );
}

function baseName(p: string): string {
  const parts = p.split(/[\\/]/).filter(Boolean);
  return parts[parts.length - 1] ?? p;
}
