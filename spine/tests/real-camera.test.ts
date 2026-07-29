/**
 * tests/real-camera.test.ts — RealRobotSDK camera surface + dead-man ping
 *
 * Phase 0 of the transport refactor: nothing outside the SDK may build robot
 * URLs. The camera surface is getCameraStreamUrl (recorder), captureFrame
 * (non-throwing, validated, timed-out — face recognizer), and takeSnapshot
 * (throwing variant on the same fetch path). The chassis ping feeds the
 * on-robot dead-man watchdog while the socket is open.
 */

import { describe, it, expect, vi, afterEach } from 'vitest';
import { WebSocket } from 'ws';
import { RealRobotSDK } from '../src/robot/real';

// A minimal valid-looking JPEG: SOI marker + padding. Standalone Uint8Array —
// Buffer.from() would sit in the shared pool, whose .buffer has a nonzero offset.
const JPEG = Uint8Array.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x00]);

const okBattery = { ok: true, json: async () => ({ battery: 50 }) };

/** fetch stub that routes /battery (constructor probe) and /snapshot separately. */
function stubFetch(snapshotImpl: (url: string, init?: any) => Promise<any>) {
  const fn = vi.fn(async (url: string, init?: any) => {
    if (String(url).includes('/battery')) return okBattery;
    return snapshotImpl(String(url), init);
  });
  vi.stubGlobal('fetch', fn);
  return fn;
}

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
  vi.useRealTimers();
});

describe('camera surface', () => {
  it('getCameraStreamUrl points at the robot MJPEG endpoint', () => {
    stubFetch(async () => okBattery);
    const sdk = new RealRobotSDK({ robotIP: '10.1.2.3' });
    expect(sdk.getCameraStreamUrl()).toBe('http://10.1.2.3:8080/stream');
  });

  it('captureFrame returns a validated JPEG buffer', async () => {
    const fetchFn = stubFetch(async () => ({
      ok: true,
      arrayBuffer: async () => JPEG.buffer,
    }));
    const sdk = new RealRobotSDK({ robotIP: '10.1.2.3' });
    const frame = await sdk.captureFrame(1234);
    expect(frame).not.toBeNull();
    expect(frame![0]).toBe(0xff);
    expect(frame![1]).toBe(0xd8);
    // Timeout is forwarded as an AbortSignal on the snapshot request.
    const snapCall = fetchFn.mock.calls.find(([u]) => String(u).includes('/snapshot'));
    expect(snapCall?.[1]?.signal).toBeInstanceOf(AbortSignal);
  });

  it('captureFrame returns null on non-200, non-JPEG, and network error', async () => {
    stubFetch(async () => ({ ok: false }));
    let sdk = new RealRobotSDK({ robotIP: '10.1.2.3' });
    expect(await sdk.captureFrame()).toBeNull();

    stubFetch(async () => ({
      ok: true,
      arrayBuffer: async () => new TextEncoder().encode('<html>not a jpeg</html>').buffer,
    }));
    sdk = new RealRobotSDK({ robotIP: '10.1.2.3' });
    expect(await sdk.captureFrame()).toBeNull();

    stubFetch(async () => {
      throw new Error('ECONNREFUSED');
    });
    sdk = new RealRobotSDK({ robotIP: '10.1.2.3' });
    expect(await sdk.captureFrame()).toBeNull();
  });

  it('takeSnapshot throws when captureFrame fails (interlock/person-check contract)', async () => {
    stubFetch(async () => {
      throw new Error('ECONNREFUSED');
    });
    const sdk = new RealRobotSDK({ robotIP: '10.1.2.3' });
    await expect(sdk.takeSnapshot()).rejects.toThrow(/Snapshot failed/);
  });
});

describe('chassis dead-man ping', () => {
  it('pings an open chassis socket every 2s and stays quiet otherwise', () => {
    vi.useFakeTimers();
    stubFetch(async () => okBattery);
    const sdk = new RealRobotSDK({ robotIP: '10.1.2.3' });

    // No chassis socket yet → no pings, no crash.
    vi.advanceTimersByTime(4100);

    const send = vi.fn();
    (sdk as any).ws_chassis = { readyState: WebSocket.OPEN, send };
    vi.advanceTimersByTime(4100);
    expect(send).toHaveBeenCalledTimes(2);
    expect(JSON.parse(send.mock.calls[0][0])).toEqual({ cmd: 'ping' });

    // Closed socket → pings stop.
    (sdk as any).ws_chassis = { readyState: WebSocket.CLOSED, send };
    vi.advanceTimersByTime(4100);
    expect(send).toHaveBeenCalledTimes(2);
  });

  it('drops pong replies without logging them', () => {
    stubFetch(async () => okBattery);
    const sdk = new RealRobotSDK({ robotIP: '10.1.2.3' });
    const log = vi.spyOn(console, 'log').mockImplementation(() => {});
    (sdk as any).handleRobotMessage(JSON.stringify({ type: 'pong' }));
    expect(log).not.toHaveBeenCalled();
  });
});
