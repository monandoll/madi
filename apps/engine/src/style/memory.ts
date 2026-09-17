import { EventEmitter } from 'node:events';
import { asc, eq } from 'drizzle-orm';
import { nanoid } from 'nanoid';
import { MemoryItem, type MemoryKind, type MemoryScope, type MemorySource } from '@madi/shared';
import type { Db } from '../db/index.js';
import { memory } from '../db/schema.js';

export interface MemoryEvents {
  'memory.updated': [];
}

type Row = typeof memory.$inferSelect;

/**
 * 제작자 기억. 세 출처가 한 목록에 섞여 있고 사용자가 설정에서 보고 지운다.
 * - reference: 완성본들에서 AI 가 추린 것. 다시 배우면 통째로 바뀐다 (사용자가 지운 것도 다시 생길 수 있다 — 근거가 남아 있으니).
 * - feedback: 편집 중 "앞으로도 이렇게" 한 것. 범위(all · topic · video)가 있다.
 * - user: 직접 쓴 것.
 */
export class MemoryStore extends EventEmitter<MemoryEvents> {
  constructor(private readonly db: Db) {
    super();
  }

  list(): MemoryItem[] {
    return this.db.select().from(memory).orderBy(asc(memory.createdAt)).all().map(toItem);
  }

  add(input: { text: string; kind: MemoryKind; scope: MemoryScope; topics?: string[]; videoId?: string | null; source: MemorySource; evidence?: string[] }): MemoryItem {
    const row: Row = {
      id: nanoid(),
      text: input.text.trim(),
      kind: input.kind,
      scope: input.scope,
      topics: input.topics ?? [],
      videoId: input.scope === 'video' ? (input.videoId ?? null) : null,
      source: input.source,
      evidence: input.evidence ?? [],
      createdAt: Date.now(),
    };
    // 같은 글이 같은 범위로 이미 있으면 다시 넣지 않는다
    const dup = this.list().find((m) => m.text === row.text && m.scope === row.scope && m.videoId === row.videoId);
    if (dup) return dup;
    this.db.insert(memory).values(row).run();
    this.emit('memory.updated');
    return toItem(row);
  }

  remove(id: string): boolean {
    const r = this.db.delete(memory).where(eq(memory.id, id)).run();
    if (r.changes > 0) this.emit('memory.updated');
    return r.changes > 0;
  }

  /** 완성본에서 추린 것을 통째로 바꾼다. feedback · user 는 그대로. */
  replaceFromReferences(items: Omit<Parameters<MemoryStore['add']>[0], 'source'>[]): void {
    this.db.delete(memory).where(eq(memory.source, 'reference')).run();
    for (const it of items) {
      const row: Row = {
        id: nanoid(),
        text: it.text.trim(),
        kind: it.kind,
        scope: it.scope,
        topics: it.topics ?? [],
        videoId: null,
        source: 'reference',
        evidence: it.evidence ?? [],
        createdAt: Date.now(),
      };
      this.db.insert(memory).values(row).run();
    }
    this.emit('memory.updated');
  }
}

function toItem(row: Row): MemoryItem {
  return MemoryItem.parse({ ...row, topics: row.topics ?? [], evidence: row.evidence ?? [] });
}
