import os from 'node:os';
import type { IPty } from '@lydell/node-pty';
import { spawn as ptySpawn } from '@lydell/node-pty';
import type { TermKind } from '@madi/shared';
import { withKnownDirs, findCli } from '../agent/detect.js';
import { installPlan, loginLine } from '../agent/install.js';
import type { Logger } from '../log.js';

/**
 * 화면 안에서 열리는 터미널.
 *
 * 왜: 로그인은 도구가 직접 물어봐야 끝난다. 검은 창을 따로 찾게 하는 대신 마디 안에서 보여 준다.
 * 폰에서 들어와도 같은 화면이 뜬다.
 *
 * **아무 명령이나 열어 주지 않는다.** 짝지은 폰이 이 PC 를 마음대로 조종하게 되기 때문이다.
 * 아래 정해진 것만 연다 — 로그인 두 개, 깔기 두 개. 셸도, 사용자가 친 명령도 없다.
 * (특히 `claude` 를 그냥 띄우면 그 안에서 `!` 로 아무 명령이나 돌릴 수 있다. 그래서 로그인 전용 명령을 쓴다.)
 */

export interface TermPlan {
  command: string;
  args: string[];
  /** 화면 맨 위에 한 줄로 알려 줄 것 */
  title: string;
}

/** 열어 줄 수 있는 것 전부. 이 목록 밖은 없다. */
export function termPlan(kind: TermKind): TermPlan | null {
  switch (kind) {
    case 'login-claude': {
      const bin = findCli('claude');
      // `claude` 를 통째로 띄우지 않는다 — setup-token 은 로그인만 하고 끝난다
      return bin ? { command: bin, args: ['setup-token'], title: 'Claude Code 로그인' } : null;
    }
    case 'login-codex': {
      const bin = findCli('codex');
      return bin ? { command: bin, args: ['login'], title: 'Codex 로그인' } : null;
    }
    case 'install-claude':
    case 'install-codex': {
      const name = kind === 'install-claude' ? 'claude' : 'codex';
      const plan = installPlan(name);
      return plan ? { ...plan, title: name === 'claude' ? 'Claude Code 설치' : 'Codex 설치' } : null;
    }
    default:
      return null;
  }
}

/** 로그인을 직접 치고 싶은 사람을 위한 한 줄 (화면에 그대로 보여 준다). */
export function termLine(kind: TermKind): string | null {
  if (kind === 'login-claude') return `${loginLine('claude')} setup-token`;
  if (kind === 'login-codex') return `${loginLine('codex')} login`;
  return null;
}

const MAX_MS = 15 * 60_000;
const COLS = { min: 20, max: 300 };
const ROWS = { min: 5, max: 120 };

export interface TermSession {
  write(data: string): void;
  resize(cols: number, rows: number): void;
  kill(): void;
}

export interface TermHandlers {
  onData(chunk: string): void;
  onExit(code: number): void;
}

/**
 * 터미널 하나 띄우기. 못 띄우면 null (도구가 없거나 이 OS 에서 못 하는 것).
 * 15분이 지나면 저절로 닫는다 — 잊고 열어 둔 창이 남지 않게.
 */
export function openTerm(kind: TermKind, size: { cols: number; rows: number }, handlers: TermHandlers, log: Logger): TermSession | null {
  const plan = termPlan(kind);
  if (!plan) return null;
  let child: IPty;
  try {
    child = ptySpawn(plan.command, plan.args, {
      name: 'xterm-256color',
      cols: clamp(size.cols, COLS.min, COLS.max),
      rows: clamp(size.rows, ROWS.min, ROWS.max),
      cwd: os.tmpdir(),
      env: withKnownDirs({ ...process.env, TERM: 'xterm-256color' }) as Record<string, string>,
    });
  } catch (err) {
    log.warn({ kind, err: err instanceof Error ? err.message : String(err) }, 'term spawn failed');
    return null;
  }
  log.info({ kind }, 'term opened');
  const timer = setTimeout(() => {
    log.info({ kind }, 'term timeout');
    try {
      child.kill();
    } catch {
      /* 이미 끝났다 */
    }
  }, MAX_MS);

  child.onData(handlers.onData);
  child.onExit(({ exitCode }) => {
    clearTimeout(timer);
    log.info({ kind, exitCode }, 'term closed');
    handlers.onExit(exitCode);
  });

  return {
    write(data) {
      try {
        child.write(data);
      } catch {
        /* 이미 끝났다 */
      }
    },
    resize(cols, rows) {
      try {
        child.resize(clamp(cols, COLS.min, COLS.max), clamp(rows, ROWS.min, ROWS.max));
      } catch {
        /* 이미 끝났다 */
      }
    },
    kill() {
      clearTimeout(timer);
      try {
        child.kill();
      } catch {
        /* 이미 끝났다 */
      }
    },
  };
}

function clamp(n: number, lo: number, hi: number): number {
  if (!Number.isFinite(n)) return lo;
  return Math.min(hi, Math.max(lo, Math.round(n)));
}
