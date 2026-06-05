/**
 * supabase/events.ts — Write robot events to Supabase
 * Gracefully skips logging if Supabase is not configured
 */

import { getSupabaseClient, isSupabaseConfigured } from './client';

export interface RobotEventRecord {
  type: string; // admin_session, robot_connection, safety_stop, snapshot, face_detected, etc.
  payload?: Record<string, any>;
  session_id?: string;
}

/**
 * Log an event to Supabase robot_event table
 * If Supabase is not configured, this is a no-op (logs to console instead)
 */
export async function logEvent(
  type: string,
  payload?: Record<string, any>
): Promise<void> {
  const client = getSupabaseClient();

  if (!client) {
    console.log(`[Event skipped — Supabase not configured] ${type}`, payload);
    return; // graceful no-op
  }

  try {
    const { error } = await client
      .from('robot_event')
      .insert({
        type,
        payload,
        occurred_at: new Date().toISOString(),
      });

    if (error) {
      console.error('[Supabase] Error logging event:', type, error);
    } else {
      console.log('[Supabase] Event logged:', type);
    }
  } catch (err) {
    console.error('[Supabase] Unexpected error logging event:', err);
  }
}

/**
 * Log admin session (connect/disconnect)
 */
export async function logAdminSession(
  sessionId: string,
  action: 'connected' | 'disconnected',
  userId?: string
): Promise<void> {
  await logEvent('admin_session', {
    session_id: sessionId,
    action,
    user_id: userId,
  });
}

/**
 * Log robot connection state
 */
export async function logRobotConnection(
  state: 'online' | 'offline'
): Promise<void> {
  await logEvent('robot_connection', {
    state,
  });
}

/**
 * Calculate purge_after timestamp based on data kind
 * Used when inserting personal data to Supabase
 * Implements DPDP Act compliance: automatic deletion after retention window
 */
export function getPurgeAfter(
  kind: 'visitor' | 'capture_admin' | 'capture_intrusion' | 'capture_patrol' | 'conversation'
): string {
  const now = new Date();

  // Retention windows (days)
  const retentionDays: Record<string, number> = {
    visitor: 30,
    capture_admin: 30,
    capture_intrusion: 365, // 1 year for intrusion detection frames
    capture_patrol: 30,
    conversation: 7, // PII-scrubbed transcripts
  };

  const days = retentionDays[kind] ?? 30;
  now.setDate(now.getDate() + days);

  return now.toISOString();
}
