import { spawn } from 'node:child_process';

export interface RunOptions {
  signal?: AbortSignal | undefined;
  onStdout?: (chunk: string) => void;
  /** 분석 데이터는 이 스트림으로 받는다. 반환 stderr는 오류 표시용 꼬리다. */
  onStderr?: (chunk: string) => void;
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
      opts.onStderr?.(d);
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

/** ffmpeg 분석 기록만 스트리밍 수집한다. 진단 로그의 크기 제한과 분리한다. */
export async function runAnalysis(bin: string, args: string[], opts: RunOptions = {}): Promise<RunResult> {
  const records: string[] = [];
  let pending = '';
  const keep = (line: string) => {
    if (/silence_(?:start|end):|pts_time:|lavfi\.signalstats\.YDIF=/.test(line)) records.push(line);
  };
  const result = await run(bin, args, { ...opts, onStderr: (chunk) => {
    opts.onStderr?.(chunk);
    const lines = (pending + chunk).split(/\r\n|\n|\r/);
    pending = lines.pop() ?? '';
    for (const line of lines) keep(line);
  } });
  if (pending) keep(pending);
  return { stdout: result.stdout, stderr: records.join('\n') };
}
