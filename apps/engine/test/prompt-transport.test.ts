import fs from 'node:fs';
import path from 'node:path';
import { expect, it } from 'vitest';
import { ClaudeProvider } from '../src/agent/claude.js';
import { CodexProvider } from '../src/agent/codex.js';
import { tempHome } from './helpers.js';

// 실제 CLI의 출력 계약만 흉내 내고, 받은 입력은 가공 없이 되돌린다.
// Windows에서는 .cmd를 실제로 거쳐 다중행·명령줄 길이 제한 회귀를 검사한다.
const echoScript = `#!/usr/bin/env node
import fs from 'node:fs';
const args=process.argv.slice(2);
let input='';
process.stdin.setEncoding('utf8');
for await (const chunk of process.stdin) input+=chunk;
const flag=args.indexOf('--append-system-prompt-file');
const text=JSON.stringify({input,system:flag>=0?fs.readFileSync(args[flag+1],'utf8'):null});
const message=args[0]==='exec'
  ? {type:'item.completed',item:{type:'agent_message',text}}
  : {type:'result',subtype:'success',is_error:false,result:text};
process.stdout.write(JSON.stringify(message)+'\\n');
`;

for (const providerId of ['claude', 'codex'] as const) {
  for (const mode of ['run', 'analyze'] as const) {
    it(`${providerId} ${mode}: preserves long Korean prompts, newlines and shell characters`, async () => {
      const home = tempHome('madi-prompt-');
      const cwd = path.join(home, '작업 폴더');
      fs.mkdirSync(cwd);
      const script = path.join(home, 'echo.mjs');
      fs.writeFileSync(script, echoScript);
      fs.chmodSync(script, 0o755);
      const bin = process.platform === 'win32' ? path.join(home, 'echo.cmd') : script;
      if (process.platform === 'win32') fs.writeFileSync(bin, `@echo off\r\n"${process.execPath}" "${script}" %*\r\n`);
      const prompt = '요청: "천천히" & <안내> | %PATH% ! ^\r\n'.repeat(500);
      const system = '스타일 규칙: 원문 그대로\n다음 줄\n'.repeat(1000);
      const provider = providerId === 'claude' ? new ClaudeProvider(() => path.join(home, 'unused.json')) : new CodexProvider();
      try {
        const options = { bin, cwd, prompt, system };
        const result = mode === 'analyze'
          ? await provider.analyze(options)
          : await provider.run({ ...options, mcp: { command: 'node', args: [], env: {} }, toolNames: [], onText() {}, onTool() {} });
        expect(result.ok, result.error).toBe(true);
        expect(JSON.parse(result.text)).toEqual(providerId === 'claude'
          ? { input: prompt, system }
          : { input: `${system}\n\n---\n\n${prompt}`, system: null });
      } finally {
        fs.rmSync(home, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
      }
    });
  }
}
