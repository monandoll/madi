import fs from 'node:fs';
import path from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { resolveSidecar } from '../src/main/sidecar.js';
import { Ffmpeg } from '../src/workers/ffmpeg.js';
import { SAMPLE_5S, SAMPLE_SILENT, tempHome } from './helpers.js';

let home: string;
const ffmpeg = new Ffmpeg({
  ffmpeg: resolveSidecar('ffmpeg', '/nonexistent'),
  ffprobe: resolveSidecar('ffprobe', '/nonexistent'),
});

beforeEach(() => {
  home = tempHome();
});
afterEach(() => {
  fs.rmSync(home, { recursive: true, force: true });
});

describe('Ffmpeg worker', () => {
  it('probe: 길이·크기·오디오를 읽는다', async () => {
    const meta = await ffmpeg.probe(SAMPLE_5S);
    expect(meta.durationSec).toBeGreaterThan(4.5);
    expect(meta.durationSec).toBeLessThan(5.5);
    expect(meta.width).toBe(1280);
    expect(meta.height).toBe(720);
    expect(meta.hasAudio).toBe(true);
    expect(meta.fps).toBe(30);

    const silent = await ffmpeg.probe(SAMPLE_SILENT);
    expect(silent.hasAudio).toBe(false);
    expect(silent.width).toBe(640);
  });

  it('probe: 영상이 아니면 던진다', async () => {
    const notVideo = path.join(home, 'x.mp4');
    fs.writeFileSync(notVideo, 'not a video');
    await expect(ffmpeg.probe(notVideo)).rejects.toThrow();
  });

  it('thumbnail: jpg 한 장을 만든다', async () => {
    const out = path.join(home, 'thumbs', 't.jpg');
    await ffmpeg.thumbnail({ input: SAMPLE_5S, output: out, durationSec: 5 });
    const st = fs.statSync(out);
    expect(st.size).toBeGreaterThan(1000);
    const meta = await ffmpeg.probe(out);
    expect(meta.width).toBe(640);
    expect(meta.height).toBe(360);
  });

  it('proxy: 720p mp4 를 만들고 진행률을 보고한다', async () => {
    const out = path.join(home, 'proxies', 'p.mp4');
    const progress: number[] = [];
    await ffmpeg.proxy({ input: SAMPLE_5S, output: out, durationSec: 5, hasAudio: true }, (r) => progress.push(r));
    expect(fs.existsSync(out)).toBe(true);
    expect(fs.existsSync(`${out}.part.mp4`)).toBe(false);
    expect(progress.at(-1)).toBe(1);
    const meta = await ffmpeg.probe(out);
    expect(meta.height).toBe(720);
    expect(meta.hasAudio).toBe(true);
  });

  it('proxy: 무음 원본은 오디오 없이', async () => {
    const out = path.join(home, 'proxies', 's.mp4');
    await ffmpeg.proxy({ input: SAMPLE_SILENT, output: out, durationSec: 3, hasAudio: false });
    const meta = await ffmpeg.probe(out);
    expect(meta.hasAudio).toBe(false);
    // 원본이 360p면 키우지 않는다
    expect(meta.height).toBe(360);
  });

  it('proxy: 취소하면 부분 파일을 지운다', async () => {
    const out = path.join(home, 'proxies', 'c.mp4');
    const ctrl = new AbortController();
    setTimeout(() => ctrl.abort(), 150);
    await expect(ffmpeg.proxy({ input: SAMPLE_5S, output: out, durationSec: 5, hasAudio: true }, undefined, ctrl.signal)).rejects.toThrow();
    expect(fs.existsSync(out)).toBe(false);
    expect(fs.existsSync(`${out}.part.mp4`)).toBe(false);
  });
});
