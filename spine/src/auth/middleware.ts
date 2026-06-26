/**
 * auth/middleware.ts — Supabase JWT verification (JWKS / ES256) + shared HTTP auth.
 *
 * Supabase signs user access tokens with ASYMMETRIC keys (ES256). We verify them
 * against the project's published JWKS — createRemoteJWKSet caches + refreshes the
 * keyset internally (no per-request fetch). HS256/jsonwebtoken is gone.
 *
 * Fail-CLOSED by default. The dev bypass (accept `test-token`/missing token, and
 * accept-all when JWKS isn't configured) is active ONLY when DEV_AUTH_BYPASS=1 AND
 * NODE_ENV !== 'production'. Production forces the bypass off even if the flag is set.
 */

import { IncomingMessage } from 'http';
import { createRemoteJWKSet, jwtVerify } from 'jose';

const SUPABASE_URL = process.env.SUPABASE_URL; // same var the supabase client uses

// Remote keyset, built once. createRemoteJWKSet caches keys + refreshes on rotation.
const JWKS = SUPABASE_URL
  ? createRemoteJWKSet(new URL(`${SUPABASE_URL}/auth/v1/.well-known/jwks.json`))
  : null;

// Kiosk credential — a static shared secret the robot chest-screen (robot_app) sends
// over the WS + HTTP. The kiosk has no Supabase session, so it can't present an ES256
// user token; this is the supported production path for it (auth go-live item #5).
// Honored ONLY when set to a non-empty value, and works in production (not gated by
// DEV_AUTH_BYPASS). Tradeoff: a long-lived static secret — rotate it manually. Set a
// long random string in spine's env; mirror it in robot_app Settings → kiosk token.
const KIOSK_TOKEN = (process.env.KIOSK_TOKEN ?? '').trim() || null;
const KIOSK_USER_ID = 'kiosk-robot';

/**
 * The ONE gate. Dev bypass allowed only with the explicit flag AND not prod.
 */
export const DEV_AUTH_BYPASS =
  process.env.DEV_AUTH_BYPASS === '1' && process.env.NODE_ENV !== 'production';

if (DEV_AUTH_BYPASS) {
  console.warn('⚠ DEV AUTH BYPASS ENABLED — never use in production');
} else if (!JWKS) {
  console.warn('⚠ SUPABASE_URL not set and DEV_AUTH_BYPASS off — auth is FAIL-CLOSED (all requests rejected)');
}

/**
 * Verify a Supabase access token (ES256, via JWKS) and extract the user id.
 * Async. Returns { valid: true, userId } or { valid: false, reason }.
 */
export async function verifyToken(
  token: string
): Promise<{ valid: boolean; userId?: string; reason?: string }> {
  // Kiosk shared secret — checked first, honored in production too (the chest
  // screen has no Supabase session). Constant-time-ish: exact string match.
  if (KIOSK_TOKEN && token === KIOSK_TOKEN) {
    return { valid: true, userId: KIOSK_USER_ID };
  }

  // Dev bypass: accept the dev sentinel tokens even when JWKS IS configured, so
  // the admin app works without a Supabase login. Mirrors authorizeRequest and
  // the documented bypass intent. Gated by DEV_AUTH_BYPASS (forced off in prod);
  // real Supabase JWTs still fall through to JWKS verification below.
  if (DEV_AUTH_BYPASS && (token === '' || token === 'dev' || token === 'test-token')) {
    return { valid: true, userId: 'dev-user' };
  }

  if (!JWKS) {
    // No JWKS configured: accept-all ONLY under the dev bypass, else fail closed.
    if (DEV_AUTH_BYPASS) return { valid: true, userId: 'dev-user' };
    return { valid: false, reason: 'auth not configured' };
  }

  try {
    const { payload } = await jwtVerify(token, JWKS, {
      audience: 'authenticated',
      issuer: `${SUPABASE_URL}/auth/v1`,
    });
    const userId = payload.sub;
    if (!userId) return { valid: false, reason: 'Token missing sub' };
    return { valid: true, userId };
  } catch (err) {
    const reason = err instanceof Error ? err.message : 'Invalid token';
    return { valid: false, reason };
  }
}

/**
 * Shared authorization for HTTP routes (/enroll, /check-face, /staff, /visit).
 * Async. Dev bypass (test-token / missing token → dev-user) is checked BEFORE the
 * JWKS verify; otherwise a real verified Supabase JWT is required.
 */
export async function authorizeRequest(
  req: IncomingMessage
): Promise<{ ok: true; userId: string } | { ok: false; status: number; reason: string }> {
  const authz = (req.headers['authorization'] as string | undefined) ?? '';
  const token = authz.startsWith('Bearer ') ? authz.slice(7).trim() : '';

  if (DEV_AUTH_BYPASS && (token === '' || token === 'dev' || token === 'test-token')) {
    return { ok: true, userId: 'dev-user' };
  }

  if (!token) {
    return { ok: false, status: 401, reason: 'Missing bearer token' };
  }

  const result = await verifyToken(token);
  if (!result.valid || !result.userId) {
    return { ok: false, status: 401, reason: result.reason ?? 'Invalid token' };
  }
  return { ok: true, userId: result.userId };
}
