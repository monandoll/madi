import type { AppUpdater } from 'electron-updater';
import { describe, expect, it } from 'vitest';
import { resolveAutoUpdater } from '../src/main/updater.js';

describe('electron-updater 모듈 로딩', () => {
  const updater = {} as AppUpdater;

  it('named export 로 노출된 autoUpdater 를 쓴다', () => {
    expect(resolveAutoUpdater({ autoUpdater: updater })).toBe(updater);
  });

  it('CommonJS 동적 import 의 default.autoUpdater 를 쓴다', () => {
    expect(resolveAutoUpdater({ default: { autoUpdater: updater } })).toBe(updater);
  });

  it('어느 쪽에도 autoUpdater 가 없으면 조용히 넘어가지 않는다', () => {
    expect(() => resolveAutoUpdater({ default: {} })).toThrow('electron-updater did not expose autoUpdater');
  });
});
