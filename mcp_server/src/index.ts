#!/usr/bin/env node
/**
 * Mikee MCP server — exposes the reception robot to any MCP client
 * (Claude Desktop, Claude Code, custom agents) over stdio.
 *
 * Architecture rule preserved: this server is a CLIENT of the spine. Every
 * motion command goes through the spine's intent layer on port 4000, so the
 * safety interlocks apply to AI agents exactly as they do to human operators.
 *
 * Required env:
 *   SPINE_URL           http://<spine-host>:4000   (default http://127.0.0.1:4000)
 *   SPINE_TOKEN         kiosk token (or Supabase JWT) the spine accepts
 *   SUPABASE_URL        Supabase project URL   (nav-point lookups)
 *   SUPABASE_ANON_KEY   Supabase anon key      (nav-point lookups)
 */

import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { loadConfig } from './config.js';
import { SpineClient } from './spine-client.js';
import { NavPointsClient } from './nav-points.js';
import { registerTools } from './tools.js';

async function main(): Promise<void> {
  const config = loadConfig();
  if (!config.spineToken) {
    // Warn but don't exit: the spine's dev bypass accepts empty tokens in dev.
    console.error('[mikee-mcp] WARNING: SPINE_TOKEN not set — only works if spine dev auth bypass is on');
  }

  const spine = new SpineClient(config.spineWsUrl, config.spineHttpUrl, config.spineToken);
  const navPoints = new NavPointsClient(config.supabaseUrl, config.supabaseAnonKey);

  const server = new McpServer({ name: 'mikee-mcp-server', version: '0.1.0' });
  registerTools(server, { spine, navPoints });

  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error(`[mikee-mcp] running on stdio — spine at ${config.spineHttpUrl}`);
}

main().catch(err => {
  console.error('[mikee-mcp] fatal:', err);
  process.exit(1);
});
