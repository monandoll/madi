/** headless 개발 진입. Electron 없이 서버·큐·감시만 띄운다. */
import { startEngine } from './engine.js';

const engine = await startEngine();
console.log(`madi engine: ${engine.url}`);

const shutdown = async () => {
  await engine.stop();
  process.exit(0);
};
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
