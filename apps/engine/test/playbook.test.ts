/**
 * 제작 지침: 에이전트가 "어디를 자를지" 판단할 근거가 컨텍스트에 실제로 들어가는지.
 * 문구 자체를 통째로 고정하지는 않는다 (다듬을 여지를 둔다). 빠지면 안 되는 기준만 확인한다.
 */
import { describe, expect, it } from 'vitest';
import { FORMATS, formatLine, formatOf, playbook } from '../src/agent/playbook.js';

describe('formatOf', () => {
  it('짧으면 릴스, 길면 롱폼', () => {
    expect(formatOf({ durationSec: 35 })).toBe('reels');
    expect(formatOf({ durationSec: 90 })).toBe('reels');
    expect(formatOf({ durationSec: 91 })).toBe('long');
    expect(formatOf({ durationSec: 600 })).toBe('long');
  });

  it('세로로 찍은 짧은 원본은 이미 숏폼 소재', () => {
    expect(formatOf({ durationSec: 40, width: 1080, height: 1920 })).toBe('reels');
  });

  it('길이를 모르면 릴스로 본다 (짧은 쪽이 안전하다)', () => {
    expect(formatOf({})).toBe('reels');
  });
});

describe('formatLine', () => {
  it('비율과 목표 길이를 한 줄로', () => {
    expect(formatLine('reels')).toContain('9:16');
    expect(formatLine('reels')).toContain('20~45초');
    expect(formatLine('long')).toContain('16:9');
  });

  it('릴스는 60초를 넘지 않는다', () => {
    expect(FORMATS.reels.hardMaxSec).toBeLessThanOrEqual(60);
    expect(FORMATS.short.hardMaxSec).toBeLessThanOrEqual(60);
  });
});

describe('playbook', () => {
  const reels = playbook({ format: 'reels', hasAudio: true });
  const long = playbook({ format: 'long', hasAudio: true });

  it('숏폼에서 결과를 가르는 기준이 들어 있다', () => {
    for (const must of ['첫 1.5초', '도입부는 버린다', '안녕하세요', '한 클립 = 한 동작', '문장 중간에서 시작하거나 끝내지 않는다', '마무리 문장']) {
      expect(reels).toContain(must);
    }
  });

  it('운동·재활에서 절대 자르면 안 되는 것을 짚어 준다', () => {
    expect(reels).toContain('운동 이름 · 횟수 · 주의사항');
  });

  it('챕터 지침은 롱폼에만 (읽을 게 적을수록 잘 따른다)', () => {
    expect(long).toContain('## 롱폼 · 챕터');
    expect(long).toContain('실제로 한 말');
    expect(reels).not.toContain('## 롱폼 · 챕터');
  });

  it('자막은 릴스 UI 에 가리지 않게', () => {
    expect(reels).toContain('0.18~0.22');
    expect(reels).toContain('set_subtitle_text');
  });

  it('소리가 없으면 자막 지침 대신 그 사정을 알려 준다', () => {
    const silent = playbook({ format: 'reels', hasAudio: false });
    expect(silent).toContain('소리가 없다');
    expect(silent).not.toContain('12~16자');
  });

  it('되묻지 말고 만들어서 보여 주라고 한다', () => {
    expect(reels).toContain('되묻지 말고');
  });
});
