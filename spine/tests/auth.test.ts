/**
 * tests/auth.test.ts — auth gating (JWKS/ES256 verify + dev bypass).
 *
 * `jose` is mocked so these are deterministic + offline — they test OUR gating
 * logic (prod fail-closed, dev bypass, await flow), not jose's crypto. The real
 * ES256 verification against the live project JWKS is proven by curl in Step 5.
 *
 * The middleware captures NODE_ENV/DEV_AUTH_BYPASS/SUPABASE_URL at module load,
 * so each scenario resets modules and re-imports with the env it wants.
 */

import { describe, it, expect, vi, beforeEach } from 'vitest';

// jose mock: a "real-token" verifies (sub set, aud/iss ok); anything else throws.
vi.mock('jose', () => ({
  createRemoteJWKSet: () => ({ _mockKeyset: true }),
  jwtVerify: vi.fn(async (token: string) => {
    if (token === 'real-token') return { payload: { sub: 'user-123', aud: 'authenticated' } };
    throw new Error('signature verification failed');
  }),
}));

const req = (auth?: string): any => ({ headers: auth ? { authorization: auth } : {} });

async function loadMiddleware(env: Record<string, string | undefined>) {
  vi.resetModules();
  for (const [k, v] of Object.entries(env)) {
    if (v === undefined) delete process.env[k];
    else process.env[k] = v;
  }
  return await import('../src/auth/middleware');
}

const SUPA = 'https://test-ref.supabase.co';

describe('PRODUCTION mode (NODE_ENV=production, DEV_AUTH_BYPASS=1 → forced off)', () => {
  beforeEach(() => {});

  it('verifyToken rejects junk / test-token (WS path)', async () => {
    const { verifyToken, DEV_AUTH_BYPASS } = await loadMiddleware({
      NODE_ENV: 'production', DEV_AUTH_BYPASS: '1', SUPABASE_URL: SUPA,
    });
    expect(DEV_AUTH_BYPASS).toBe(false); // prod forces bypass off even with flag=1
    expect((await verifyToken('test-token')).valid).toBe(false);
    expect((await verifyToken('garbage')).valid).toBe(false);
  });

  it('verifyToken accepts a real ES256 token → userId from sub', async () => {
    const { verifyToken } = await loadMiddleware({
      NODE_ENV: 'production', DEV_AUTH_BYPASS: '1', SUPABASE_URL: SUPA,
    });
    const r = await verifyToken('real-token');
    expect(r.valid).toBe(true);
    expect(r.userId).toBe('user-123');
  });

  it('authorizeRequest: no token → 401, test-token → 401, real token → ok', async () => {
    const { authorizeRequest } = await loadMiddleware({
      NODE_ENV: 'production', DEV_AUTH_BYPASS: '1', SUPABASE_URL: SUPA,
    });
    expect(await authorizeRequest(req())).toMatchObject({ ok: false, status: 401 });
    expect(await authorizeRequest(req('Bearer test-token'))).toMatchObject({ ok: false, status: 401 });
    expect(await authorizeRequest(req('Bearer real-token'))).toMatchObject({ ok: true, userId: 'user-123' });
  });

  it('no SUPABASE_URL + no bypass → fail closed', async () => {
    const { verifyToken } = await loadMiddleware({
      NODE_ENV: 'production', DEV_AUTH_BYPASS: undefined, SUPABASE_URL: undefined,
    });
    const r = await verifyToken('real-token');
    expect(r.valid).toBe(false);
    expect(r.reason).toBe('auth not configured');
  });
});

describe('DEV mode (DEV_AUTH_BYPASS=1, not production)', () => {
  it('authorizeRequest: test-token / missing token → dev-user', async () => {
    const { authorizeRequest, DEV_AUTH_BYPASS } = await loadMiddleware({
      NODE_ENV: 'development', DEV_AUTH_BYPASS: '1', SUPABASE_URL: SUPA,
    });
    expect(DEV_AUTH_BYPASS).toBe(true);
    expect(await authorizeRequest(req('Bearer test-token'))).toMatchObject({ ok: true, userId: 'dev-user' });
    expect(await authorizeRequest(req())).toMatchObject({ ok: true, userId: 'dev-user' });
  });
});
