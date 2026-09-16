#!/usr/bin/env node
/** 테스트용 가짜 탐색기. 받은 폴더 경로를 MADI_HOME/opened.txt 에 적는다. MADI_OPENER=fixtures/fake-opener.mjs */
import fs from 'node:fs';
import path from 'node:path';
fs.writeFileSync(path.join(process.env['MADI_HOME'] ?? '.', 'opened.txt'), process.argv[2] ?? '');
