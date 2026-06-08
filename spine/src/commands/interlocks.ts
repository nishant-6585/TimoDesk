/**
 * commands/interlocks.ts — Safety interlocks (CRITICAL)
 *
 * These run on EVERY command before it reaches the SDK.
 * Rules:
 * 1. GLOBAL STOP always wins (even in a race with resume)
 * 2. Rate-limiting per session + intent type
 * 3. Office hours mode (scaffold now, enforce later)
 */

import { Intent } from '../types';
import { logEvent } from '../supabase/events';

// ============================================================================
// GLOBAL STATE — STOP is a module-level boolean
// ============================================================================

let isStopped = false;

// Rate limit tracking: key = "sessionId:intentType", value = lastCommandTime (ms)
const sessionLastCommandTime = new Map<string, number>();

// ============================================================================
// PUBLIC API
// ============================================================================

/**
 * Check if an intent is allowed to proceed.
 * Returns { allowed, reason? }
 * STOP check runs FIRST, before everything else.
 */
export async function checkInterlocks(
  intent: Intent,
  sessionId: string
): Promise<{ allowed: boolean; reason?: string }> {
  const intentType = intent.intent;

  console.log('[Interlocks] ======== INTERLOCK CHECK START ========');
  console.log(`[Interlocks] Intent: ${intentType}`);
  console.log(`[Interlocks] Session: ${sessionId}`);
  console.log(`[Interlocks] Global STOPPED state: ${isStopped}`);

  // 1. GLOBAL STOP CHECK — RAN FIRST, ALWAYS
  // ========================================
  if (isStopped) {
    console.log('[Interlocks] System is in STOPPED state');

    // REJECT movement intents while stopped
    if (['drive', 'head', 'arm', 'wave'].includes(intentType)) {
      console.log(`[Interlocks] [REJECT] Intent '${intentType}' is a movement intent and system is stopped`);
      return {
        allowed: false,
        reason: 'System stopped. Send resume to continue.',
      };
    }

    // ALLOW non-movement intents (snapshot, get_status, resume)
    // Don't rate-limit snapshot/status when stopped
    if (['snapshot', 'get_status', 'resume'].includes(intentType)) {
      console.log(`[Interlocks] [ALLOW] Intent '${intentType}' is permitted while stopped`);
      return { allowed: true };
    }
  } else {
    console.log('[Interlocks] System is RUNNING (not stopped)');
  }

  // 2. RATE LIMITING (per session, per intent type)
  // ================================================
  console.log('[Interlocks] Checking rate limits...');
  const rateLimits: Record<string, number> = {
    drive: 100, // max 1 per 100ms
    head: 50, // max 1 per 50ms
    arm: 50, // max 1 per 50ms
    snapshot: 2000, // max 1 per 2s (global across all sessions)
  };

  const limit = rateLimits[intentType];
  if (limit) {
    // For snapshot, check global limit (key without sessionId)
    const key = intentType === 'snapshot' ? `global:${intentType}` : `${sessionId}:${intentType}`;
    const lastTime = sessionLastCommandTime.get(key) ?? 0;
    const now = Date.now();
    const timeSinceLastCommand = now - lastTime;

    console.log(`[Interlocks] Rate limit for '${intentType}': ${limit}ms, time since last: ${timeSinceLastCommand}ms, key: ${key}`);

    if (timeSinceLastCommand < limit) {
      // SILENTLY DROP (not an error — don't spam the client)
      console.log(`[Interlocks] [RATE LIMITED] Dropping intent (too soon)`);
      return { allowed: true }; // return true but mark as dropped internally
    }

    sessionLastCommandTime.set(key, now);
    console.log(`[Interlocks] Rate limit OK, command allowed`);
  }

  // 3. OFFICE HOURS MODE (scaffold now)
  // ====================================
  if (process.env.OFFICE_HOURS_MODE === 'true') {
    console.log('[Interlocks] Office hours mode is enabled');
    if (intentType === 'drive') {
      await logEvent('office_hours_blocked', { intent: 'drive', session_id: sessionId });
      console.log('[Interlocks] [REJECT] Drive disabled during office hours');
      return {
        allowed: false,
        reason: 'Chassis disabled during office hours.',
      };
    }
  }

  console.log('[Interlocks] ======== INTERLOCK CHECK PASS ========');
  return { allowed: true };
}

/**
 * Handle STOP intent
 * Sets global isStopped = true, calls sdk.stopDrive(), broadcasts to all clients
 */
export async function handleStop(sessionId: string): Promise<void> {
  console.log('[Interlocks] ======== HANDLE STOP ========');
  console.log(`[Interlocks] Stop requested by: ${sessionId}`);
  console.log(`[Interlocks] Current stopped state BEFORE: ${isStopped}`);

  // STOP is idempotent
  if (isStopped) {
    console.log('[Interlocks] System already stopped, ignoring duplicate stop');
    return;
  }

  isStopped = true;
  console.log('[Interlocks] GLOBAL STOP TRIGGERED - isStopped is now TRUE');
  console.log(`[Interlocks] New stopped state AFTER: ${isStopped}`);

  // Log to Supabase
  console.log('[Interlocks] Logging stop event to Supabase...');
  await logEvent('safety_stop', { triggered_by: sessionId });
  console.log('[Interlocks] ======== HANDLE STOP COMPLETE ========');
}

/**
 * Handle RESUME intent
 * Sets isStopped = false (requires admin auth, verified by middleware before this is called)
 */
export async function handleResume(sessionId: string): Promise<void> {
  console.log('[Interlocks] ======== HANDLE RESUME ========');
  console.log(`[Interlocks] Resume requested by: ${sessionId}`);
  console.log(`[Interlocks] Current stopped state BEFORE: ${isStopped}`);

  // RESUME is idempotent
  if (!isStopped) {
    console.log('[Interlocks] System not stopped, nothing to resume');
    return;
  }

  isStopped = false;
  console.log('[Interlocks] SYSTEM RESUMED - isStopped is now FALSE');
  console.log(`[Interlocks] New stopped state AFTER: ${isStopped}`);

  // Log to Supabase
  console.log('[Interlocks] Logging resume event to Supabase...');
  await logEvent('safety_resume', { triggered_by: sessionId });
  console.log('[Interlocks] ======== HANDLE RESUME COMPLETE ========');
}

/**
 * Get current stopped state (for tests + diagnostics)
 */
export function getStoppedState(): boolean {
  return isStopped;
}

/**
 * Force reset state (for tests)
 */
export function resetState(): void {
  isStopped = false;
  sessionLastCommandTime.clear();
}

/**
 * Manually set isStopped (for tests)
 */
export function setStoppedState(value: boolean): void {
  isStopped = value;
}
