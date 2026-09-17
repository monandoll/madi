/**
 * AI 도구 찾기: 설치 위치는 PC 마다 다르다. 사용자가 직접 골라 준 파일을 먼저 보고,
 * 그 파일이 사라지면 다시 평소 자리들을 뒤진다. "다시 찾기"(fresh)는 캐시를 건너뛴다.
 */
import fs from 'node:fs';
import path from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { cliVersion, detectCli, findCli, resetCliCache } from '../src/agent/detect.js';
import { exeName, fakeCli, tempHome } from './helpers.js';

let home: string;
const FAKE = fakeCli('claude');

beforeEach(() => {
  home = tempHome('madi-detect-');
  resetCliCache();
  delete process.env['MADI_CLAUDE_BIN'];
  delete process.env['MADI_CODEX_BIN'];
});
afterEach(() => {
  resetCliCache();
  fs.rmSync(home, { recursive: true, force: true });
});

describe('findCli', () => {
  it('직접 골라 준 파일이 있으면 그것부터 쓴다', () => {
    expect(findCli('claude', FAKE)).toBe(FAKE);
  });

  it('직접 고른 파일이 없어졌으면 평소 자리에서 다시 찾는다 (여기선 못 찾음)', () => {
    expect(findCli('claude', path.join(home, '없는-파일'))).not.toBe(path.join(home, '없는-파일'));
  });

  it('폴더를 골라 줬으면 무시한다', () => {
    expect(findCli('claude', home)).not.toBe(home);
  });

  it('환경변수가 직접 고른 파일보다 우선한다 (개발·테스트용)', () => {
    process.env['MADI_CLAUDE_BIN'] = FAKE;
    expect(findCli('claude', '/다른/경로')).toBe(FAKE);
    process.env['MADI_CLAUDE_BIN'] = '/없는/경로';
    expect(findCli('claude', FAKE)).toBeNull();
  });
});

describe('cliVersion', () => {
  it('진짜 도는 파일이면 버전을 돌려준다', async () => {
    expect(await cliVersion(FAKE)).not.toBeNull();
  });

  it('아무 파일이나 고르면 null (그 파일로는 안 된다고 말해 줄 수 있게)', async () => {
    const notCli = path.join(home, '메모.txt');
    fs.writeFileSync(notCli, '이건 도구가 아니다');
    expect(await cliVersion(notCli)).toBeNull();
    expect(await cliVersion(path.join(home, '아예-없음'))).toBeNull();
  });
});

describe('detectCli', () => {
  it('직접 고른 파일로 찾으면 custom 이 켜진다', async () => {
    const info = await detectCli('claude', { custom: FAKE });
    expect(info).toMatchObject({ installed: true, path: FAKE, custom: true });
    expect(info.version).not.toBeNull();
  });

  it('고른 경로마다 따로 센다 (한쪽 결과가 다른 쪽을 가리지 않게)', async () => {
    const bad = path.join(home, '아님');
    fs.writeFileSync(bad, '이건 도구가 아니다');
    const wrong = await detectCli('claude', { custom: bad });
    expect(wrong).toMatchObject({ path: bad, custom: true, installed: false });
    const right = await detectCli('claude', { custom: FAKE });
    expect(right).toMatchObject({ path: FAKE, custom: true, installed: true });
  });

  it('fresh 면 캐시를 버리고 처음부터 다시 찾는다 (다시 찾기 버튼)', async () => {
    const later = path.join(home, exeName('claude-나중에'));
    // 아직 없으니 직접 고른 파일로는 못 잡는다 (평소 자리로 넘어간다)
    expect((await detectCli('claude', { custom: later })).custom).toBe(false);
    fs.copyFileSync(FAKE, later);
    fs.chmodSync(later, 0o755);
    // 캐시를 그대로 보면 아직 못 본 상태
    expect((await detectCli('claude', { custom: later })).custom).toBe(false);
    // 다시 찾기
    expect(await detectCli('claude', { custom: later, fresh: true })).toMatchObject({ path: later, custom: true, installed: true });
  });
});
