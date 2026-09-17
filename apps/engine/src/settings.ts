import { eq } from 'drizzle-orm';
import { DEFAULT_SETTINGS, Settings, type SettingsPatch } from '@madi/shared';
import type { Db } from './db/index.js';
import { kv } from './db/schema.js';

const KEY = 'settings';

export class SettingsStore {
  constructor(private readonly db: Db) {}

  get(): Settings {
    const row = this.db.select().from(kv).where(eq(kv.key, KEY)).get();
    if (!row) return { ...DEFAULT_SETTINGS };
    const raw = row.value as Partial<Settings> | null;
    const parsed = Settings.safeParse(raw);
    // 깨진 값은 기본값으로 덮되, 살릴 수 있는 필드는 살린다.
    const next = parsed.success ? parsed.data : { ...DEFAULT_SETTINGS, ...raw };
    // remoteMode 가 생기기 전에 토큰을 넣어 둔 사용자 → 토큰 방식으로 이어서 쓴다
    if (raw && raw.remoteMode === undefined && raw.tunnelToken) next.remoteMode = 'token';
    return next;
  }

  patch(patch: SettingsPatch): Settings {
    const now = this.get();
    // ai 는 한 겹 더 깊게 합친다 — 프로바이더만 바꿀 때 직접 골라 둔 실행 파일 경로가 날아가면 안 된다
    const ai = patch.ai ? { ...now.ai, ...patch.ai, paths: { ...now.ai.paths, ...(patch.ai.paths ?? {}) } } : now.ai;
    const next = Settings.parse({ ...now, ...patch, ai });
    this.db
      .insert(kv)
      .values({ key: KEY, value: next, updatedAt: Date.now() })
      .onConflictDoUpdate({ target: kv.key, set: { value: next, updatedAt: Date.now() } })
      .run();
    return next;
  }
}
