import { PlanRecipe, type EditPlan, type TimeRange } from '@madi/shared';

/** 타입·시각·보존 범위를 확인한다. 잘못된 실행 제안은 저장하지 않는다. */
export function parseRecipe(raw: unknown, duration: number, keeps: TimeRange[]): PlanRecipe | null {
  if (raw === undefined || raw === null) return null;
  const parsed = PlanRecipe.safeParse(raw);
  if (!parsed.success) return null;
  const r = parsed.data;
  if ([...r.parts, ...r.captions].some((p) => p.end > duration || p.end <= p.start)) return null;
  if (r.parts.some((p) => p.end - p.start < 0.3)) return null;
  if (r.parts.length) {
    const sorted = [...r.parts].sort((a, b) => a.start - b.start);
    if (sorted.some((p, i) => i > 0 && p.start < sorted[i - 1]!.end - 0.01)) return null;
    for (const k of keeps) {
      let cursor = k.start;
      for (const p of sorted) { if (p.start <= cursor + 0.01 && p.end > cursor) cursor = p.end; }
      if (cursor < k.end - 0.01) return null;
    }
  }
  return r;
}

export function recipeForRange(plan: EditPlan, range?: TimeRange): PlanRecipe | null {
  if (!plan.recipe) return null;
  return { ...plan.recipe, parts: range ? [] : plan.recipe.parts, captions: plan.recipe.captions.flatMap((c) => {
    if (!range) return [c];
    const start = Math.max(c.start, range.start), end = Math.min(c.end, range.end);
    return end > start ? [{ ...c, start, end }] : [];
  }) };
}
