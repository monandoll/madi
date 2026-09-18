import { EventEmitter } from 'node:events';
import { and, asc, eq, inArray } from 'drizzle-orm';
import { nanoid } from 'nanoid';
import { MemoryItem, type MemoryKind, type MemoryScope, type MemorySource, type MemoryStatus } from '@madi/shared';
import type { Db } from '../db/index.js';
import { kv, memory } from '../db/schema.js';

export interface MemoryEvents {
  'memory.updated': [];
}

type Row = typeof memory.$inferSelect;

/** 사용자가 뺀 완성본 기억 글. 다시 배워도 같은 글은 다시 제안하지 않는다. */
const DISMISSED_KEY = 'memory.dismissed';
const DISMISSED_MAX = 300;

/**
 * 제작자 기억. 세 출처가 한 목록에 섞여 있고 사용자가 설정에서 보고 고치고 지운다.
 * - reference: 완성본들에서 AI 가 추린 것. **제안(proposed)** 으로 들어오고 사용자가 확인해야 편집에 쓴다 (기획안 §12).
 *   다시 배우면 통째로 바뀌되, 이미 확인한 글은 확인 상태를 이어받고 사용자가 뺀 글은 다시 제안하지 않는다.
 * - feedback: 편집 중 "앞으로도 이렇게" 한 것 (사용자가 예라고 한 것이라 바로 approved). 범위(all · topic · video)가 있다.
 * - user: 직접 쓴 것 (approved).
 */
export class MemoryStore extends EventEmitter<MemoryEvents> {
  constructor(private readonly db: Db) {
    super();
  }

  list(): MemoryItem[] {
    return this.db.select().from(memory).orderBy(asc(memory.createdAt)).all().map(toItem);
  }

  /** 편집에 쓰는 것 — 사용자가 확인한 줄만. */
  listApproved(): MemoryItem[] {
    return this.list().filter((m) => m.status === 'approved');
  }

  get(id: string): MemoryItem | null {
    const row = this.db.select().from(memory).where(eq(memory.id, id)).get();
    return row ? toItem(row) : null;
  }

  add(input: { text: string; kind: MemoryKind; scope: MemoryScope; topics?: string[]; videoId?: string | null; source: MemorySource; status?: MemoryStatus; evidence?: string[] }): MemoryItem {
    const row: Row = {
      id: nanoid(),
      text: input.text.trim(),
      kind: input.kind,
      scope: input.scope,
      topics: input.topics ?? [],
      videoId: input.scope === 'video' ? (input.videoId ?? null) : null,
      source: input.source,
      status: input.status ?? 'approved',
      evidence: input.evidence ?? [],
      createdAt: Date.now(),
    };
    // 같은 글이 같은 범위로 이미 있으면 다시 넣지 않는다 (직접 쓴 글이 제안과 같으면 제안을 확인한 것으로 친다)
    const dup = this.list().find((m) => m.text === row.text && m.scope === row.scope && m.videoId === row.videoId);
    if (dup) {
      if (dup.status === 'proposed' && row.status === 'approved') this.approve([dup.id]);
      return this.get(dup.id) ?? dup;
    }
    this.db.insert(memory).values(row).run();
    this.emit('memory.updated');
    return toItem(row);
  }

  /** 제안 확인. ids 가 없으면 제안 전부. 돌려주는 값은 바뀐 줄 수. */
  approve(ids?: string[]): number {
    const targets = this.list().filter((m) => m.status === 'proposed' && (!ids || ids.includes(m.id)));
    if (targets.length === 0) return 0;
    this.db
      .update(memory)
      .set({ status: 'approved' })
      .where(
        inArray(
          memory.id,
          targets.map((m) => m.id),
        ),
      )
      .run();
    this.emit('memory.updated');
    return targets.length;
  }

  /** 글 고치기. 완성본에서 온 줄을 고치면 사용자가 손댄 것이니 확인한 것으로 본다. */
  updateText(id: string, text: string): MemoryItem | null {
    const cur = this.get(id);
    if (!cur) return null;
    this.db.update(memory).set({ text: text.trim(), status: 'approved' }).where(eq(memory.id, id)).run();
    this.emit('memory.updated');
    return this.get(id);
  }

  /** 한 줄 빼기. 완성본에서 온 글이면 다시 제안하지 않도록 기억해 둔다. */
  remove(id: string): boolean {
    const cur = this.get(id);
    if (!cur) return false;
    if (cur.source === 'reference') this.dismiss([cur.text]);
    this.db.delete(memory).where(eq(memory.id, id)).run();
    this.emit('memory.updated');
    return true;
  }

  /** 전부(또는 제안만) 지우기 — 기획안 §12 "특정 기억 또는 전체 기억 삭제". */
  removeAll(opts: { onlyProposed?: boolean } = {}): number {
    const rows = this.list().filter((m) => !opts.onlyProposed || m.status === 'proposed');
    if (rows.length === 0) return 0;
    this.dismiss(rows.filter((m) => m.source === 'reference').map((m) => m.text));
    if (opts.onlyProposed) this.db.delete(memory).where(and(eq(memory.status, 'proposed'))).run();
    else this.db.delete(memory).run();
    this.emit('memory.updated');
    return rows.length;
  }

  /**
   * 완성본에서 추린 것을 통째로 바꾼다. feedback · user 는 그대로.
   * 새 줄은 제안(proposed)으로 들어오되, 같은 글을 이미 확인했으면 approved 를 이어받고, 사용자가 뺀 글은 넣지 않는다.
   */
  replaceFromReferences(items: Omit<Parameters<MemoryStore['add']>[0], 'source' | 'status'>[]): void {
    const before = new Map(
      this.list()
        .filter((m) => m.source === 'reference')
        .map((m) => [m.text, m.status] as const),
    );
    const dismissed = new Set(this.dismissed());
    this.db.delete(memory).where(eq(memory.source, 'reference')).run();
    for (const it of items) {
      const text = it.text.trim();
      if (!text || dismissed.has(text)) continue;
      const row: Row = {
        id: nanoid(),
        text,
        kind: it.kind,
        scope: it.scope,
        topics: it.topics ?? [],
        videoId: null,
        source: 'reference',
        status: before.get(text) === 'approved' ? 'approved' : 'proposed',
        evidence: it.evidence ?? [],
        createdAt: Date.now(),
      };
      this.db.insert(memory).values(row).run();
    }
    this.emit('memory.updated');
  }

  /** 사용자가 뺀 완성본 기억 글 목록 (최근 것이 뒤). */
  dismissed(): string[] {
    const row = this.db.select().from(kv).where(eq(kv.key, DISMISSED_KEY)).get();
    const v = row?.value;
    return Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : [];
  }

  private dismiss(texts: string[]): void {
    const clean = texts.map((t) => t.trim()).filter(Boolean);
    if (clean.length === 0) return;
    const next = [...new Set([...this.dismissed(), ...clean])].slice(-DISMISSED_MAX);
    this.db
      .insert(kv)
      .values({ key: DISMISSED_KEY, value: next, updatedAt: Date.now() })
      .onConflictDoUpdate({ target: kv.key, set: { value: next, updatedAt: Date.now() } })
      .run();
  }
}

function toItem(row: Row): MemoryItem {
  return MemoryItem.parse({ ...row, topics: row.topics ?? [], evidence: row.evidence ?? [] });
}
