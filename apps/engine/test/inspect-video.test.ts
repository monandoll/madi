import { expect, it } from 'vitest';
import { Edit, DEFAULT_SUBTITLE_STYLE, VideoFramesRequest } from '@madi/shared';
import { inspectionSamples } from '../src/workers/inspect-video.js';

const edit = Edit.parse({ id: 'e', videoId: 'v', title: '', createdAt: 0, keep: null, parts: [{ start: 20, end: 30 }, { start: 0, end: 10 }], cuts: [{ start: 2, end: 5, reason: 'manual' }], crop: 'vertical', subtitles: false, transcriptId: null, subtitleStyle: DEFAULT_SUBTITLE_STYLE, speed: [] });

it('samples the selected edit in output order and never samples discarded footage', () => {
  const samples = inspectionSamples(40, edit, VideoFramesRequest.parse({ count: 16 }));
  expect(samples[0]!.sourceTime).toBeCloseTo(20.05);
  expect(samples.at(-1)!.sourceTime).toBeCloseTo(9.95);
  expect(samples.at(-1)!.outputTime).toBeCloseTo(16.95);
  expect(samples.every(s => (s.sourceTime >= 20 && s.sourceTime < 30) || (s.sourceTime >= 0 && s.sourceTime < 2) || (s.sourceTime >= 5 && s.sourceTime < 10))).toBe(true);
  expect(samples.map(s => s.outputTime)).toEqual(samples.map(s => s.outputTime).sort((a, b) => a - b));
});

it('supports a dense follow-up look with original timestamps and correct output offsets', () => {
  const samples = inspectionSamples(40, edit, VideoFramesRequest.parse({ range: { start: 5, end: 6 }, count: 8 }));
  expect(samples).toHaveLength(8);
  expect(samples[0]).toEqual({ sourceTime: 5.05, outputTime: 12.05 });
  expect(samples.at(-1)!.sourceTime).toBeCloseTo(5.95);
  expect(() => inspectionSamples(40, edit, VideoFramesRequest.parse({ range: { start: 2, end: 5 } }))).toThrow();
});
