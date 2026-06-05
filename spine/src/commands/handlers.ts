/**
 * commands/handlers.ts — Intent handlers
 * Each intent type has a handler that calls the SDK
 */

import { Intent, RobotStatus, SpineMessage } from '../types';
import { RobotSDK } from '../robot/interface';
import { logEvent } from '../supabase/events';
import { handleStop, handleResume } from './interlocks';

export async function handleIntent(
  intent: Intent,
  sessionId: string,
  sdk: RobotSDK
): Promise<SpineMessage> {
  try {
    switch (intent.intent) {
      case 'drive': {
        const dir = intent.dir as 'forward' | 'back' | 'left' | 'right';
        if (!dir) return { type: 'error', message: 'drive intent missing dir' };
        await sdk.drive(dir);
        await logEvent('command_drive', { session_id: sessionId, dir });
        return { type: 'ack', intent: 'drive', ok: true };
      }

      case 'head': {
        const lr = intent.lr;
        const ud = intent.ud;
        if (lr === undefined || ud === undefined) {
          return { type: 'error', message: 'head intent missing lr or ud' };
        }
        await sdk.setHeadPosition(lr, ud);
        await logEvent('command_head', { session_id: sessionId, lr, ud });
        return { type: 'ack', intent: 'head', ok: true };
      }

      case 'arm': {
        const left = intent.left;
        const right = intent.right;
        if (left === undefined || right === undefined) {
          return { type: 'error', message: 'arm intent missing left or right' };
        }
        await sdk.setArmPosition(left, right);
        await logEvent('command_arm', { session_id: sessionId, left, right });
        return { type: 'ack', intent: 'arm', ok: true };
      }

      case 'wave': {
        await sdk.wave();
        await logEvent('command_wave', { session_id: sessionId });
        return { type: 'ack', intent: 'wave', ok: true };
      }

      case 'stop': {
        await handleStop(sessionId);
        await sdk.stopDrive();
        return { type: 'stopped' };
      }

      case 'resume': {
        await handleResume(sessionId);
        return { type: 'resumed' };
      }

      case 'snapshot': {
        const buffer = await sdk.takeSnapshot();
        // In a real system, upload to cloud storage and return URL
        // For now, just log it
        await logEvent('snapshot', {
          session_id: sessionId,
          size_bytes: buffer.length,
        });
        return { type: 'ack', intent: 'snapshot', ok: true };
      }

      case 'get_status': {
        const status = await sdk.getStatus();
        return { type: 'robot_status', status };
      }

      default:
        return { type: 'error', message: `unknown intent: ${intent.intent}` };
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : 'unknown error';
    console.error('[Handlers] Error handling intent:', message);
    await logEvent('handler_error', {
      session_id: sessionId,
      intent: intent.intent,
      error: message,
    });
    return { type: 'error', message };
  }
}
