import { spawn } from 'node:child_process';

export interface RunOptions {
  signal?: AbortSignal | undefined;
  onStdout?: (chunk: string) => void;
  /** stderr 마지막 N자를 오류 메시지에 붙인다 */
  stderrTail?: number;
  /** 환경 변수 (없으면 상속) */
  env?: NodeJS.ProcessEnv | undefined;
}

export interface RunResult {
  stdout: string;
  stderr: string;
}

export class SpawnError extends Error {
  constructor(
    message: string,
    readonly code: number | null,
    readonly stderr: string,
  ) {
    super(message);
  }
}

/** 바이너리 하나 실행. 인자는 배열로만 (셸 없음). */
export function run(bin: string, args: string[], opts: RunOptions = {}): Promise<RunResult> {
  return new Promise((resolve, reject) => {
    const child = spawn(bin, args, { stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true, ...(opts.env ? { env: opts.env } : {}) });
    let stdout = '';
    let stderr = '';
    child.stdout.setEncoding('utf8');
    child.stderr.setEncoding('utf8');
    child.stdout.on('data', (d: string) => {
      stdout += d;
      opts.onStdout?.(d);
    });
    child.stderr.on('data', (d: string) => {
      stderr += d;
      if (stderr.length > 64_000) stderr = stderr.slice(-32_000);
    });
    const onAbort = () => child.kill('SIGKILL');
    opts.signal?.addEventListener('abort', onAbort, { once: true });
    child.on('error', (err) => {
      opts.signal?.removeEventListener('abort', onAbort);
      reject(new SpawnError(`${bin}: ${err.message}`, null, stderr));
    });
    child.on('close', (code) => {
      opts.signal?.removeEventListener('abort', onAbort);
      if (code === 0) resolve({ stdout, stderr });
      else {
        const tail = stderr.trim().slice(-(opts.stderrTail ?? 400));
        reject(new SpawnError(`${bin} exited ${code}${tail ? `: ${tail}` : ''}`, code, stderr));
      }
    });
  });
}
