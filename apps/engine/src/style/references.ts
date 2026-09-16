import fs from 'node:fs';
import path from 'node:path';
import { EventEmitter } from 'node:events';
import { asc, eq } from 'drizzle-orm';
import { nanoid } from 'nanoid';
import { linkSiteLabel, Reference, type ReferenceStats, type ReferenceStatus, type Segment, titleFromFileName } from '@madi/shared';
import type { Db } from '../db/index.js';
import { references } from '../db/schema.js';

export interface ReferenceEvents {
  'reference.updated': [Reference];
}

type Row = typeof references.$inferSelect;

/** 완성본 목록. 갤러리의 videos 와 분리 — 편집 대상이 아니라 배우는 대상. */
export class ReferenceStore extends EventEmitter<ReferenceEvents> {
  constructor(private readonly db: Db) {
    super();
  }

  list(): Reference[] {
    return this.db.select().from(references).orderBy(asc(references.fileName)).all().map(toRef);
  }

  get(id: string): Reference | null {
    const row = this.db.select().from(references).where(eq(references.id, id)).get();
    return row ? toRef(row) : null;
  }

  getByPath(p: string): Reference | null {
    const row = this.db.select().from(references).where(eq(references.path, p)).get();
    return row ? toRef(row) : null;
  }

  getByUrl(url: string): Reference | null {
    const row = this.db.select().from(references).where(eq(references.url, url)).get();
    return row ? toRef(row) : null;
  }

  segmentsOf(id: string): Segment[] | null {
    const row = this.db.select({ segments: references.segments }).from(references).where(eq(references.id, id)).get();
    return (row?.segments as Segment[] | null) ?? null;
  }

  /**
   * 파일 하나 등록. 이미 있으면 크기가 바뀌었을 때만 다시 분석 대상으로 돌린다.
   * 돌려주는 값의 changed 가 true 면 analyze 잡을 걸어야 한다.
   */
  upsertFromFile(p: string): { ref: Reference; changed: boolean } {
    const abs = path.resolve(p);
    const size = fs.statSync(abs).size;
    const existing = this.getByPath(abs);
    const now = Date.now();
    if (existing) {
      const needs = existing.sizeBytes !== size || existing.status === 'missing';
      if (!needs) return { ref: existing, changed: false };
      const ref = this.update(existing.id, { sizeBytes: size, status: 'queued', stats: null, segments: null, error: null });
      return { ref, changed: true };
    }
    const fileName = path.basename(abs);
    const row: Row = {
      id: nanoid(),
      path: abs,
      fileName,
      title: titleFromFileName(fileName),
      sizeBytes: size,
      status: 'queued',
      source: 'folder',
      url: null,
      stats: null,
      segments: null,
      error: null,
      createdAt: now,
      updatedAt: now,
    };
    this.db.insert(references).values(row).run();
    const ref = toRef(row);
    this.emit('reference.updated', ref);
    return { ref, changed: true };
  }

  /**
   * 링크 하나 등록. 파일은 아직 없다 — download 잡이 dir/<id>.mp4 로 받은 뒤 채운다.
   * 같은 링크가 이미 있으면 그것을 돌려주고(changed=false), 실패했던 것이면 다시 받게 돌린다(changed=true).
   */
  upsertFromLink(url: string, dir: string): { ref: Reference; changed: boolean } {
    const existing = this.getByUrl(url);
    if (existing) {
      if (existing.status !== 'failed' && existing.status !== 'missing') return { ref: existing, changed: false };
      const ref = this.update(existing.id, { status: 'queued', stats: null, segments: null, error: null });
      return { ref, changed: true };
    }
    const id = nanoid();
    const fileName = `${id}.mp4`;
    const now = Date.now();
    const row: Row = {
      id,
      path: path.join(dir, fileName),
      fileName,
      title: `${linkSiteLabel(url)} 영상`,
      sizeBytes: 0,
      status: 'queued',
      source: 'link',
      url,
      stats: null,
      segments: null,
      error: null,
      createdAt: now,
      updatedAt: now,
    };
    this.db.insert(references).values(row).run();
    const ref = toRef(row);
    this.emit('reference.updated', ref);
    return { ref, changed: true };
  }

  /** 링크 완성본을 지운다 (받은 파일도). 폴더 완성본은 폴더에서 빼는 것이라 여기서 안 지운다. */
  remove(id: string): Reference | null {
    const ref = this.get(id);
    if (!ref) return null;
    this.db.delete(references).where(eq(references.id, id)).run();
    if (ref.source === 'link') fs.rmSync(ref.path, { force: true });
    return ref;
  }

  update(
    id: string,
    patch: Partial<{ path: string; fileName: string; title: string; sizeBytes: number; status: ReferenceStatus; stats: ReferenceStats | null; segments: Segment[] | null; error: string | null }>,
  ): Reference {
    this.db
      .update(references)
      .set({ ...patch, updatedAt: Date.now() })
      .where(eq(references.id, id))
      .run();
    const ref = this.get(id);
    if (!ref) throw new Error(`reference not found: ${id}`);
    this.emit('reference.updated', ref);
    return ref;
  }

  /** 지금 폴더에 없는 것은 missing. 폴더에 다시 나타나면 upsert 가 되살린다. 링크 완성본은 폴더와 무관하니 건드리지 않는다. */
  markMissingExcept(presentPaths: Set<string>): void {
    for (const r of this.list()) {
      if (r.source === 'link') continue;
      if (!presentPaths.has(r.path) && r.status !== 'missing') this.update(r.id, { status: 'missing' });
    }
  }
}

function toRef(row: Row): Reference {
  return Reference.parse({ ...row, stats: row.stats ?? null });
}
