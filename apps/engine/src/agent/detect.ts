import { execFile } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnCli } from './provider.js';

export type CliName = 'claude' | 'codex';

/**
 * 에이전트 CLI 찾기. 우선순위:
 * 1. MADI_CLAUDE_BIN / MADI_CODEX_BIN
 * 2. PATH
 * 3. 흔한 설치 위치 (트레이 앱은 로그인 셸 PATH 를 물려받지 못한다)
 */
export function findCli(name: CliName): string | null {
  const fromEnv = process.env[`MADI_${name.toUpperCase()}_BIN`];
  if (fromEnv) return fs.existsSync(fromEnv) ? fromEnv : null;
  const candidates = process.platform === 'win32' ? [`${name}.cmd`, `${name}.exe`, name] : [name];
  const dirs = [...(process.env['PATH'] ?? '').split(path.delimiter), ...knownDirs()].filter(Boolean);
  for (const dir of dirs) {
    for (const c of candidates) {
      const p = path.join(dir, c);
      try {
        if (fs.statSync(p).isFile()) return p;
      } catch {
        /* 없음 */
      }
    }
  }
  return null;
}

function knownDirs(): string[] {
  const home = os.homedir();
  const out = [
    path.join(home, '.claude', 'local'),
    path.join(home, '.local', 'bin'),
    path.join(home, '.npm-global', 'bin'),
    path.join(home, '.volta', 'bin'),
    path.join(home, '.bun', 'bin'),
    '/opt/homebrew/bin',
    '/usr/local/bin',
    '/usr/bin',
  ];
  if (process.platform === 'win32') {
    const appData = process.env['APPDATA'];
    const local = process.env['LOCALAPPDATA'];
    if (appData) out.push(path.join(appData, 'npm'));
    if (local) out.push(path.join(local, 'Programs', 'claude'), path.join(local, 'Microsoft', 'WinGet', 'Links'));
  }
  // nvm / fnm 의 현재 node 옆
  try {
    const nvm = path.join(home, '.nvm', 'versions', 'node');
    for (const v of fs.readdirSync(nvm)) out.push(path.join(nvm, v, 'bin'));
  } catch {
    /* nvm 없음 */
  }
  return out;
}

export interface CliInfo {
  installed: boolean;
  path: string | null;
  version: string | null;
}

const cache = new Map<CliName, { at: number; info: CliInfo }>();

/** 설치 여부 + 버전. 60초 캐시. `--version` 이 8초 안에 안 끝나면 설치 안 된 것으로 본다. */
export async function detectCli(name: CliName, opts: { fresh?: boolean } = {}): Promise<CliInfo> {
  const hit = cache.get(name);
  if (hit && !opts.fresh && Date.now() - hit.at < 60_000) return hit.info;
  const bin = findCli(name);
  let info: CliInfo = { installed: false, path: bin, version: null };
  if (bin) {
    const version = await cliVersion(bin);
    info = { installed: version !== null, path: bin, version };
  }
  cache.set(name, { at: Date.now(), info });
  return info;
}

function cliVersion(bin: string): Promise<string | null> {
  return new Promise((resolve) => {
    let out = '';
    let child;
    try {
      child = spawnCli(bin, ['--version'], { cwd: os.tmpdir(), env: { ...process.env } });
    } catch {
      resolve(null);
      return;
    }
    const timer = setTimeout(() => {
      child.kill('SIGKILL');
      resolve(null);
    }, 8_000);
    child.stdout?.setEncoding('utf8');
    child.stdout?.on('data', (d: string) => (out += d));
    child.on('error', () => {
      clearTimeout(timer);
      resolve(null);
    });
    child.on('close', (code) => {
      clearTimeout(timer);
      const m = /(\d+\.\d+(?:\.\d+)?)/.exec(out);
      resolve(code === 0 ? (m?.[1] ?? out.trim().slice(0, 40) ?? '') : null);
    });
    child.stdin?.end();
  });
}

/** 테스트용: 캐시 비우기. */
export function resetCliCache(): void {
  cache.clear();
}

// execFile 은 직접 안 쓰지만, spawnCli 없이 단순 실행이 필요할 때를 위해 남겨 둔다.
export const _execFile = execFile;
