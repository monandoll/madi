import fs from 'node:fs';
import path from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { isDirectRequest, isLoopback, makePin, MAX_PIN_TRIES, readCookie, RemoteAuth } from '../src/remote.js';
import { tempHome } from './helpers.js';

let home: string;
let file: string;

beforeEach(() => {
  home = tempHome('madi-remote-');
  file = path.join(home, 'pairs.json');
});
afterEach(() => {
  fs.rmSync(home, { recursive: true, force: true });
});

describe('isLoopback', () => {
  it('127.x · ::1 · IPv6 매핑은 이 PC', () => {
    expect(isLoopback('127.0.0.1')).toBe(true);
    expect(isLoopback('127.0.0.53')).toBe(true);
    expect(isLoopback('::1')).toBe(true);
    expect(isLoopback('::ffff:127.0.0.1')).toBe(true);
  });
  it('밖의 주소와 빈 값은 아니다', () => {
    expect(isLoopback('192.168.0.5')).toBe(false);
    expect(isLoopback('1.2.3.4')).toBe(false);
    expect(isLoopback(undefined)).toBe(false);
  });
});

describe('isDirectRequest', () => {
  it('루프백이고 터널 흔적이 없으면 이 PC 에서 직접 연 것', () => {
    expect(isDirectRequest('127.0.0.1', { host: 'localhost:41520' })).toBe(true);
  });

  it('cloudflared 가 붙인 헤더가 하나라도 있으면 밖에서 온 것', () => {
    expect(isDirectRequest('127.0.0.1', { 'cf-connecting-ip': '203.0.113.9' })).toBe(false);
    expect(isDirectRequest('127.0.0.1', { 'cf-ray': 'abc-ICN' })).toBe(false);
    expect(isDirectRequest('127.0.0.1', { 'x-forwarded-for': '203.0.113.9' })).toBe(false);
    expect(isDirectRequest('127.0.0.1', { 'x-forwarded-host': 'odd-words.trycloudflare.com' })).toBe(false);
    expect(isDirectRequest('127.0.0.1', { 'x-real-ip': '203.0.113.9' })).toBe(false);
    expect(isDirectRequest('127.0.0.1', { forwarded: 'for=203.0.113.9' })).toBe(false);
    expect(isDirectRequest('127.0.0.1', { 'x-forwarded-for': ['203.0.113.9'] })).toBe(false);
  });

  it('빈 헤더 값은 흔적으로 치지 않는다', () => {
    expect(isDirectRequest('127.0.0.1', { 'x-forwarded-for': '  ', 'cf-ray': undefined })).toBe(true);
  });

  it('루프백이 아니면 헤더가 깨끗해도 아니다 (랜에서 들어온 경우)', () => {
    expect(isDirectRequest('192.168.0.7', {})).toBe(false);
  });
});

describe('makePin', () => {
  it('언제나 여섯 자리 숫자', () => {
    for (let i = 0; i < 200; i++) expect(makePin()).toMatch(/^\d{6}$/);
  });
});

describe('RemoteAuth', () => {
  it('숫자가 맞으면 표를 주고, 그 표는 통과한다', () => {
    const auth = new RemoteAuth(file);
    expect(auth.deviceCount).toBe(0);
    const token = auth.pair(auth.currentPin);
    expect(token).toBeTruthy();
    expect(auth.has(token!)).toBe(true);
    expect(auth.deviceCount).toBe(1);
  });

  it('틀린 숫자는 표가 없고, 모르는 표는 통과하지 못한다', () => {
    const auth = new RemoteAuth(file);
    const wrong = auth.currentPin === '000000' ? '111111' : '000000';
    expect(auth.pair(wrong)).toBeNull();
    expect(auth.deviceCount).toBe(0);
    expect(auth.has('아무거나')).toBe(false);
    expect(auth.has(undefined)).toBe(false);
    expect(auth.has('')).toBe(false);
  });

  it('앞뒤 공백은 넘어간다 (폰 자동완성)', () => {
    const auth = new RemoteAuth(file);
    expect(auth.pair(` ${auth.currentPin} `)).toBeTruthy();
  });

  it('열 번 틀리면 숫자가 바뀐다 (찍어서 맞히기 방지)', () => {
    const auth = new RemoteAuth(file);
    const first = auth.currentPin;
    const wrong = first === '000000' ? '111111' : '000000';
    for (let i = 0; i < MAX_PIN_TRIES - 1; i++) expect(auth.pair(wrong)).toBeNull();
    expect(auth.currentPin).toBe(first);
    expect(auth.pair(wrong)).toBeNull();
    expect(auth.currentPin).not.toBe(first);
    // 바뀐 숫자로는 여전히 짝지을 수 있다
    expect(auth.pair(auth.currentPin)).toBeTruthy();
  });

  it('맞히면 실패 횟수가 초기화된다', () => {
    const auth = new RemoteAuth(file);
    const first = auth.currentPin;
    const wrong = first === '000000' ? '111111' : '000000';
    for (let i = 0; i < MAX_PIN_TRIES - 1; i++) auth.pair(wrong);
    expect(auth.pair(first)).toBeTruthy();
    for (let i = 0; i < MAX_PIN_TRIES - 1; i++) auth.pair(wrong);
    expect(auth.currentPin).toBe(first);
  });

  it('짝지은 기기는 파일에 남아 다시 켜도 기억한다', () => {
    const auth = new RemoteAuth(file);
    const token = auth.pair(auth.currentPin)!;
    expect(fs.existsSync(file)).toBe(true);
    const again = new RemoteAuth(file);
    expect(again.has(token)).toBe(true);
    expect(again.deviceCount).toBe(1);
    // 숫자는 켤 때마다 새로 만든다 (파일에 없다)
    expect(fs.readFileSync(file, 'utf8')).not.toContain(auth.currentPin);
  });

  it('밖에서 접속을 끄면 기억한 기기가 전부 끊긴다', () => {
    const auth = new RemoteAuth(file);
    const token = auth.pair(auth.currentPin)!;
    const before = auth.currentPin;
    auth.forgetAll();
    expect(auth.has(token)).toBe(false);
    expect(auth.deviceCount).toBe(0);
    expect(auth.currentPin).not.toBe(before);
    expect(new RemoteAuth(file).has(token)).toBe(false);
  });

  it('망가진 파일이어도 기동한다', () => {
    fs.writeFileSync(file, '{ 이건 JSON 이 아니다');
    const auth = new RemoteAuth(file);
    expect(auth.deviceCount).toBe(0);
    expect(auth.pair(auth.currentPin)).toBeTruthy();
  });
});

describe('readCookie', () => {
  it('여러 쿠키 중 이름이 맞는 값만 꺼낸다', () => {
    expect(readCookie('a=1; madi_pair=tok-123; b=2', 'madi_pair')).toBe('tok-123');
    expect(readCookie('madi_pair=tok-123', 'madi_pair')).toBe('tok-123');
    expect(readCookie('a=1', 'madi_pair')).toBeUndefined();
    expect(readCookie(undefined, 'madi_pair')).toBeUndefined();
    expect(readCookie('madi_pair_other=x', 'madi_pair')).toBeUndefined();
  });
  it('퍼센트 인코딩을 푼다', () => {
    expect(readCookie('madi_pair=a%20b', 'madi_pair')).toBe('a b');
  });
});
