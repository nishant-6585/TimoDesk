/**
 * server.ts — WebSocket server for admin clients
 * Clients connect → auth → session established → route intents
 */

import { WebSocket, WebSocketServer } from 'ws';
import { RobotSDK } from './robot/interface';
import { SpineMessage, AdminMessage, RobotStatus } from './types';
import { routeMessage } from './commands/router';
import { verifyToken } from './auth/middleware';
import { logAdminSession, logEvent } from './supabase/events';
import { createSensorPipeline } from './sensors';

const PORT = parseInt(process.env.SPINE_PORT || '4000', 10);

interface AuthenticatedSocket extends WebSocket {
  sessionId?: string;
  userId?: string;
}

export function startServer(sdk: RobotSDK): Promise<void> {
  return new Promise((resolve, reject) => {
    const wss = new WebSocketServer({ port: PORT });

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

          const msg = JSON.parse(data) as AdminMessage;

          // 1. AUTH — must be first message
          if (msg.type === 'auth') {
            clearTimeout(authTimeout);

            const token = msg.token || '';
            const auth = verifyToken(token);

            if (!auth.valid) {
              console.log(`[Spine] Auth failed: ${auth.reason}`);
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

            console.log(`[Spine] Authenticated: ${ws.userId} (session ${ws.sessionId})`);
            await logAdminSession(ws.sessionId, 'connected', ws.userId);

            ws.send(
              JSON.stringify({
                type: 'authenticated',
                message: `Welcome ${ws.userId}`,
              } as SpineMessage)
            );

            // Emit initial robot status
            const status = await sdk.getStatus();
            ws.send(
              JSON.stringify({
                type: 'robot_status',
                status,
              } as SpineMessage)
            );

            return;
          }

          // 2. All other messages require auth
          if (!authenticated) {
            ws.send(
              JSON.stringify({
                type: 'error',
                message: 'Not authenticated — send auth message first',
              } as SpineMessage)
            );
            return;
          }

          // 3. Route the message
          const response = await routeMessage(msg, ws.sessionId!, ws.userId!, sdk);
          ws.send(JSON.stringify(response));
        } catch (err) {
          console.error('[Spine] Message handling error:', err);
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

    wss.on('listening', () => {
      console.log(`✓ Spine WebSocket server listening on port ${PORT}`);
      resolve();
    });

    wss.on('error', (err) => {
      console.error('[Spine] Server error:', err);
      reject(err);
    });

    // Register robot event handler to broadcast to all clients
    sdk.onEvent((event) => {
      const msg: SpineMessage = {
        type: 'event',
        event: event.type,
        ...event,
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
