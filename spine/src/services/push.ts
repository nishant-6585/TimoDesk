/**
 * push.ts — FCM (HTTP v1) push sender for the mobile admin app (#90 Part B).
 *
 * Best-effort + idempotent: every public function swallows its own errors and
 * NEVER throws, so a push failure can never crash an event handler. If Firebase
 * isn't configured (no service-account key), all calls no-op with a one-time log.
 *
 * Auth: the legacy server-key API is deprecated, so we mint a short-lived OAuth
 * token from the service account via google-auth-library (the standard, minimal
 * way to call the v1 endpoint) and POST to messages:send per token.
 *
 * Targeting: v1 pushes to ALL registered admin devices (the host is named in the
 * body). Host-specific targeting needs a staff↔auth.users link that doesn't
 * exist yet — see the TODO below.
 */
import { SupabaseClient } from '@supabase/supabase-js';
import { GoogleAuth } from 'google-auth-library';

const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
const BATTERY_LOW_THRESHOLD = 20; // percent

export interface PushPayload {
  title: string;
  body: string;
  data?: Record<string, string>;
}

// 'all' = every registered device; or a list of auth user ids.
export type PushTarget = 'all' | string[];

let _auth: GoogleAuth | null = null;
let _projectId: string | null = null;
let _warned = false;

/** Resolve the service account once. Returns null (and warns once) if absent. */
function getAuth(): { auth: GoogleAuth; projectId: string } | null {
  const raw = process.env.FCM_SERVICE_ACCOUNT || process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!raw) {
    if (!_warned) {
      console.log('[push] FCM not configured (no FCM_SERVICE_ACCOUNT) — push disabled.');
      _warned = true;
    }
    return null;
  }
  try {
    if (!_auth) {
      // FCM_SERVICE_ACCOUNT may be an inline JSON string OR a file path
      // (GOOGLE_APPLICATION_CREDENTIALS is always a path).
      const looksJson = raw.trim().startsWith('{');
      const credentials = looksJson ? JSON.parse(raw) : undefined;
      _auth = new GoogleAuth({
        scopes: [FCM_SCOPE],
        ...(credentials ? { credentials } : { keyFile: raw }),
      });
      _projectId =
        process.env.FCM_PROJECT_ID ||
        (credentials?.project_id as string | undefined) ||
        null;
    }
    if (!_projectId) {
      console.error('[push] No FCM project id (set FCM_PROJECT_ID or use a service-account JSON).');
      return null;
    }
    return { auth: _auth, projectId: _projectId };
  } catch (err) {
    console.error('[push] Failed to init FCM auth:', err);
    return null;
  }
}

interface TokenRow {
  token: string;
  user_id: string;
}

/** Core sender. Looks up tokens, POSTs to FCM v1, prunes stale tokens. Never throws. */
export async function sendPush(
  supabase: SupabaseClient,
  target: PushTarget,
  payload: PushPayload
): Promise<void> {
  try {
    const cfg = getAuth();
    if (!cfg) return;

    let q = supabase.from('device_token').select('token, user_id');
    if (target !== 'all') {
      if (target.length === 0) return;
      q = q.in('user_id', target);
    }
    const { data, error } = await q;
    if (error) {
      console.error('[push] device_token lookup failed:', error.message);
      return;
    }
    const rows = (data ?? []) as TokenRow[];
    if (rows.length === 0) return;

    const client = await cfg.auth.getClient();
    const accessToken = (await client.getAccessToken()).token;
    if (!accessToken) {
      console.error('[push] Could not mint FCM OAuth token.');
      return;
    }
    const url = `https://fcm.googleapis.com/v1/projects/${cfg.projectId}/messages:send`;

    // Best-effort fan-out. Failures per-token don't abort the batch.
    await Promise.all(
      rows.map(async (row) => {
        try {
          const res = await fetch(url, {
            method: 'POST',
            headers: {
              Authorization: `Bearer ${accessToken}`,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({
              message: {
                token: row.token,
                notification: { title: payload.title, body: payload.body },
                data: payload.data ?? {},
              },
            }),
          });
          if (res.status === 404 || res.status === 400) {
            // UNREGISTERED / invalid token — prune it so we stop trying.
            const errBody = await res.text();
            if (/UNREGISTERED|INVALID_ARGUMENT|registration-token-not-registered/i.test(errBody)) {
              await supabase.from('device_token').delete().eq('token', row.token);
              console.log('[push] Pruned stale token for user', row.user_id);
            }
          }
        } catch (err) {
          console.error('[push] send failed for one token:', err);
        }
      })
    );
  } catch (err) {
    // Absolute backstop — push must never crash a caller.
    console.error('[push] sendPush fatal (swallowed):', err);
  }
}

// ── Trigger helpers (condition + debounce live here; called from event handlers) ──

/** Visitor arrived → notify admins. (TODO: target the host's own devices once a
 *  staff↔auth.users link exists; for now all admins, host named in the body.) */
export async function notifyVisitorArrived(
  supabase: SupabaseClient,
  visitorName: string,
  hostName: string
): Promise<void> {
  await sendPush(supabase, 'all', {
    title: 'Visitor arrived',
    body: `👋 ${visitorName} is here to see ${hostName}.`,
    data: { type: 'visitor_arrived' },
  });
}

let _batteryWasLow = false;
/** Battery telemetry → push admins once when crossing below the low threshold. */
export async function maybeNotifyBatteryLow(
  supabase: SupabaseClient,
  battery: number
): Promise<void> {
  const low = battery <= BATTERY_LOW_THRESHOLD;
  if (low && !_batteryWasLow) {
    _batteryWasLow = true;
    await sendPush(supabase, 'all', {
      title: 'Mikee battery low',
      body: `🔋 Battery at ${battery}% — please dock Mikee soon.`,
      data: { type: 'battery_low', battery: String(battery) },
    });
  } else if (!low && battery > BATTERY_LOW_THRESHOLD + 5) {
    _batteryWasLow = false; // reset with hysteresis so we don't re-alert at the edge
  }
}

/** Confirmed after-hours intrusion → push every admin immediately (F9).
 *  Deliberately NOT deduped like battery/obstacle: the IntrusionDetector's own
 *  cooldown already governs how often this fires, and a security alert must not
 *  be suppressed by a latched flag. */
export async function maybeNotifyIntrusion(
  supabase: SupabaseClient,
  waypoint: string | null
): Promise<void> {
  await sendPush(supabase, 'all', {
    title: '🚨 Intrusion detected',
    body: waypoint
      ? `A person was detected near "${waypoint}" during the after-hours patrol.`
      : 'A person was detected during the after-hours patrol.',
    data: { type: 'intrusion_detected', ...(waypoint ? { waypoint } : {}) },
  });
}

let _obstacleWasBlocked = false;
/** Obstacle state → push admins once when Mikee becomes blocked. */
export async function maybeNotifyObstacleBlocked(
  supabase: SupabaseClient,
  obstacleState: string
): Promise<void> {
  const blocked = obstacleState === 'blocked';
  if (blocked && !_obstacleWasBlocked) {
    _obstacleWasBlocked = true;
    await sendPush(supabase, 'all', {
      title: 'Mikee is blocked',
      body: '🚧 Mikee is blocked by an obstacle and stopped moving.',
      data: { type: 'obstacle_blocked' },
    });
  } else if (!blocked) {
    _obstacleWasBlocked = false;
  }
}
