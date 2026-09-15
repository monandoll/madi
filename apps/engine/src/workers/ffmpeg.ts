import fs from 'node:fs';
import path from 'node:path';
import {
  type Encoder,
  parseEncoderList,
  parseProbe,
  pickEncoder,
  probeArgs,
  type ProbeResult,
  ProgressParser,
  proxyArgs,
  thumbnailArgs,
  thumbnailTime,
} from '@madi/ffmpeg-presets';
import { run } from './spawn.js';

export interface FfmpegBins {
  ffmpeg: string;
  ffprobe: string;
}

/** 순수 스폰 래퍼. DB를 모른다. */
export class Ffmpeg {
  private encoder: Encoder | null = null;

  constructor(private readonly bins: FfmpegBins) {}

  async detectEncoder(): Promise<Encoder> {
    if (this.encoder) return this.encoder;
    try {
      const { stdout } = await run(this.bins.ffmpeg, ['-hide_banner', '-encoders']);
      this.encoder = pickEncoder({ platform: process.platform, available: parseEncoderList(stdout) });
    } catch {
      this.encoder = 'libx264';
    }
    return this.encoder;
  }

  async probe(input: string, signal?: AbortSignal): Promise<ProbeResult> {
    const { stdout } = await run(this.bins.ffprobe, probeArgs(input), { signal: signal ?? undefined });
    return parseProbe(stdout);
  }

  async proxy(
    opts: { input: string; output: string; durationSec: number; hasAudio: boolean },
    onProgress?: (ratio: number) => void,
    signal?: AbortSignal,
  ): Promise<void> {
    const encoder = await this.detectEncoder();
    const tmp = `${opts.output}.part.mp4`;
    fs.mkdirSync(path.dirname(opts.output), { recursive: true });
    const parser = new ProgressParser(opts.durationSec, onProgress ?? (() => {}));
    try {
      await run(this.bins.ffmpeg, proxyArgs({ input: opts.input, output: tmp, encoder, hasAudio: opts.hasAudio }), {
        signal: signal ?? undefined,
        onStdout: (c) => parser.feed(c),
      });
      fs.renameSync(tmp, opts.output);
    } catch (err) {
      fs.rmSync(tmp, { force: true });
      throw err;
    }
  }

  async thumbnail(opts: { input: string; output: string; durationSec: number }, signal?: AbortSignal): Promise<void> {
    fs.mkdirSync(path.dirname(opts.output), { recursive: true });
    await run(this.bins.ffmpeg, thumbnailArgs({ input: opts.input, output: opts.output, atSec: thumbnailTime(opts.durationSec) }), {
      signal: signal ?? undefined,
    });
  }
}
