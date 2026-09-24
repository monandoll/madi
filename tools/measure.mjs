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

/**
 * 보조 문구의 **베이스라인** 행을 찾는다.
 *
 * ★ "가장 아래 노란 픽셀" 로 재면 안 된다. 그건 `y` · `g` 의 디센더 끝이고,
 *   디센더가 있는 문구와 없는 문구가 다른 값을 낸다. 글자를 한 픽셀도 안 움직이고
 *   `is likely misaligned.` 를 `COMPARE BOTH SIDES` 로만 바꿔도 판정이 뒤집힌다.
 *   게다가 원본은 유튜브 재인코딩본이라 얇은 디센더가 임계값 아래로 사라져서
 *   crisp 한 렌더와 애초에 같은 자리를 재지 않는다.
 *   (docs/findings/2026-09-25-coretext-caption-measurement.md §6)
 *
 * 베이스라인은 **행별 픽셀 수가 뚝 떨어지는 행**이다. 소문자 몸통이 거기서 끝나고
 * 디센더 몇 획만 아래로 내려가므로 픽셀 수가 1/5 이하로 준다. 디센더 유무와 무관하다.
 */
function baselineRow(rows, band) {
  let peak = 0;
  for (let y = band.top; y <= band.bottom; y++) peak = Math.max(peak, rows[y]);
  const floor = peak * 0.35;
  let baseline = band.top;
  for (let y = band.top; y <= band.bottom; y++) if (rows[y] >= floor) baseline = y;
  return baseline;
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
      // 노랑 판정을 느슨하게 잡는다. 엄격하게 잡으면 원본의 흐릿한 획이 통째로 빠져서
      // 베이스라인을 못 찾는다. 대신 아래에서 본문보다 아래쪽만 본다.
      else if (r > 150 && g > 120 && b < r - 60 && b < g - 40) yellowRows[y]++;
    }
  }
  // 글자는 한 행에 최소 이만큼은 찍힌다. 벽·옷 같은 큰 흰 면은 훨씬 많이 찍히므로 상한도 둔다.
  const minPx = Math.max(8, Math.round(W * 0.012));
  const maxPx = Math.round(W * 0.6);
  const textRows = whiteRows.map((n) => (n >= minPx && n <= maxPx ? n : 0));
  const white = bands(textRows, minPx);

  const cols = whiteCols.map((n, x) => (n >= 2 ? x : -1)).filter((x) => x >= 0);

  // 본문 = 가장 아래 흰 **글자** 줄.
  // ★ 그냥 "가장 아래 묶음" 을 쓰면 안 된다. 자막 아래에도 밝은 것이 있다(흰 양말 · 벤치
  //   하이라이트). 글자 줄은 두껍고 배경 얼룩은 얇으므로 **가장 두꺼운 묶음 급**만 남기고
  //   그중 가장 아래를 쓴다. 2줄 자막이면 마지막 줄이 뽑힌다 — 하단여백이 마지막 줄 기준이므로 맞다.
  const tallest = white.length ? Math.max(...white.map((b) => b.h)) : 0;
  const textBands = white.filter((b) => b.h >= tallest * 0.6);
  const main = textBands.length ? textBands[textBands.length - 1] : null;

  // 보조 문구는 **본문보다 아래**에 있다. 위쪽을 잘라내야 살색·벽이 노랑으로 오인되지 않는다.
  const minYellow = Math.max(4, Math.round(W * 0.005));
  let yellowSearch = yellowRows.map((n, y) => (main && y > main.bottom ? n : 0));
  let yellow = bands(yellowSearch, minYellow, 4);
  if (!yellow.length) {
    // 훅 카드처럼 본문 밴드가 화면 아래까지 닿는 프레임에서는 자를 게 없다.
    // 그때는 아래쪽 전체에서 가장 아래 노란 묶음을 쓴다 (오인 가능성을 감수한다).
    yellowSearch = yellowRows;
    const all = bands(yellowSearch, minYellow, 4);
    yellow = all.length ? [all[all.length - 1]] : [];
  }
  const secondaryBand = yellow.length ? yellow[0] : null;

  return {
    file, W, H,
    main: main && {
      h: main.h,
      hRatio: +(main.h / H).toFixed(4),
      bottomRatio: +((H - main.bottom - 1) / H).toFixed(4),
    },
    secondary: secondaryBand && {
      h: secondaryBand.h,
      // 참고용. 디센더 유무로 흔들리므로 판정에 쓰지 않는다.
      inkBottomRatio: +((H - secondaryBand.bottom - 1) / H).toFixed(4),
      baselineRatio: +((H - baselineRow(yellowSearch, secondaryBand) - 1) / H).toFixed(4),
    },
    widthRatio: cols.length ? +((cols[cols.length - 1] - cols[0] + 1) / W).toFixed(4) : 0,
    lines: textBands.length,
  };
}

// --- 출력 --------------------------------------------------------------

/**
 * 크리에이터 실제 업로드본 실측값. 맞춰야 할 목표다.
 * docs/findings/2026-09-23-reference-measurement.md · AGENTS.md §9
 * 렌더러(Remotion · CoreText · 무엇이든)와 무관한 사실이므로 여기 고정한다.
 */
const REFERENCE = {
  hRatio: 0.0359,             // 본문 글자 높이 / 프레임 높이
  bottomRatio: 0.2352,        // 본문 아래끝에서 화면 아래까지
  /**
   * 보조 문구 **베이스라인**에서 화면 아래까지.
   *
   * 예전 값은 "보조 문구 아래끝 0.204" 였다. 그건 노란 픽셀이 찍힌 가장 아래 행인데,
   * 디센더가 있는 문구/없는 문구가 다르게 나오고 원본의 재인코딩 번짐까지 섞여 있었다.
   * 베이스라인은 두 원본(yt_15s · yt_7s)에서 모두 y=1020 @1280 으로 일치한다.
   *   (1280 - 1020 - 1) / 1280 = 0.2023
   * docs/findings/2026-09-25-coretext-caption-measurement.md §6
   */
  secondaryBaselineRatio: 0.2023,
};

/** 허용 오차. AGENTS.md §12-0 통과 조건 A */
const TOL = { hRatio: 0.001, bottomRatio: 0.003, secondaryBaselineRatio: 0.003 };

const files = process.argv.slice(2);
if (!files.length) {
  console.error('사용법: node measure.mjs <png> [<png> ...]');
  process.exit(1);
}

const pad = (s, n) => String(s).padEnd(n);
console.log('');
console.log(pad('파일', 34), pad('본문높이', 18), pad('하단여백', 14), pad('보조베이스', 12), pad('보조아래끝', 12), '폭');
console.log('-'.repeat(104));
for (const f of files) {
  try {
    const m = analyze(f);
    const hr = m.main ? `${m.main.h}px (${(m.main.hRatio * 100).toFixed(2)}%)` : '-';
    const br = m.main ? m.main.bottomRatio.toFixed(4) : '-';
    const sb = m.secondary ? m.secondary.baselineRatio.toFixed(4) : '-';
    const si = m.secondary ? m.secondary.inkBottomRatio.toFixed(4) : '-';
    console.log(pad(f.slice(-33), 34), pad(hr, 18), pad(br, 14), pad(sb, 12), pad(si, 12), m.widthRatio.toFixed(3));
  } catch (e) {
    console.log(pad(f.slice(-33), 34), '오류:', e.message);
  }
}
console.log('-'.repeat(104));
console.log(pad('원본 실측 (목표)', 31), pad(`${(REFERENCE.hRatio * 100).toFixed(2)}%`, 18), pad(REFERENCE.bottomRatio.toFixed(4), 14), REFERENCE.secondaryBaselineRatio.toFixed(4));
console.log(pad('허용 오차', 33), pad(`+-${(TOL.hRatio * 100).toFixed(2)}%`, 18), pad(`+-${TOL.bottomRatio}`, 14), `+-${TOL.secondaryBaselineRatio}`);
console.log('');

// 판정
for (const f of files) {
  try {
    const m = analyze(f);
    if (!m.main) continue;
    const checks = [
      ['본문높이', Math.abs(m.main.hRatio - REFERENCE.hRatio) <= TOL.hRatio],
      ['하단여백', Math.abs(m.main.bottomRatio - REFERENCE.bottomRatio) <= TOL.bottomRatio],
      ...(m.secondary ? [['보조베이스', Math.abs(m.secondary.baselineRatio - REFERENCE.secondaryBaselineRatio) <= TOL.secondaryBaselineRatio]] : []),
    ];
    const bad = checks.filter(([, ok]) => !ok).map(([n]) => n);
    console.log(`${bad.length ? 'FAIL' : 'PASS'}  ${f.slice(-40)}${bad.length ? '  — ' + bad.join(', ') : ''}`);
  } catch { /* 위에서 이미 알렸다 */ }
}
console.log('');
console.log('G4 하한은 본문높이 >= 3.2%. 하단여백은 본문 아래끝에서 화면 아래까지의 비율.');
console.log('보조 문구는 **베이스라인**으로 판정한다. 아래끝은 디센더 유무로 흔들려서 참고만 한다.');
console.log('');
