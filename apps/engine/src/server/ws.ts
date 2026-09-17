import type { Hono } from 'hono';
import { createNodeWebSocket } from '@hono/node-ws';
import type { WSContext } from 'hono/ws';
import { TermIn, type TermOut, type WsEvent } from '@madi/shared';
import type { Logger } from '../log.js';
import { openTerm, termLine, termPlan, type TermSession } from './term.js';

/**
 * /ws 로 붙은 브라우저 전부에 이벤트를 뿌린다.
 * /api/term 은 화면 안 터미널 — `/api/*` 라서 밖에서 들어온 기기는 짝을 지어야 붙는다.
 */
export function attachWs(app: Hono, version: string, log: Logger) {
  const { injectWebSocket, upgradeWebSocket } = createNodeWebSocket({ app });
  const clients = new Set<WSContext>();
  // 터미널은 한 번에 하나 (여러 창이 같은 로그인을 동시에 물지 않게)
  let term: TermSession | null = null;

  app.get(
    '/ws',
    upgradeWebSocket(() => ({
      onOpen(_evt, ws) {
        clients.add(ws);
        ws.send(JSON.stringify({ type: 'hello', version } satisfies WsEvent));
      },
      onClose(_evt, ws) {
        clients.delete(ws);
      },
    })),
  );

  app.get(
    '/api/term',
    upgradeWebSocket(() => {
      const send = (msg: TermOut, ws: WSContext) => {
        try {
          ws.send(JSON.stringify(msg));
        } catch {
          /* 닫혔다 */
        }
      };
      let mine: TermSession | null = null;
      const close = () => {
        if (mine) {
          mine.kill();
          if (term === mine) term = null;
          mine = null;
        }
      };
      return {
        onMessage(evt, ws) {
          const raw = safeJson(String(evt.data));
          const parsed = TermIn.safeParse(raw);
          if (!parsed.success) {
            // 목록 밖을 열려고 하면 바로 아니라고 말해 준다 (기다리게 두지 않는다)
            if (typeof raw === 'object' && raw !== null && (raw as { t?: unknown }).t === 'open') send({ t: 'error', code: 'bad_kind' }, ws);
            return;
          }
          const msg = parsed.data;
          if (msg.t === 'open') {
            if (mine) return;
            if (term) return send({ t: 'error', code: 'busy' }, ws);
            if (!termPlan(msg.kind)) return send({ t: 'error', code: 'not_found' }, ws);
            const session = openTerm(
              msg.kind,
              { cols: msg.cols, rows: msg.rows },
              {
                onData: (d) => send({ t: 'out', d }, ws),
                onExit: (code) => {
                  send({ t: 'exit', code }, ws);
                  if (term === mine) term = null;
                  mine = null;
                },
              },
              log,
            );
            if (!session) return send({ t: 'error', code: 'not_found' }, ws);
            mine = session;
            term = session;
            send({ t: 'ready', title: termPlan(msg.kind)!.title, line: termLine(msg.kind) }, ws);
            return;
          }
          if (!mine) return;
          if (msg.t === 'in') mine.write(msg.d);
          else if (msg.t === 'size') mine.resize(msg.cols, msg.rows);
          else if (msg.t === 'kill') close();
        },
        onClose() {
          close();
        },
        onError() {
          close();
        },
      };
    }),
  );

  return {
    injectWebSocket,
    broadcast(event: WsEvent) {
      const data = JSON.stringify(event);
      for (const ws of clients) {
        try {
          ws.send(data);
        } catch {
          clients.delete(ws);
        }
      }
    },
    closeAll() {
      term?.kill();
      term = null;
      for (const ws of clients) {
        try {
          ws.close();
        } catch {
          /* already gone */
        }
      }
      clients.clear();
    },
    get size() {
      return clients.size;
    },
  };
}

function safeJson(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}
