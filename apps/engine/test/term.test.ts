/**
 * 화면 안 터미널: 열 수 있는 것은 정해진 몇 개뿐이다.
 * 짝지은 폰이 이 PC 를 마음대로 조종하면 안 되므로, 셸도 사용자가 친 명령도 열리지 않는다.
 */
import fs from 'node:fs';
import path from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { TermKind } from '@madi/shared';
import { resetCliCache } from '../src/agent/detect.js';
import { openTerm, ptyTarget, termLine, termPlan } from '../src/server/term.js';
import { fakeCli, quietLogger, tempHome } from './helpers.js';

let home: string;

beforeEach(() => {
  home = tempHome('madi-term-');
  resetCliCache();
  process.env['MADI_CLAUDE_BIN'] = fakeCli('claude');
  process.env['MADI_CODEX_BIN'] = fakeCli('codex');
});
afterEach(() => {
  resetCliCache();
  delete process.env['MADI_CLAUDE_BIN'];
  delete process.env['MADI_CODEX_BIN'];
  fs.rmSync(home, { recursive: true, force: true });
});

describe('termPlan', () => {
  it('로그인은 도구를 통째로 띄우지 않는다 (그 안에서 아무 명령이나 돌릴 수 있으므로)', () => {
    const claude = termPlan('login-claude')!;
    expect(claude.command).toBe(fakeCli('claude'));
    expect(claude.args).toEqual(['setup-token']);
    const codex = termPlan('login-codex')!;
    expect(codex.args).toEqual(['login']);
  });

  it('깔기는 공식 설치기 한 줄', () => {
    const plan = termPlan('install-claude')!;
    expect(`${plan.command} ${plan.args.join(' ')}`).toMatch(/claude\.ai\/install/);
  });

  it('도구가 없으면 열지 않는다', () => {
    delete process.env['MADI_CODEX_BIN'];
    process.env['MADI_CODEX_BIN'] = path.join(home, '없는-파일');
    expect(termPlan('login-codex')).toBeNull();
  });

  it('셸이나 아무 명령은 목록에 없다', () => {
    // 스키마가 받아 주는 값이 네 개뿐이고, 그 밖은 열리지 않는다
    expect(TermKind.options).toEqual(['login-claude', 'login-codex', 'install-claude', 'install-codex']);
    for (const bad of ['bash', 'sh', 'cmd', 'powershell', 'login-claude; rm -rf /']) {
      expect(TermKind.safeParse(bad).success).toBe(false);
      expect(termPlan(bad as never)).toBeNull();
    }
  });

  it('직접 치고 싶은 사람을 위한 한 줄도 같이 준다', () => {
    expect(termLine('login-claude')).toBe('claude setup-token');
    expect(termLine('login-codex')).toBe('codex login');
    expect(termLine('install-claude')).toBeNull();
  });
});

describe('ptyTarget (윈도우)', () => {
  it('npm 으로 깐 claude.cmd 는 cmd.exe 를 거쳐 띄운다 (그냥 띄우면 종료 코드 193)', () => {
    const t = ptyTarget('C:\\Users\\Kim Eunjung\\AppData\\Roaming\\npm\\claude.cmd', ['setup-token'], 'win32');
    expect(t.command).toMatch(/cmd\.exe$/i);
    // 띄어쓰기가 있는 경로는 따옴표로 묶는다 (사용자 이름에 공백이 흔하다)
    expect(t.args).toBe('/d /s /c ""C:\\Users\\Kim Eunjung\\AppData\\Roaming\\npm\\claude.cmd" setup-token"');
  });

  it('.exe 나 맥·리눅스 실행 파일은 그대로 띄운다', () => {
    expect(ptyTarget('C:\\bin\\codex.exe', ['login'], 'win32')).toEqual({ command: 'C:\\bin\\codex.exe', args: ['login'] });
    expect(ptyTarget('/usr/local/bin/codex', ['login'], 'darwin')).toEqual({ command: '/usr/local/bin/codex', args: ['login'] });
  });
});

describe('openTerm', () => {
  it('진짜 터미널로 띄우고, 나온 글과 끝난 것을 알려 준다', async () => {
    const out: string[] = [];
    const exit = new Promise<number>((resolve) => {
      const session = openTerm('login-codex', { cols: 80, rows: 24 }, { onData: (d) => out.push(d), onExit: resolve }, quietLogger(home));
      expect(session).not.toBeNull();
    });
    expect(await exit).toBe(0);
    expect(out.join('')).toContain('로그인');
  });

  it('창 크기가 이상해도 죽지 않는다', async () => {
    const exit = new Promise<number>((resolve) => {
      const session = openTerm('login-codex', { cols: 0, rows: Number.NaN }, { onData: () => undefined, onExit: resolve }, quietLogger(home));
      session!.resize(99999, -3);
    });
    expect(await exit).toBe(0);
  });

  it('도구가 없으면 null', () => {
    process.env['MADI_CODEX_BIN'] = path.join(home, '없음');
    resetCliCache();
    expect(openTerm('login-codex', { cols: 80, rows: 24 }, { onData: () => undefined, onExit: () => undefined }, quietLogger(home))).toBeNull();
  });
});
