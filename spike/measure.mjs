/**
 * PNG 한 장에서 자막 지표를 재서 tokens.ts 목표치와 대조한다.
 *
 * 눈대중을 그만두기 위한 도구다. 여기서 재는 항목이 그대로
 * `AGENTS.md §8` 품질 게이트(G4 자막 크기 · G5 분절 · 자막 위치)의 씨앗이다.
 * 3단계에서 `src/review/gate.ts` 로 옮긴다.
 *
 *   node measure.mjs out/caption-probe.png
 *   node measure.mjs public/reference/yt_11s.png
 *   node measure.mjs out/caption-probe.png public/reference/yt_11s.png   # 둘을 나란히
 *
 * 의존성 없음. PNG 를 직접 푼다 (node:zlib).
 */
import { readFileSync } from 'node:fs';
import { inflateSync } from 'node:zlib';
import { CAPTION, CAPTION_SECONDARY } from './remotion/tokens.ts';

// --- 최소 PNG 디코더 (8-bit RGB/RGBA, non-interlaced) ---------------------

function decodePng(buf) {
  if (buf.readUInt32BE(0) !== 0x89504e47) throw new Error('PNG 아님');
  let pos = 8;
  let width = 0, height = 0, bitDepth = 0, colorType = 0;
  const idat = [];
  while (pos < buf.length) {
    const len = buf.readUInt32BE(pos);
    const type = buf.toString('ascii', pos + 4, pos + 8);
    const data = buf.subarray(pos + 8, pos + 8 + len);
    if (type === 'IHDR') {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      bitDepth = data[8];
      colorType = data[9];
      if (data[12] !== 0) throw new Error('interlaced PNG 미지원');
    } else if (type === 'IDAT') idat.push(data);
    else if (type === 'IEND') break;
    pos += 12 + len;
  }
  if (bitDepth !== 8) throw new Error(`bitDepth ${bitDepth} 미지원`);
  const channels = { 0: 1, 2: 3, 4: 2, 6: 4 }[colorType];
  if (!channels) throw new Error(`colorType ${colorType} 미지원`);

  const raw = inflateSync(Buffer.concat(idat));
  const stride = width * channels;
  const out = Buffer.alloc(height * stride);
  let rp = 0;
  for (let y = 0; y < height; y++) {
    const filter = raw[rp++];
    const line = raw.subarray(rp, rp + stride);
    rp += stride;
    const cur = out.subarray(y * stride, (y + 1) * stride);
    const prev = y > 0 ? out.subarray((y - 1) * stride, y * stride) : null;
    for (let x = 0; x < stride; x++) {
      const a = x >= channels ? cur[x - channels] : 0;
      const b = prev ? prev[x] : 0;
      const c = prev && x >= channels ? prev[x - channels] : 0;
      let v = line[x];
      if (filter === 1) v += a;
      else if (filter === 2) v += b;
      else if (filter === 3) v += (a + b) >> 1;
      else if (filter === 4) {
        const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
        v += pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
      }
      cur[x] = v & 0xff;
    }
  }
  return { width, height, channels, data: out };
}

// --- 지표 --------------------------------------------------------------

/** 글자 행 묶음. 최소 minPx 픽셀이 있는 행을 잇는다. */
function bands(rows, minPx, minHeight = 6) {
  const out = [];
  let s = null;
  for (let y = 0; y < rows.length; y++) {
    const on = rows[y] >= minPx;
    if (on && s === null) s = y;
    if (!on && s !== null) {
      if (y - s >= minHeight) out.push({ top: s, bottom: y - 1, h: y - s });
      s = null;
    }
  }
  if (s !== null && rows.length - s >= minHeight) out.push({ top: s, bottom: rows.length - 1, h: rows.length - s });
  return out;
}

function analyze(file) {
  const { width: W, height: H, channels, data } = decodePng(readFileSync(file));
  const at = (x, y) => {
    const i = (y * W + x) * channels;
    return [data[i], data[i + 1], data[i + 2]];
  };
  // 자막은 화면 아래쪽에 있다. 위쪽 인물·배경을 빼고 본다.
  const y0 = Math.floor(H * 0.6);
  const whiteRows = new Array(H).fill(0);
  const yellowRows = new Array(H).fill(0);
  const whiteCols = new Array(W).fill(0);
  for (let y = y0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      const [r, g, b] = at(x, y);
      if (r > 230 && g > 230 && b > 230) { whiteRows[y]++; whiteCols[x]++; }
      else if (r > 200 && g > 165 && b < 125) yellowRows[y]++;
    }
  }
  // 글자는 한 행에 최소 이만큼은 찍힌다. 벽·옷 같은 큰 흰 면은 훨씬 많이 찍히므로 상한도 둔다.
  const minPx = Math.max(8, Math.round(W * 0.012));
  const maxPx = Math.round(W * 0.6);
  const textRows = whiteRows.map((n) => (n >= minPx && n <= maxPx ? n : 0));
  const white = bands(textRows, minPx);
  const yellow = bands(yellowRows, Math.max(6, Math.round(W * 0.008)));

  const cols = whiteCols.map((n, x) => (n >= 2 ? x : -1)).filter((x) => x >= 0);
  const main = white.length ? white[white.length - 1] : null; // 가장 아래 흰 글자 줄 = 본문

  return {
    file, W, H,
    main: main && {
      h: main.h,
      hRatio: +(main.h / H).toFixed(4),
      bottomRatio: +((H - main.bottom - 1) / H).toFixed(4),
    },
    secondary: yellow.length ? {
      h: yellow[yellow.length - 1].h,
      hRatio: +(yellow[yellow.length - 1].h / H).toFixed(4),
      bottomRatio: +((H - yellow[yellow.length - 1].bottom - 1) / H).toFixed(4),
    } : null,
    widthRatio: cols.length ? +((cols[cols.length - 1] - cols[0] + 1) / W).toFixed(4) : 0,
    lines: white.length,
  };
}

// --- 출력 --------------------------------------------------------------

/**
 * 실제로 그려지는 글자 높이는 fontSize 그대로가 아니다.
 * Pretendard ExtraBold + 외곽선 조합에서 측정: 글자높이 = fontSize x 0.889
 * (fontSize 72 -> 64px, fontSize 78 -> 70px)
 */
const GLYPH_RATIO = 0.889;

/** 원본(크리에이터 실제 업로드본) 실측값. docs/findings/2026-09-23-reference-measurement.md */
const REFERENCE = { hRatio: 0.0359, bottomRatio: 0.2352, secondaryBottomRatio: 0.204 };

const targets = {
  bottomRatio: CAPTION.bottomRatio,
  hRatio: (CAPTION.fontSize * GLYPH_RATIO) / 1920,
  secondaryHRatio: (CAPTION.fontSize * CAPTION_SECONDARY.scale * GLYPH_RATIO) / 1920,
};

const files = process.argv.slice(2);
if (!files.length) {
  console.error('사용법: node measure.mjs <png> [<png> ...]');
  process.exit(1);
}

const pad = (s, n) => String(s).padEnd(n);
console.log('');
console.log(pad('파일', 34), pad('본문높이', 18), pad('하단여백', 14), pad('보조하단', 12), '폭');
console.log('-'.repeat(92));
for (const f of files) {
  try {
    const m = analyze(f);
    const hr = m.main ? `${m.main.h}px (${(m.main.hRatio * 100).toFixed(2)}%)` : '-';
    const br = m.main ? m.main.bottomRatio.toFixed(4) : '-';
    const sb = m.secondary ? m.secondary.bottomRatio.toFixed(4) : '-';
    console.log(pad(f.slice(-33), 34), pad(hr, 18), pad(br, 14), pad(sb, 12), m.widthRatio.toFixed(3));
  } catch (e) {
    console.log(pad(f.slice(-33), 34), '오류:', e.message);
  }
}
console.log('-'.repeat(92));
console.log(pad('tokens.ts 예상', 34), pad(`${(targets.hRatio * 100).toFixed(2)}%`, 18), pad(targets.bottomRatio.toFixed(4), 14), '');
console.log(pad('원본 실측 (맞춰야 할 값)', 30), pad(`${(REFERENCE.hRatio * 100).toFixed(2)}%`, 18), pad(REFERENCE.bottomRatio.toFixed(4), 14), REFERENCE.secondaryBottomRatio.toFixed(4));
console.log('');
console.log('본문높이 하한은 G4 >= 3.2%. 하단여백은 본문 아래끝에서 화면 아래까지의 비율.');
console.log('원본 실측 행과 +-0.003 안에 들어오면 통과다.');
console.log('');
