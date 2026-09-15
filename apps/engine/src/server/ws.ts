import type { Hono } from 'hono';
import { createNodeWebSocket } from '@hono/node-ws';
import type { WSContext } from 'hono/ws';
import type { WsEvent } from '@madi/shared';

/** /ws 로 붙은 브라우저 전부에 이벤트를 뿌린다. */
export function attachWs(app: Hono, version: string) {
  const { injectWebSocket, upgradeWebSocket } = createNodeWebSocket({ app });
  const clients = new Set<WSContext>();

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
