import { describe, expect, it } from 'vitest';
import { DEFAULT_SUBTITLE_STYLE } from '@madi/shared';
import { parseSilences, silenceDetectArgs, silencesToCuts } from './silence.js';
import { assColor, buildAss, escapeFilterPath, renderPlan } from './render.js';

it('두 자막의 모양과 간격을 분리하고 조각 재배치·반복 후에도 같은 시각에 표시한다', () => {
  const ass = buildAss([{ id: 'a', start: 0, end: 1, text: '첫 문구', secondaryText: 'First caption', words: [] }, { id: 'b', start: 1, end: 2, text: '둘째 문구', secondaryText: 'Second caption', words: [] }], [{ start: 1, end: 2 }, { start: 0, end: 1 }, { start: 1, end: 2 }], { ...DEFAULT_SUBTITLE_STYLE, background: 'outline', color: '#FFFFFF', outlineColor: '#000000', outlineWidth: 2, bottom: 0.4, secondaryColor: '#FFFF00', secondaryScale: 0.5, secondaryItalic: true }, { width: 1080, height: 1920 });
  expect(ass).toContain('Style: Secondary,Pretendard,28,&H0000FFFF&');
  expect(ass).toContain('100,100,0,0,1,2,0,2');
  expect(ass).toContain('0:00:00.00,0:00:01.00,Secondary,,0,0,0,,Second caption');
  expect(ass).toContain('0:00:01.00,0:00:02.00,Secondary,,0,0,0,,First caption');
  expect(ass).toContain('0:00:02.00,0:00:03.00,Secondary,,0,0,0,,Second caption');
  const primary = ass.split('\n').find((l) => l.startsWith('Dialogue:') && l.includes('Madi'))!;
  expect(Number(primary.split(',')[7])).toBeGreaterThan(768);
});

describe('silence', () => {
  it('args 는 오디오만 훑는다', () => {
    const a = silenceDetectArgs('in.mp4');
    expect(a).toContain('-vn');
    expect(a.join(' ')).toContain('silencedetect=noise=-35dB:d=0.7');
  });
  it('stderr 를 구간으로 파싱하고, 안 끝난 구간은 끝까지', () => {
    const err = [
      '[silencedetect @ 0x1] silence_start: 1.5',
      '[silencedetect @ 0x1] silence_end: 3.25 | silence_duration: 1.75',
      '[silencedetect @ 0x1] silence_start: 9',
    ].join('\n');
    expect(parseSilences(err, 10)).toEqual([
      { start: 1.5, end: 3.25 },
      { start: 9, end: 10 },
    ]);
  });
  it('컷은 앞뒤 숨을 남기고, 맨 앞·뒤는 끝까지 잘라낸다', () => {
    const cuts = silencesToCuts(
      [
        { start: 0, end: 1 },
        { start: 4, end: 6 },
        { start: 9.5, end: 10 },
        { start: 7, end: 7.4 },
      ],
      10,
    );
    expect(cuts).toEqual([
      { start: 0, end: 0.8, reason: 'silence' },
      { start: 4.2, end: 5.8, reason: 'silence' },
      { start: 9.7, end: 10, reason: 'silence' },
    ]);
  });
});

describe('renderPlan', () => {
  const base = { input: 'in.mp4', output: 'out.mp4', durationSec: 10, width: 1920, height: 1080, hasAudio: true, encoder: 'libx264' as const };
  it('컷을 빼고 이어붙인다', () => {
    const plan = renderPlan({ ...base, edit: { keep: null, cuts: [{ start: 2, end: 3, reason: 'silence' }], crop: 'none', subtitles: false, subtitleStyle: DEFAULT_SUBTITLE_STYLE } });
    const fc = plan.args[plan.args.indexOf('-filter_complex') + 1]!;
    expect(fc).toContain('trim=start=0.000:end=2.000');
    expect(fc).toContain('trim=start=3.000:end=10.000');
    expect(fc).toContain('concat=n=2:v=1:a=1');
    expect(plan.durationSec).toBe(9);
    expect(plan.width).toBe(1920);
    expect(plan.args).toContain('-c:a');
  });
  it('세로 변환은 가운데 크롭 후 1080x1920, 무음이면 -an', () => {
    const plan = renderPlan({ ...base, hasAudio: false, edit: { keep: { start: 1, end: 4 }, cuts: [], crop: 'vertical', subtitles: false, subtitleStyle: DEFAULT_SUBTITLE_STYLE } });
    const fc = plan.args[plan.args.indexOf('-filter_complex') + 1]!;
    expect(fc).toContain('crop=');
    expect(fc).toContain('scale=1080:1920');
    expect(fc).toContain('concat=n=1:v=1:a=0');
    expect(plan.args).toContain('-an');
    expect(plan.width).toBe(1080);
    expect(plan.durationSec).toBe(3);
  });
  it('세로 초점: 0.5 면 가운데, 1 이면 오른쪽 끝을 잡는다', () => {
    const at = (focus: number | null) => {
      const plan = renderPlan({ ...base, edit: { keep: null, cuts: [], crop: 'vertical', cropFocus: focus, subtitles: false, subtitleStyle: DEFAULT_SUBTITLE_STYLE } });
      return plan.args[plan.args.indexOf('-filter_complex') + 1]!;
    };
    expect(at(null)).toContain("x='(iw-min(iw,ih*9/16))*0.500'");
    expect(at(1)).toContain("x='(iw-min(iw,ih*9/16))*1.000'");
    expect(at(0)).toContain("*0.000'");
  });
  it('조각(parts)은 준 순서대로 이어 붙인다 — 시범을 먼저, 설명을 뒤에', () => {
    const plan = renderPlan({ ...base, edit: { keep: null, parts: [{ start: 6, end: 9 }, { start: 1, end: 3 }], cuts: [{ start: 7, end: 7.5, reason: 'ai' }], crop: 'none', subtitles: false, subtitleStyle: DEFAULT_SUBTITLE_STYLE } });
    const fc = plan.args[plan.args.indexOf('-filter_complex') + 1]!;
    expect(fc.indexOf('trim=start=6.000:end=7.000')).toBeLessThan(fc.indexOf('trim=start=1.000:end=3.000'));
    expect(fc).toContain('concat=n=3:v=1:a=1');
    expect(plan.durationSec).toBe(4.5);
    expect(plan.segments).toEqual([
      { start: 6, end: 7 },
      { start: 7.5, end: 9 },
      { start: 1, end: 3 },
    ]);
  });
  it('자막 파일 경로를 이스케이프해서 subtitles 필터에 넣는다', () => {
    const plan = renderPlan({ ...base, subtitleFile: 'C:\\madi\\a:b.ass', edit: { keep: null, cuts: [], crop: 'none', subtitles: true, subtitleStyle: DEFAULT_SUBTITLE_STYLE } });
    const fc = plan.args[plan.args.indexOf('-filter_complex') + 1]!;
    expect(fc).toContain("subtitles='C\\:/madi/a\\:b.ass'");
    expect(escapeFilterPath("/tmp/it's.ass")).toBe("/tmp/it\\'s.ass");
    const withFonts = renderPlan({ ...base, subtitleFile: '/a.ass', fontsDir: '/app/fonts', edit: { keep: null, cuts: [], crop: 'none', subtitles: true, subtitleStyle: DEFAULT_SUBTITLE_STYLE } });
    expect(withFonts.args[withFonts.args.indexOf('-filter_complex') + 1]).toContain("subtitles='/a.ass':fontsdir='/app/fonts'");
  });
  it('남는 구간이 없으면 던진다', () => {
    expect(() => renderPlan({ ...base, edit: { keep: { start: 20, end: 30 }, cuts: [], crop: 'none', subtitles: false, subtitleStyle: DEFAULT_SUBTITLE_STYLE } })).toThrow('nothing to render');
  });
});

describe('buildAss', () => {
  it('색은 &HAABBGGRR&', () => {
    expect(assColor('#E8C33F')).toBe('&H003FC3E8&');
    expect(assColor('#2B2622')).toBe('&H0022262B&');
  });
  it('잘린 단어는 빼고 시각을 옮긴다', () => {
    const ass = buildAss(
      [
        {
          id: 's1',
          start: 0,
          end: 4,
          text: '허리를 굽히지 말고 골반부터',
          words: [
            { start: 0, end: 1, text: '허리를', p: null },
            { start: 1, end: 2, text: '굽히지', p: null },
            { start: 2, end: 3, text: '말고', p: null },
            { start: 3, end: 4, text: '골반부터', p: null },
          ],
        },
      ],
      [
        { start: 0, end: 2 },
        { start: 3, end: 4 },
      ],
      DEFAULT_SUBTITLE_STYLE,
      { width: 1080, height: 1920 },
    );
    expect(ass).toContain('BorderStyle');
    expect(ass).toContain('Dialogue: 0,0:00:00.00,0:00:02.00,Madi,,0,0,0,,허리를 굽히지');
    expect(ass).toContain('Dialogue: 0,0:00:02.00,0:00:03.00,Madi,,0,0,0,,골반부터');
    expect(ass).not.toContain('말고');
  });

  it('강조 단어는 그 구간에서만 색 · 크기 태그로 감싼다 (기획안 §6 예시 2)', () => {
    const seg = {
      id: 's1',
      start: 0,
      end: 4,
      text: '골반부터 접고 골반을 세우고',
      words: [
        { start: 0, end: 1, text: '골반부터', p: null },
        { start: 1, end: 2, text: '접고', p: null },
        { start: 2, end: 3, text: '골반을', p: null },
        { start: 3, end: 4, text: '세우고', p: null },
      ],
    };
    const ass = buildAss([seg], [{ start: 0, end: 4 }], DEFAULT_SUBTITLE_STYLE, { width: 1080, height: 1920 }, [{ term: '골반', start: 0, end: 1.5 }]);
    const tag = `{\\c${assColor(DEFAULT_SUBTITLE_STYLE.emphasisColor)}\\fs${Math.round(DEFAULT_SUBTITLE_STYLE.fontSize * 1.15)}}`;
    expect(ass).toContain(`,,${tag}골반{\\r}부터 접고 골반을 세우고`);
    // 문장 하나짜리(직접 쓴 자막)도 안에서 단어를 찾는다
    const manual = buildAss([{ id: 'm', start: 0, end: 2, text: '무릎을 펴고', words: [] }], [{ start: 0, end: 2 }], DEFAULT_SUBTITLE_STYLE, { width: 1080, height: 1920 }, [{ term: '무릎', start: null, end: null }]);
    expect(manual).toContain(`,,${tag}무릎{\\r}을 펴고`);
  });
});
