import { describe, expect, it } from 'vitest';
import { formatDate, formatDuration } from './format.js';

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
