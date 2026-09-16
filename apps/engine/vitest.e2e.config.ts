import { defineConfig } from 'vitest/config';

/** 엔진 e2e — 실제 ffmpeg 을 돌리고 임시 MADI_HOME 에 서버를 띄운다. `pnpm e2e:engine`. */
export default defineConfig({
  test: {
    include: ['test/e2e.*.test.ts'],
    testTimeout: 60_000,
    hookTimeout: 60_000,
    fileParallelism: false,
  },
});
