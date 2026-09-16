/** 18:24, 1:02:03 */
export function formatDuration(sec: number | null | undefined): string {
  if (sec == null || !Number.isFinite(sec)) return '';
  const total = Math.max(0, Math.round(sec));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const mm = h > 0 ? String(m).padStart(2, '0') : String(m);
  return `${h > 0 ? `${h}:` : ''}${mm}:${String(s).padStart(2, '0')}`;
}

/** 9월 14일. 해가 다르면 2025년 9월 14일. */
export function formatDate(ms: number, now: Date = new Date()): string {
  const d = new Date(ms);
  const base = `${d.getMonth() + 1}월 ${d.getDate()}일`;
  return d.getFullYear() === now.getFullYear() ? base : `${d.getFullYear()}년 ${base}`;
}

/** 오전 10:12 */
export function formatTime(ms: number): string {
  const d = new Date(ms);
  const h = d.getHours();
  const hh = h % 12 === 0 ? 12 : h % 12;
  return `${h < 12 ? '오전' : '오후'} ${hh}:${String(d.getMinutes()).padStart(2, '0')}`;
}

/** 자막 편집 입력용: 3 · 3.5 · 0:03 · 1:02.5 · 1:02:03 → 초. 이상하면 null. */
export function parseClock(input: string): number | null {
  const t = input.trim();
  if (!t) return null;
  const parts = t.split(':');
  if (parts.length > 3 || parts.some((p) => !/^\d+(\.\d+)?$/.test(p))) return null;
  let sec = 0;
  for (const p of parts) sec = sec * 60 + Number(p);
  return Number.isFinite(sec) ? Math.round(sec * 10) / 10 : null;
}

/** parseClock 의 반대. 0:03.5 (소수점은 있을 때만) */
export function formatClock(sec: number): string {
  const total = Math.max(0, Math.round(sec * 10) / 10);
  const m = Math.floor(total / 60);
  const s = total - m * 60;
  const ss = Number.isInteger(s) ? String(s).padStart(2, '0') : s.toFixed(1).padStart(4, '0');
  return `${m}:${ss}`;
}
