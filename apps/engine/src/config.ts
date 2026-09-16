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
  outputsDir: string;
  modelsDir: string;
  /** 에이전트 실행 임시 폴더 등 */
  workDir: string;
  /** StyleProfile (style.md, params.json, examples/) */
  styleDir: string;
  rootDir: string;
  migrationsDir: string;
  webDir: string;
  binDir: string;
  fontsDir: string;
  /** MCP 서버 진입점. 개발: src/mcp/index.ts (tsx), 패키징: resources/mcp.mjs */
  mcpEntry: string;
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
    outputsDir: path.join(dataDir, 'outputs'),
    modelsDir: path.join(dataDir, 'models'),
    workDir: path.join(dataDir, 'work'),
    styleDir: path.join(dataDir, 'style'),
    rootDir,
    migrationsDir: isDev ? path.join(rootDir, 'apps/engine/drizzle') : path.join(rootDir, 'drizzle'),
    webDir: isDev ? path.join(rootDir, 'apps/web/dist') : path.join(rootDir, 'web'),
    binDir: isDev ? path.join(rootDir, 'resources/bin') : path.join(rootDir, 'bin'),
    fontsDir: isDev ? path.join(rootDir, 'resources/fonts') : path.join(rootDir, 'fonts'),
    mcpEntry: isDev ? path.join(rootDir, 'apps/engine/src/mcp/index.ts') : path.join(rootDir, 'mcp.mjs'),
    isDev,
    ...overrides,
  };
  for (const dir of [cfg.dataDir, cfg.logsDir, cfg.proxiesDir, cfg.thumbsDir, cfg.outputsDir, cfg.modelsDir, cfg.workDir, cfg.styleDir]) {
    fs.mkdirSync(dir, { recursive: true });
  }
  return cfg;
}
