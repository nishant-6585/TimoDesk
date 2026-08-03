/**
 * handlers/recordings.ts — video recording routes, EVERY ONE behind auth.
 *
 *   POST   /record/start      start ffmpeg over the robot's MJPEG stream
 *   POST   /record/stop       stop + finalize the current clip
 *   GET    /record/status     is a recording running right now
 *   GET    /recordings        list saved clips (newest first)
 *   GET    /recordings/:file  stream a clip (HTTP Range, so <video> can seek)
 *   DELETE /recordings/:file  delete a clip
 *
 * WHY THIS FILE EXISTS: these routes used to live inline in server.ts with NO auth
 * check at all, while the spine sits on a public tunnel (HANDOFF) — anyone who knew
 * the URL could list and download office camera footage. Pulling them into a handler
 * makes the gate testable and keeps server.ts owning only the ffmpeg lifecycle.
 *
 * The ffmpeg process itself stays in server.ts (it must survive across requests);
 * this module takes it as an injected [RecordingController].
 */

import { IncomingMessage, ServerResponse } from 'http';
import fs from 'fs';
import path from 'path';
import { authorizeRequest } from '../auth/middleware';

export interface RecordStatus {
  recording: boolean;
  file: string | null;
  startedAt?: number;
  maxMs: number;
}

/** The ffmpeg lifecycle, owned by server.ts and injected here. */
export interface RecordingController {
  /** Directory holding the .mp4 clips. */
  dir: string;
  status(): RecordStatus;
  start(): { ok: boolean; file?: string; error?: string };
  stop(): { ok: boolean; file?: string };
  /** Basename of the clip currently being written, or null when idle. */
  activeFile(): string | null;
}

function json(res: ServerResponse, status: number, payload: unknown): void {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(payload));
}

/**
 * Handle any /record* or /recordings* request.
 * Returns false when the route didn't match, so server.ts can fall through.
 */
export async function handleRecordings(
  req: IncomingMessage,
  res: ServerResponse,
  ctl: RecordingController
): Promise<boolean> {
  const url = (req.url || '').replace(/\?.*$/, '');
  const fileMatch = url.match(/^\/recordings\/([^/]+)$/);
  const isRecordingsRoute =
    url === '/record/start' ||
    url === '/record/stop' ||
    url === '/record/status' ||
    url === '/recordings' ||
    !!fileMatch;
  if (!isRecordingsRoute) return false;

  // Playback is the ONE route that may carry its token in the query string: the
  // admin opens the clip URL directly in the browser (url_launcher / <video>),
  // which cannot set an Authorization header.
  const allowQueryToken = !!fileMatch && req.method === 'GET';
  const auth = await authorizeRequest(req, { allowQueryToken });
  if (!auth.ok) {
    json(res, auth.status, { ok: false, reason: auth.reason });
    return true;
  }

  if (url === '/record/start' && req.method === 'POST') {
    const r = ctl.start();
    json(res, r.ok ? 200 : 409, r);
    return true;
  }

  if (url === '/record/stop' && req.method === 'POST') {
    const r = ctl.stop();
    json(res, r.ok ? 200 : 409, r);
    return true;
  }

  // Current status — so a screen shows live state on load (the WS
  // recording_state broadcast keeps it in sync after that).
  if (url === '/record/status' && req.method === 'GET') {
    json(res, 200, { ok: true, ...ctl.status() });
    return true;
  }

  // List clips, newest first, for the admin Gallery.
  if (url === '/recordings' && req.method === 'GET') {
    try {
      const files = fs.existsSync(ctl.dir)
        ? fs.readdirSync(ctl.dir).filter((f) => f.endsWith('.mp4'))
        : [];
      const active = ctl.activeFile();
      const list = files
        .map((f) => {
          const st = fs.statSync(path.join(ctl.dir, f));
          return { file: f, size: st.size, mtime: st.mtimeMs };
        })
        // Exclude the clip still being written (ffmpeg finalizes it on stop).
        .filter((r) => r.file !== active)
        .sort((a, b) => b.mtime - a.mtime);
      json(res, 200, { ok: true, recordings: list });
    } catch (err) {
      json(res, 500, { ok: false, reason: String(err) });
    }
    return true;
  }

  if (fileMatch) {
    // Path-traversal-safe: a basename inside ctl.dir, and .mp4 only.
    const name = path.basename(decodeURIComponent(fileMatch[1]));
    const filePath = path.join(ctl.dir, name);

    if (req.method === 'DELETE') {
      if (!name.endsWith('.mp4') || !fs.existsSync(filePath)) {
        json(res, 404, { ok: false, reason: 'not found' });
        return true;
      }
      if (ctl.activeFile() === name) {
        json(res, 409, { ok: false, reason: 'still recording' });
        return true;
      }
      try {
        fs.unlinkSync(filePath);
        json(res, 200, { ok: true });
      } catch (err) {
        json(res, 500, { ok: false, reason: String(err) });
      }
      return true;
    }

    if (req.method === 'GET') {
      if (!name.endsWith('.mp4') || !fs.existsSync(filePath)) {
        res.writeHead(404);
        res.end('not found');
        return true;
      }
      const stat = fs.statSync(filePath);
      const range = req.headers.range;
      if (range) {
        const m = range.match(/bytes=(\d+)-(\d*)/);
        const start = m ? parseInt(m[1], 10) : 0;
        const end = m && m[2] ? parseInt(m[2], 10) : stat.size - 1;
        res.writeHead(206, {
          'Content-Type': 'video/mp4',
          'Content-Range': `bytes ${start}-${end}/${stat.size}`,
          'Accept-Ranges': 'bytes',
          'Content-Length': end - start + 1,
        });
        fs.createReadStream(filePath, { start, end }).pipe(res);
      } else {
        res.writeHead(200, {
          'Content-Type': 'video/mp4',
          'Content-Length': stat.size,
          'Accept-Ranges': 'bytes',
        });
        fs.createReadStream(filePath).pipe(res);
      }
      return true;
    }
  }

  json(res, 405, { ok: false, reason: 'method not allowed' });
  return true;
}
