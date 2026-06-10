/**
 * server.ts — WebSocket server + HTTP endpoints (admin clients + enrollment)
 * Clients connect → auth → session established → route intents
 * POST /enroll → face enrollment (JWT auth + DPDP gates)
 */

import http from 'http';
import { WebSocket, WebSocketServer } from 'ws';
import { RobotSDK } from './robot/interface';
import { SpineMessage, AdminMessage, RobotStatus } from './types';
import { routeMessage } from './commands/router';
import { verifyToken } from './auth/middleware';
import { logAdminSession, logEvent } from './supabase/events';
import { createSensorPipeline } from './sensors';
import { handleEnroll } from './handlers/enroll';
import { getSupabaseClient } from './supabase/client';

const PORT = parseInt(process.env.SPINE_PORT || '4000', 10);

interface AuthenticatedSocket extends WebSocket {
  sessionId?: string;
  userId?: string;
}

export function startServer(sdk: RobotSDK): Promise<void> {
  return new Promise((resolve, reject) => {
    const supabase = getSupabaseClient();

    // Create HTTP server (used for both WebSocket + HTTP routes)
    const httpServer = http.createServer(async (req, res) => {
      // CORS headers on every response
      res.setHeader('Access-Control-Allow-Origin', '*');
      res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
      res.setHeader('Access-Control-Allow-Headers', 'authorization, content-type');

      // Handle preflight OPTIONS
      if (req.method === 'OPTIONS') {
        res.writeHead(204);
        res.end();
        return;
      }

      // Handle HTTP routes
      if (req.url === '/enroll' && req.method === 'POST') {
        await handleEnroll(req, res, supabase);
        return;
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
            const auth = verifyToken(token);

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

          // 3. Route the message
          console.log(`[Spine WebSocket] Authenticated message, routing to handler...`);
          const response = await routeMessage(msg, ws.sessionId!, ws.userId!, sdk);
          console.log(`[Spine WebSocket] Handler returned response type: ${response.type}`);
          console.log(`[Spine WebSocket] Sending response to client: ${JSON.stringify(response)}`);
          ws.send(JSON.stringify(response));
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

    // Register robot event handler to broadcast to all clients
    sdk.onEvent((event) => {
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
    });

    // Sensor/obstacle awareness (Phase 1A): each SensorEvent updates the cached
    // RobotStatus, broadcasts it to all clients, and logs to Supabase.
    const broadcastStatus = (status: RobotStatus) => {
      const msg: SpineMessage = { type: 'robot_status', status };
      wss.clients.forEach((client: WebSocket) => {
        if (client.readyState === WebSocket.OPEN) {
          client.send(JSON.stringify(msg));
        }
      });
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
  });
}
