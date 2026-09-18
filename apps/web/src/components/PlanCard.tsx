import type { EditPlan, TimeRange } from '@madi/shared';
import { copy } from '../copy.js';
import { formatDuration } from '../lib/format.js';

interface Props {
  plan: EditPlan;
  /** 숏폼 후보 → 바로 만들기. 바쁘면 undefined (버튼이 안 보인다). */
  onShort?: ((range: TimeRange, title: string) => void) | undefined;
  /** 편집안대로 롱폼 만들기 */
  onApply?: (() => void) | undefined;
}

/**
 * 편집안 카드 (기획안 §4 의 롱폼 편집안 표 + 숏폼 후보 표). 카드 틀은 챕터 카드와 같다 (1px 선, 8px).
 * 여기서는 아무것도 자동으로 만들지 않는다 — 사용자가 후보를 눌러야 렌더가 걸린다 (§6).
 */
export function PlanCard({ plan, onShort, onApply }: Props) {
  const c = copy.detail.planCard;
  const span = (r: { start: number; end: number }) => `${formatDuration(r.start)}–${formatDuration(r.end)}`;
  return (
    <div className="flex w-full flex-col overflow-hidden rounded-thumb border border-line" data-testid="plan-card">
      <div className="flex flex-col gap-1 px-3 pt-2.5 pb-2">
        <span className="text-13 font-medium pc:text-14">{c.title}</span>
        <Line label={c.purpose}>{plan.purpose}</Line>
        {plan.hook && <Line label={c.hook}>{plan.hook}</Line>}
        {!plan.fromTranscript && <span className="text-12 text-text-3">{c.noTranscript}</span>}
      </div>

      {plan.sections.length > 0 && (
        <div className="border-t border-line-soft" data-testid="plan-sections">
          <div className="px-3 pt-2 pb-1 text-12 text-text-3">{c.sections}</div>
          {plan.sections.map((s, i) => (
            <div key={i} className="flex items-start gap-2.5 px-3 py-[7px] pc:gap-3" data-testid="plan-section">
              <span className="w-[86px] flex-none text-11 text-text-3 pc:text-12">{span(s)}</span>
              <span className="flex min-w-0 flex-1 flex-col gap-px">
                <span className="text-13 font-medium pc:text-14">
                  {s.title}
                  {c.sectionKind[s.kind] && c.sectionKind[s.kind] !== s.title ? <span className="ml-1.5 text-11 font-normal text-text-3">{c.sectionKind[s.kind]}</span> : null}
                </span>
                {s.note && <span className="text-12 text-text-2">{s.note}</span>}
              </span>
            </div>
          ))}
        </div>
      )}

      {plan.keepRanges.length > 0 && (
        <div className="border-t border-line-soft px-3 py-2" data-testid="plan-keeps">
          <div className="pb-1 text-12 text-text-3">{c.keeps}</div>
          {plan.keepRanges.map((k, i) => (
            <div key={i} className="flex gap-2.5 py-[3px] text-12 pc:gap-3 pc:text-13">
              <span className="w-[86px] flex-none text-text-3">{span(k)}</span>
              <span className="min-w-0 flex-1 text-text-2">{k.why}</span>
            </div>
          ))}
        </div>
      )}

      {plan.cutCandidates.length > 0 && (
        <div className="border-t border-line-soft px-3 py-2" data-testid="plan-cuts">
          <div className="pb-1 text-12 text-text-3">{c.cuts}</div>
          {plan.cutCandidates.map((k, i) => (
            <div key={i} className="flex gap-2.5 py-[3px] text-12 pc:gap-3 pc:text-13">
              <span className="w-[86px] flex-none text-text-3">{span(k)}</span>
              <span className="min-w-0 flex-1 text-text-2">
                {c.cutKind[k.kind] ? <span className="mr-1.5 rounded-pill bg-track px-1.5 py-px text-11 text-text-2">{c.cutKind[k.kind]}</span> : null}
                {k.why}
              </span>
            </div>
          ))}
        </div>
      )}

      {plan.shortCandidates.length > 0 && (
        <div className="border-t border-line-soft" data-testid="plan-shorts">
          <div className="px-3 pt-2 pb-1 text-12 text-text-3">{c.shorts}</div>
          {plan.shortCandidates.map((s, i) => (
            <div key={i} className="flex items-center gap-2.5 px-3 py-[7px] pc:gap-3 pc:hover:bg-surface-2" data-testid="plan-short">
              <span className="flex min-w-0 flex-1 flex-col gap-px">
                <span className="text-13 font-medium pc:text-14">
                  {s.title}
                  {c.channel[s.channel] ? <span className="ml-1.5 text-11 font-normal text-text-3">{c.channel[s.channel]}</span> : null}
                </span>
                <span className="text-12 text-text-2">
                  {span(s)} · {s.why}
                </span>
              </span>
              {onShort && (
                <button type="button" onClick={() => onShort({ start: s.start, end: s.end }, s.title)} className="flex-none text-12 text-accent pc:text-13" data-testid="plan-short-make">
                  {c.makeShort}
                </button>
              )}
            </div>
          ))}
        </div>
      )}

      {plan.terms.length > 0 && (
        <div className="border-t border-line-soft px-3 py-2 text-12 text-text-3">
          {c.terms}: {plan.terms.join(', ')}
        </div>
      )}

      {onApply && (
        <button type="button" onClick={onApply} className="flex min-h-11 items-center border-t border-line-soft px-3 text-left text-13 font-medium text-accent hover:bg-surface-2" data-testid="plan-apply">
          {c.apply(plan.cutCandidates.length)}
        </button>
      )}
    </div>
  );
}

function Line({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex gap-2.5 text-13 leading-normal">
      <span className="w-8 flex-none text-text-3">{label}</span>
      <span className="min-w-0 flex-1 text-text-2" style={{ textWrap: 'pretty' }}>
        {children}
      </span>
    </div>
  );
}
