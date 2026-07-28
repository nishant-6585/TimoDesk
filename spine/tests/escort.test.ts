/**
 * tests/escort.test.ts — Follow-Me escort sequencer
 *
 * Covers:
 *  - happy path: mid-leg checkpoint (2m traveled) → pause → person found → resume same goal
 *  - happy path: arrival check passes → next leg dispatched; final arrival → complete
 *  - failure path: nobody within the timeout → visitor_lost, escort stops cleanly
 *  - escort_stop mid-check, user cancel, nav timeout, dispatch failure
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { EscortController, EscortDeps, EscortPoint } from '../src/escort';

const CFG = { checkIntervalM: 2, checkTimeoutMs: 6_000, scanRetryMs: 1_000 };

const pt = (x: number, name?: string): EscortPoint => ({ x, y: 0, z: 0, rotation: 0, name });

function makeDeps(overrides: Partial<EscortDeps> = {}) {
  const deps = {
    navi: vi.fn(async () => {}),
    pauseNavi: vi.fn(async () => {}),
    resumeNavi: vi.fn(async () => {}),
    scanForPerson: vi.fn(async () => true),
    onCheckState: vi.fn(),
    onFinish: vi.fn(),
    onEvent: vi.fn(),
    ...overrides,
  };
  return deps;
}

// Flush pending microtasks under fake timers.
const flush = () => vi.advanceTimersByTimeAsync(0);

describe('EscortController', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it('start dispatches the first leg and resets progress', async () => {
    const deps = makeDeps();
    const escort = new EscortController(deps, CFG);
    escort.start([pt(0, 'Reception'), pt(10, 'Meeting Room')]);
    await flush();

    expect(deps.navi).toHaveBeenCalledTimes(1);
    expect(deps.navi).toHaveBeenCalledWith(expect.objectContaining({ name: 'Reception' }), 0);
    expect(escort.state).toEqual({ active: true, index: 0, total: 2, checking: false });
  });

  it('mid-leg checkpoint: 2m traveled → pause, person found → resume same goal', async () => {
    const deps = makeDeps();
    const escort = new EscortController(deps, CFG);
    escort.start([pt(0, 'A'), pt(10, 'B')]);
    await flush();

    // Feed the pose stream the navi watch would deliver: 1.2m then 0.9m more.
    escort.handlePose({ x: 0, y: 0, z: 0, rotation: 0 });
    escort.handlePose({ x: 1.2, y: 0, z: 0, rotation: 0 });
    expect(deps.pauseNavi).not.toHaveBeenCalled();

    escort.handlePose({ x: 2.1, y: 0, z: 0, rotation: 0 }); // cumulative 2.1m ≥ 2m
    await flush();

    expect(deps.pauseNavi).toHaveBeenCalledTimes(1);
    expect(deps.scanForPerson).toHaveBeenCalled();
    expect(deps.resumeNavi).toHaveBeenCalledTimes(1);
    expect(deps.resumeNavi).toHaveBeenCalledWith(expect.objectContaining({ name: 'A' }));
    expect(deps.onCheckState).toHaveBeenCalledWith(true);
    expect(deps.onCheckState).toHaveBeenCalledWith(false);
    expect(escort.state.active).toBe(true);
    expect(deps.onFinish).not.toHaveBeenCalled();

    // Distance accumulator reset: next 1m of travel does not re-trigger.
    escort.handlePose({ x: 2.5, y: 0, z: 0, rotation: 0 });
    escort.handlePose({ x: 3.4, y: 0, z: 0, rotation: 0 });
    await flush();
    expect(deps.pauseNavi).toHaveBeenCalledTimes(1);
  });

  it('poses during a check are ignored (no double checkpoint)', async () => {
    let resolveScan: (v: boolean) => void = () => {};
    const deps = makeDeps({
      scanForPerson: vi.fn(() => new Promise<boolean>((r) => { resolveScan = r; })),
    });
    const escort = new EscortController(deps, CFG);
    escort.start([pt(0), pt(10)]);
    await flush();

    escort.handlePose({ x: 0, y: 0, z: 0, rotation: 0 });
    escort.handlePose({ x: 2.5, y: 0, z: 0, rotation: 0 });
    await flush();
    expect(deps.pauseNavi).toHaveBeenCalledTimes(1);

    // Watch keeps polling while we scan — must not start a second checkpoint.
    escort.handlePose({ x: 5, y: 0, z: 0, rotation: 0 });
    escort.handlePose({ x: 9, y: 0, z: 0, rotation: 0 });
    await flush();
    expect(deps.pauseNavi).toHaveBeenCalledTimes(1);

    resolveScan(true);
    await flush();
    expect(deps.resumeNavi).toHaveBeenCalledTimes(1);
  });

  it('arrival check passes → advances to the next leg', async () => {
    const deps = makeDeps();
    const escort = new EscortController(deps, CFG);
    escort.start([pt(0, 'A'), pt(10, 'B')]);
    await flush();

    escort.handleNaviDone('arrived');
    await flush();

    expect(deps.scanForPerson).toHaveBeenCalled();
    expect(deps.navi).toHaveBeenCalledTimes(2);
    expect(deps.navi).toHaveBeenLastCalledWith(expect.objectContaining({ name: 'B' }), 1);
    expect(escort.state.index).toBe(1);
    expect(deps.onFinish).not.toHaveBeenCalled();
  });

  it('final arrival → complete (no person check needed at the destination)', async () => {
    const deps = makeDeps();
    const escort = new EscortController(deps, CFG);
    escort.start([pt(0, 'A'), pt(10, 'B')]);
    await flush();
    escort.handleNaviDone('arrived'); // A → check → leg B
    await flush();
    deps.scanForPerson.mockClear();

    escort.handleNaviDone('arrived'); // B is the destination
    await flush();

    expect(deps.scanForPerson).not.toHaveBeenCalled();
    expect(deps.onFinish).toHaveBeenCalledWith('complete', false);
    expect(escort.state.active).toBe(false);
  });

  it('failure path: nobody within the timeout → visitor_lost, stops cleanly', async () => {
    const deps = makeDeps({ scanForPerson: vi.fn(async () => false) });
    const escort = new EscortController(deps, CFG);
    escort.start([pt(0, 'A'), pt(10, 'B')]);
    await flush();

    escort.handlePose({ x: 0, y: 0, z: 0, rotation: 0 });
    escort.handlePose({ x: 2.5, y: 0, z: 0, rotation: 0 });
    await flush();
    expect(deps.pauseNavi).toHaveBeenCalledTimes(1);

    // Scans keep failing across the whole timeout window.
    await vi.advanceTimersByTimeAsync(CFG.checkTimeoutMs + CFG.scanRetryMs);

    expect(deps.onFinish).toHaveBeenCalledWith('visitor_lost', false);
    expect(deps.resumeNavi).not.toHaveBeenCalled();
    expect(escort.state.active).toBe(false);
    expect(deps.onCheckState).toHaveBeenLastCalledWith(false);

    // Fully stopped: later poses/arrivals must not dispatch anything.
    escort.handlePose({ x: 5, y: 0, z: 0, rotation: 0 });
    escort.handleNaviDone('arrived');
    await flush();
    expect(deps.navi).toHaveBeenCalledTimes(1);
  });

  it('person appears on a retry scan within the window → resumes', async () => {
    const scan = vi
      .fn(async () => false)
      .mockResolvedValueOnce(false)
      .mockResolvedValueOnce(false)
      .mockResolvedValueOnce(true);
    const deps = makeDeps({ scanForPerson: scan });
    const escort = new EscortController(deps, CFG);
    escort.start([pt(0), pt(10)]);
    await flush();

    escort.handlePose({ x: 0, y: 0, z: 0, rotation: 0 });
    escort.handlePose({ x: 2.5, y: 0, z: 0, rotation: 0 });
    await vi.advanceTimersByTimeAsync(CFG.scanRetryMs * 2 + 10);

    expect(deps.resumeNavi).toHaveBeenCalledTimes(1);
    expect(deps.onFinish).not.toHaveBeenCalled();
  });

  it('escort_stop mid-check → stopped, no resume dispatched', async () => {
    const deps = makeDeps({ scanForPerson: vi.fn(async () => false) });
    const escort = new EscortController(deps, CFG);
    escort.start([pt(0), pt(10)]);
    await flush();

    escort.handlePose({ x: 0, y: 0, z: 0, rotation: 0 });
    escort.handlePose({ x: 2.5, y: 0, z: 0, rotation: 0 });
    await flush();

    escort.stop();
    await vi.advanceTimersByTimeAsync(CFG.checkTimeoutMs + CFG.scanRetryMs);

    expect(deps.onFinish).toHaveBeenCalledTimes(1);
    expect(deps.onFinish).toHaveBeenCalledWith('stopped', false);
    expect(deps.resumeNavi).not.toHaveBeenCalled();
  });

  it('user cancel ends the escort', async () => {
    const deps = makeDeps();
    const escort = new EscortController(deps, CFG);
    escort.start([pt(0), pt(10)]);
    await flush();

    escort.handleNaviDone('cancelled');
    expect(deps.onFinish).toHaveBeenCalledWith('nav_cancelled', false);
    expect(escort.state.active).toBe(false);
  });

  it('navi watch timeout ends the escort', async () => {
    const deps = makeDeps();
    const escort = new EscortController(deps, CFG);
    escort.start([pt(0), pt(10)]);
    await flush();

    escort.handleNaviDone('timeout');
    expect(deps.onFinish).toHaveBeenCalledWith('nav_timeout', true);
  });

  it('leg dispatch failure (e.g. STOP interlock) → nav_failed', async () => {
    const deps = makeDeps({ navi: vi.fn(async () => { throw new Error('system stopped'); }) });
    const escort = new EscortController(deps, CFG);
    escort.start([pt(0), pt(10)]);
    await flush();

    expect(deps.onFinish).toHaveBeenCalledWith('nav_failed', false);
    expect(escort.state.active).toBe(false);
  });

  it('scan errors are misses, not crashes', async () => {
    const scan = vi
      .fn(async () => true)
      .mockRejectedValueOnce(new Error('camera unreachable'));
    const deps = makeDeps({ scanForPerson: scan });
    const escort = new EscortController(deps, CFG);
    escort.start([pt(0), pt(10)]);
    await flush();

    escort.handlePose({ x: 0, y: 0, z: 0, rotation: 0 });
    escort.handlePose({ x: 2.5, y: 0, z: 0, rotation: 0 });
    await vi.advanceTimersByTimeAsync(CFG.scanRetryMs + 10);

    expect(deps.resumeNavi).toHaveBeenCalledTimes(1); // second scan succeeded
    expect(deps.onFinish).not.toHaveBeenCalled();
  });

  it('emits lifecycle events (started / checkpoint / person_confirmed / finished)', async () => {
    const deps = makeDeps();
    const escort = new EscortController(deps, CFG);
    escort.start([pt(0), pt(10)]);
    await flush();

    escort.handlePose({ x: 0, y: 0, z: 0, rotation: 0 });
    escort.handlePose({ x: 2.5, y: 0, z: 0, rotation: 0 });
    await flush();
    escort.handleNaviDone('arrived');
    await flush();
    escort.handleNaviDone('arrived');
    await flush();

    const events = deps.onEvent.mock.calls.map((c) => c[0]);
    expect(events).toContain('started');
    expect(events).toContain('checkpoint');
    expect(events).toContain('person_confirmed');
    expect(events).toContain('arrival_check');
    expect(events[events.length - 1]).toBe('finished');
    expect(deps.onEvent).toHaveBeenLastCalledWith('finished', { reason: 'complete' });
  });
});
