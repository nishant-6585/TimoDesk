/**
 * tests/recordings.test.ts — the auth gate on the recording routes.
 *
 * These routes shipped UNAUTHENTICATED while the spine sat on a public tunnel,
 * so the gate is the behaviour worth pinning: every route 401s without a token,
 * and playback (and ONLY playback) may present its token in the query string
 * because a browser <video>/url_launcher request cannot set a header.
 *
 * `fs` is mocked so nothing touches the disk; the ffmpeg controller is a stub.
 */

import { describe, it, expect, vi, beforeEach } from 'vitest';

// The middleware reads KIOSK_TOKEN/DEV_AUTH_BYPASS at module load, so the env has
// to be set before the imports below run — hoisted, like tests/auth.test.ts does
// with resetModules. No SUPABASE_URL: the kiosk secret is the only way in here.
vi.hoisted(() => {
  process.env.DEV_AUTH_BYPASS = '0';
  process.env.KIOSK_TOKEN = 'kiosk-secret';
});

vi.mock('fs', () => {
  const files: Record<string, { size: number; mtimeMs: number }> = {
    'rec-a.mp4': { size: 100, mtimeMs: 2000 },
    'rec-b.mp4': { size: 200, mtimeMs: 3000 },
    'notes.txt': { size: 10, mtimeMs: 1000 },
  };
  const mock = {
    existsSync: vi.fn((p: string) => p === '/recordings' || p.split('/').pop()! in files),
    readdirSync: vi.fn(() => Object.keys(files)),
    statSync: vi.fn((p: string) => files[p.split('/').pop()!] ?? { size: 0, mtimeMs: 0 }),
    unlinkSync: vi.fn(),
    createReadStream: vi.fn(() => ({ pipe: vi.fn() })),
  };
  return { default: mock, ...mock };
});

import fs from 'fs';
import { handleRecordings, RecordingController } from '../src/handlers/recordings';

function makeReq(method: string, url: string, token?: string): any {
  return {
    method,
    url,
    headers: token ? { authorization: `Bearer ${token}` } : {},
  };
}

function makeRes() {
  const res: any = {
    statusCode: 0,
    headers: {} as Record<string, unknown>,
    body: '',
    writeHead: vi.fn((code: number, headers?: Record<string, unknown>) => {
      res.statusCode = code;
      if (headers) res.headers = headers;
    }),
    end: vi.fn((chunk?: string) => {
      res.body = chunk ?? '';
    }),
  };
  return res;
}

const ctl: RecordingController = {
  dir: '/recordings',
  status: () => ({ recording: false, file: null, maxMs: 300000 }),
  start: () => ({ ok: true, file: 'rec-new.mp4' }),
  stop: () => ({ ok: true, file: 'rec-new.mp4' }),
  activeFile: () => null,
};

const json = (res: any) => JSON.parse(res.body);

beforeEach(() => vi.clearAllMocks());

describe('auth gate', () => {
  const routes: [string, string][] = [
    ['POST', '/record/start'],
    ['POST', '/record/stop'],
    ['GET', '/record/status'],
    ['GET', '/recordings'],
    ['GET', '/recordings/rec-a.mp4'],
    ['DELETE', '/recordings/rec-a.mp4'],
  ];

  it.each(routes)('%s %s → 401 without a token', async (method, url) => {
    const res = makeRes();
    const handled = await handleRecordings(makeReq(method, url), res, ctl);
    expect(handled).toBe(true);
    expect(res.statusCode).toBe(401);
    expect(json(res).ok).toBe(false);
  });

  it.each(routes)('%s %s → not 401 with a valid token', async (method, url) => {
    const res = makeRes();
    await handleRecordings(makeReq(method, url, 'kiosk-secret'), res, ctl);
    expect(res.statusCode).not.toBe(401);
  });

  it('leaves unrelated routes alone (returns false, writes nothing)', async () => {
    const res = makeRes();
    expect(await handleRecordings(makeReq('GET', '/staff'), res, ctl)).toBe(false);
    expect(res.writeHead).not.toHaveBeenCalled();
  });
});

describe('?token= fallback (browser playback only)', () => {
  it('accepts a query token on GET /recordings/:file', async () => {
    const res = makeRes();
    await handleRecordings(makeReq('GET', '/recordings/rec-a.mp4?token=kiosk-secret'), res, ctl);
    expect(res.statusCode).toBe(200);
    expect(res.headers['Content-Type']).toBe('video/mp4');
  });

  it('rejects a WRONG query token', async () => {
    const res = makeRes();
    await handleRecordings(makeReq('GET', '/recordings/rec-a.mp4?token=nope'), res, ctl);
    expect(res.statusCode).toBe(401);
  });

  it('does NOT accept a query token on DELETE — headers only', async () => {
    const res = makeRes();
    await handleRecordings(makeReq('DELETE', '/recordings/rec-a.mp4?token=kiosk-secret'), res, ctl);
    expect(res.statusCode).toBe(401);
    expect(fs.unlinkSync).not.toHaveBeenCalled();
  });

  it('does NOT accept a query token on the list route', async () => {
    const res = makeRes();
    await handleRecordings(makeReq('GET', '/recordings?token=kiosk-secret'), res, ctl);
    expect(res.statusCode).toBe(401);
  });
});

describe('behaviour (authorized)', () => {
  it('lists only .mp4s, newest first, excluding the clip being written', async () => {
    const res = makeRes();
    const recording: RecordingController = { ...ctl, activeFile: () => 'rec-b.mp4' };
    await handleRecordings(makeReq('GET', '/recordings', 'kiosk-secret'), res, recording);
    expect(json(res)).toEqual({
      ok: true,
      recordings: [{ file: 'rec-a.mp4', size: 100, mtime: 2000 }],
    });
  });

  it('start returns 409 when a recording is already running', async () => {
    const res = makeRes();
    const busy: RecordingController = { ...ctl, start: () => ({ ok: false, error: 'already recording' }) };
    await handleRecordings(makeReq('POST', '/record/start', 'kiosk-secret'), res, busy);
    expect(res.statusCode).toBe(409);
    expect(json(res).error).toBe('already recording');
  });

  it('serves a byte range for seeking', async () => {
    const res = makeRes();
    const req = makeReq('GET', '/recordings/rec-a.mp4', 'kiosk-secret');
    req.headers.range = 'bytes=10-49';
    await handleRecordings(req, res, ctl);
    expect(res.statusCode).toBe(206);
    expect(res.headers['Content-Range']).toBe('bytes 10-49/100');
    expect(res.headers['Content-Length']).toBe(40);
  });

  it('refuses to delete the clip still being written', async () => {
    const res = makeRes();
    const recording: RecordingController = { ...ctl, activeFile: () => 'rec-a.mp4' };
    await handleRecordings(makeReq('DELETE', '/recordings/rec-a.mp4', 'kiosk-secret'), res, recording);
    expect(res.statusCode).toBe(409);
    expect(fs.unlinkSync).not.toHaveBeenCalled();
  });

  it('404s a non-mp4 name instead of reading it', async () => {
    const res = makeRes();
    await handleRecordings(makeReq('GET', '/recordings/notes.txt', 'kiosk-secret'), res, ctl);
    expect(res.statusCode).toBe(404);
    expect(fs.createReadStream).not.toHaveBeenCalled();
  });

  it('strips path traversal before touching the filesystem', async () => {
    const res = makeRes();
    await handleRecordings(
      makeReq('DELETE', '/recordings/' + encodeURIComponent('../../etc/passwd'), 'kiosk-secret'),
      res,
      ctl
    );
    expect(res.statusCode).toBe(404); // basename('../../etc/passwd') = 'passwd', not .mp4
    expect(fs.unlinkSync).not.toHaveBeenCalled();
  });
});
