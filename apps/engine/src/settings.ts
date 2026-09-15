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
    const parsed = Settings.safeParse(row.value);
    // 깨진 값은 기본값으로 덮되, 살릴 수 있는 필드는 살린다.
    return parsed.success ? parsed.data : { ...DEFAULT_SETTINGS, ...(row.value as Partial<Settings>) };
  }

  patch(patch: SettingsPatch): Settings {
    const next = Settings.parse({ ...this.get(), ...patch });
    this.db
      .insert(kv)
      .values({ key: KEY, value: next, updatedAt: Date.now() })
      .onConflictDoUpdate({ target: kv.key, set: { value: next, updatedAt: Date.now() } })
      .run();
    return next;
  }
}
