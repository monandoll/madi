import { eq } from 'drizzle-orm';
import { type Chapter, Chapters } from '@madi/shared';
import type { Db } from '../db/index.js';
import { chapters } from '../db/schema.js';

/** 영상당 챕터 하나. */
export class ChapterStore {
  constructor(private readonly db: Db) {}

  get(videoId: string): Chapters | null {
    const row = this.db.select().from(chapters).where(eq(chapters.videoId, videoId)).get();
    return row ? Chapters.parse(row) : null;
  }

  set(videoId: string, items: Chapter[], fromTranscript: boolean): Chapters {
    const row = { videoId, items, fromTranscript, createdAt: Date.now() };
    this.db
      .insert(chapters)
      .values(row)
      .onConflictDoUpdate({ target: chapters.videoId, set: { items, fromTranscript, createdAt: row.createdAt } })
      .run();
    return Chapters.parse(row);
  }
}
