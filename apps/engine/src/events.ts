import type { Db } from './db/index.js';
import { events } from './db/schema.js';

/** 사용 이벤트 기록. 로컬 SQLite에만 남는다. */
export class EventLog {
  constructor(private readonly db: Db) {}

  record(name: string, props?: Record<string, unknown>, durationMs?: number): void {
    this.db
      .insert(events)
      .values({ name, props: props ?? null, durationMs: durationMs ?? null, createdAt: Date.now() })
      .run();
  }
}
