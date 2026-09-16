/**
 * 마디 MCP 서버 (stdio). 에이전트 CLI 가 자식 프로세스로 띄운다.
 * 도구 호출은 전부 돌고 있는 엔진의 /api/agent/tools/:name 으로 넘긴다 — DB 를 여기서 열지 않는다.
 * 의존성 없음: JSON-RPC 2.0 을 줄 단위로 읽고 쓴다.
 *
 * env: MADI_ENGINE_URL, MADI_AGENT_TOKEN, MADI_VIDEO_ID, MADI_RUN_ID
 */
import { serveStdio } from './server.js';

serveStdio({
  engineUrl: process.env['MADI_ENGINE_URL'] ?? '',
  token: process.env['MADI_AGENT_TOKEN'] ?? '',
  videoId: process.env['MADI_VIDEO_ID'] ?? '',
  runId: process.env['MADI_RUN_ID'] ?? '',
  stdin: process.stdin,
  stdout: process.stdout,
});
