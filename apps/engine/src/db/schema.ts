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
    type: text('type', { enum: ['probe', 'proxy', 'thumbnail', 'transcribe', 'silence', 'render', 'analyze', 'chapters'] }).notNull(),
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

/** whisper 결과. 영상당 하나. segments 는 JSON. */
export const transcripts = sqliteTable('transcripts', {
  id: text('id').primaryKey(),
  videoId: text('video_id')
    .notNull()
    .unique()
    .references(() => videos.id, { onDelete: 'cascade' }),
  language: text('language').notNull(),
  model: text('model').notNull(),
  segments: text('segments', { mode: 'json' }).notNull(),
  createdAt: integer('created_at').notNull(),
});

/** 편집 결정 목록. 결과물은 항상 여기서 재현된다. */
export const edits = sqliteTable('edits', {
  id: text('id').primaryKey(),
  videoId: text('video_id')
    .notNull()
    .references(() => videos.id, { onDelete: 'cascade' }),
  title: text('title').notNull(),
  keep: text('keep', { mode: 'json' }),
  cuts: text('cuts', { mode: 'json' }).notNull(),
  crop: text('crop', { enum: ['none', 'vertical'] }).notNull().default('none'),
  subtitles: integer('subtitles', { mode: 'boolean' }).notNull().default(false),
  transcriptId: text('transcript_id'),
  subtitleStyle: text('subtitle_style', { mode: 'json' }).notNull(),
  speed: text('speed', { mode: 'json' }).notNull(),
  createdAt: integer('created_at').notNull(),
});

export const outputs = sqliteTable(
  'outputs',
  {
    id: text('id').primaryKey(),
    videoId: text('video_id')
      .notNull()
      .references(() => videos.id, { onDelete: 'cascade' }),
    editId: text('edit_id')
      .notNull()
      .references(() => edits.id, { onDelete: 'cascade' }),
    title: text('title').notNull(),
    kind: text('kind', { enum: ['long', 'short'] }).notNull(),
    path: text('path').notNull(),
    durationSec: real('duration_sec').notNull(),
    width: integer('width').notNull(),
    height: integer('height').notNull(),
    sizeBytes: integer('size_bytes').notNull(),
    createdAt: integer('created_at').notNull(),
  },
  (t) => [index('outputs_video_idx').on(t.videoId, t.createdAt)],
);

/** 영상별 대화. 문구는 코드 + params, UI 가 문장으로 만든다. */
export const messages = sqliteTable(
  'messages',
  {
    id: text('id').primaryKey(),
    videoId: text('video_id')
      .notNull()
      .references(() => videos.id, { onDelete: 'cascade' }),
    role: text('role', { enum: ['assistant', 'user'] }).notNull(),
    kind: text('kind', { enum: ['text', 'progress', 'output', 'error', 'chapters'] }).notNull(),
    code: text('code').notNull(),
    params: text('params', { mode: 'json' }).notNull(),
    jobId: text('job_id'),
    outputId: text('output_id'),
    createdAt: integer('created_at').notNull(),
    updatedAt: integer('updated_at').notNull(),
  },
  (t) => [index('messages_video_idx').on(t.videoId, t.createdAt)],
);

/** 완성본(예전에 만든 결과물). 스타일 학습용. 갤러리엔 안 뜬다. */
export const references = sqliteTable(
  'references',
  {
    id: text('id').primaryKey(),
    path: text('path').notNull(),
    fileName: text('file_name').notNull(),
    title: text('title').notNull(),
    sizeBytes: integer('size_bytes').notNull(),
    status: text('status', { enum: ['queued', 'analyzing', 'done', 'failed', 'missing'] })
      .notNull()
      .default('queued'),
    stats: text('stats', { mode: 'json' }),
    /** 짝 맞추기용 자막 (있을 때만) */
    segments: text('segments', { mode: 'json' }),
    error: text('error'),
    createdAt: integer('created_at').notNull(),
    updatedAt: integer('updated_at').notNull(),
  },
  (t) => [uniqueIndex('references_path_idx').on(t.path)],
);

/** 롱폼 챕터. 영상당 하나, 다시 나누면 덮어쓴다. */
export const chapters = sqliteTable('chapters', {
  videoId: text('video_id')
    .primaryKey()
    .references(() => videos.id, { onDelete: 'cascade' }),
  items: text('items', { mode: 'json' }).notNull(),
  fromTranscript: integer('from_transcript', { mode: 'boolean' }).notNull().default(false),
  createdAt: integer('created_at').notNull(),
});
