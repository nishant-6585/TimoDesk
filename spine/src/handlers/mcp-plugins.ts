/**
 * /mcp/plugins — HTTP surface for the MCP plugin platform.
 *
 *   GET    /mcp/plugins                 → { ok, plugins }        (tokens redacted)
 *   POST   /mcp/plugins                 → add { name, url, authorization_token?, enabled?, description? }
 *   DELETE /mcp/plugins/:name           → remove
 *   POST   /mcp/plugins/:name/enable    → enable
 *   POST   /mcp/plugins/:name/disable   → disable
 *
 * Same auth model as the other endpoints (JWT / kiosk token / dev bypass).
 */

import { IncomingMessage, ServerResponse } from 'http';
import { authorizeRequest } from '../auth/middleware';
import { McpPluginRegistry, McpPlugin } from '../services/mcp-plugins';

function readBody(req: IncomingMessage): Promise<string> {
  return new Promise(resolve => {
    let b = '';
    req.on('data', c => (b += c.toString()));
    req.on('end', () => resolve(b));
  });
}

function json(res: ServerResponse, status: number, payload: unknown): void {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(payload));
}

/** Handle any request under /mcp/plugins. Returns false if the route didn't match. */
export async function handleMcpPlugins(
  req: IncomingMessage,
  res: ServerResponse,
  registry: McpPluginRegistry
): Promise<boolean> {
  const url = (req.url || '').replace(/\?.*$/, '');
  if (!url.startsWith('/mcp/plugins')) return false;

  const auth = await authorizeRequest(req);
  if (!auth.ok) {
    json(res, auth.status, { ok: false, reason: auth.reason });
    return true;
  }

  if (url === '/mcp/plugins' && req.method === 'GET') {
    json(res, 200, { ok: true, plugins: registry.list() });
    return true;
  }

  if (url === '/mcp/plugins' && req.method === 'POST') {
    let body: Partial<McpPlugin>;
    try {
      body = JSON.parse(await readBody(req)) as Partial<McpPlugin>;
    } catch {
      json(res, 400, { ok: false, reason: 'Invalid JSON body' });
      return true;
    }
    const result = registry.add(body);
    if (!result.ok) {
      json(res, 400, { ok: false, reason: result.reason });
      return true;
    }
    json(res, 201, { ok: true, plugin: result.plugin });
    return true;
  }

  const toggleMatch = url.match(/^\/mcp\/plugins\/([^/]+)\/(enable|disable)$/);
  if (toggleMatch && req.method === 'POST') {
    const plugin = registry.setEnabled(decodeURIComponent(toggleMatch[1]), toggleMatch[2] === 'enable');
    if (!plugin) {
      json(res, 404, { ok: false, reason: `plugin "${toggleMatch[1]}" not found` });
      return true;
    }
    json(res, 200, { ok: true, plugin });
    return true;
  }

  const nameMatch = url.match(/^\/mcp\/plugins\/([^/]+)$/);
  if (nameMatch && req.method === 'DELETE') {
    const removed = registry.remove(decodeURIComponent(nameMatch[1]));
    if (!removed) {
      json(res, 404, { ok: false, reason: `plugin "${nameMatch[1]}" not found` });
      return true;
    }
    json(res, 200, { ok: true });
    return true;
  }

  json(res, 405, { ok: false, reason: `unsupported ${req.method} on ${url}` });
  return true;
}
