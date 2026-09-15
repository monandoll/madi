import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { ENGINE_PORT } from '@madi/shared';

/**
 * 엔진이 쓰는 경로 모음.
 * - dataDir: ~/.madi (MADI_HOME 으로 바꿀 수 있음) — DB, 로그, 프록시, 썸네일
 * - rootDir: 레포 루트 또는 패키징된 resources 경로 — 마이그레이션, 웹 정적 파일, 바이너리
 */
export interface EngineConfig {
  port: number;
  dataDir: string;
  dbPath: string;
  logsDir: string;
  proxiesDir: string;
  thumbsDir: string;
  rootDir: string;
  migrationsDir: string;
  webDir: string;
  binDir: string;
  isDev: boolean;
}

function findRepoRoot(from: string): string {
  let dir = from;
  for (let i = 0; i < 8; i++) {
    if (fs.existsSync(path.join(dir, 'pnpm-workspace.yaml'))) return dir;
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return from;
}

export function loadConfig(overrides: Partial<EngineConfig> = {}): EngineConfig {
  const env = process.env;
  const dataDir = overrides.dataDir ?? env['MADI_HOME'] ?? path.join(os.homedir(), '.madi');
  const here = path.dirname(fileURLToPath(import.meta.url));
  const repoRoot = findRepoRoot(here);
  // 패키징된 앱은 MADI_ROOT=process.resourcesPath 로 넘긴다.
  const rootDir = overrides.rootDir ?? env['MADI_ROOT'] ?? repoRoot;
  const isDev = !env['MADI_ROOT'];

  const cfg: EngineConfig = {
    port: overrides.port ?? Number(env['MADI_PORT'] ?? ENGINE_PORT),
    dataDir,
    dbPath: overrides.dbPath ?? env['MADI_DB'] ?? path.join(dataDir, 'madi.db'),
    logsDir: path.join(dataDir, 'logs'),
    proxiesDir: path.join(dataDir, 'proxies'),
    thumbsDir: path.join(dataDir, 'thumbs'),
    rootDir,
    migrationsDir: isDev ? path.join(rootDir, 'apps/engine/drizzle') : path.join(rootDir, 'drizzle'),
    webDir: isDev ? path.join(rootDir, 'apps/web/dist') : path.join(rootDir, 'web'),
    binDir: isDev ? path.join(rootDir, 'resources/bin') : path.join(rootDir, 'bin'),
    isDev,
    ...overrides,
  };
  for (const dir of [cfg.dataDir, cfg.logsDir, cfg.proxiesDir, cfg.thumbsDir]) {
    fs.mkdirSync(dir, { recursive: true });
  }
  return cfg;
}
