import { eq } from 'drizzle-orm';
import { EditPlan, type PlanFeedbackKind, type PlanVerdict } from '@madi/shared';
import type { Db } from '../db/index.js';
import { kv, plans } from '../db/schema.js';

const REJECT_KEY = 'plan.rejected';

/** 영상당 편집안 하나. 다시 만들면 덮어쓴다. */
export class PlanStore {
  constructor(private readonly db: Db) {}

  get(videoId: string): EditPlan | null {
    const row = this.db.select().from(plans).where(eq(plans.videoId, videoId)).get();
    if (!row) return null;
    const parsed = EditPlan.safeParse(row.plan);
    return parsed.success ? parsed.data : null;
  }

  set(plan: EditPlan): EditPlan {
    this.db
      .insert(plans)
      .values({ videoId: plan.videoId, plan, createdAt: plan.createdAt })
      .onConflictDoUpdate({ target: plans.videoId, set: { plan, createdAt: plan.createdAt } })
      .run();
    return plan;
  }

  remove(videoId: string): void {
    this.db.delete(plans).where(eq(plans.videoId, videoId)).run();
  }

  /**
   * 후보 하나에 판단을 남긴다 (같은 자리의 이전 판단은 덮는다). verdict 가 null 이면 지운다.
   * 편집안이 없거나 그 자리에 후보가 없으면 null.
   */
  setFeedback(videoId: string, fb: { kind: PlanFeedbackKind; index: number; verdict: PlanVerdict | null }): EditPlan | null {
    const plan = this.get(videoId);
    if (!plan) return null;
    const list = fb.kind === 'cut' ? plan.cutCandidates : plan.shortCandidates;
    if (fb.index >= list.length) return null;
    const rest = plan.feedback.filter((f) => !(f.kind === fb.kind && f.index === fb.index));
    const feedback = fb.verdict ? [...rest, { kind: fb.kind, index: fb.index, verdict: fb.verdict, at: Date.now() }] : rest;
    return this.set({ ...plan, feedback });
  }

  /** 잘라낼 후보를 종류별로 몇 번 뺐는지 (영상을 넘어 누적). 늘리고 새 값을 돌려준다. */
  bumpRejected(cutKind: string): number {
    const counts = this.rejectedCounts();
    const n = (counts[cutKind] ?? 0) + 1;
    const next = { ...counts, [cutKind]: n };
    this.db
      .insert(kv)
      .values({ key: REJECT_KEY, value: next, updatedAt: Date.now() })
      .onConflictDoUpdate({ target: kv.key, set: { value: next, updatedAt: Date.now() } })
      .run();
    return n;
  }

  rejectedCounts(): Record<string, number> {
    const row = this.db.select().from(kv).where(eq(kv.key, REJECT_KEY)).get();
    const v = row?.value;
    return v && typeof v === 'object' && !Array.isArray(v) ? (v as Record<string, number>) : {};
  }
}
