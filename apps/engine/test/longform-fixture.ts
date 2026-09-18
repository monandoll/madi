import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { resolveSidecar } from '../src/main/sidecar.js';

/**
 * 롱폼 테스트용 영상을 ffmpeg 로 만든다: 색이 다른 장면 N개(각 sceneSec 초)를 이어 붙이고,
 * 오디오는 장면마다 다른 톤 + 경계에 2초 무음. 작게(320x180) 만들어 몇 초면 끝난다.
 */
export function makeLongformFixture(out: string, opts: { scenes?: number; sceneSec?: number } = {}): string {
  const scenes = opts.scenes ?? 4;
  const sceneSec = opts.sceneSec ?? 50;
  if (fs.existsSync(out)) return out;
  fs.mkdirSync(path.dirname(out), { recursive: true });
  const ffmpeg = resolveSidecar('ffmpeg', '/nonexistent');
  const colors = ['red', 'green', 'blue', 'yellow', 'magenta', 'cyan', 'orange', 'purple'];
  const inputs: string[] = [];
  const filter: string[] = [];
  for (let i = 0; i < scenes; i++) {
    inputs.push('-f', 'lavfi', '-i', `color=c=${colors[i % colors.length]}:s=320x180:r=24:d=${sceneSec}`);
    // 톤 48초 + 앞뒤 1초씩 무음 → 경계마다 2초 무음
    inputs.push('-f', 'lavfi', '-i', `sine=frequency=${300 + i * 120}:sample_rate=44100:d=${sceneSec}`);
    filter.push(`[${i * 2 + 1}:a]volume='if(lt(t,1)+gt(t,${sceneSec - 1}),0,1)':eval=frame[a${i}]`);
  }
  const vin = Array.from({ length: scenes }, (_, i) => `[${i * 2}:v]`).join('');
  const ain = Array.from({ length: scenes }, (_, i) => `[a${i}]`).join('');
  filter.push(`${vin}concat=n=${scenes}:v=1:a=0[v]`, `${ain}concat=n=${scenes}:v=0:a=1[a]`);
  execFileSync(
    ffmpeg,
    ['-hide_banner', '-y', ...inputs, '-filter_complex', filter.join(';'), '-map', '[v]', '-map', '[a]', '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-movflags', '+faststart', out],
    { stdio: 'ignore' },
  );
  return out;
}

/**
 * 시범 침묵 테스트용 영상: 가만히 말함(회색 화면 + 톤) → 말 없이 동작(움직이는 테스트 패턴, 무음) → 다시 말함.
 * 무음 구간은 하나(가운데)인데 그동안만 화면이 움직인다. 쉬는 구간 자르기가 그 침묵을 남겨야 한다.
 */
export function makeDemoSilenceFixture(out: string, opts: { talkSec?: number; demoSec?: number } = {}): string {
  const talk = opts.talkSec ?? 3;
  const demo = opts.demoSec ?? 2.5;
  if (fs.existsSync(out)) return out;
  fs.mkdirSync(path.dirname(out), { recursive: true });
  const ffmpeg = resolveSidecar('ffmpeg', '/nonexistent');
  const total = talk * 2 + demo;
  execFileSync(
    ffmpeg,
    [
      '-hide_banner', '-y',
      '-f', 'lavfi', '-i', `color=c=gray:s=320x180:r=24:d=${talk}`,
      '-f', 'lavfi', '-i', `testsrc2=s=320x180:r=24:d=${demo}`,
      '-f', 'lavfi', '-i', `color=c=gray:s=320x180:r=24:d=${talk}`,
      '-f', 'lavfi', '-i', `sine=frequency=440:sample_rate=44100:d=${total}`,
      '-filter_complex',
      `[0:v][1:v][2:v]concat=n=3:v=1:a=0[v];[3:a]volume='if(between(t,${talk},${talk + demo}),0,1)':eval=frame[a]`,
      '-map', '[v]', '-map', '[a]', '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-movflags', '+faststart', out,
    ],
    { stdio: 'ignore' },
  );
  return out;
}
