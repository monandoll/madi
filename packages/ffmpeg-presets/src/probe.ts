import { z } from 'zod';

export function probeArgs(input: string): string[] {
  return ['-v', 'error', '-print_format', 'json', '-show_format', '-show_streams', input];
}

const Stream = z.object({
  codec_type: z.string(),
  codec_name: z.string().optional(),
  width: z.number().int().optional(),
  height: z.number().int().optional(),
  r_frame_rate: z.string().optional(),
  avg_frame_rate: z.string().optional(),
  duration: z.string().optional(),
  tags: z.record(z.string(), z.string()).optional(),
  side_data_list: z.array(z.object({ rotation: z.number().optional() }).passthrough()).optional(),
});

const ProbeJson = z.object({
  format: z
    .object({
      duration: z.string().optional(),
      size: z.string().optional(),
    })
    .optional(),
  streams: z.array(Stream).default([]),
});

export interface ProbeResult {
  durationSec: number;
  /** 회전 메타데이터를 반영한 표시 크기 */
  width: number;
  height: number;
  fps: number | null;
  hasAudio: boolean;
  videoCodec: string | null;
}

function parseRate(rate: string | undefined): number | null {
  if (!rate) return null;
  const [n, d] = rate.split('/').map(Number);
  if (!n || !d) return null;
  const v = n / d;
  return Number.isFinite(v) && v > 0 ? Math.round(v * 1000) / 1000 : null;
}

function rotationOf(stream: z.infer<typeof Stream>): number {
  const tag = stream.tags?.['rotate'];
  if (tag) return Number(tag) || 0;
  const side = stream.side_data_list?.find((s) => typeof s.rotation === 'number');
  return side?.rotation ?? 0;
}

export function parseProbe(stdout: string): ProbeResult {
  const json = ProbeJson.parse(JSON.parse(stdout));
  const video = json.streams.find((s) => s.codec_type === 'video');
  if (!video || !video.width || !video.height) {
    throw new Error('no video stream');
  }
  const duration = Number(json.format?.duration ?? video.duration ?? NaN);
  if (!Number.isFinite(duration)) throw new Error('no duration');

  const rotated = Math.abs(rotationOf(video)) % 180 === 90;
  return {
    durationSec: Math.round(duration * 1000) / 1000,
    width: rotated ? video.height : video.width,
    height: rotated ? video.width : video.height,
    fps: parseRate(video.avg_frame_rate) ?? parseRate(video.r_frame_rate),
    hasAudio: json.streams.some((s) => s.codec_type === 'audio'),
    videoCodec: video.codec_name ?? null,
  };
}
