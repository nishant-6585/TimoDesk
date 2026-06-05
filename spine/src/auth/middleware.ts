/**
 * auth/middleware.ts — JWT verification and session extraction
 * For development: if JWT_SECRET is not set, skip auth (dev mode)
 */

import { createRequire } from 'module';
const require = createRequire(import.meta.url);
const jwt = require('jsonwebtoken');

const JWT_SECRET = process.env.JWT_SECRET;

if (!JWT_SECRET) {
  console.warn('⚠ JWT_SECRET not set — auth is DISABLED (dev mode only)');
}

/**
 * Verify JWT token and extract user ID
 * Returns { valid: true, userId: string } or { valid: false, reason: string }
 */
export function verifyToken(
  token: string
): { valid: boolean; userId?: string; reason?: string } {
  // Dev mode: no auth
  if (!JWT_SECRET) {
    console.log('[Auth] Dev mode — accepting all connections');
    return { valid: true, userId: 'dev-user' };
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
 * Create a JWT token (for testing; not used in production)
 */
export function createToken(userId: string): string {
  if (!JWT_SECRET) {
    throw new Error('JWT_SECRET not set');
  }

  return jwt.sign({ sub: userId }, JWT_SECRET, { expiresIn: '24h' });
}
