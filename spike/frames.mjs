// reference/final.mp4 → public/frames/*.png (0.5초 간격)
// AGENTS.md §9 / stage-0.spec.md 작업순서 3
import { spawn } from 'node:child_process';
import { existsSync, mkdirSync } from 'node:fs';

const FFMPEG = process.env.FFMPEG_PATH || 'ffmpeg';
const SRC = 'reference/final.mp4';
const OUT = 'public/frames';

if (!existsSync(SRC)) {
  console.error(`\n[frames] ${SRC} 가 없습니다.`);
  console.error('크리에이터가 실제로 업로드한 숏폼 1편을 여기에 두세요. 0단계의 유일한 입력입니다.\n');
  process.exit(1);
}
mkdirSync(OUT, { recursive: true });

const args = ['-hide_banner', '-loglevel', 'error', '-y', '-i', SRC, '-vf', 'fps=2', `${OUT}/%04d.png`];
const p = spawn(FFMPEG, args, { stdio: 'inherit' });
p.on('exit', (code) => {
  if (code === 0) console.log(`\n[frames] ${OUT}/ 에 저장했습니다.`);
  else console.log(`  PROBE_BACKDROP=frames/0001.png pnpm probe  로 자막을 겹쳐 볼 수 있습니다.`);
  process.exit(code ?? 1);
});
