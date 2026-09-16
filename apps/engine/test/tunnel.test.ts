import { EventEmitter } from 'node:events';
import { PassThrough } from 'node:stream';
import type { ChildProcess } from 'node:child_process';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { Tunnel } from '../src/tunnel.js';
import { quietLogger, tempHome } from './helpers.js';

/** cloudflared 흉내: 우리가 stdout 에 줄을 밀어 넣고 exit 을 낼 수 있는 가짜 자식 프로세스 */
function fakeChild() {
  const child = new EventEmitter() as ChildProcess & { stdout: PassThrough; stderr: PassThrough; killed: boolean };
  child.stdout = new PassThrough();
  child.stderr = new PassThrough();
  child.killed = false;
  child.kill = vi.fn(() => {
    child.killed = true;
    return true;
  }) as ChildProcess['kill'];
  return child;
}

let home: string;
let spawned: ReturnType<typeof fakeChild>[];
let tunnel: Tunnel;

beforeEach(() => {
  home = tempHome();
  spawned = [];
  vi.useFakeTimers();
  const spawnImpl = vi.fn(() => {
    const c = fakeChild();
    spawned.push(c);
    return c;
  });
  tunnel = new Tunnel('/fake/cloudflared', quietLogger(home), spawnImpl as never);
});
afterEach(() => {
  tunnel.stop();
  vi.useRealTimers();
});

describe('Tunnel', () => {
  it('토큰이 없으면 아무것도 안 띄운다', () => {
    tunnel.apply(null);
    tunnel.apply('   ');
    expect(spawned).toHaveLength(0);
    expect(tunnel.state.status).toBe('off');
  });

  it('토큰을 주면 띄우고, 등록 로그가 오면 running', () => {
    tunnel.apply('tok');
    expect(spawned).toHaveLength(1);
    expect(tunnel.state.status).toBe('starting');
    spawned[0]!.stderr.write('INF Registered tunnel connection connIndex=0\n');
    expect(tunnel.state.status).toBe('running');
  });

  it('죽으면 백오프로 다시 띄우고, 토큰 오류면 bad_token', () => {
    tunnel.apply('tok');
    spawned[0]!.stderr.write('ERR Unauthorized: Invalid tunnel token\n');
    spawned[0]!.emit('exit', 1);
    expect(tunnel.state).toEqual({ status: 'error', error: 'bad_token' });
    vi.advanceTimersByTime(2_000);
    expect(spawned).toHaveLength(2);
    spawned[1]!.emit('exit', 1);
    vi.advanceTimersByTime(3_999);
    expect(spawned).toHaveLength(2); // 4초 백오프 전
    vi.advanceTimersByTime(1);
    expect(spawned).toHaveLength(3);
  });

  it('같은 토큰이면 그대로, 바뀌면 내리고 다시, 없애면 내린다', () => {
    tunnel.apply('a');
    tunnel.apply('a');
    expect(spawned).toHaveLength(1);
    tunnel.apply('b');
    expect(spawned[0]!.kill).toHaveBeenCalled();
    expect(spawned).toHaveLength(2);
    tunnel.apply(null);
    expect(spawned[1]!.kill).toHaveBeenCalled();
    expect(tunnel.state.status).toBe('off');
    expect(spawned).toHaveLength(2);
  });

  it('stop 뒤에는 재시작하지 않는다', () => {
    tunnel.apply('a');
    tunnel.stop();
    spawned[0]!.emit('exit', 1);
    vi.advanceTimersByTime(60_000);
    expect(spawned).toHaveLength(1);
    expect(tunnel.state.status).toBe('off');
  });
});
