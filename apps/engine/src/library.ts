import { EventEmitter } from 'node:events';
import { and, asc, desc, eq, isNotNull, sql } from 'drizzle-orm';
import { nanoid } from 'nanoid';
import type { z } from 'zod';
import { ChatMessage, Edit, Output, Transcript, type Segment } from '@madi/shared';
import type { Db } from './db/index.js';
import { edits, messages, outputs, transcripts } from './db/schema.js';

export interface LibraryEvents {
  'message.added': [ChatMessage];
  'message.updated': [ChatMessage];
  'output.added': [Output];
}

/** parts · cropFocus · subtitleAuto 는 안 주면 기본값 (zod default). */
type EditInsert = Omit<z.input<typeof Edit>, 'id' | 'createdAt'>;
type OutputInsert = Omit<Output, 'id' | 'createdAt'>;
type MessageInsert = Pick<ChatMessage, 'videoId' | 'role' | 'kind' | 'code'> &
  Partial<Pick<ChatMessage, 'params' | 'jobId' | 'outputId'>>;

/** 자막·편집·결과물·대화. 영상 하나에 매달린 것들. */
export class Library extends EventEmitter<LibraryEvents> {
  constructor(private readonly db: Db) {
    super();
  }

  // ---- transcripts ----
  transcriptOf(videoId: string): Transcript | null {
    const row = this.db.select().from(transcripts).where(eq(transcripts.videoId, videoId)).get();
    return row ? Transcript.parse(row) : null;
  }

  transcript(id: string): Transcript | null {
    const row = this.db.select().from(transcripts).where(eq(transcripts.id, id)).get();
    return row ? Transcript.parse(row) : null;
  }

  /** 영상당 하나. 다시 만들면 덮어쓴다. */
  setTranscript(videoId: string, t: { language: string; model: string; segments: Segment[] }): Transcript {
    const existing = this.transcriptOf(videoId);
    const id = existing?.id ?? nanoid();
    const row = { id, videoId, ...t, createdAt: Date.now() };
    this.db
      .insert(transcripts)
      .values(row)
      .onConflictDoUpdate({ target: transcripts.videoId, set: { language: t.language, model: t.model, segments: t.segments, createdAt: row.createdAt } })
      .run();
    return Transcript.parse(row);
  }

  // ---- edits ----
  createEdit(e: EditInsert): Edit {
    const row = Edit.parse({ ...e, id: nanoid(), createdAt: Date.now() });
    this.db.insert(edits).values(row).run();
    return row;
  }

  /** 수동 숏폼(구간을 정한 편집) 개수. 제목의 번호에 쓴다. */
  shortEditCount(videoId: string): number {
    const row = this.db
      .select({ n: sql<number>`count(*)` })
      .from(edits)
      .where(and(eq(edits.videoId, videoId), isNotNull(edits.keep)))
      .get();
    return row?.n ?? 0;
  }

  edit(id: string): Edit | null {
    const row = this.db.select().from(edits).where(eq(edits.id, id)).get();
    return row ? Edit.parse(row) : null;
  }

  updateEdit(id: string, patch: Partial<EditInsert>): Edit {
    this.db.update(edits).set(patch).where(eq(edits.id, id)).run();
    const e = this.edit(id);
    if (!e) throw new Error(`edit not found: ${id}`);
    return e;
  }

  // ---- outputs ----
  /** id 를 미리 정해 파일 이름과 맞출 수 있다. */
  addOutput(o: OutputInsert, id: string = nanoid()): Output {
    const row = { ...o, id, createdAt: Date.now() };
    this.db.insert(outputs).values(row).run();
    const out = Output.parse(row);
    this.emit('output.added', out);
    return out;
  }

  output(id: string): Output | null {
    const row = this.db.select().from(outputs).where(eq(outputs.id, id)).get();
    return row ? Output.parse(row) : null;
  }

  /** 이 편집으로 만든 결과물들 (최근 것부터). */
  outputsForEdit(editId: string): Output[] {
    return this.db.select().from(outputs).where(eq(outputs.editId, editId)).orderBy(desc(outputs.createdAt)).all().map((r) => Output.parse(r));
  }

  outputsOf(videoId: string): Output[] {
    return this.db.select().from(outputs).where(eq(outputs.videoId, videoId)).orderBy(desc(outputs.createdAt)).all().map((r) => Output.parse(r));
  }

  allOutputs(): Output[] {
    return this.db.select().from(outputs).orderBy(desc(outputs.createdAt)).all().map((r) => Output.parse(r));
  }

  outputCount(videoId: string): number {
    return this.outputsOf(videoId).length;
  }

  // ---- messages ----
  say(m: MessageInsert): ChatMessage {
    const now = Date.now();
    const row: ChatMessage = {
      id: nanoid(),
      videoId: m.videoId,
      role: m.role,
      kind: m.kind,
      code: m.code,
      params: m.params ?? {},
      jobId: m.jobId ?? null,
      outputId: m.outputId ?? null,
      createdAt: now,
      updatedAt: now,
    };
    this.db.insert(messages).values(row).run();
    this.emit('message.added', row);
    return row;
  }

  updateMessage(id: string, patch: Partial<Pick<ChatMessage, 'kind' | 'code' | 'params' | 'outputId' | 'jobId'>>): ChatMessage {
    this.db
      .update(messages)
      .set({ ...patch, updatedAt: Date.now() })
      .where(eq(messages.id, id))
      .run();
    const row = this.db.select().from(messages).where(eq(messages.id, id)).get();
    if (!row) throw new Error(`message not found: ${id}`);
    const msg = ChatMessage.parse(row);
    this.emit('message.updated', msg);
    return msg;
  }

  messageForJob(jobId: string): ChatMessage | null {
    const row = this.db.select().from(messages).where(eq(messages.jobId, jobId)).get();
    return row ? ChatMessage.parse(row) : null;
  }

  messagesOf(videoId: string): ChatMessage[] {
    return this.db.select().from(messages).where(eq(messages.videoId, videoId)).orderBy(asc(messages.createdAt)).all().map((r) => ChatMessage.parse(r));
  }
}
