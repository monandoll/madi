import { type ChildProcess, spawn } from 'node:child_process';
import type { AiProvider } from '@madi/shared';
import { withKnownDirs } from './detect.js';

/** 러너가 프로바이더에 넘기는 것. 프롬프트는 이미 완성된 상태(스타일 규칙 포함). */
export interface AgentRunOptions {
  /** 이번 요청 (영상 정보 + 대화 + 사용자 말) */
  prompt: string;
  /** 역할·규칙. 프로바이더가 시스템 프롬프트로 넣거나 앞에 붙인다. */
  system: string;
  /** 우리 MCP 서버. 에이전트는 이 도구만 쓴다. */
  mcp: { command: string; args: string[]; env: Record<string, string> };
  /** MCP 도구 이름들 (서버 접두어 없이) */
  toolNames: string[];
  /** 빈 임시 폴더. 에이전트 CLI 의 작업 폴더 (프로젝트 설정이 끼어들지 않게). */
  cwd: string;
  /** 러너가 이미 찾아 둔 실행 파일. 없으면 프로바이더가 직접 찾는다. */
  bin?: string | null;
  signal?: AbortSignal | undefined;
  /** 지금까지의 답 전체 (턴 사이는 빈 줄) */
  onText(text: string): void;
  onTool(name: string): void;
  /** 원시 로그 한 줄 (디버그) */
  onLog?: (line: string) => void;
}

export interface AgentResult {
  text: string;
  toolCalls: number;
  ok: boolean;
  /** ok=false 일 때 이유. 'not_installed' 면 CLI 가 없다. */
  error?: string;
}

export interface AgentProvider {
  id: Exclude<AiProvider, 'none'>;
  label: string;
  /** CLI 경로. custom 은 사용자가 이 PC 에서 직접 골라 준 파일. 없으면 null. */
  bin(custom?: string | null): string | null;
  run(opts: AgentRunOptions): Promise<AgentResult>;
}

/** 스트림 파서가 내는 사건. 프로바이더 둘이 같은 모양으로 낸다. */
export type StreamEvent = { type: 'text'; text: string } | { type: 'tool'; name: string } | { type: 'done'; ok: boolean; error?: string };

export interface StreamParser {
  feed(line: string): StreamEvent[];
  readonly text: string;
  readonly toolCalls: number;
  readonly done: boolean;
}

/**
 * CLI 를 띄우고 stdout 을 줄 단위로 파서에 먹인다. 프롬프트는 stdin 으로.
 * Windows 의 .cmd 셈(npm 전역 설치)은 cmd.exe 를 거쳐야 돈다.
 */
export function runCli(
  bin: string,
  args: string[],
  input: string | null,
  parser: StreamParser,
  opts: Pick<AgentRunOptions, 'cwd' | 'signal' | 'onText' | 'onTool' | 'onLog'> & { env?: Record<string, string> },
): Promise<AgentResult> {
  return new Promise((resolve) => {
    // 트레이 앱엔 로그인 셸 PATH 가 없다 → node·codex·claude 가 있을 만한 곳을 붙인다
    const env = withKnownDirs({ ...process.env, ...opts.env });
    // 중첩 실행 가드: 이 엔진이 Claude Code 안에서 개발될 때 자식 claude 가 거부하지 않게
    delete env['CLAUDECODE'];
    delete env['CLAUDE_CODE_ENTRYPOINT'];
    let child: ChildProcess;
    try {
      child = spawnCli(bin, args, { cwd: opts.cwd, env });
    } catch (err) {
      resolve({ text: '', toolCalls: 0, ok: false, error: (err as Error).message });
      return;
    }
    let stderr = '';
    let buf = '';
    let settled = false;
    const finish = (r: AgentResult) => {
      if (settled) return;
      settled = true;
      opts.signal?.removeEventListener('abort', onAbort);
      resolve(r);
    };
    const onAbort = () => {
      child.kill('SIGKILL');
      finish({ text: parser.text, toolCalls: parser.toolCalls, ok: false, error: 'aborted' });
    };
    opts.signal?.addEventListener('abort', onAbort, { once: true });

    const handle = (line: string) => {
      const trimmed = line.trim();
      if (!trimmed) return;
      opts.onLog?.(trimmed);
      for (const ev of parser.feed(trimmed)) {
        if (ev.type === 'text') opts.onText(ev.text);
        else if (ev.type === 'tool') opts.onTool(ev.name);
      }
    };
    child.stdout?.setEncoding('utf8');
    child.stdout?.on('data', (d: string) => {
      buf += d;
      let i: number;
      while ((i = buf.indexOf('\n')) >= 0) {
        handle(buf.slice(0, i));
        buf = buf.slice(i + 1);
      }
    });
    child.stderr?.setEncoding('utf8');
    child.stderr?.on('data', (d: string) => {
      stderr += d;
      if (stderr.length > 32_000) stderr = stderr.slice(-16_000);
    });
    child.on('error', (err: NodeJS.ErrnoException) => {
      finish({ text: parser.text, toolCalls: parser.toolCalls, ok: false, error: err.code === 'ENOENT' ? 'not_installed' : err.message });
    });
    child.on('close', (code) => {
      if (buf.trim()) handle(buf);
      const parsed = parser.feed('');
      void parsed;
      const ok = code === 0 && !parserError(parser);
      finish({
        text: parser.text,
        toolCalls: parser.toolCalls,
        ok,
        ...(ok ? {} : { error: parserError(parser) ?? `exit ${code}: ${stderr.trim().slice(-400)}` }),
      });
    });
    if (input !== null) {
      child.stdin?.on('error', () => {});
      child.stdin?.end(input);
    } else {
      child.stdin?.end();
    }
  });
}

function parserError(p: StreamParser): string | null {
  return (p as { error?: string | null }).error ?? null;
}

export function spawnCli(bin: string, args: string[], opts: { cwd: string; env: NodeJS.ProcessEnv }): ChildProcess {
  if (process.platform === 'win32' && /\.(cmd|bat)$/i.test(bin)) {
    const cmd = process.env['ComSpec'] ?? 'cmd.exe';
    const line = [bin, ...args].map(quoteWin).join(' ');
    return spawn(cmd, ['/d', '/s', '/c', `"${line}"`], { cwd: opts.cwd, env: opts.env, stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true, windowsVerbatimArguments: true });
  }
  return spawn(bin, args, { cwd: opts.cwd, env: opts.env, stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true });
}

/** 윈도우 명령줄 한 조각 따옴표 씌우기 (cmd.exe 를 거쳐 갈 때). */
export function quoteWin(s: string): string {
  if (s === '') return '""';
  if (!/[\s"]/.test(s)) return s;
  return `"${s.replace(/(\\*)"/g, '$1$1\\"').replace(/(\\+)$/, '$1$1')}"`;
}
