/**
 * tests/real-online.test.ts — RealRobotSDK online liveness
 *
 * Regression coverage for the "Robot offline - command not sent" bug: the
 * cached `online` flag used to be hardcoded false, so the admin Control screen
 * blocked every joystick/gesture command even when the robot was reachable.
 * `online` is now driven by the battery HTTP probe (boot + every 30s) and emits
 * a robot_online/robot_offline transition event the server re-broadcasts.
 */

import { describe, it, expect, vi, afterEach } from 'vitest';
import { RealRobotSDK } from '../src/robot/real';
import { RobotEvent } from '../src/types';

// Constructing the SDK kicks off an immediate battery probe; `flush` lets the
// in-flight fetch().then() chain settle before we assert.
const flush = () => new Promise((r) => setTimeout(r, 0));

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

describe('RealRobotSDK online liveness', () => {
  it('starts offline and goes online when the battery probe succeeds', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue({ ok: true, json: async () => ({ battery: 77 }) })
    );

    const sdk = new RealRobotSDK({ robotIP: '10.0.0.1' });
    const events: RobotEvent[] = [];
    sdk.onEvent((e) => events.push(e));

    expect((await sdk.getStatus()).online).toBe(false);

    await flush();

    const status = await sdk.getStatus();
    expect(status.online).toBe(true);
    expect(status.battery).toBe(77);
    expect(events.some((e) => e.type === 'robot_online')).toBe(true);
  });

  it('goes offline when the battery probe fails', async () => {
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new Error('ECONNREFUSED')));

    const sdk = new RealRobotSDK({ robotIP: '10.0.0.1' });
    await flush();

    expect((await sdk.getStatus()).online).toBe(false);
  });
});
