/**
 * auth/middleware.ts — JWT verification + shared HTTP authorization.
 *
 * Fail-CLOSED by default. The dev bypass (accept `test-token`/missing token, and
 * accept-all when JWT_SECRET is unset) is active ONLY when DEV_AUTH_BYPASS is
 * explicitly enabled AND we're not in production. In production the bypass is
 * always off, even if the flag is set (defense in depth).
 */

import { IncomingMessage } from 'http';
import { createRequire } from 'module';
const require = createRequire(import.meta.url);
const jwt = require('jsonwebtoken');

const JWT_SECRET = process.env.JWT_SECRET;

/**
 * The ONE gate. Dev bypass allowed only with the explicit flag AND not prod.
 * NODE_ENV=production forces it off regardless of the flag.
 */
export const DEV_AUTH_BYPASS =
  process.env.DEV_AUTH_BYPASS === '1' && process.env.NODE_ENV !== 'production';

if (DEV_AUTH_BYPASS) {
  console.warn('⚠ DEV AUTH BYPASS ENABLED — never use in production');
} else if (!JWT_SECRET) {
  console.warn('⚠ JWT_SECRET not set and DEV_AUTH_BYPASS off — auth is FAIL-CLOSED (all requests rejected)');
}

/**
 * Verify a JWT and extract the user id.
 * Returns { valid: true, userId } or { valid: false, reason }.
 */
export function verifyToken(
  token: string
): { valid: boolean; userId?: string; reason?: string } {
  if (!JWT_SECRET) {
    // No secret configured: accept-all ONLY under the dev bypass, else fail closed.
    if (DEV_AUTH_BYPASS) {
      return { valid: true, userId: 'dev-user' };
    }
    return { valid: false, reason: 'auth not configured' };
  }

  try {
    const decoded = jwt.verify(token, JWT_SECRET) as any;
    const userId = decoded.sub || decoded.user_id || decoded.id;
    if (!userId) {
      return { valid: false, reason: 'Token missing user ID' };
    }
    return { valid: true, userId };
  } catch (err) {
    const reason = err instanceof Error ? err.message : 'Invalid token';
    return { valid: false, reason };
  }
}

/**
 * Shared authorization for HTTP routes (/enroll, /check-face, /staff).
 * Extracts the bearer token and applies the gate:
 *  - DEV_AUTH_BYPASS on + (token is 'test-token' or missing) → allow as 'dev-user'
 *  - otherwise require a real verified JWT
 *  - no secret + not bypass → reject (verifyToken fails closed)
 */
export function authorizeRequest(
  req: IncomingMessage
): { ok: true; userId: string } | { ok: false; status: number; reason: string } {
  const authz = (req.headers['authorization'] as string | undefined) ?? '';
  const token = authz.startsWith('Bearer ') ? authz.slice(7).trim() : '';

  if (DEV_AUTH_BYPASS && (token === '' || token === 'test-token')) {
    return { ok: true, userId: 'dev-user' };
  }

  if (!token) {
    return { ok: false, status: 401, reason: 'Missing bearer token' };
  }

  const result = verifyToken(token);
  if (!result.valid || !result.userId) {
    return { ok: false, status: 401, reason: result.reason ?? 'Invalid token' };
  }
  return { ok: true, userId: result.userId };
}

/**
 * Create a JWT token (for testing; not used in production).
 */
export function createToken(userId: string): string {
  if (!JWT_SECRET) {
    throw new Error('JWT_SECRET not set');
  }
  return jwt.sign({ sub: userId }, JWT_SECRET, { expiresIn: '24h' });
}
