/**
 * commands/router.ts — Route intents to handlers
 * Orchestrates: parse → interlock check → handler → response
 */

import { Intent, SpineMessage, AdminMessage } from '../types';
import { RobotSDK } from '../robot/interface';
import { checkInterlocks } from './interlocks';
import { handleIntent } from './handlers';

/**
 * Main router: parse admin message and route to handler
 * Returns a SpineMessage to send back to the client
 */
export async function routeMessage(
  raw: unknown,
  sessionId: string,
  userId: string,
  sdk: RobotSDK
): Promise<SpineMessage> {
  // 1. Parse and validate message
  let msg: AdminMessage;
  try {
    if (typeof raw !== 'object' || raw === null) {
      throw new Error('Invalid message format');
    }
    msg = raw as AdminMessage;
  } catch (err) {
    return {
      type: 'error',
      message: 'Malformed JSON or invalid message structure',
    };
  }

  // 2. Route by message type
  if (msg.type === 'ping') {
    return { type: 'pong' };
  }

  if (msg.type === 'intent') {
    if (!msg.intent) {
      return { type: 'error', message: 'intent message missing intent field' };
    }

    const intent = msg.intent;

    // 3. Check safety interlocks
    const interlock = await checkInterlocks(intent, sessionId);
    if (!interlock.allowed) {
      return {
        type: 'error',
        message: interlock.reason || 'Intent blocked by safety interlocks',
      };
    }

    // 4. Route to handler
    const response = await handleIntent(intent, sessionId, sdk);
    return response;
  }

  return {
    type: 'error',
    message: `unknown message type: ${msg.type}`,
  };
}
