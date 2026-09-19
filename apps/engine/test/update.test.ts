/**
 * 새 버전 상태 — 순수 상태 기계. 훅이 없으면(브라우저만) 확인 · 설치가 안 되고, 받아 둔 뒤에만 설치가 된다.
 */
import { describe, expect, it, vi } from 'vitest';
import { UpdateStatus } from '../src/update.js';

describe('UpdateStatus', () => {
  it('처음엔 최신이고, 훅이 없으면 확인 · 설치가 false', async () => {
    const u = new UpdateStatus('0.2.19');
    expect(u.state).toMatchObject({ current: '0.2.19', available: null, downloaded: false, canInstall: false, checking: false });
    expect(await u.check()).toBe(false);
    expect(u.install()).toBe(false);
  });

  it('electron-updater 이벤트 순서대로: 확인 중 → 있음 → 받음 → 설치', async () => {
    const u = new UpdateStatus('0.2.19');
    const install = vi.fn();
    const check = vi.fn(async () => undefined);
    const seen: string[] = [];
    u.on('update.changed', (s) => seen.push(`${s.checking ? 'c' : '-'}${s.available ?? ''}${s.downloaded ? '!' : ''}${s.canInstall ? '+' : ''}`));
    u.setHooks({ check, install });
    expect(await u.check()).toBe(true);
    expect(check).toHaveBeenCalledOnce();
    u.available('0.2.20');
    expect(u.state).toMatchObject({ available: '0.2.20', downloaded: false, canInstall: false });
    expect(u.install()).toBe(false); // 아직 안 받았다
    u.downloaded('0.2.20');
    expect(u.state.canInstall).toBe(true);
    expect(u.install()).toBe(true);
    expect(install).toHaveBeenCalledOnce();
    expect(seen).toEqual(['-', 'c', '-0.2.20', '-0.2.20!+']); // 확인 훅이 끝나도 "있음/없음" 이벤트가 올 때까지 checking
  });

  it('없음 · 오류는 그렇게 적히고, 확인 훅이 던지면 오류로 남는다', async () => {
    const u = new UpdateStatus('0.2.19');
    u.available('0.2.20');
    u.notAvailable();
    expect(u.state.available).toBeNull();
    u.failed('x'.repeat(300));
    expect(u.state.error).toHaveLength(200);
    u.setHooks({
      check: async () => {
        throw new Error('offline');
      },
      install: () => undefined,
    });
    await u.check();
    expect(u.state).toMatchObject({ checking: false, error: 'offline' });
  });
});
