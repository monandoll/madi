/**
 * 화면 안 터미널 e2e: 브라우저가 /api/term 소켓을 열면 진짜 PTY 가 붙고, 나온 글이 그대로 흘러온다.
 * 열리는 것은 정해진 몇 개뿐이고, 밖에서 들어온 기기는 짝을 지어야 붙는다.
 */
import fs from 'node:fs';
import path from 'node:path';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { WebSocket } from 'ws';
import { type TermOut } from '@madi/shared';
import { resetCliCache } from '../src/agent/detect.js';
import { type Engine, startEngine } from '../src/engine.js';
import { FIXTURES, freePort, tempHome } from './helpers.js';

let home: string;
let engine: Engine;

/** 터널을 지나온 척 (짝짓기 전에는 막혀야 한다) */
const REMOTE = { 'cf-connecting-ip': '203.0.113.9' };

beforeAll(async () => {
  home = tempHome('madi-term-e2e-');
  process.env['MADI_QUIET'] = '1';
  process.env['MADI_CLAUDE_BIN'] = path.join(FIXTURES, 'fake-claude.mjs');
  process.env['MADI_CODEX_BIN'] = path.join(FIXTURES, 'fake-codex.mjs');
  resetCliCache();
  engine = await startEngine({ dataDir: home, dbPath: path.join(home, 'madi.db'), port: await freePort() });
});

afterAll(async () => {
  await engine?.stop();
  delete process.env['MADI_CLAUDE_BIN'];
  delete process.env['MADI_CODEX_BIN'];
  fs.rmSync(home, { recursive: true, force: true });
});

const wsUrl = () => `${engine.url.replace('http', 'ws')}/api/term`;

/** 소켓을 열고 메시지를 모은다. 끝나거나 오류가 나면 돌려준다. */
function run(open: unknown, opts: { headers?: Record<string, string>; sendAfterReady?: unknown } = {}): Promise<TermOut[]> {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(wsUrl(), { headers: opts.headers });
    const got: TermOut[] = [];
    const timer = setTimeout(() => {
      ws.close();
      resolve(got);
    }, 15_000);
    ws.on('open', () => ws.send(JSON.stringify(open)));
    ws.on('message', (raw) => {
      const msg = JSON.parse(String(raw)) as TermOut;
      got.push(msg);
      if (msg.t === 'ready' && opts.sendAfterReady) ws.send(JSON.stringify(opts.sendAfterReady));
      if (msg.t === 'exit' || msg.t === 'error') {
        clearTimeout(timer);
        ws.close();
        resolve(got);
      }
    });
    ws.on('error', (err) => {
      clearTimeout(timer);
      reject(err);
    });
  });
}

const textOf = (msgs: TermOut[]) => msgs.filter((m): m is Extract<TermOut, { t: 'out' }> => m.t === 'out').map((m) => m.d).join('');

describe('화면 안 터미널', () => {
  it('로그인을 열면 진짜 터미널이 붙고 나온 글이 흘러온다', async () => {
    const msgs = await run({ t: 'open', kind: 'login-codex', cols: 80, rows: 24 });
    const ready = msgs.find((m) => m.t === 'ready');
    expect(ready).toMatchObject({ t: 'ready', title: 'Codex 로그인', line: 'codex login' });
    expect(textOf(msgs)).toContain('브라우저에서 열기');
    expect(msgs.at(-1)).toMatchObject({ t: 'exit', code: 0 });
  });

  it('claude 는 통째로 띄우지 않고 로그인만 여는 명령을 쓴다', async () => {
    const msgs = await run({ t: 'open', kind: 'login-claude', cols: 80, rows: 24 });
    expect(msgs.find((m) => m.t === 'ready')).toMatchObject({ line: 'claude setup-token' });
    expect(textOf(msgs)).toContain('Claude Code 로그인');
  });

  it('정해진 것 말고는 열리지 않는다 (셸도, 아무 명령도)', async () => {
    for (const kind of ['bash', 'sh', '../../bin/sh', 'login-claude; echo hi']) {
      const msgs = await run({ t: 'open', kind, cols: 80, rows: 24 });
      expect(msgs.filter((m) => m.t === 'ready')).toHaveLength(0);
      expect(msgs.at(-1)).toMatchObject({ t: 'error', code: 'bad_kind' });
    }
  });

  it('밖에서 들어온 기기는 짝을 짓기 전엔 붙지 못한다', async () => {
    await expect(run({ t: 'open', kind: 'login-codex', cols: 80, rows: 24 }, { headers: REMOTE })).rejects.toThrow();
  });

  it('창이 하나 열려 있으면 두 번째는 기다리라고 한다', async () => {
    const first = new WebSocket(wsUrl());
    await new Promise((r) => first.on('open', r));
    // 오래 걸리는 것을 물려 둔다 (가짜 설치기)
    process.env['MADI_INSTALL_CODEX'] = 'sleep 5';
    first.send(JSON.stringify({ t: 'open', kind: 'install-codex', cols: 80, rows: 24 }));
    await new Promise((r) => first.on('message', r));

    const msgs = await run({ t: 'open', kind: 'login-codex', cols: 80, rows: 24 });
    expect(msgs.at(-1)).toMatchObject({ t: 'error', code: 'busy' });

    first.close();
    delete process.env['MADI_INSTALL_CODEX'];
    // 닫으면 다음 사람이 열 수 있다
    await new Promise((r) => setTimeout(r, 500));
    const after = await run({ t: 'open', kind: 'login-codex', cols: 80, rows: 24 });
    expect(after.find((m) => m.t === 'ready')).toBeTruthy();
  });

  it('도구가 없으면 못 연다고 말해 준다', async () => {
    const keep = process.env['MADI_CODEX_BIN'];
    process.env['MADI_CODEX_BIN'] = path.join(home, '없는-파일');
    resetCliCache();
    const msgs = await run({ t: 'open', kind: 'login-codex', cols: 80, rows: 24 });
    expect(msgs.at(-1)).toMatchObject({ t: 'error', code: 'not_found' });
    process.env['MADI_CODEX_BIN'] = keep;
    resetCliCache();
  });
});
