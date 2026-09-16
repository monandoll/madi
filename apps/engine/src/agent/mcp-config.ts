import fs from 'node:fs';
import path from 'node:path';
import { MCP_SERVER_NAME } from './claude.js';
import type { AgentRunOptions } from './provider.js';

/** claude --mcp-config 용 JSON 파일. 실행 폴더(cwd)에 둔다. */
export function writeMcpConfig(mcp: AgentRunOptions['mcp'], cwd: string): string {
  const file = path.join(cwd, 'mcp.json');
  fs.writeFileSync(file, JSON.stringify({ mcpServers: { [MCP_SERVER_NAME]: { command: mcp.command, args: mcp.args, env: mcp.env } } }, null, 2), 'utf8');
  return file;
}
