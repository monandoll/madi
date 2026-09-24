// out/final.mp4 vs reference/final.mp4 → out/compare.png (같은 시각 나란히)
// stage-0.spec.md 통과 조건은 이 시트를 사람이 눈으로 보고 판정한다.
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';

const FFMPEG = process.env.FFMPEG_PATH || 'ffmpeg';
const MINE = 'out/final.mp4';
const REF = 'reference/final.mp4';
const TIMES = (process.env.COMPARE_AT || '1,4,8,14,20').split(',').map(Number);

for (const f of [MINE, REF]) {
  if (!existsSync(f)) { console.error(`[compare] ${f} 없음`); process.exit(1); }
}

// 각 시각에서 두 영상을 위아래로 붙이고, 시각들을 가로로 이어 붙인다.
const inputs = [];
const filters = [];
TIMES.forEach((t, i) => {
  inputs.push('-ss', String(t), '-i', REF, '-ss', String(t), '-i', MINE);
  const a = i * 2, b = i * 2 + 1;
  filters.push(`[${a}:v]scale=320:-1,drawtext=text='ref ${t}s':x=8:y=8:fontcolor=red:fontsize=18[r${i}]`);
  filters.push(`[${b}:v]scale=320:-1,drawtext=text='mine ${t}s':x=8:y=8:fontcolor=red:fontsize=18[m${i}]`);
  filters.push(`[r${i}][m${i}]vstack=inputs=2[c${i}]`);
});
filters.push(`${TIMES.map((_, i) => `[c${i}]`).join('')}hstack=inputs=${TIMES.length}[out]`);

const args = ['-hide_banner', '-loglevel', 'error', '-y', ...inputs,
  '-filter_complex', filters.join(';'), '-map', '[out]', '-frames:v', '1', 'out/compare.png'];

const p = spawn(FFMPEG, args, { stdio: 'inherit' });
p.on('exit', (code) => {
  if (code === 0) console.log('\n[compare] out/compare.png — 위=원본, 아래=내 렌더. 통과 조건 5개를 눈으로 판정하세요.');
  process.exit(code ?? 1);
});
