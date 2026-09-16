// 트레이 아이콘 PNG 를 코드로 만든다 (외부 이미지 없이). 22x22, 둥근 점.
// tray.png: accent 색 (Windows). trayTemplate.png: 검정 (macOS 템플릿 이미지, 시스템이 색을 입힌다).
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const out = path.resolve(here, '../build');
fs.mkdirSync(out, { recursive: true });

function crc32(buf) {
  let c;
  const table = [];
  for (let n = 0; n < 256; n++) {
    c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c >>> 0;
  }
  let crc = 0xffffffff;
  for (const b of buf) crc = table[(crc ^ b) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}
function png(size, rgb) {
  const rows = [];
  const r = size / 2;
  for (let y = 0; y < size; y++) {
    const row = [0];
    for (let x = 0; x < size; x++) {
      const dx = x + 0.5 - r;
      const dy = y + 0.5 - r;
      const d = Math.sqrt(dx * dx + dy * dy);
      const a = Math.max(0, Math.min(1, r - 2 - d + 0.5)); // 가장자리 안티앨리어싱
      row.push(rgb[0], rgb[1], rgb[2], Math.round(a * 255));
    }
    rows.push(Buffer.from(row));
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0);
  ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // RGBA
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(Buffer.concat(rows))),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}
fs.writeFileSync(path.join(out, 'tray.png'), png(22, [0xc9, 0x6a, 0x4b]));
fs.writeFileSync(path.join(out, 'tray@2x.png'), png(44, [0xc9, 0x6a, 0x4b]));
fs.writeFileSync(path.join(out, 'trayTemplate.png'), png(22, [0, 0, 0]));
fs.writeFileSync(path.join(out, 'trayTemplate@2x.png'), png(44, [0, 0, 0]));
// 앱 아이콘 (설치 파일·독). electron-builder 는 512px 이상을 요구한다. 정식 아이콘은 디자인이 나오면 교체.
fs.writeFileSync(path.join(out, 'icon.png'), png(1024, [0xc9, 0x6a, 0x4b]));
console.log('tray icons → build/');
