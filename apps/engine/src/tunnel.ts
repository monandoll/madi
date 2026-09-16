import { type ChildProcess, spawn } from 'node:child_process';
import type { TunnelStatus } from '@madi/shared';
import type { Logger } from './log.js';

export interface TunnelState {
  status: TunnelStatus;
  error: string | null;
}

/**
 * cloudflared 관리. 토큰이 있으면 `cloudflared tunnel run --token …` 을 띄우고,
 * 죽으면 백오프로 다시 띄운다. 접근 제어는 Cloudflare Access 가 한다 — 앱엔 로그인이 없다.
 */
export class Tunnel {
  private child: ChildProcess | null = null;
  private token: string | null = null;
  private retry = 0;
  private timer: ReturnType<typeof setTimeout> | undefined;
  private stopped = false;
  state: TunnelState = { status: 'off', error: null };

  constructor(
    private readonly bin: string,
    private readonly log: Logger,
    private readonly spawnImpl: typeof spawn = spawn,
  ) {}

  /** 토큰이 바뀌면 다시 띄우고, 없어지면 내린다. */
  apply(token: string | null): void {
    const next = token?.trim() || null;
    if (next === this.token && (this.child || !next)) return;
    this.token = next;
    this.kill();
    this.retry = 0;
    if (!next) {
      this.state = { status: 'off', error: null };
      return;
    }
    this.start();
  }

  private start(): void {
    if (this.stopped || !this.token) return;
    this.state = { status: 'starting', error: null };
    let child: ChildProcess;
    try {
      child = this.spawnImpl(this.bin, ['tunnel', '--no-autoupdate', 'run', '--token', this.token], { stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true });
    } catch (err) {
      this.fail(err instanceof Error ? err.message : String(err));
      return;
    }
    this.child = child;
    let tail = '';
    const onData = (d: Buffer) => {
      const text = d.toString();
      tail = (tail + text).slice(-2000);
      // cloudflared 는 연결되면 "Registered tunnel connection" 을 낸다
      if (/Registered tunnel connection|Connection .* registered/i.test(text)) {
        this.retry = 0;
        this.state = { status: 'running', error: null };
        this.log.info('tunnel connected');
      }
    };
    child.stdout?.on('data', onData);
    child.stderr?.on('data', onData);
    child.on('error', (err) => this.fail(err.message));
    child.on('exit', (code) => {
      this.child = null;
      if (this.stopped || !this.token) return;
      const reason = /token|unauthorized|invalid/i.test(tail) ? 'bad_token' : `exit ${code}`;
      this.fail(reason);
      const wait = Math.min(60_000, 2_000 * 2 ** this.retry++);
      this.timer = setTimeout(() => this.start(), wait);
    });
  }

  private fail(error: string): void {
    this.state = { status: 'error', error };
    this.log.warn({ error }, 'tunnel down');
  }

  private kill(): void {
    clearTimeout(this.timer);
    this.child?.kill();
    this.child = null;
  }

  stop(): void {
    this.stopped = true;
    this.kill();
    this.state = { status: 'off', error: null };
  }
}
