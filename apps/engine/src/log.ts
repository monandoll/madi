import path from 'node:path';
import pino, { type Logger } from 'pino';

/** 로그는 ~/.madi/logs/engine.log. 개발 중엔 stdout에도 사람이 읽기 좋게. */
export function createLogger(logsDir: string, isDev: boolean): Logger {
  const streams: pino.StreamEntry[] = [
    { level: 'info', stream: pino.destination({ dest: path.join(logsDir, 'engine.log'), mkdir: true, sync: true }) },
  ];
  if (isDev && process.env['MADI_QUIET'] !== '1') {
    streams.push({ level: 'debug', stream: process.stdout });
  }
  return pino({ level: 'debug', base: null }, pino.multistream(streams));
}

export type { Logger };
