/**
 * commands/handlers.ts — Intent handlers
 * Each intent type has a handler that calls the SDK
 */

import { Intent, SpineMessage } from '../types';
import { RobotSDK } from '../robot/interface';
import { logEvent } from '../supabase/events';
import { handleStop, handleResume } from './interlocks';

export async function handleIntent(
  intent: Intent,
  sessionId: string,
  sdk: RobotSDK
): Promise<SpineMessage> {
  const intentType = intent.intent;
  console.log('[Handlers] ======== HANDLE INTENT START ========');
  console.log(`[Handlers] Intent type: ${intentType}`);
  console.log(`[Handlers] Session: ${sessionId}`);

  try {
    switch (intentType) {
      case 'drive': {
        const dir = intent.dir as 'forward' | 'back' | 'left' | 'right';
        if (!dir) return { type: 'error', message: 'drive intent missing dir' };
        console.log(`[Handlers] Executing drive: ${dir}`);
        await sdk.drive(dir);
        await logEvent('command_drive', { session_id: sessionId, dir });
        console.log(`[Handlers] Drive command complete`);
        return { type: 'ack', intent: 'drive', ok: true };
      }

      case 'head': {
        const lr = intent.lr;
        const ud = intent.ud;
        if (lr === undefined || ud === undefined) {
          return { type: 'error', message: 'head intent missing lr or ud' };
        }
        console.log(`[Handlers] Executing head position: LR=${lr}, UD=${ud}`);
        await sdk.setHeadPosition(lr, ud);
        await logEvent('command_head', { session_id: sessionId, lr, ud });
        console.log(`[Handlers] Head position command complete`);
        return { type: 'ack', intent: 'head', ok: true };
      }

      case 'arm': {
        const left = intent.left;
        const right = intent.right;
        if (left === undefined || right === undefined) {
          return { type: 'error', message: 'arm intent missing left or right' };
        }
        console.log(`[Handlers] Executing arm position: L=${left}, R=${right}`);
        await sdk.setArmPosition(left, right);
        await logEvent('command_arm', { session_id: sessionId, left, right });
        console.log(`[Handlers] Arm position command complete`);
        return { type: 'ack', intent: 'arm', ok: true };
      }

      case 'wave': {
        console.log(`[Handlers] Executing wave gesture`);
        await sdk.wave();
        await logEvent('command_wave', { session_id: sessionId });
        console.log(`[Handlers] Wave gesture complete`);
        return { type: 'ack', intent: 'wave', ok: true };
      }

      case 'stop': {
        console.log(`[Handlers] STOP intent received - calling handleStop()`);
        await handleStop(sessionId);
        console.log(`[Handlers] handleStop() complete - now calling sdk.stopDrive()`);
        await sdk.stopDrive();
        console.log(`[Handlers] sdk.stopDrive() complete - returning 'stopped' message`);
        return { type: 'stopped' };
      }

      case 'resume': {
        console.log(`[Handlers] RESUME intent received - calling handleResume()`);
        await handleResume(sessionId);
        console.log(`[Handlers] handleResume() complete - returning 'resumed' message`);
        return { type: 'resumed' };
      }

      case 'snapshot': {
        console.log(`[Handlers] Executing snapshot`);
        const buffer = await sdk.takeSnapshot();
        // In a real system, upload to cloud storage and return URL
        // For now, just log it
        await logEvent('snapshot', {
          session_id: sessionId,
          size_bytes: buffer.length,
        });
        console.log(`[Handlers] Snapshot complete (${buffer.length} bytes)`);
        return { type: 'ack', intent: 'snapshot', ok: true };
      }

      case 'get_status': {
        console.log(`[Handlers] Fetching robot status`);
        const status = await sdk.getStatus();
        console.log(`[Handlers] Status fetched: online=${status.online}`);
        return { type: 'robot_status', status };
      }

      default:
        console.error(`[Handlers] Unknown intent: ${intentType}`);
        return { type: 'error', message: `unknown intent: ${intentType}` };
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : 'unknown error';
    console.error('[Handlers] !!!! ERROR handling intent !!!!');
    console.error(`[Handlers] Intent: ${intentType}`);
    console.error(`[Handlers] Error: ${message}`);
    await logEvent('handler_error', {
      session_id: sessionId,
      intent: intentType,
      error: message,
    });
    return { type: 'error', message };
  } finally {
    console.log('[Handlers] ======== HANDLE INTENT COMPLETE ========');
  }
}
