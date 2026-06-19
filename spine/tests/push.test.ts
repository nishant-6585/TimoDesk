/**
 * tests/push.test.ts — FCM push sender (#90 Part B).
 *
 * The critical contract is BEST-EFFORT: push must NEVER throw, so it can never
 * crash an event handler. These tests assert that contract with FCM unconfigured
 * (no FCM_SERVICE_ACCOUNT) — the common dev/CI state — where every path no-ops
 * cleanly. End-to-end delivery needs real Firebase config and is verified
 * manually on a device (see HANDOFF #90).
 */
import { describe, it, expect, beforeEach } from 'vitest';
import {
  sendPush,
  notifyVisitorArrived,
  maybeNotifyBatteryLow,
  maybeNotifyObstacleBlocked,
} from '../src/services/push';

// Minimal supabase stub. With FCM unconfigured, sendPush returns BEFORE touching
// supabase, so these methods should never even be called — but we make them safe.
const supabaseStub: any = {
  from: () => ({
    select: () => ({ in: async () => ({ data: [], error: null }) }),
    delete: () => ({ eq: async () => ({ data: null, error: null }) }),
  }),
};

describe('push (best-effort, FCM unconfigured)', () => {
  beforeEach(() => {
    delete process.env.FCM_SERVICE_ACCOUNT;
    delete process.env.GOOGLE_APPLICATION_CREDENTIALS;
  });

  it('sendPush no-ops and does not throw when FCM is unconfigured', async () => {
    await expect(sendPush(supabaseStub, 'all', { title: 't', body: 'b' })).resolves.toBeUndefined();
  });

  it('sendPush no-ops on an empty user-id target', async () => {
    await expect(sendPush(supabaseStub, [], { title: 't', body: 'b' })).resolves.toBeUndefined();
  });

  it('notifyVisitorArrived never throws', async () => {
    await expect(notifyVisitorArrived(supabaseStub, 'Asha', 'Rohit')).resolves.toBeUndefined();
  });

  it('maybeNotifyBatteryLow never throws (crossing + recovery)', async () => {
    await expect(maybeNotifyBatteryLow(supabaseStub, 12)).resolves.toBeUndefined(); // crosses low
    await expect(maybeNotifyBatteryLow(supabaseStub, 10)).resolves.toBeUndefined(); // still low (debounced)
    await expect(maybeNotifyBatteryLow(supabaseStub, 80)).resolves.toBeUndefined(); // recovered
  });

  it('maybeNotifyObstacleBlocked never throws (blocked + clear)', async () => {
    await expect(maybeNotifyObstacleBlocked(supabaseStub, 'blocked')).resolves.toBeUndefined();
    await expect(maybeNotifyObstacleBlocked(supabaseStub, 'running')).resolves.toBeUndefined();
  });
});
