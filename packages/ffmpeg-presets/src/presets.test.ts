import { describe, expect, it } from 'vitest';
import { encoderSmokeArgs, parseEncoderList, pickEncoder, supportsNvencPresets } from './encoder.js';
import { parseProbe, probeArgs } from './probe.js';
import { proxyArgs } from './proxy.js';
import { thumbnailArgs, thumbnailTime } from './thumbnail.js';
import { ProgressParser } from './progress.js';

describe('encoder', () => {
  it('맥에서는 videotoolbox, 엔비디아면 nvenc, 아니면 libx264', () => {
    expect(pickEncoder({ platform: 'darwin', available: new Set(['h264_videotoolbox', 'libx264']) })).toBe('h264_videotoolbox');
    expect(pickEncoder({ platform: 'win32', available: new Set(['h264_nvenc', 'libx264']) })).toBe('h264_nvenc');
    expect(pickEncoder({ platform: 'linux', available: new Set(['libx264']) })).toBe('libx264');
  });

  it('ffmpeg -encoders 출력을 파싱한다', () => {
    const out = [
      'Encoders:',
      ' V..... = Video',
      ' ------',
      ' V....D libx264              libx264 H.264 / AVC / MPEG-4 AVC / MPEG-4 part 10 (codec h264)',
      ' V....D h264_nvenc           NVIDIA NVENC H.264 encoder (codec h264)',
      ' A....D aac                  AAC (Advanced Audio Coding)',
    ].join('\n');
    const set = parseEncoderList(out);
    expect(set.has('libx264')).toBe(true);
    expect(set.has('h264_nvenc')).toBe(true);
    expect(set.has('aac')).toBe(true);
    expect(set.has('Video')).toBe(false);
  });

  it('인코더 확인은 합성 입력 2프레임을 null 로 버린다', () => {
    const args = encoderSmokeArgs('h264_videotoolbox');
    expect(args).toContain('lavfi');
    expect(args.slice(-2)).toEqual(['null', '-']);
    expect(args[args.indexOf('-c:v') + 1]).toBe('h264_videotoolbox');
    expect(args[args.indexOf('-frames:v') + 1]).toBe('2');
  });

  it('nvenc 도움말에 p4 프리셋이 있어야 새 프리셋을 쓴다', () => {
    const modern = [
      '  -preset            <int>        E..V....... Set the encoding preset (from 0 to 18) (default p4)',
      '     p4                           E..V....... fast (default)',
    ].join('\n');
    const legacy = [
      '  -preset            <int>        E..V..... Set the encoding preset (from 0 to 11) (default medium)',
      '     medium                       E..V..... hq 1 pass',
    ].join('\n');
    expect(supportsNvencPresets(modern)).toBe(true);
    expect(supportsNvencPresets(legacy)).toBe(false);
  });
});

describe('probe', () => {
  it('args는 json 출력', () => {
    expect(probeArgs('/a b.mp4')).toEqual(['-v', 'error', '-print_format', 'json', '-show_format', '-show_streams', '/a b.mp4']);
  });

  it('회전 메타를 반영하고 오디오 유무를 판단한다', () => {
    const json = JSON.stringify({
      format: { duration: '18.417000' },
      streams: [
        { codec_type: 'video', codec_name: 'h264', width: 1920, height: 1080, avg_frame_rate: '30000/1001', tags: { rotate: '90' } },
        { codec_type: 'audio', codec_name: 'aac' },
      ],
    });
    const r = parseProbe(json);
    expect(r.durationSec).toBe(18.417);
    expect(r.width).toBe(1080);
    expect(r.height).toBe(1920);
    expect(r.fps).toBe(29.97);
    expect(r.hasAudio).toBe(true);
    expect(r.videoCodec).toBe('h264');
  });

  it('영상 스트림이 없으면 던진다', () => {
    expect(() => parseProbe(JSON.stringify({ streams: [{ codec_type: 'audio' }] }))).toThrow('no video stream');
  });
});

describe('proxy / thumbnail args', () => {
  it('720p 이하로만 줄이고 faststart를 켠다', () => {
    const args = proxyArgs({ input: 'in.mp4', output: 'out.mp4', encoder: 'libx264', hasAudio: true });
    expect(args).toContain("scale=w=-2:h='min(720,ih)'");
    expect(args.join(' ')).toContain('-movflags +faststart');
    expect(args.join(' ')).toContain('-c:a aac');
    expect(args.at(-1)).toBe('out.mp4');
  });

  it('무음 영상은 -an', () => {
    const args = proxyArgs({ input: 'in.mp4', output: 'out.mp4', encoder: 'h264_nvenc', hasAudio: false });
    expect(args).toContain('-an');
    expect(args).toContain('h264_nvenc');
  });

  it('썸네일 시점은 10% 지점, 0.5초 이상', () => {
    expect(thumbnailTime(100)).toBe(10);
    expect(thumbnailTime(2)).toBe(0.5);
    expect(thumbnailTime(0.4)).toBe(0);
    expect(thumbnailArgs({ input: 'a', output: 'b.jpg', atSec: 1.5 })).toContain('1.500');
  });
});

describe('ProgressParser', () => {
  it('블록 단위로 진행률을 낸다', () => {
    const got: number[] = [];
    const p = new ProgressParser(10, (r) => got.push(r));
    p.feed('frame=1\nout_time_us=2500000\nprogress=con');
    p.feed('tinue\nout_time_us=10000000\nprogress=end\n');
    expect(got).toEqual([0.25, 1]);
  });
});
