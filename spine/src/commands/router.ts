/**
 * commands/router.ts — Route intents to handlers
 * Orchestrates: parse → interlock check → handler → response
 */

import { SpineMessage, AdminMessage } from '../types';
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
  _userId: string,
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
    const intentType = intent.intent;

    console.log('[Router] ======== INTENT RECEIVED ========');
    console.log(`[Router] Intent type: ${intentType}`);
    console.log(`[Router] Session ID: ${sessionId}`);
    console.log(`[Router] Full intent payload: ${JSON.stringify(intent)}`);

    // 3. Check safety interlocks
    console.log('[Router] Checking safety interlocks...');
    const interlock = await checkInterlocks(intent, sessionId);

    if (!interlock.allowed) {
      console.log(`[Router] [INTERLOCK BLOCKED] Reason: ${interlock.reason}`);
      return {
        type: 'error',
        message: interlock.reason || 'Intent blocked by safety interlocks',
      };
    }

    console.log('[Router] [INTERLOCK PASSED] Intent allowed to proceed');

    // 4. Route to handler
    console.log('[Router] Routing to handler...');
    const response = await handleIntent(intent, sessionId, sdk);
    console.log(`[Router] Handler response type: ${response.type}`);
    console.log(`[Router] ======== INTENT COMPLETE ========`);
    return response;
  }

  return {
    type: 'error',
    message: `unknown message type: ${msg.type}`,
  };
}
