// 자막 한 장만 렌더. 영상 없이 파이프라인·폰트·레이아웃 확인.
import { bundle } from '@remotion/bundler';
import { webpackOverride } from './webpack-override.mjs';
import { renderStill, selectComposition } from '@remotion/renderer';
import { ensureBrowserRunnable } from './ensure-browser.mjs';
import { mkdirSync, existsSync, readdirSync } from 'node:fs';
import path from 'node:path';

const inputProps = {
  text: process.env.PROBE_TEXT || '골반 틀어졌으면',
  secondary: process.env.PROBE_SECONDARY || 'If your pelvis is tilted',
  emphasis: process.env.PROBE_EMPHASIS ? JSON.parse(process.env.PROBE_EMPHASIS) : [{ from: 0, to: 2 }],
  ...(process.env.PROBE_BACKDROP ? { backdrop: process.env.PROBE_BACKDROP.replace(/^\.?\/?public\//, '') } : {}),
};

if (inputProps.backdrop && !existsSync(`public/${inputProps.backdrop}`)) {
  console.error(`\n[probe] public/${inputProps.backdrop} 가 없습니다.`);
  console.error('PROBE_BACKDROP 은 public/ 안의 경로입니다 (public/ 접두사는 쓰지 않습니다).');
  for (const dir of ['reference', 'frames']) {
    if (existsSync(`public/${dir}`)) {
      console.error(`\n  ${dir}/ 안에 있는 것:`);
      for (const f of readdirSync(`public/${dir}`).slice(0, 12)) console.error(`    ${dir}/${f}`);
    }
  }
  console.error('');
  process.exit(1);
}

mkdirSync('out', { recursive: true });
ensureBrowserRunnable();
console.log('[probe] 번들링...');
const serveUrl = await bundle({ entryPoint: path.resolve('remotion/index.ts'), publicDir: path.resolve('public'), webpackOverride });
const composition = await selectComposition({ serveUrl, id: 'CaptionProbe', inputProps });
await renderStill({
  composition,
  serveUrl,
  output: 'out/caption-probe.png',
  inputProps,
  frame: 20,
  timeoutInMilliseconds: 120000,
  chromiumOptions: { gl: 'angle' },
});
console.log('[probe] out/caption-probe.png');
