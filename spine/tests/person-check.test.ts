/**
 * tests/person-check.test.ts — escort person-presence scanner
 *
 * The face-api detection itself (countFaces) needs loaded models + real
 * frames, so these tests inject `detect` and verify the scan choreography:
 * head sweep, early exit, recenter, and fail-safe error handling.
 */

import { describe, it, expect, vi } from 'vitest';
import { createPersonScanner } from '../src/services/person-check';

function makeSdk() {
  return {
    setHeadPosition: vi.fn(async (_lr: number, _ud: number) => {}),
    takeSnapshot: vi.fn(async () => Buffer.from('jpeg')),
  };
}

const OPTS = { headSettleMs: 0 }; // no real waiting in tests

describe('createPersonScanner', () => {
  it('sweeps the head and passes when a person appears in any frame', async () => {
    const sdk = makeSdk();
    // Nothing at center (50), person found at the second position (30).
    const detect = vi
      .fn(async () => false)
      .mockResolvedValueOnce(false)
      .mockResolvedValueOnce(true);
    const scan = createPersonScanner(sdk, { ...OPTS, detect });

    await expect(scan()).resolves.toBe(true);

    // Swept center then left, stopped early (never scanned 70), recentered.
    const headCalls = sdk.setHeadPosition.mock.calls.map((c) => c[0]);
    expect(headCalls).toEqual([50, 30, 50]);
    expect(sdk.takeSnapshot).toHaveBeenCalledTimes(2);
  });

  it('fails when no frame across the whole sweep contains a person', async () => {
    const sdk = makeSdk();
    const detect = vi.fn(async () => false);
    const scan = createPersonScanner(sdk, { ...OPTS, detect });

    await expect(scan()).resolves.toBe(false);

    // Full sweep + recenter.
    const headCalls = sdk.setHeadPosition.mock.calls.map((c) => c[0]);
    expect(headCalls).toEqual([50, 30, 70, 50]);
    expect(detect).toHaveBeenCalledTimes(3);
  });

  it('camera/head errors are misses, never throws (fail-safe)', async () => {
    const sdk = makeSdk();
    sdk.takeSnapshot.mockRejectedValue(new Error('camera unreachable'));
    const detect = vi.fn(async () => true); // would pass, but frames never arrive
    const scan = createPersonScanner(sdk, { ...OPTS, detect });

    await expect(scan()).resolves.toBe(false);
    expect(detect).not.toHaveBeenCalled();
  });

  it('a failing head servo still allows detection at the other positions', async () => {
    const sdk = makeSdk();
    sdk.setHeadPosition
      .mockRejectedValueOnce(new Error('head busy')) // center move fails
      .mockResolvedValue(undefined);
    const detect = vi.fn(async () => true);
    const scan = createPersonScanner(sdk, { ...OPTS, detect });

    await expect(scan()).resolves.toBe(true);
  });
});
