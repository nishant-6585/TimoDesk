/**
 * /kb/providers — HTTP surface for 3rd-party KB sources (local-first fallback).
 *
 *   GET    /kb/providers                → { ok, providers }   (tokens redacted)
 *   POST   /kb/providers                → add { name, url, authorization_token?, priority?, enabled?, description? }
 *   POST   /kb/providers/:name         → partial update { url?, authorization_token?, priority?, enabled?, description? }
 *   POST   /kb/providers/:name/enable  → enable
 *   POST   /kb/providers/:name/disable → disable
 *   DELETE /kb/providers/:name         → remove
 *
 * Same auth model as the other endpoints (JWT / kiosk token / dev bypass).
 */

import { IncomingMessage, ServerResponse } from 'http';
import { authorizeRequest } from '../auth/middleware';
import { KbProviderRegistry } from '../services/kb-providers';

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

async function parseJson(req: IncomingMessage): Promise<Record<string, unknown> | null> {
  try {
    return JSON.parse(await readBody(req)) as Record<string, unknown>;
  } catch {
    return null;
  }
}

/** Handle any request under /kb/providers. Returns false if the route didn't match. */
export async function handleKbProviders(
  req: IncomingMessage,
  res: ServerResponse,
  registry: KbProviderRegistry
): Promise<boolean> {
  const url = (req.url || '').replace(/\?.*$/, '');
  if (!url.startsWith('/kb/providers')) return false;

  const auth = await authorizeRequest(req);
  if (!auth.ok) {
    json(res, auth.status, { ok: false, reason: auth.reason });
    return true;
  }

  try {
    if (url === '/kb/providers' && req.method === 'GET') {
      json(res, 200, { ok: true, providers: registry.list() });
      return true;
    }

    if (url === '/kb/providers' && req.method === 'POST') {
      const body = await parseJson(req);
      if (!body) {
        json(res, 400, { ok: false, reason: 'Invalid JSON body' });
        return true;
      }
      const provider = registry.add(body as Parameters<KbProviderRegistry['add']>[0]);
      json(res, 201, { ok: true, provider });
      return true;
    }

    const toggleMatch = url.match(/^\/kb\/providers\/([^/]+)\/(enable|disable)$/);
    if (toggleMatch && req.method === 'POST') {
      const provider = registry.update(decodeURIComponent(toggleMatch[1]), {
        enabled: toggleMatch[2] === 'enable',
      });
      json(res, 200, { ok: true, provider });
      return true;
    }

    const nameMatch = url.match(/^\/kb\/providers\/([^/]+)$/);
    if (nameMatch && req.method === 'POST') {
      const body = await parseJson(req);
      if (!body) {
        json(res, 400, { ok: false, reason: 'Invalid JSON body' });
        return true;
      }
      const provider = registry.update(
        decodeURIComponent(nameMatch[1]),
        body as Parameters<KbProviderRegistry['update']>[1]
      );
      json(res, 200, { ok: true, provider });
      return true;
    }

    if (nameMatch && req.method === 'DELETE') {
      registry.remove(decodeURIComponent(nameMatch[1]));
      json(res, 200, { ok: true });
      return true;
    }

    json(res, 405, { ok: false, reason: `unsupported ${req.method} on ${url}` });
    return true;
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    json(res, /not found/.test(reason) ? 404 : 400, { ok: false, reason });
    return true;
  }
}
