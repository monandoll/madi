import { useState } from 'react';
import type React from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { linkSiteLabel, normalizeVideoUrl, type MemoryItem, type Reference, type ReferenceInsight, type StyleResponse } from '@madi/shared';
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
  const excludeRef = useMutation({ mutationFn: (v: { id: string; excluded: boolean }) => api.patchReference(v.id, v.excluded), onSuccess: put });
  const removeMemory = useMutation({ mutationFn: (id: string) => api.removeMemory(id), onSuccess: put });
  const approveMemory = useMutation({ mutationFn: (ids?: string[]) => api.approveMemory(ids), onSuccess: put });
  const editMemory = useMutation({ mutationFn: (v: { id: string; text: string }) => api.patchMemory(v.id, { text: v.text }), onSuccess: put });
  const clearMemory = useMutation({
    mutationFn: () => api.clearMemory(false),
    onSuccess: (data) => {
      put(data);
      setClearing(false);
    },
  });
  const addMemory = useMutation({ mutationFn: (text: string) => api.addMemory({ text }), onSuccess: (data) => { put(data); setMemoryDraft(''); } });
  const [memoryDraft, setMemoryDraft] = useState('');
  const [clearing, setClearing] = useState(false);
  const [openInsight, setOpenInsight] = useState<string | null>(null);

  const rules = style.data?.rules ?? [];
  const refs = style.data?.references ?? [];
  const links = refs.filter((r) => r.source === 'link');
  const folderRefs = refs.filter((r) => r.source === 'folder');
  const memory = style.data?.memory ?? [];
  const proposed = memory.filter((m) => m.status === 'proposed');
  const approved = memory.filter((m) => m.status !== 'proposed');
  const insightOn = style.data?.insightOn ?? false;
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
        <button type="submit" data-testid="style-rule-add" disabled={draft.trim().length < 2 || add.isPending} className="rounded-thumb border border-line px-3.5 text-13 font-medium hover:bg-hover disabled:text-text-3">
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
        {folderRefs.length > 0 && (
          <Card testId="reference-list">
            {folderRefs.map((r, i) => (
              <ReferenceRow
                key={r.id}
                reference={r}
                first={i === 0}
                open={openInsight === r.id}
                onToggle={() => setOpenInsight(openInsight === r.id ? null : r.id)}
                insightOn={insightOn}
                onExclude={() => excludeRef.mutate({ id: r.id, excluded: !r.excluded })}
              />
            ))}
          </Card>
        )}
        {links.length > 0 && (
          <Card testId="link-list">
            {links.map((r, i) => (
              <LinkRow
                key={r.id}
                reference={r}
                first={i === 0}
                onRemove={() => removeRef.mutate(r.id)}
                removing={removeRef.isPending}
                open={openInsight === r.id}
                onToggle={() => setOpenInsight(openInsight === r.id ? null : r.id)}
                insightOn={insightOn}
                onExclude={() => excludeRef.mutate({ id: r.id, excluded: !r.excluded })}
              />
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

      {/* AI 가 기억한 것 — 완성본에서 찾은 것은 확인해야 쓰이고, 사용자가 보고 고치고 지운다 (기획안 §12) */}
      <div className="flex flex-col gap-[9px] pt-3" data-testid="memory-section">
        <SectionTitle>{copy.settings.memoryLabel}</SectionTitle>
        <p className="text-12 text-text-3">{aiOn || memory.length ? copy.settings.memoryIntro : copy.settings.memoryOff}</p>
        {proposed.length > 0 && (
          <div className="flex flex-col gap-[7px]" data-testid="memory-proposed">
            <div className="flex items-baseline justify-between gap-2">
              <span className="text-13 font-medium">{copy.settings.memoryProposedLabel(proposed.length)}</span>
              <button type="button" onClick={() => approveMemory.mutate(undefined)} disabled={approveMemory.isPending} className="text-13 text-accent hover:text-accent-hover" data-testid="memory-approve-all">
                {copy.settings.memoryApproveAll}
              </button>
            </div>
            <Card testId="memory-proposed-list">
              {proposed.map((m, i) => (
                <MemoryRow
                  key={m.id}
                  item={m}
                  first={i === 0}
                  onRemove={() => removeMemory.mutate(m.id)}
                  removing={removeMemory.isPending}
                  onApprove={() => approveMemory.mutate([m.id])}
                  approving={approveMemory.isPending}
                />
              ))}
            </Card>
            <p className="text-12 text-text-3">{copy.settings.memoryProposedHelp}</p>
          </div>
        )}
        <Card testId="memory-list">
          {approved.length === 0 && (
            <CardRow first>
              <span className="text-13 text-text-3">{copy.settings.memoryEmpty}</span>
            </CardRow>
          )}
          {approved.map((m, i) => (
            <MemoryRow key={m.id} item={m} first={i === 0} onRemove={() => removeMemory.mutate(m.id)} removing={removeMemory.isPending} onEdit={(text) => editMemory.mutate({ id: m.id, text })} />
          ))}
        </Card>
        <form
          className="flex gap-2"
          data-testid="memory-form"
          onSubmit={(e) => {
            e.preventDefault();
            if (memoryDraft.trim().length < 2 || addMemory.isPending) return;
            addMemory.mutate(memoryDraft.trim());
          }}
        >
          <input
            data-testid="memory-input"
            className="min-w-0 flex-1 rounded-thumb border border-input bg-surface px-3 py-[9px] text-14 outline-none placeholder:text-text-3 focus:border-accent"
            value={memoryDraft}
            maxLength={300}
            placeholder={copy.settings.memoryAddPlaceholder}
            onChange={(e) => setMemoryDraft(e.target.value)}
          />
          <button type="submit" disabled={memoryDraft.trim().length < 2 || addMemory.isPending} className="rounded-thumb border border-line px-3.5 text-13 font-medium hover:bg-hover disabled:text-text-3" data-testid="memory-add">
            {copy.settings.memoryAdd}
          </button>
        </form>
        {memory.length > 0 &&
          (clearing ? (
            <div className="flex flex-wrap items-center gap-3 text-13" data-testid="memory-clear-confirm">
              <span className="text-text-2">{copy.settings.memoryClearConfirm}</span>
              <button type="button" onClick={() => clearMemory.mutate()} disabled={clearMemory.isPending} className="font-medium text-accent hover:text-accent-hover" data-testid="memory-clear-yes">
                {copy.settings.memoryClearYes}
              </button>
              <button type="button" onClick={() => setClearing(false)} className="text-text-2 hover:text-accent">
                {copy.settings.memoryClearNo}
              </button>
            </div>
          ) : (
            <button type="button" onClick={() => setClearing(true)} className="self-start text-13 text-text-2 hover:text-accent" data-testid="memory-clear">
              {copy.settings.memoryClearAll}
            </button>
          ))}
      </div>
    </section>
  );
}

/** 폴더 완성본 한 줄: 제목 · 상태 · 메모 펼치기 · 학습에서 빼기. */
function ReferenceRow({
  reference: r,
  first,
  open,
  onToggle,
  insightOn,
  onExclude,
}: {
  reference: Reference;
  first: boolean;
  open: boolean;
  onToggle(): void;
  insightOn: boolean;
  onExclude(): void;
}) {
  return (
    <>
      <CardRow first={first} testId="reference-row" data-excluded={r.excluded ? 'true' : 'false'}>
        <span className={`flex min-w-0 flex-1 flex-col gap-px ${r.excluded ? 'text-text-3' : ''}`}>
          <span className="truncate text-14 font-medium">{r.title}</span>
          <span className="truncate text-12 text-text-3">{r.excluded ? copy.settings.referenceExcluded : r.insight ? r.insight.purpose : insightOn && r.status === 'done' ? copy.settings.insightPending : ''}</span>
        </span>
        <Status on={r.status === 'done' && !r.excluded} busy={r.status === 'queued' || r.status === 'analyzing'} testId="reference-status">
          {r.excluded ? copy.settings.referenceExcluded : (copy.settings.linkStatus[r.status] ?? r.status)}
        </Status>
        {r.insight && !r.excluded && (
          <button type="button" onClick={onToggle} className="flex-none text-13 text-accent hover:text-accent-hover" data-testid="insight-toggle">
            {open ? copy.settings.insightClose : copy.settings.insightOpen}
          </button>
        )}
        <button type="button" onClick={onExclude} className="flex-none text-13 text-text-2 hover:text-accent" data-testid="reference-exclude">
          {r.excluded ? copy.settings.referenceInclude : copy.settings.referenceExclude}
        </button>
      </CardRow>
      {open && r.insight && !r.excluded && <InsightView insight={r.insight} />}
    </>
  );
}

/** 완성본 메모 — 취지 · 도입 · 구성 · 남긴 것 · 숏폼 후보 · 용어. */
function InsightView({ insight: i }: { insight: ReferenceInsight }) {
  const clock = (sec: number) => `${Math.floor(sec / 60)}:${String(Math.floor(sec % 60)).padStart(2, '0')}`;
  const row = (label: string, body: React.ReactNode) => (
    <div className="flex gap-3 text-13 leading-normal">
      <span className="w-14 flex-none text-text-3">{label}</span>
      <span className="min-w-0 flex-1 text-text-2" style={{ textWrap: 'pretty' }}>
        {body}
      </span>
    </div>
  );
  return (
    <div className="flex flex-col gap-1.5 border-t border-line-faint bg-surface-2 px-3 py-2.5" data-testid="insight-view">
      {row(copy.settings.insightPurpose, i.purpose)}
      {i.hook && row(copy.settings.insightHook, i.hook)}
      {i.sections.length > 0 && row(copy.settings.insightSections, i.sections.map((s) => `${s.title} ${clock(s.start)}~${clock(s.end)}`).join(' → '))}
      {i.keepRanges.length > 0 && row(copy.settings.insightKeep, i.keepRanges.map((k) => `${clock(k.start)}~${clock(k.end)} ${k.why}`).join(' · '))}
      {i.shortCandidates.length > 0 && row(copy.settings.insightShorts, i.shortCandidates.map((k) => `${k.title} (${clock(k.start)}~${clock(k.end)}) — ${k.why}`).join(' · '))}
      {i.terms.length > 0 && row(copy.settings.insightTerms, i.terms.join(', '))}
      {i.titleNote && row(copy.settings.insightTitle, i.titleNote)}
    </div>
  );
}

/** 기억 한 줄: 종류 · 글(고치기) · 범위 · 출처 · (제안이면 쓰기) · 빼기. */
function MemoryRow({
  item: m,
  first,
  onRemove,
  removing,
  onApprove,
  approving = false,
  onEdit,
}: {
  item: MemoryItem;
  first: boolean;
  onRemove(): void;
  removing: boolean;
  onApprove?: (() => void) | undefined;
  approving?: boolean;
  onEdit?: ((text: string) => void) | undefined;
}) {
  const [editing, setEditing] = useState(false);
  const [text, setText] = useState(m.text);
  const scope = m.scope === 'topic' ? m.topics.join(', ') : copy.settings.memoryScope[m.scope];
  const save = () => {
    const t = text.trim();
    setEditing(false);
    if (t.length >= 2 && t !== m.text && onEdit) onEdit(t);
    else setText(m.text);
  };
  return (
    <CardRow first={first} testId="memory-row" data-kind={m.kind} data-scope={m.scope} data-status={m.status}>
      <span className="flex-none rounded-pill bg-accent-soft px-2 py-0.5 text-11 font-medium text-accent">{copy.settings.memoryKind[m.kind]}</span>
      <span className="flex min-w-0 flex-1 flex-col gap-px">
        {editing ? (
          <input
            autoFocus
            data-testid="memory-edit-input"
            className="min-w-0 rounded-thumb border border-input bg-surface px-2 py-1 text-13 outline-none focus:border-accent pc:text-14"
            value={text}
            maxLength={300}
            onChange={(e) => setText(e.target.value)}
            onBlur={save}
            onKeyDown={(e) => {
              if (e.key === 'Enter') save();
              if (e.key === 'Escape') {
                setText(m.text);
                setEditing(false);
              }
            }}
          />
        ) : (
          <span className="text-13 leading-normal pc:text-14" style={{ textWrap: 'pretty' }}>
            {m.text}
          </span>
        )}
        <span className="text-12 text-text-3">
          {scope} · {copy.settings.memorySource[m.source]}
        </span>
      </span>
      {onApprove && (
        <button type="button" onClick={onApprove} disabled={approving} className="flex-none text-13 font-medium text-accent hover:text-accent-hover" data-testid="memory-approve">
          {copy.settings.memoryApprove}
        </button>
      )}
      {onEdit && !editing && (
        <button type="button" onClick={() => setEditing(true)} className="flex-none text-13 text-text-2 hover:text-accent" data-testid="memory-edit">
          {copy.settings.memoryEdit}
        </button>
      )}
      <button type="button" onClick={onRemove} disabled={removing} className="flex-none text-13 text-text-2 hover:text-accent" data-testid="memory-remove">
        {copy.settings.memoryRemove}
      </button>
    </CardRow>
  );
}

/** 링크 완성본 한 줄: 출처 · 제목 · 상태 점 · 빼기. 못 읽었으면 이유를 AI 말투로. */
function LinkRow({
  reference: r,
  first,
  onRemove,
  removing,
  open,
  onToggle,
  insightOn,
  onExclude,
}: {
  reference: Reference;
  first: boolean;
  onRemove(): void;
  removing: boolean;
  open: boolean;
  onToggle(): void;
  insightOn: boolean;
  onExclude(): void;
}) {
  const failedText = r.status === 'failed' ? (copy.settings.linkErrors[r.error ?? ''] ?? copy.settings.linkErrors['link_failed']) : null;
  const sub = r.excluded ? copy.settings.referenceExcluded : (failedText ?? (r.insight ? r.insight.purpose : insightOn && r.status === 'done' ? copy.settings.insightPending : r.url));
  return (
    <>
      <CardRow first={first} testId="link-row" data-excluded={r.excluded ? 'true' : 'false'}>
        <span className={`flex min-w-0 flex-1 flex-col gap-px ${r.excluded ? 'text-text-3' : ''}`}>
          <span className="truncate text-14 font-medium">
            <span className="text-text-3">{linkSiteLabel(r.url ?? '')} · </span>
            {r.title}
          </span>
          <span className="truncate text-12 text-text-3">{sub}</span>
        </span>
        <Status on={r.status === 'done' && !r.excluded} busy={r.status === 'queued' || r.status === 'downloading' || r.status === 'analyzing'} testId="link-status">
          {r.excluded ? copy.settings.referenceExcluded : (copy.settings.linkStatus[r.status] ?? r.status)}
        </Status>
        {r.insight && !r.excluded && (
          <button type="button" onClick={onToggle} className="flex-none text-13 text-accent hover:text-accent-hover" data-testid="insight-toggle">
            {open ? copy.settings.insightClose : copy.settings.insightOpen}
          </button>
        )}
        {r.status === 'done' && (
          <button type="button" onClick={onExclude} className="flex-none text-13 text-text-2 hover:text-accent" data-testid="reference-exclude">
            {r.excluded ? copy.settings.referenceInclude : copy.settings.referenceExclude}
          </button>
        )}
        <button type="button" onClick={onRemove} disabled={removing} className="flex-none text-13 text-text-2 hover:text-accent" data-testid="link-remove">
          {copy.folders.remove}
        </button>
      </CardRow>
      {open && r.insight && !r.excluded && <InsightView insight={r.insight} />}
    </>
  );
}

function baseName(p: string): string {
  const parts = p.split(/[\\/]/).filter(Boolean);
  return parts[parts.length - 1] ?? p;
}
