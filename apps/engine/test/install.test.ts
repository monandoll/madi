/**
 * AI 도구가 아예 없는 PC: 마디가 공식 설치기를 대신 돌린다.
 * 명령은 플랫폼마다 다르고, 사용자가 터미널에 직접 칠 한 줄도 같은 곳에서 나온다.
 */
import { EventEmitter } from 'node:events';
import { PassThrough } from 'node:stream';
import type { ChildProcess } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { AiInstaller, installLine, installPlan, loginLine, loginPlan } from '../src/agent/install.js';
import { resetCliCache } from '../src/agent/detect.js';
import { fakeCli, quietLogger, tempHome } from './helpers.js';

let home: string;

beforeEach(() => {
  home = tempHome('madi-install-');
  resetCliCache();
  delete process.env['MADI_INSTALL_CLAUDE'];
  delete process.env['MADI_INSTALL_CODEX'];
});
afterEach(() => {
  resetCliCache();
  fs.rmSync(home, { recursive: true, force: true });
});

describe('installLine', () => {
  it('맥은 공식 설치기를 curl 로 받는다 (node 없이)', () => {
    expect(installLine('claude', 'darwin')).toBe('curl -fsSL https://claude.ai/install.sh | bash');
    expect(installLine('codex', 'darwin')).toBe('curl -fsSL https://chatgpt.com/codex/install.sh | sh');
  });

  it('윈도우는 powershell 한 줄', () => {
    expect(installLine('claude', 'win32')).toBe('powershell -ExecutionPolicy ByPass -c "irm https://claude.ai/install.ps1 | iex"');
    expect(installLine('codex', 'win32')).toContain('https://chatgpt.com/codex/install.ps1');
  });

  it('npm 도 node 도 쓰지 않는다 (관리자 권한 없이 사용자 폴더에 깔린다)', () => {
    for (const p of ['darwin', 'win32', 'linux'] as const) {
      for (const n of ['claude', 'codex'] as const) {
        expect(installLine(n, p)).not.toMatch(/npm|node/);
      }
    }
  });

  it('모르는 OS 면 없다', () => {
    expect(installLine('claude', 'aix')).toBeNull();
  });
});

describe('installPlan', () => {
  it('맥·리눅스는 bash, 윈도우는 powershell 로 띄운다', () => {
    expect(installPlan('claude', 'darwin')).toEqual({ command: '/bin/bash', args: ['-lc', 'curl -fsSL https://claude.ai/install.sh | bash'] });
    const win = installPlan('codex', 'win32')!;
    expect(win.command).toBe('powershell.exe');
    expect(win.args).toContain('-NoProfile');
    expect(win.args.at(-1)).toBe('irm https://chatgpt.com/codex/install.ps1 | iex');
  });

  it('모르는 OS 면 null (화면에서 깔기 버튼을 숨긴다)', () => {
    expect(installPlan('claude', 'aix')).toBeNull();
  });

  it('환경변수로 갈아 끼울 수 있다 (테스트·수동 조정)', () => {
    process.env['MADI_INSTALL_CLAUDE'] = 'echo hi';
    expect(installPlan('claude', 'darwin')).toEqual({ command: '/bin/sh', args: ['-c', 'echo hi'] });
  });
});

describe('loginPlan', () => {
  it('로그인은 도구를 그냥 실행하는 것', () => {
    expect(loginLine('claude')).toBe('claude');
    expect(loginLine('codex')).toBe('codex');
  });

  it('맥은 터미널 앱, 윈도우는 새 명령 창을 연다', () => {
    expect(loginPlan('claude', 'darwin')!.command).toBe('osascript');
    expect(loginPlan('claude', 'darwin')!.args.join(' ')).toContain('do script "claude"');
    expect(loginPlan('codex', 'win32')).toEqual({ command: 'cmd.exe', args: ['/c', 'start', '', 'cmd', '/k', 'codex'] });
  });

  it('창을 못 여는 곳(리눅스 개발)에서는 null', () => {
    expect(loginPlan('claude', 'linux')).toBeNull();
  });
});

/** 설치기 흉내: 우리가 exit 을 낼 수 있는 가짜 자식 */
function fakeChild() {
  const child = new EventEmitter() as ChildProcess & { stdout: PassThrough; stderr: PassThrough };
  child.stdout = new PassThrough();
  child.stderr = new PassThrough();
  child.kill = vi.fn(() => true) as ChildProcess['kill'];
  return child;
}

describe('AiInstaller', () => {
  it('깔고 나서 진짜 도는지 확인한다 — 되면 다 됐어요', async () => {
    // 설치기가 "깔아 놓은" 자리를 환경변수로 가리킨다
    process.env['MADI_CLAUDE_BIN'] = fakeCli('claude');
    const children: ReturnType<typeof fakeChild>[] = [];
    const spawnImpl = vi.fn(() => {
      const c = fakeChild();
      children.push(c);
      return c;
    });
    const inst = new AiInstaller(quietLogger(home), spawnImpl as never);
    expect(inst.start('claude')).toBe(true);
    expect(inst.state).toMatchObject({ provider: 'claude', status: 'running', step: 'downloading' });
    // 깔고 있는 동안 또 누르면 무시
    expect(inst.start('codex')).toBe(false);

    children[0]!.emit('exit', 0);
    await vi.waitFor(() => expect(inst.state.status).toBe('done'));
    expect(inst.state.error).toBeNull();
    delete process.env['MADI_CLAUDE_BIN'];
  });

  it('안 깔렸으면 왜 안 됐는지 남긴다', async () => {
    process.env['MADI_CLAUDE_BIN'] = path.join(home, '없는-파일');
    const children: ReturnType<typeof fakeChild>[] = [];
    const spawnImpl = vi.fn(() => {
      const c = fakeChild();
      children.push(c);
      return c;
    });
    const inst = new AiInstaller(quietLogger(home), spawnImpl as never);
    inst.start('claude');
    children[0]!.stderr.write('curl: (6) Could not resolve host: claude.ai\n');
    children[0]!.emit('exit', 1);
    await vi.waitFor(() => expect(inst.state.status).toBe('failed'));
    expect(inst.state.error).toBe('exit 1');

    // 닫으면 비워져서 다시 누를 수 있다
    inst.clear();
    expect(inst.state).toEqual({ provider: null, status: 'idle', step: null, error: null });
    delete process.env['MADI_CLAUDE_BIN'];
  });

  it('인터넷이 끊긴 경우는 그렇게 말해 준다', async () => {
    process.env['MADI_CLAUDE_BIN'] = path.join(home, '없는-파일');
    const children: ReturnType<typeof fakeChild>[] = [];
    const inst = new AiInstaller(
      quietLogger(home),
      vi.fn(() => {
        const c = fakeChild();
        children.push(c);
        return c;
      }) as never,
    );
    inst.start('claude');
    children[0]!.stderr.write('curl: (6) Could not resolve host\n');
    // exit 0 인데 실제로는 안 깔린 경우 — 로그에서 이유를 집는다
    children[0]!.emit('exit', 0);
    await vi.waitFor(() => expect(inst.state.status).toBe('failed'));
    expect(inst.state.error).toBe('network');
    delete process.env['MADI_CLAUDE_BIN'];
  });
});
