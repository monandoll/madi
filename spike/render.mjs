// composition.json → out/final.mp4
// stage-0.spec.md 작업순서 6
import { bundle } from '@remotion/bundler';
import { renderMedia, selectComposition } from '@remotion/renderer';
import { readFileSync, mkdirSync, existsSync } from 'node:fs';
import path from 'node:path';

const root = path.resolve('remotion/Root.tsx');
const specPath = 'composition.json';

if (!existsSync(specPath)) {
  console.error(`\n[render] ${specPath} 가 없습니다. reference/final.mp4 을 손으로 옮겨 적으세요.\n`);
  process.exit(1);
}
const spec = JSON.parse(readFileSync(specPath, 'utf8'));
mkdirSync('out', { recursive: true });

console.log('[render] 번들링...');
const serveUrl = await bundle({ entryPoint: root });

const composition = await selectComposition({
  serveUrl,
  id: 'Short',
  inputProps: { spec },
});

console.log('[render] 렌더...');
await renderMedia({
  composition,
  serveUrl,
  codec: 'h264',
  outputLocation: 'out/final.mp4',
  inputProps: { spec },
  onProgress: ({ progress }) => process.stdout.write(`\r  ${Math.round(progress * 100)}%`),
});
console.log('\n[render] out/final.mp4');
