import fs from 'node:fs';
import { Readable } from 'node:stream';
import type { Context } from 'hono';

const MIME: Record<string, string> = { '.mp4': 'video/mp4', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png' };

/** Range 요청을 지원하는 파일 응답 (프록시 영상 스트리밍용). */
export function serveFile(c: Context, filePath: string): Response {
  let st: fs.Stats;
  try {
    st = fs.statSync(filePath);
  } catch {
    return new Response('Not Found', { status: 404 });
  }
  const ext = filePath.slice(filePath.lastIndexOf('.')).toLowerCase();
  const type = MIME[ext] ?? 'application/octet-stream';
  const range = c.req.header('range');
  const headers: Record<string, string> = {
    'Content-Type': type,
    'Accept-Ranges': 'bytes',
    'Cache-Control': 'private, max-age=3600',
    'Last-Modified': st.mtime.toUTCString(),
  };

  if (range) {
    const m = /^bytes=(\d*)-(\d*)$/.exec(range);
    if (m) {
      const start = m[1] ? Number(m[1]) : Math.max(0, st.size - Number(m[2]));
      const end = m[1] && m[2] ? Math.min(Number(m[2]), st.size - 1) : st.size - 1;
      if (start <= end && start < st.size) {
        headers['Content-Range'] = `bytes ${start}-${end}/${st.size}`;
        headers['Content-Length'] = String(end - start + 1);
        const stream = Readable.toWeb(fs.createReadStream(filePath, { start, end })) as ReadableStream;
        return new Response(stream, { status: 206, headers });
      }
      return new Response(null, { status: 416, headers: { 'Content-Range': `bytes */${st.size}` } });
    }
  }
  headers['Content-Length'] = String(st.size);
  if (c.req.method === 'HEAD') return new Response(null, { status: 200, headers });
  const stream = Readable.toWeb(fs.createReadStream(filePath)) as ReadableStream;
  return new Response(stream, { status: 200, headers });
}
