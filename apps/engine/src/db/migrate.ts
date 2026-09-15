import { loadConfig } from '../config.js';
import { openDb } from './index.js';

const cfg = loadConfig();
const { sqlite } = openDb(cfg.dbPath, cfg.migrationsDir);
sqlite.close();
console.log(`migrated ${cfg.dbPath}`);
