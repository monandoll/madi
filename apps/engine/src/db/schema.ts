import { index, integer, real, sqliteTable, text, uniqueIndex } from 'drizzle-orm/sqlite-core';

export const videos = sqliteTable(
  'videos',
  {
    id: text('id').primaryKey(),
    path: text('path').notNull(),
    fileName: text('file_name').notNull(),
    title: text('title').notNull(),
    kind: text('kind', { enum: ['long', 'short'] }).notNull().default('long'),
    status: text('status', { enum: ['registered', 'preparing', 'ready', 'failed', 'missing'] })
      .notNull()
      .default('registered'),
    durationSec: real('duration_sec'),
    width: integer('width'),
    height: integer('height'),
    fps: real('fps'),
    hasAudio: integer('has_audio', { mode: 'boolean' }),
    sizeBytes: integer('size_bytes').notNull(),
    recordedAt: integer('recorded_at').notNull(),
    thumbnailPath: text('thumbnail_path'),
    error: text('error'),
    createdAt: integer('created_at').notNull(),
    updatedAt: integer('updated_at').notNull(),
  },
  (t) => [uniqueIndex('videos_path_idx').on(t.path), index('videos_recorded_idx').on(t.recordedAt)],
);

export const proxies = sqliteTable('proxies', {
  id: text('id').primaryKey(),
  videoId: text('video_id')
    .notNull()
    .references(() => videos.id, { onDelete: 'cascade' }),
  path: text('path').notNull(),
  width: integer('width').notNull(),
  height: integer('height').notNull(),
  createdAt: integer('created_at').notNull(),
});

export const jobs = sqliteTable(
  'jobs',
  {
    id: text('id').primaryKey(),
    type: text('type', { enum: ['probe', 'proxy', 'thumbnail', 'transcribe', 'render'] }).notNull(),
    status: text('status', { enum: ['queued', 'running', 'done', 'failed', 'canceled'] })
      .notNull()
      .default('queued'),
    progress: real('progress').notNull().default(0),
    videoId: text('video_id'),
    payload: text('payload', { mode: 'json' }).notNull(),
    error: text('error'),
    attempts: integer('attempts').notNull().default(0),
    createdAt: integer('created_at').notNull(),
    startedAt: integer('started_at'),
    finishedAt: integer('finished_at'),
  },
  (t) => [index('jobs_status_type_idx').on(t.status, t.type, t.createdAt), index('jobs_video_idx').on(t.videoId)],
);

/** 사용 이벤트. 외부 전송 없음. 판매 판단 근거. */
export const events = sqliteTable('events', {
  id: integer('id').primaryKey({ autoIncrement: true }),
  name: text('name').notNull(),
  props: text('props', { mode: 'json' }),
  durationMs: integer('duration_ms'),
  createdAt: integer('created_at').notNull(),
});

/** key-value. 'settings' 한 행에 Settings JSON. */
export const kv = sqliteTable('kv', {
  key: text('key').primaryKey(),
  value: text('value', { mode: 'json' }).notNull(),
  updatedAt: integer('updated_at').notNull(),
});
