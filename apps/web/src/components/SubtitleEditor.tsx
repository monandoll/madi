import { useState } from 'react';
import type { Segment } from '@madi/shared';
import { copy } from '../copy.js';
import { formatClock, parseClock } from '../lib/format.js';

export interface SubtitleLineDraft {
  key: string;
  start: string;
  end: string;
  text: string;
}

interface Props {
  segments: Segment[];
  durationSec: number;
  saving: boolean;
  onSave(lines: { start: number; end: number; text: string }[]): void;
  onCancel(): void;
}

/**
 * 자막 직접 쓰기/고치기 (AI 없이도). 줄마다 시작·끝·글. 소리가 없는 영상에도 원하는 자리에 자막을 단다.
 * 저장하면 자막이 통째로 바뀌고 바로 "자막 넣기"가 돌아 결과물이 만들어진다.
 */
export function SubtitleEditor({ segments, durationSec, saving, onSave, onCancel }: Props) {
  const [lines, setLines] = useState<SubtitleLineDraft[]>(() =>
    segments.length
      ? segments.map((s, i) => ({ key: `${i}`, start: formatClock(s.start), end: formatClock(s.end), text: s.text }))
      : [{ key: '0', start: formatClock(0), end: formatClock(Math.min(3, durationSec || 3)), text: '' }],
  );
  const [error, setError] = useState<string | null>(null);
  const patch = (key: string, p: Partial<SubtitleLineDraft>) => setLines((ls) => ls.map((l) => (l.key === key ? { ...l, ...p } : l)));
  const add = () => {
    const last = lines[lines.length - 1];
    const from = last ? (parseClock(last.end) ?? 0) : 0;
    const to = Math.min(durationSec || from + 3, from + 3);
    setLines((ls) => [...ls, { key: `${Date.now()}`, start: formatClock(from), end: formatClock(to > from ? to : from + 3), text: '' }]);
  };
  const remove = (key: string) => setLines((ls) => ls.filter((l) => l.key !== key));

  const submit = () => {
    const out: { start: number; end: number; text: string }[] = [];
    for (const l of lines) {
      const text = l.text.trim();
      if (!text) continue;
      const start = parseClock(l.start);
      const end = parseClock(l.end);
      if (start === null || end === null) {
        setError(copy.subtitleEditor.badTime);
        return;
      }
      if (end <= start) {
        setError(copy.subtitleEditor.badRange);
        return;
      }
      out.push({ start, end, text });
    }
    if (out.length === 0) {
      setError(copy.subtitleEditor.empty);
      return;
    }
    setError(null);
    onSave(out);
  };

  return (
    <div className="mb-1.5 flex flex-col gap-2 rounded-panel border border-line bg-surface p-3" data-testid="subtitle-editor">
      <div className="flex items-baseline justify-between gap-2">
        <span className="text-14 font-semibold">{copy.subtitleEditor.title}</span>
        <span className="text-12 text-text-3">{copy.subtitleEditor.hint}</span>
      </div>
      <div className="flex flex-col gap-1.5">
        {lines.map((l) => (
          <div key={l.key} className="flex items-center gap-1.5" data-testid="subtitle-editor-row">
            <input
              value={l.start}
              onChange={(e) => patch(l.key, { start: e.target.value })}
              inputMode="decimal"
              aria-label={copy.subtitleEditor.start}
              className="w-[58px] flex-none rounded-thumb border border-input bg-surface px-2 py-[7px] text-center text-13 outline-none focus:border-accent"
              data-testid="subtitle-editor-start"
            />
            <span className="text-12 text-text-3">–</span>
            <input
              value={l.end}
              onChange={(e) => patch(l.key, { end: e.target.value })}
              inputMode="decimal"
              aria-label={copy.subtitleEditor.end}
              className="w-[58px] flex-none rounded-thumb border border-input bg-surface px-2 py-[7px] text-center text-13 outline-none focus:border-accent"
              data-testid="subtitle-editor-end"
            />
            <input
              value={l.text}
              onChange={(e) => patch(l.key, { text: e.target.value })}
              placeholder={copy.subtitleEditor.placeholder}
              maxLength={200}
              aria-label={copy.subtitleEditor.text}
              className="min-w-0 flex-1 rounded-thumb border border-input bg-surface px-3 py-[7px] text-14 outline-none placeholder:text-text-3 focus:border-accent"
              data-testid="subtitle-editor-text"
            />
            <button type="button" onClick={() => remove(l.key)} aria-label={copy.subtitleEditor.remove} className="flex-none px-1 text-13 text-text-3 hover:text-accent">
              ×
            </button>
          </div>
        ))}
      </div>
      <button type="button" onClick={add} className="self-start text-13 font-medium text-accent hover:text-accent-hover" data-testid="subtitle-editor-add">
        {copy.subtitleEditor.add}
      </button>
      {error && <p className="text-12 text-error">{error}</p>}
      <div className="flex items-center justify-end gap-2 pt-1">
        <button type="button" onClick={onCancel} disabled={saving} className="rounded-thumb px-3 py-2 text-13 text-text-2 hover:bg-hover">
          {copy.subtitleEditor.cancel}
        </button>
        <button type="button" onClick={submit} disabled={saving} className="rounded-thumb bg-accent px-3.5 py-2 text-13 font-semibold text-white hover:bg-accent-hover disabled:opacity-60" data-testid="subtitle-editor-save">
          {copy.subtitleEditor.save}
        </button>
      </div>
    </div>
  );
}
