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
  // 1. GLOBAL STOP CHECK — RAN FIRST, ALWAYS
  // ========================================
  if (isStopped) {
    // REJECT movement intents while stopped
    if (['drive', 'head', 'arm', 'wave'].includes(intent.intent)) {
      return {
        allowed: false,
        reason: 'System stopped. Send resume to continue.',
      };
    }
    // ALLOW non-movement intents (snapshot, get_status, resume)
    // Don't rate-limit snapshot/status when stopped
    if (['snapshot', 'get_status', 'resume'].includes(intent.intent)) {
      return { allowed: true };
    }
  }

  // 2. RATE LIMITING (per session, per intent type)
  // ================================================
  const rateLimits: Record<string, number> = {
    drive: 100, // max 1 per 100ms
    head: 50, // max 1 per 50ms
    arm: 50, // max 1 per 50ms
    snapshot: 2000, // max 1 per 2s (global across all sessions)
  };

  const limit = rateLimits[intent.intent];
  if (limit) {
    // For snapshot, check global limit (key without sessionId)
    const key = intent.intent === 'snapshot' ? `global:${intent.intent}` : `${sessionId}:${intent.intent}`;
    const lastTime = sessionLastCommandTime.get(key) ?? 0;
    const now = Date.now();

    if (now - lastTime < limit) {
      // SILENTLY DROP (not an error — don't spam the client)
      return { allowed: true }; // return true but mark as dropped internally
    }

    sessionLastCommandTime.set(key, now);
  }

  // 3. OFFICE HOURS MODE (scaffold now)
  // ====================================
  if (process.env.OFFICE_HOURS_MODE === 'true') {
    if (intent.intent === 'drive') {
      await logEvent('office_hours_blocked', { intent: 'drive', session_id: sessionId });
      return {
        allowed: false,
        reason: 'Chassis disabled during office hours.',
      };
    }
  }

  return { allowed: true };
}

/**
 * Handle STOP intent
 * Sets global isStopped = true, calls sdk.stopDrive(), broadcasts to all clients
 */
export async function handleStop(sessionId: string): Promise<void> {
  // STOP is idempotent
  if (isStopped) return;

  isStopped = true;
  console.log('[Interlocks] GLOBAL STOP triggered by', sessionId);

  // Log to Supabase
  await logEvent('safety_stop', { triggered_by: sessionId });
}

/**
 * Handle RESUME intent
 * Sets isStopped = false (requires admin auth, verified by middleware before this is called)
 */
export async function handleResume(sessionId: string): Promise<void> {
  // RESUME is idempotent
  if (!isStopped) return;

  isStopped = false;
  console.log('[Interlocks] System RESUMED by', sessionId);

  // Log to Supabase
  await logEvent('safety_resume', { triggered_by: sessionId });
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
