import { type ChildProcess, spawn } from 'node:child_process';
import type { AiInstallState } from '@madi/shared';
import type { Logger } from '../log.js';
import { cliVersion, findCli, resetCliCache, type CliName } from './detect.js';

/**
 * AI 도구가 아예 안 깔린 PC 를 위한 길.
 *
 * 두 회사 다 공식 설치기가 있다 — node 도, 관리자 권한도 필요 없고 사용자 폴더에 깔린다.
 * 마디가 그 설치기를 대신 돌리고, 사용자에게는 "받는 중 → 다 됐어요"만 보여 준다.
 * 로그인만은 창이 떠야 해서 터미널을 대신 열어 준다 (거기서 브라우저가 열린다).
 */

/** 공식 설치기 주소 (둘 다 node 없이 사용자 폴더에 깐다). */
function installUrl(name: CliName): string {
  return name === 'claude' ? 'https://claude.ai/install' : 'https://chatgpt.com/codex/install';
}

/** 윈도우에서 돌릴 한 줄 (powershell 안쪽). */
function psLine(name: CliName): string {
  return `irm ${installUrl(name)}.ps1 | iex`;
}

/** 맥·리눅스에서 돌릴 한 줄. */
function shLine(name: CliName): string {
  return `curl -fsSL ${installUrl(name)}.sh | ${name === 'claude' ? 'bash' : 'sh'}`;
}

/** 설치 한 줄. 사용자가 터미널에 직접 쳐도 되는 그 명령 그대로 (화면의 "터미널에서 직접 하기"). */
export function installLine(name: CliName, platform: NodeJS.Platform = process.platform): string | null {
  if (platform === 'win32') return `powershell -ExecutionPolicy ByPass -c "${psLine(name)}"`;
  if (platform === 'darwin' || platform === 'linux') return shLine(name);
  return null;
}

/** 로그인 한 줄. 도구를 그냥 실행하면 로그인 화면이 뜬다. */
export function loginLine(name: CliName): string {
  return name === 'claude' ? 'claude' : 'codex';
}

export interface Plan {
  command: string;
  args: string[];
}

/** 설치기를 어떻게 띄울지. 못 하는 OS 면 null (화면에서 자동 설치 버튼을 숨긴다). */
export function installPlan(name: CliName, platform: NodeJS.Platform = process.platform): Plan | null {
  // 테스트·수동 조정용 탈출구: 이 값이 있으면 그대로 쓴다
  const override = process.env[`MADI_INSTALL_${name.toUpperCase()}`];
  if (override) return { command: '/bin/sh', args: ['-c', override] };
  if (platform === 'win32') return { command: 'powershell.exe', args: ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', psLine(name)] };
  if (platform === 'darwin' || platform === 'linux') return { command: '/bin/bash', args: ['-lc', shLine(name)] };
  return null;
}

/**
 * 로그인 창(터미널)을 여는 방법. 도구가 브라우저를 띄우려면 진짜 터미널이 있어야 한다.
 * macOS 는 Terminal.app, Windows 는 새 명령 창. 리눅스(개발)는 못 연다.
 */
export function loginPlan(name: CliName, platform: NodeJS.Platform = process.platform): Plan | null {
  const line = loginLine(name);
  if (platform === 'darwin') {
    return { command: 'osascript', args: ['-e', `tell application "Terminal" to do script "${line}"`, '-e', 'tell application "Terminal" to activate'] };
  }
  if (platform === 'win32') return { command: 'cmd.exe', args: ['/c', 'start', '', 'cmd', '/k', line] };
  return null;
}

const TIMEOUT_MS = 5 * 60_000;

/**
 * 설치 한 번. 동시에 하나만.
 * 끝나면 정말 깔렸는지 실행해 보고(`--version`), 찾아 둔 기억을 지워 다음 확인 때 새로 찾게 한다.
 */
export class AiInstaller {
  private child: ChildProcess | null = null;
  private timer: ReturnType<typeof setTimeout> | undefined;
  state: AiInstallState = { provider: null, status: 'idle', step: null, error: null };

  constructor(
    private readonly log: Logger,
    private readonly spawnImpl: typeof spawn = spawn,
  ) {}

  get busy(): boolean {
    return this.state.status === 'running';
  }

  /** 이 PC 에서 마디가 대신 깔아 줄 수 있는가. */
  canInstall(name: CliName): boolean {
    return installPlan(name) !== null;
  }

  /** 시작. 이미 하고 있으면 false. */
  start(name: CliName): boolean {
    if (this.busy) return false;
    const plan = installPlan(name);
    if (!plan) {
      this.state = { provider: name, status: 'failed', step: null, error: 'unsupported' };
      return true;
    }
    this.state = { provider: name, status: 'running', step: 'downloading', error: null };
    let child: ChildProcess;
    try {
      child = this.spawnImpl(plan.command, plan.args, { stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true });
    } catch (err) {
      this.finish(name, err instanceof Error ? err.message : String(err));
      return true;
    }
    this.child = child;
    let tail = '';
    const onData = (d: Buffer) => {
      tail = (tail + d.toString()).slice(-4000);
      this.log.debug({ tool: name, line: d.toString().slice(0, 200) }, 'ai install');
    };
    child.stdout?.on('data', onData);
    child.stderr?.on('data', onData);
    this.timer = setTimeout(() => {
      this.child?.kill('SIGKILL');
      this.finish(name, 'timeout');
    }, TIMEOUT_MS);
    child.on('error', (err) => this.finish(name, err.message));
    child.on('exit', (code) => {
      this.child = null;
      clearTimeout(this.timer);
      if (this.state.status !== 'running') return;
      this.state = { ...this.state, step: 'checking' };
      void this.verify(name, code === 0 ? null : `exit ${code}`, tail);
    });
    return true;
  }

  /** 정말 깔렸는지 실행해 본다. 깔렸으면 exit 코드가 이상해도 성공으로 친다. */
  private async verify(name: CliName, failure: string | null, tail: string): Promise<void> {
    resetCliCache();
    const bin = findCli(name);
    const version = bin ? await cliVersion(bin) : null;
    if (version !== null) {
      this.state = { provider: name, status: 'done', step: null, error: null };
      this.log.info({ tool: name, version }, 'ai installed');
      return;
    }
    this.finish(name, failure ?? reasonFrom(tail));
  }

  private finish(name: CliName, error: string): void {
    clearTimeout(this.timer);
    this.child = null;
    this.state = { provider: name, status: 'failed', step: null, error };
    this.log.warn({ tool: name, error }, 'ai install failed');
  }

  /** 다음 시도를 위해 비운다 (화면에서 오류를 닫을 때). */
  clear(): void {
    if (this.busy) return;
    this.state = { provider: null, status: 'idle', step: null, error: null };
  }

  stop(): void {
    clearTimeout(this.timer);
    this.child?.kill();
    this.child = null;
  }
}

/** 로그 꼬리에서 사람이 알아볼 이유 하나. */
function reasonFrom(tail: string): string {
  if (/network|resolve host|timed? out|connection/i.test(tail)) return 'network';
  if (/permission denied|EACCES|Access is denied/i.test(tail)) return 'permission';
  return 'failed';
}
