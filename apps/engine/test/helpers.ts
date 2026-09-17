import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { openDb } from '../src/db/index.js';
import { createLogger } from '../src/log.js';

export const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
export const FIXTURES = path.join(REPO_ROOT, 'fixtures');
export const SAMPLE_5S = path.join(FIXTURES, 'sample-5s.mp4');
export const SAMPLE_SILENT = path.join(FIXTURES, 'sample-silent-3s.mp4');
export const MIGRATIONS = path.join(REPO_ROOT, 'apps/engine/drizzle');

/**
 * 가짜 CLI 의 실행 파일 경로.
 *
 * 윈도우는 `.mjs` 를 바로 띄우지 못한다 (CreateProcess 가 거절, 종료 코드 193). 진짜 도구도 그 자리엔
 * `claude.cmd` 가 놓이므로, 여기서도 `node <픽스처>` 를 부르는 `.cmd` 껍데기를 만들어 그 경로를 준다.
 * 덕분에 윈도우에서는 cmd.exe 를 거치는 길(spawnCli · ptyTarget)까지 같이 확인된다.
 */
export function fakeCli(name: 'claude' | 'codex'): string {
  const script = path.join(FIXTURES, `fake-${name}.mjs`);
  if (process.platform !== 'win32') return script;
  const dir = path.join(os.tmpdir(), 'madi-fake-bin');
  fs.mkdirSync(dir, { recursive: true });
  const shim = path.join(dir, `${name}.cmd`);
  fs.writeFileSync(shim, `@echo off\r\n"${process.execPath}" "${script}" %*\r\n`);
  return shim;
}

/** 실행 파일 이름 (윈도우면 .cmd 를 붙여야 실행된다). */
export function exeName(base: string): string {
  return process.platform === 'win32' ? `${base}.cmd` : base;
}

/** 테스트마다 새 임시 홈. */
export function tempHome(prefix = 'madi-test-'): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), prefix));
}

export function openTestDb(home: string) {
  fs.mkdirSync(home, { recursive: true });
  return openDb(path.join(home, 'test.db'), MIGRATIONS);
}

export function quietLogger(home: string) {
  process.env['MADI_QUIET'] = '1';
  return createLogger(path.join(home, 'logs'), true);
}

export async function waitFor(pred: () => boolean | Promise<boolean>, timeoutMs = 30_000, every = 100): Promise<void> {
  const until = Date.now() + timeoutMs;
  while (Date.now() < until) {
    if (await pred()) return;
    await new Promise((r) => setTimeout(r, every));
  }
  throw new Error('waitFor: timeout');
}

/** 비어 있는 포트 하나. */
export async function freePort(): Promise<number> {
  const net = await import('node:net');
  return new Promise((resolve, reject) => {
    const srv = net.createServer();
    srv.listen(0, '127.0.0.1', () => {
      const addr = srv.address();
      const port = typeof addr === 'object' && addr ? addr.port : 0;
      srv.close(() => resolve(port));
    });
    srv.on('error', reject);
  });
}
