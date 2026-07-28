/**
 * mcp-plugins-http.test.ts — the /mcp/plugins HTTP surface.
 * Auth is mocked open; the registry runs against a temp file.
 */
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { EventEmitter } from 'events';
import { mkdtempSync, rmSync } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';
import type { IncomingMessage, ServerResponse } from 'http';

vi.mock('../src/auth/middleware', () => ({
  authorizeRequest: vi.fn(async () => ({ ok: true, userId: 'test-user' })),
}));

import { handleMcpPlugins } from '../src/handlers/mcp-plugins';
import { McpPluginRegistry } from '../src/services/mcp-plugins';

let dir: string;
let registry: McpPluginRegistry;

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'mcp-http-'));
  registry = new McpPluginRegistry(join(dir, 'plugins.json'));
});

afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

interface FakeRes {
  status: number;
  body: Record<string, unknown>;
}

async function request(method: string, url: string, body?: unknown): Promise<FakeRes | null> {
  const req = new EventEmitter() as unknown as IncomingMessage;
  (req as { method: string }).method = method;
  (req as { url: string }).url = url;
  (req as { headers: object }).headers = {};

  const out: FakeRes = { status: 0, body: {} };
  const res = {
    writeHead: (status: number) => {
      out.status = status;
    },
    end: (payload?: string) => {
      out.body = payload ? (JSON.parse(payload) as Record<string, unknown>) : {};
    },
  } as unknown as ServerResponse;

  const handled = handleMcpPlugins(req, res, registry);
  // Emit the body after the handler has attached its listeners.
  setImmediate(() => {
    if (body !== undefined) req.emit('data', JSON.stringify(body));
    req.emit('end');
  });
  return (await handled) ? out : null;
}

describe('/mcp/plugins HTTP surface', () => {
  it('ignores unrelated routes', async () => {
    expect(await request('GET', '/kb/status')).toBeNull();
  });

  it('POST adds a plugin and GET lists it with the token redacted', async () => {
    const post = await request('POST', '/mcp/plugins', {
      name: 'slack',
      url: 'https://mcp.slack.com/mcp',
      authorization_token: 'xoxp-secret',
    });
    expect(post?.status).toBe(201);

    const get = await request('GET', '/mcp/plugins');
    expect(get?.status).toBe(200);
    const plugins = get?.body.plugins as Array<Record<string, unknown>>;
    expect(plugins).toHaveLength(1);
    expect(plugins[0].name).toBe('slack');
    expect(plugins[0].has_token).toBe(true);
    expect(JSON.stringify(get?.body)).not.toContain('xoxp-secret');
  });

  it('rejects invalid bodies with 400', async () => {
    const res = await request('POST', '/mcp/plugins', { name: 'bad name!', url: 'nope' });
    expect(res?.status).toBe(400);
  });

  it('enable/disable and delete round-trip; unknown names 404', async () => {
    await request('POST', '/mcp/plugins', { name: 'crm', url: 'https://mcp.example.com/crm' });

    const off = await request('POST', '/mcp/plugins/crm/disable');
    expect(off?.status).toBe(200);
    expect((off?.body.plugin as { enabled: boolean }).enabled).toBe(false);

    const del = await request('DELETE', '/mcp/plugins/crm');
    expect(del?.status).toBe(200);

    expect((await request('POST', '/mcp/plugins/crm/enable'))?.status).toBe(404);
    expect((await request('DELETE', '/mcp/plugins/crm'))?.status).toBe(404);
  });
});
