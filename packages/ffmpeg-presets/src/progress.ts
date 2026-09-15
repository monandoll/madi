/**
 * `-progress pipe:1` 출력 파서. 블록마다 `out_time_us=...` 와 `progress=continue|end` 가 온다.
 * 청크 단위로 feed() 하면 완성된 값을 콜백으로 준다.
 */
export class ProgressParser {
  private buffer = '';
  private outTimeUs: number | null = null;

  constructor(
    private readonly totalSec: number,
    private readonly onProgress: (ratio: number) => void,
  ) {}

  feed(chunk: string): void {
    this.buffer += chunk;
    let nl: number;
    while ((nl = this.buffer.indexOf('\n')) >= 0) {
      const line = this.buffer.slice(0, nl).trim();
      this.buffer = this.buffer.slice(nl + 1);
      this.line(line);
    }
  }

  private line(line: string): void {
    const eq = line.indexOf('=');
    if (eq < 0) return;
    const key = line.slice(0, eq);
    const value = line.slice(eq + 1);
    if (key === 'out_time_us' || key === 'out_time_ms') {
      const n = Number(value);
      if (Number.isFinite(n) && n >= 0) this.outTimeUs = n;
    } else if (key === 'progress') {
      if (value === 'end') {
        this.onProgress(1);
      } else if (this.outTimeUs !== null && this.totalSec > 0) {
        this.onProgress(Math.min(0.999, this.outTimeUs / 1_000_000 / this.totalSec));
      }
    }
  }
}
