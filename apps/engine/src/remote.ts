import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

/**
 * 밖에서 접속하기의 잠금.
 *
 * 터널을 켜면 주소만 알면 누구나 들어올 수 있다 (빠른 터널엔 로그인이 없다).
 * 그래서 **이 PC 에서 직접 연 브라우저가 아니면** 6자리 숫자를 한 번 묻고, 맞으면 그 기기에 표를 하나 준다.
 * QR 에 숫자를 실어 주므로 폰에서는 찍기만 하면 된다.
 *
 * "이 PC 에서 직접"은 IP 만으로 못 가른다 — cloudflared 도 127.0.0.1 로 붙기 때문이다.
 * 대신 터널을 지나온 요청에는 cloudflared 가 늘 붙이는 헤더(cf-connecting-ip 등)가 있다.
 */

export const PAIR_COOKIE = 'madi_pair';
/** 틀린 숫자를 이만큼 넣으면 숫자를 새로 만든다 (찍어서 맞히기 방지). */
export const MAX_PIN_TRIES = 10;

/** 루프백 주소인가 (IPv6 매핑 포함). */
export function isLoopback(address: string | undefined): boolean {
  if (!address) return false;
  const a = address.replace(/^::ffff:/, '');
  return a === '127.0.0.1' || a === '::1' || a.startsWith('127.');
}

/** 프록시·터널을 지나온 흔적. 하나라도 있으면 이 PC 에서 직접 연 것이 아니다. */
const FORWARD_HEADERS = ['cf-connecting-ip', 'cf-ray', 'x-forwarded-for', 'x-forwarded-host', 'x-real-ip', 'forwarded'];

/**
 * 이 PC 에서 직접 연 요청인가. 루프백이면서 터널 흔적이 없어야 한다.
 * 터널 쪽에서 헤더를 지우고 들어올 수는 없다 — cloudflared 가 붙이는 값이라 클라이언트가 못 지운다.
 */
export function isDirectRequest(address: string | undefined, headers: Record<string, string | string[] | undefined>): boolean {
  if (!isLoopback(address)) return false;
  return !FORWARD_HEADERS.some((h) => {
    const v = headers[h];
    return typeof v === 'string' ? v.trim() !== '' : Array.isArray(v) && v.length > 0;
  });
}

/** 6자리 숫자. 앞자리 0 도 나온다. */
export function makePin(): string {
  return String(crypto.randomInt(0, 1_000_000)).padStart(6, '0');
}

function newToken(): string {
  return crypto.randomBytes(24).toString('base64url');
}

/** 시간이 일정한 비교 (길이가 다르면 바로 false). */
function sameSecret(a: string, b: string): boolean {
  const x = Buffer.from(a);
  const y = Buffer.from(b);
  return x.length === y.length && crypto.timingSafeEqual(x, y);
}

interface Stored {
  devices: string[];
}

/**
 * 짝지은 기기 목록. 파일에 남겨서 마디를 껐다 켜도 폰이 다시 숫자를 치지 않게 한다.
 * 숫자(pin)는 메모리에만 둔다 — 켤 때마다 새로 만든다.
 */
export class RemoteAuth {
  private pin: string = makePin();
  private tries = 0;
  private devices = new Set<string>();

  constructor(private readonly filePath: string) {
    try {
      const raw = JSON.parse(fs.readFileSync(filePath, 'utf8')) as Stored;
      for (const d of raw.devices ?? []) if (typeof d === 'string' && d) this.devices.add(d);
    } catch {
      /* 없으면 빈 목록 */
    }
  }

  get currentPin(): string {
    return this.pin;
  }

  get deviceCount(): number {
    return this.devices.size;
  }

  /** 터널을 켤 때마다 새 숫자. 이미 짝지은 기기는 그대로 둔다. */
  resetPin(): string {
    this.pin = makePin();
    this.tries = 0;
    return this.pin;
  }

  has(token: string | undefined): boolean {
    if (!token) return false;
    for (const d of this.devices) if (sameSecret(d, token)) return true;
    return false;
  }

  /** 숫자가 맞으면 이 기기의 표를 돌려준다. 틀리면 null (여러 번 틀리면 숫자가 바뀐다). */
  pair(pin: string): string | null {
    if (!sameSecret(pin.trim(), this.pin)) {
      if (++this.tries >= MAX_PIN_TRIES) this.resetPin();
      return null;
    }
    const token = newToken();
    this.devices.add(token);
    this.tries = 0;
    this.save();
    return token;
  }

  /** 짝지은 기기 전부 끊기 (밖에서 접속을 끌 때). */
  forgetAll(): void {
    this.devices.clear();
    this.resetPin();
    this.save();
  }

  private save(): void {
    try {
      fs.mkdirSync(path.dirname(this.filePath), { recursive: true });
      fs.writeFileSync(this.filePath, JSON.stringify({ devices: [...this.devices] } satisfies Stored), { mode: 0o600 });
    } catch {
      /* 못 써도 이번 실행 동안은 동작한다 */
    }
  }
}

/** 쿠키 한 줄에서 값 꺼내기 (hono/cookie 를 안 쓰는 곳에서도 쓴다). */
export function readCookie(header: string | undefined, name: string): string | undefined {
  if (!header) return undefined;
  for (const part of header.split(';')) {
    const i = part.indexOf('=');
    if (i < 0) continue;
    if (part.slice(0, i).trim() === name) return decodeURIComponent(part.slice(i + 1).trim());
  }
  return undefined;
}
