import { type ChildProcess, spawn } from 'node:child_process';
import type { RemoteMode, TunnelStatus } from '@madi/shared';
import type { Logger } from './log.js';

export interface TunnelState {
  status: TunnelStatus;
  error: string | null;
  /** 밖에서 들어올 주소. quick 모드에서 cloudflared 가 알려 준다. token 모드는 사용자가 정한 도메인이라 모른다. */
  url: string | null;
}

export interface TunnelConfig {
  mode: RemoteMode;
  token: string | null;
  /** quick 모드에서 터널이 가리킬 로컬 주소 */
  localUrl: string;
}

/** quick 터널 주소: cloudflared 가 로그에 한 번 찍는다. */
export function parseQuickUrl(text: string): string | null {
  return /https:\/\/[a-z0-9][a-z0-9-]*(?:\.[a-z0-9-]+)*\.trycloudflare\.com/i.exec(text)?.[0] ?? null;
}

/** 같은 설정인가 (바뀌었을 때만 다시 띄우려고). */
function sameConfig(a: TunnelConfig | null, b: TunnelConfig): boolean {
  return !!a && a.mode === b.mode && a.token === b.token && a.localUrl === b.localUrl;
}

/**
 * cloudflared 관리.
 * - quick: `cloudflared tunnel --url <로컬>` — 계정도 토큰도 없이 임시 주소를 받는다. 껐다 켜면 주소가 바뀐다.
 * - token: `cloudflared tunnel run --token …` — 고정 주소 (고급).
 * 죽으면 백오프로 다시 띄운다. 들어오는 사람 잠금은 엔진이 6자리 숫자로 한다 (remote.ts).
 */
export class Tunnel {
  private child: ChildProcess | null = null;
  private config: TunnelConfig | null = null;
  private retry = 0;
  private timer: ReturnType<typeof setTimeout> | undefined;
  private stopped = false;
  state: TunnelState = { status: 'off', error: null, url: null };

  constructor(
    private readonly bin: string,
    private readonly log: Logger,
    private readonly spawnImpl: typeof spawn = spawn,
  ) {}

  /** 설정이 바뀌면 다시 띄우고, off 면 내린다. */
  apply(config: TunnelConfig): void {
    const next: TunnelConfig = { ...config, token: config.token?.trim() || null };
    const off = next.mode === 'off' || (next.mode === 'token' && !next.token);
    if (off) {
      if (this.config === null && this.state.status === 'off') return;
      this.config = null;
      this.kill();
      this.setState({ status: 'off', error: null, url: null });
      return;
    }
    if (sameConfig(this.config, next) && this.child) return;
    this.config = next;
    this.kill();
    this.retry = 0;
    this.start();
  }

  private args(c: TunnelConfig): string[] {
    return c.mode === 'quick'
      ? ['tunnel', '--no-autoupdate', '--url', c.localUrl]
      : ['tunnel', '--no-autoupdate', 'run', '--token', c.token!];
  }

  private start(): void {
    const c = this.config;
    if (this.stopped || !c) return;
    this.setState({ status: 'starting', error: null, url: c.mode === 'quick' ? null : this.state.url });
    let child: ChildProcess;
    try {
      child = this.spawnImpl(this.bin, this.args(c), { stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true });
    } catch (err) {
      this.fail(err instanceof Error ? err.message : String(err));
      return;
    }
    this.child = child;
    let tail = '';
    const onData = (d: Buffer) => {
      const text = d.toString();
      tail = (tail + text).slice(-4000);
      if (c.mode === 'quick' && !this.state.url) {
        const url = parseQuickUrl(text);
        if (url) {
          this.setState({ ...this.state, url });
          this.log.info({ url }, 'quick tunnel url');
        }
      }
      // cloudflared 는 연결되면 "Registered tunnel connection" 을 낸다
      if (/Registered tunnel connection|Connection .* registered/i.test(text)) {
        this.retry = 0;
        this.setState({ status: 'running', error: null, url: this.state.url });
        this.log.info({ mode: c.mode }, 'tunnel connected');
      }
    };
    child.stdout?.on('data', onData);
    child.stderr?.on('data', onData);
    child.on('error', (err) => this.fail(err.message));
    child.on('exit', (code) => {
      this.child = null;
      if (this.stopped || !this.config) return;
      const reason = /token|unauthorized|invalid/i.test(tail) ? 'bad_token' : `exit ${code}`;
      this.fail(reason);
      const wait = Math.min(60_000, 2_000 * 2 ** this.retry++);
      this.timer = setTimeout(() => this.start(), wait);
    });
  }

  private setState(next: TunnelState): void {
    this.state = next;
  }

  private fail(error: string): void {
    this.setState({ status: 'error', error, url: this.config?.mode === 'quick' ? null : this.state.url });
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
    this.setState({ status: 'off', error: null, url: null });
  }
}
