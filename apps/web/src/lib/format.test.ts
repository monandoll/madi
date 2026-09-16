import { describe, expect, it } from 'vitest';
import { formatClock, formatDate, formatDuration, parseClock } from './format.js';

describe('formatDuration', () => {
  it('분:초', () => {
    expect(formatDuration(1104)).toBe('18:24');
    expect(formatDuration(72)).toBe('1:12');
    expect(formatDuration(5.4)).toBe('0:05');
  });
  it('시간이 있으면 시:분:초', () => {
    expect(formatDuration(3723)).toBe('1:02:03');
  });
  it('없으면 빈 문자열', () => {
    expect(formatDuration(null)).toBe('');
  });
});

describe('formatDate', () => {
  it('같은 해면 월 일만', () => {
    const now = new Date(2025, 8, 15);
    expect(formatDate(new Date(2025, 8, 14).getTime(), now)).toBe('9월 14일');
  });
  it('다른 해면 연도 붙임', () => {
    const now = new Date(2026, 0, 1);
    expect(formatDate(new Date(2025, 8, 14).getTime(), now)).toBe('2025년 9월 14일');
  });
});

describe('parseClock / formatClock (자막 직접 쓰기)', () => {
  it('초 · 분:초 · 시:분:초, 소수점', () => {
    expect(parseClock('3')).toBe(3);
    expect(parseClock('3.5')).toBe(3.5);
    expect(parseClock('0:03')).toBe(3);
    expect(parseClock('1:02.5')).toBe(62.5);
    expect(parseClock('1:02:03')).toBe(3723);
    expect(parseClock(' 12 ')).toBe(12);
  });
  it('이상한 값은 null', () => {
    expect(parseClock('')).toBeNull();
    expect(parseClock('abc')).toBeNull();
    expect(parseClock('1:2:3:4')).toBeNull();
    expect(parseClock('-1')).toBeNull();
  });
  it('formatClock 은 parseClock 과 짝', () => {
    expect(formatClock(3)).toBe('0:03');
    expect(formatClock(62.5)).toBe('1:02.5');
    expect(formatClock(0)).toBe('0:00');
    for (const v of [0, 3, 3.5, 62.5, 125]) expect(parseClock(formatClock(v))).toBe(v);
  });
});
