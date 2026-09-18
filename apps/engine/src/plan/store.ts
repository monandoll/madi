import { eq } from 'drizzle-orm';
import { EditPlan } from '@madi/shared';
import type { Db } from '../db/index.js';
import { plans } from '../db/schema.js';

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
}
