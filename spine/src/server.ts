/**
 * server.ts — WebSocket server + HTTP endpoints (admin clients + enrollment)
 * Clients connect → auth → session established → route intents
 * POST /enroll → face enrollment (JWT auth + DPDP gates)
 */

import http from 'http';
import { WebSocket, WebSocketServer } from 'ws';
import { RobotSDK } from './robot/interface';
import { SpineMessage, AdminMessage, RobotStatus, RobotEvent, RobotPosition } from './types';
import { routeMessage } from './commands/router';
import { verifyToken } from './auth/middleware';
import { logAdminSession, logEvent } from './supabase/events';
import { createSensorPipeline } from './sensors';
import { handleEnroll } from './handlers/enroll';
import { handleCheckFace } from './handlers/check-face';
import { handleVisit } from './handlers/visit';
import { handleVoiceLog } from './handlers/voice';
import { handleListStaff, handleUpdateStaff, handleDeleteStaff } from './handlers/staff';
import { handleListCaptures } from './handlers/captures';
import { handleAsk } from './handlers/ask';
import { getSupabaseClient } from './supabase/client';
import { initializeFaceModels } from './services/face-embedding';
import { FaceRecognitionService } from './services/face-recognition';
import { maybeNotifyBatteryLow, maybeNotifyObstacleBlocked } from './services/push';

const PORT = parseInt(process.env.SPINE_PORT || '4000', 10);

interface AuthenticatedSocket extends WebSocket {
  sessionId?: string;
  userId?: string;
}

export function startServer(sdk: RobotSDK): Promise<void> {
  return new Promise(async (resolve, reject) => {
    const supabase = getSupabaseClient();

    // Single broadcast path for RobotEvents → admin clients. Assigned once the
    // WebSocket server exists (below); declared here so HTTP route handlers
    // (e.g. /visit) can reference it. No-op until assigned (requests arrive after).
    let broadcastRobotEvent: (event: RobotEvent) => void = () => {};

    // Spine-owned navigation state, broadcast to ALL clients (admin + robot app)
    // so a Go To pressed on either platform shows its banner + Cancel on both.
    // Cleared on the robot's cancel_result; replaced by each new navi.
    let naviState: {
      active: boolean;
      point?: RobotPosition;
      name?: string;
      source?: string;
      startedAt?: number;
      cancelling?: boolean;
      arrived?: boolean;
      stalled?: boolean;
      arrivalText?: string;
    } = { active: false };
    let broadcastNaviState: () => void = () => {};

    // Arrival watcher: while a navi is active, poll the live pose against the
    // target. Within ARRIVE_DIST_M we're "there"; we then wait for the heading
    // to align (or ARRIVE_ROT_WAIT_MS of hunting) and CANCEL the residual goal —
    // the chassis otherwise keeps rotating at the point indefinitely. Broadcasts
    // navi_state {active:false, arrived:true} so both UIs show "complete".
    const ARRIVE_DIST_M = 0.4;
    const ARRIVE_ROT_TOL_DEG = 20;
    const ARRIVE_ROT_WAIT_MS = 10_000;
    const NAVI_WATCH_TIMEOUT_MS = 4 * 60_000;
    let naviWatchTimer: ReturnType<typeof setInterval> | null = null;
    const stopNaviWatch = () => {
      if (naviWatchTimer) {
        clearInterval(naviWatchTimer);
        naviWatchTimer = null;
      }
    };
    const startNaviWatch = () => {
      stopNaviWatch();
      const target = naviState.point;
      if (!target || !sdk.getPosition) return;
      const watchStarted = Date.now();
      let nearSince: number | null = null;
      let lastPose: RobotPosition | null = null;
      let lastMovedAt = Date.now();
      naviWatchTimer = setInterval(async () => {
        if (!naviState.active) {
          stopNaviWatch();
          return;
        }
        try {
          const pos = await sdk.getPosition!();
          const dist = Math.hypot(pos.x - target.x, pos.y - target.y);

          // Stall detection: goal active but the robot has not TRANSLATED
          // (>0.15m) for 30s and isn't at the goal → either fully wedged (needs
          // power-cycle) or spinning in place because the planner can't find a
          // clear path out of its spot. Rotation deliberately does NOT count as
          // progress — endless rotate-in-place is exactly a failure mode.
          if (lastPose) {
            const translated = Math.hypot(pos.x - lastPose.x, pos.y - lastPose.y) > 0.15;
            if (translated) {
              lastMovedAt = Date.now();
              if (naviState.stalled) {
                naviState = { ...naviState, stalled: false };
                broadcastNaviState();
              }
            } else if (!naviState.stalled && dist > ARRIVE_DIST_M &&
                Date.now() - lastMovedAt > 30_000) {
              console.log('[Spine] Navi STALLED — goal active but robot not translating');
              naviState = { ...naviState, stalled: true };
              broadcastNaviState();
            }
          } else {
            lastMovedAt = Date.now();
          }
          lastPose = pos;
          if (dist <= ARRIVE_DIST_M) {
            nearSince = nearSince ?? Date.now();
            const rotDelta = Math.abs(((pos.rotation - target.rotation + 540) % 360) - 180);
            if (rotDelta <= ARRIVE_ROT_TOL_DEG || Date.now() - nearSince >= ARRIVE_ROT_WAIT_MS) {
              console.log(`[Spine] Navi arrival detected (dist ${dist.toFixed(2)}m, rotΔ ${rotDelta.toFixed(0)}°) — completing`);
              stopNaviWatch();
              const name = naviState.name;
              const arrivalText = naviState.arrivalText;
              naviState = { active: false, arrived: true, name, arrivalText };
              // Kill any residual rotation-hunting at the goal.
              try {
                await sdk.cancelNavi?.();
              } catch { /* best-effort */ }
              broadcastNaviState();
              naviState = { active: false }; // arrived is a one-shot flag
            }
          } else {
            nearSince = null;
          }
          if (naviState.active && Date.now() - watchStarted > NAVI_WATCH_TIMEOUT_MS) {
            console.log('[Spine] Navi watch timeout — clearing stale navi_state');
            stopNaviWatch();
            naviState = { active: false };
            broadcastNaviState();
          }
        } catch { /* pose read failed — skip this tick */ }
      }, 2000);
    };

    // Initialize face-api models BEFORE server starts (required for enrollment)
    try {
      console.log('[Spine] Loading face-api models...');
      const modelUrl = process.env.FACE_API_MODEL_URL || 'https://cdn.jsdelivr.net/npm/@vladmandic/face-api@latest/model';
      await initializeFaceModels(modelUrl);
      console.log('[Spine] ✓ Face-api models loaded');
    } catch (err) {
      console.error('[Spine] Failed to load face-api models:', err);
      // Non-fatal: server starts but /enroll will fail with clearer error
    }

    // Create HTTP server (used for both WebSocket + HTTP routes)
    const httpServer = http.createServer(async (req, res) => {
      // CORS headers on every response
      res.setHeader('Access-Control-Allow-Origin', '*');
      res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PATCH, DELETE, OPTIONS');
      res.setHeader('Access-Control-Allow-Headers', 'authorization, content-type');

      // Handle preflight OPTIONS
      if (req.method === 'OPTIONS') {
        res.writeHead(204);
        res.end();
        return;
      }

      // Handle HTTP routes
      const url = req.url || '';

      // Battery bridge: real chassis charge fed from adb logcat (robot-core
      // robot_info). Doesn't need Supabase. Body: { battery: 0-100, charging: bool }.
      if (url === '/robot/battery' && req.method === 'POST') {
        let body = '';
        req.on('data', (c) => (body += c));
        req.on('end', () => {
          try {
            const { battery, charging } = JSON.parse(body || '{}');
            if (typeof battery === 'number' && sdk.setRealBattery) {
              sdk.setRealBattery(battery, !!charging);
            }
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ ok: true }));
          } catch {
            res.writeHead(400, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ ok: false, reason: 'bad body' }));
          }
        });
        return;
      }

      // All HTTP routes need Supabase; fail clearly if it isn't configured.
      if (!supabase) {
        res.writeHead(503, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: false, reason: 'Supabase not configured' }));
        return;
      }

      if (url === '/enroll' && req.method === 'POST') {
        await handleEnroll(req, res, supabase);
        return;
      }

      if (url === '/check-face' && req.method === 'POST') {
        await handleCheckFace(req, res, supabase);
        return;
      }

      if (url === '/visit' && req.method === 'POST') {
        await handleVisit(req, res, supabase, broadcastRobotEvent);
        return;
      }

      if (url === '/voice/log' && req.method === 'POST') {
        await handleVoiceLog(req, res, supabase);
        return;
      }

      if (url === '/staff' && req.method === 'GET') {
        await handleListStaff(req, res, supabase);
        return;
      }

      if (url === '/captures' && req.method === 'GET') {
        await handleListCaptures(req, res, supabase);
        return;
      }

      if (url === '/ask' && req.method === 'POST') {
        await handleAsk(req, res, supabase);
        return;
      }

      const staffMatch = url.match(/^\/staff\/([^/]+)$/);
      if (staffMatch) {
        const staffId = decodeURIComponent(staffMatch[1]);
        if (req.method === 'PATCH') {
          await handleUpdateStaff(req, res, supabase, staffId);
          return;
        }
        if (req.method === 'DELETE') {
          await handleDeleteStaff(req, res, supabase, staffId);
          return;
        }
      }

      // 404 for unknown routes
      res.writeHead(404);
      res.end(JSON.stringify({ error: 'Not found' }));
    });

    // Attach WebSocket server to HTTP server
    const wss = new WebSocketServer({ server: httpServer });

    console.log(`[Spine] WebSocket server starting on port ${PORT}`);

    wss.on('connection', (ws: AuthenticatedSocket) => {
      const tempSessionId = Math.random().toString(36).substring(7);
      console.log(`[Spine] Client connected: ${tempSessionId}`);

      let authenticated = false;

      // Timeout: client must auth within 5s
      const authTimeout = setTimeout(() => {
        if (!authenticated) {
          console.log(`[Spine] Auth timeout: ${tempSessionId}`);
          ws.close(1000, 'Auth timeout');
        }
      }, 5000);

      ws.on('message', async (rawData: Buffer | ArrayBuffer | Buffer[]) => {
        try {
          const data = Array.isArray(rawData)
            ? Buffer.concat(rawData).toString()
            : rawData.toString();

          console.log(`[Spine WebSocket] ======== MESSAGE RECEIVED ========`);
          console.log(`[Spine WebSocket] Session: ${tempSessionId} (authenticated: ${authenticated})`);
          console.log(`[Spine WebSocket] Raw data: ${data}`);

          const msg = JSON.parse(data) as AdminMessage;
          console.log(`[Spine WebSocket] Parsed message type: ${msg.type}`);

          // 1. AUTH — must be first message
          if (msg.type === 'auth') {
            console.log(`[Spine WebSocket] Processing AUTH message`);
            clearTimeout(authTimeout);

            const token = msg.token || '';
            const auth = await verifyToken(token);

            if (!auth.valid) {
              console.log(`[Spine WebSocket] Auth failed: ${auth.reason}`);
              ws.send(
                JSON.stringify({
                  type: 'error',
                  message: `Auth failed: ${auth.reason}`,
                } as SpineMessage)
              );
              ws.close(1000, 'Auth failed');
              return;
            }

            authenticated = true;
            ws.sessionId = tempSessionId;
            ws.userId = auth.userId;

            console.log(`[Spine WebSocket] Authenticated: ${ws.userId} (session ${ws.sessionId})`);
            await logAdminSession(ws.sessionId, 'connected', ws.userId);

            const authResponse = {
              type: 'authenticated',
              message: `Welcome ${ws.userId}`,
            } as SpineMessage;
            console.log(`[Spine WebSocket] Sending auth response: ${JSON.stringify(authResponse)}`);
            ws.send(JSON.stringify(authResponse));

            // Emit initial robot status
            console.log(`[Spine WebSocket] Fetching and sending initial robot status`);
            const status = await sdk.getStatus();
            const statusResponse = { type: 'robot_status', status } as SpineMessage;
            ws.send(JSON.stringify(statusResponse));

            // Emit current navigation state so a client joining mid-nav shows the banner.
            ws.send(JSON.stringify({ type: 'navi_state', ...naviState } as SpineMessage));

            return;
          }

          // 2. All other messages require auth
          if (!authenticated) {
            console.log(`[Spine WebSocket] Received non-auth message but not authenticated`);
            ws.send(
              JSON.stringify({
                type: 'error',
                message: 'Not authenticated — send auth message first',
              } as SpineMessage)
            );
            return;
          }

          // Voice phase (#80): robot_app broadcasts its voice state → re-broadcast
          // to ALL clients (admin app) as a voice_* event. Not a robot command, so
          // it bypasses the interlock/handler path. Payload shape mirrors the other
          // events (eventPayload.payload.state), consistent with face_detected.
          if (msg.type === 'intent' && msg.intent?.intent === 'voice_state') {
            const vs = msg.intent.voiceState;
            if (vs === 'listening' || vs === 'thinking' || vs === 'speaking' || vs === 'idle') {
              broadcastRobotEvent({ type: `voice_${vs}`, payload: { state: vs } });
            }
            ws.send(JSON.stringify({ type: 'ack', intent: 'voice_state', ok: true } as SpineMessage));
            return;
          }

          // 3. Route the message
          console.log(`[Spine WebSocket] Authenticated message, routing to handler...`);
          const response = await routeMessage(msg, ws.sessionId!, ws.userId!, sdk);
          console.log(`[Spine WebSocket] Handler returned response type: ${response.type}`);
          console.log(`[Spine WebSocket] Sending response to client: ${JSON.stringify(response)}`);
          ws.send(JSON.stringify(response));

          // Navigation state sync: a successfully-acked navi/cancel_navi updates
          // the shared navi_state and pushes it to every connected client.
          if (msg.type === 'intent' && response.type === 'ack' && response.ok) {
            const it = msg.intent?.intent;
            if (it === 'navi') {
              naviState = {
                active: true,
                point: msg.intent?.point,
                name: msg.intent?.name,
                source: msg.intent?.source ?? 'admin',
                arrivalText: msg.intent?.arrivalText,
                startedAt: Date.now(),
              };
              broadcastNaviState();
              startNaviWatch();
            } else if (it === 'cancel_navi' && naviState.active) {
              naviState = { ...naviState, cancelling: true };
              broadcastNaviState();
            }
          }
          console.log(`[Spine WebSocket] ======== MESSAGE COMPLETE ========`);
        } catch (err) {
          console.error('[Spine WebSocket] !!!! MESSAGE HANDLING ERROR !!!!');
          console.error('[Spine WebSocket] Error:', err);
          ws.send(
            JSON.stringify({
              type: 'error',
              message: 'Internal server error',
            } as SpineMessage)
          );
        }
      });

      ws.on('close', async () => {
        clearTimeout(authTimeout);
        if (authenticated && ws.sessionId) {
          console.log(`[Spine] Client disconnected: ${ws.sessionId}`);
          await logAdminSession(ws.sessionId, 'disconnected', ws.userId);
        }
      });

      ws.on('error', (err) => {
        console.error('[Spine] WebSocket error:', err);
      });
    });

    httpServer.listen(PORT, () => {
      console.log(`✓ Spine server listening on port ${PORT} (WebSocket + HTTP routes)`);
      resolve();
    });

    httpServer.on('error', (err) => {
      console.error('[Spine] Server error:', err);
      reject(err);
    });

    // CRITICAL: Process-level safety nets to prevent enrollment crashes from killing the broker
    // These MUST stay in place: a bad face image must not take down robot control/camera/WS
    process.on('unhandledRejection', (err) => {
      console.error('[Spine] UNHANDLED REJECTION:', err);
      // Log but don't exit — /enroll handler should still return 500
    });

    process.on('uncaughtException', (err) => {
      console.error('[Spine] UNCAUGHT EXCEPTION:', err);
      // Log but don't exit — keep server alive for robot control
    });

    broadcastNaviState = () => {
      const msg = { type: 'navi_state', ...naviState } as SpineMessage;
      console.log(`[Spine] Broadcasting navi_state: ${JSON.stringify(msg)}`);
      wss.clients.forEach((client) => {
        if (client.readyState === WebSocket.OPEN) {
          client.send(JSON.stringify(msg));
        }
      });
    };

    // Single broadcast path for all RobotEvents → { type:'event', event, eventPayload }.
    broadcastRobotEvent = (event: RobotEvent) => {
      const { type: eventType, ...rest } = event;
      const msg: SpineMessage = {
        type: 'event',
        event: eventType,
        eventPayload: rest,
      };
      wss.clients.forEach((client) => {
        if (client.readyState === WebSocket.OPEN) {
          client.send(JSON.stringify(msg));
        }
      });
      // The robot confirmed a navigation cancel → clear the shared navi state.
      if (eventType === 'navi_event' && (event.payload as Record<string, any>)?.event === 'cancel_result') {
        if (naviState.active || naviState.cancelling) {
          naviState = { active: false };
          broadcastNaviState();
        }
      }
      // Push trigger (#90): battery low → notify admins (best-effort, never throws).
      if (eventType === 'battery_update' && supabase) {
        const level = Number(event.payload?.level);
        if (Number.isFinite(level)) void maybeNotifyBatteryLow(supabase, level);
      }
    };

    // Robot-originated events (battery, etc.) go through it…
    sdk.onEvent(broadcastRobotEvent);

    // …and so does the autonomous face recognizer (same path, one event shape).
    if (supabase) {
      const recognizerIP = process.env.ROBOT_IP || '192.168.99.101';
      const recognizer = new FaceRecognitionService(recognizerIP, supabase, broadcastRobotEvent);
      recognizer.start().catch((err) => {
        console.error('[Spine] Face recognizer failed to start:', err);
        // Non-fatal: robot control/camera/WS keep running.
      });
    } else {
      console.log('[Spine] Face recognizer disabled — Supabase not configured.');
    }

    // Sensor/obstacle awareness (Phase 1A): each SensorEvent updates the cached
    // RobotStatus, broadcasts it to all clients, and logs to Supabase.
    const broadcastStatus = (status: RobotStatus) => {
      const msg: SpineMessage = { type: 'robot_status', status };
      wss.clients.forEach((client: WebSocket) => {
        if (client.readyState === WebSocket.OPEN) {
          client.send(JSON.stringify(msg));
        }
      });
      // Push trigger (#90): obstacle blocked → notify admins (best-effort).
      // Fires once the CSJBot nav events feed the pipeline (#81).
      if (supabase && status.obstacleState) {
        void maybeNotifyObstacleBlocked(supabase, status.obstacleState);
      }
    };

    void sdk.getStatus().then((initialStatus) => {
      const handleSensorEvent = createSensorPipeline(
        initialStatus,
        broadcastStatus,
        (type, payload) => {
          void logEvent(type, payload);
        }
      );
      sdk.onSensorEvent(handleSensorEvent);
    });

    // Status heartbeat: clients only request robot_status once (at auth), so
    // without this they'd never see the robot come online/offline or battery
    // change after connecting. Poll the SDK and broadcast every 5s. getStatus()
    // is a cheap read of cached state (no robot round-trip), so this is light.
    setInterval(() => {
      void sdk.getStatus().then(broadcastStatus);
    }, 5000);
  });
}
