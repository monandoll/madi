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
