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

  if (DEV_AUTH_BYPASS && (token === '' || token === 'test-token')) {
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
