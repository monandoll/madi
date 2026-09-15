import { describe, expect, it } from 'vitest';
import { Video, isVideoFile, kindFromDuration, titleFromFileName } from './video.js';
import { JobPayload } from './job.js';
import { WsEvent } from './ws.js';

describe('video helpers', () => {
  it('60초 이하는 short, 넘으면 long', () => {
    expect(kindFromDuration(59.9)).toBe('short');
    expect(kindFromDuration(60)).toBe('short');
    expect(kindFromDuration(60.1)).toBe('long');
  });

  it('확장자 대소문자 무관하게 영상 파일을 판정한다', () => {
    expect(isVideoFile('a.MP4')).toBe(true);
    expect(isVideoFile('a.mov')).toBe(true);
    expect(isVideoFile('a.txt')).toBe(false);
    expect(isVideoFile('.DS_Store')).toBe(false);
  });

  it('제목은 파일명에서 확장자를 뗀 것', () => {
    expect(titleFromFileName('햄스트링 풀버전.mp4')).toBe('햄스트링 풀버전');
    expect(titleFromFileName('no-ext')).toBe('no-ext');
  });

  it('Video 스키마는 null 메타를 허용한다 (probe 전)', () => {
    const now = Date.now();
    const parsed = Video.safeParse({
      id: 'v1',
      path: '/x/a.mp4',
      fileName: 'a.mp4',
      title: 'a',
      kind: 'long',
      status: 'registered',
      durationSec: null,
      width: null,
      height: null,
      fps: null,
      hasAudio: null,
      sizeBytes: 10,
      recordedAt: now,
      createdAt: now,
      updatedAt: now,
      error: null,
    });
    expect(parsed.success).toBe(true);
  });
});

describe('job payload', () => {
  it('render는 editId가 필요하다', () => {
    expect(JobPayload.safeParse({ type: 'render', videoId: 'v' }).success).toBe(false);
    expect(JobPayload.safeParse({ type: 'render', videoId: 'v', editId: 'e' }).success).toBe(true);
  });
});

describe('ws events', () => {
  it('모르는 타입은 거부한다', () => {
    expect(WsEvent.safeParse({ type: 'nope' }).success).toBe(false);
    expect(WsEvent.safeParse({ type: 'video.removed', videoId: 'v' }).success).toBe(true);
  });
});
