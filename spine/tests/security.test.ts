/**
 * tests/security.test.ts — F9 after-hours scheduling + intrusion confirmation.
 *
 * The two rules that matter operationally: a window that WRAPS midnight (the
 * normal 19:00→06:00 case), and "one positive frame is not an intruder".
 */

import { describe, it, expect, vi } from 'vitest';
import {
  parseTimeOfDay,
  parseWindow,
  isWithinWindow,
  IntrusionDetector,
  SecurityScheduler,
} from '../src/security';

const at = (h: number, m = 0) => h * 60 + m;

describe('parseTimeOfDay / parseWindow', () => {
  it('parses valid times', () => {
    expect(parseTimeOfDay('19:00')).toBe(at(19));
    expect(parseTimeOfDay('06:30')).toBe(at(6, 30));
    expect(parseTimeOfDay('0:00')).toBe(0);
  });

  it('rejects nonsense rather than guessing', () => {
    expect(parseTimeOfDay('25:00')).toBeNull();
    expect(parseTimeOfDay('19:99')).toBeNull();
    expect(parseTimeOfDay('evening')).toBeNull();
  });

  it('parses a window string, and returns null when unset/malformed', () => {
    expect(parseWindow('19:00-06:00')).toEqual({ fromMinutes: at(19), toMinutes: at(6) });
    expect(parseWindow(undefined)).toBeNull();
    expect(parseWindow('19:00')).toBeNull();
    // Malformed must disable the scheduler, never default to "patrol now".
    expect(parseWindow('nonsense-here')).toBeNull();
  });
});

describe('isWithinWindow', () => {
  it('handles a same-day window', () => {
    expect(isWithinWindow(at(10), at(9), at(17))).toBe(true);
    expect(isWithinWindow(at(8), at(9), at(17))).toBe(false);
    expect(isWithinWindow(at(17), at(9), at(17))).toBe(false); // end-exclusive
  });

  it('handles a window that wraps midnight (the real after-hours case)', () => {
    const from = at(19);
    const to = at(6);
    expect(isWithinWindow(at(20), from, to)).toBe(true); // evening
    expect(isWithinWindow(at(2), from, to)).toBe(true); // small hours
    expect(isWithinWindow(at(23, 59), from, to)).toBe(true);
    expect(isWithinWindow(at(12), from, to)).toBe(false); // midday: NOT patrolling
    expect(isWithinWindow(at(6), from, to)).toBe(false); // window closes at 06:00
  });

  it('treats an equal-ends window as always open', () => {
    expect(isWithinWindow(at(3), at(19), at(19))).toBe(true);
  });
});

describe('IntrusionDetector', () => {
  it('does not alarm on a single positive scan', () => {
    const d = new IntrusionDetector();
    expect(d.record(true)).toBe(false);
  });

  it('confirms on consecutive positives', () => {
    const d = new IntrusionDetector();
    expect(d.record(true)).toBe(false);
    expect(d.record(true)).toBe(true);
  });

  it('a clean scan breaks the streak (false-alarm guard)', () => {
    const d = new IntrusionDetector();
    d.record(true);
    expect(d.record(false)).toBe(false);
    // Streak restarted — one more positive must NOT be enough.
    expect(d.record(true)).toBe(false);
    expect(d.record(true)).toBe(true);
  });

  it('does not re-alarm during the cooldown, then alarms again after it', () => {
    let now = 0;
    const d = new IntrusionDetector({ confirmScans: 2, cooldownMs: 1000 }, () => now);
    d.record(true);
    expect(d.record(true)).toBe(true); // first alert
    expect(d.record(true)).toBe(false); // same incident, cooling down
    now += 1500;
    expect(d.record(true)).toBe(true); // cooldown expired
  });

  it('reset clears the streak between patrols', () => {
    const d = new IntrusionDetector();
    d.record(true);
    d.reset();
    expect(d.record(true)).toBe(false); // needs a fresh pair
  });
});

describe('SecurityScheduler', () => {
  function make(nowMin: number, patrolActive = false) {
    let active = patrolActive;
    const clock = { minutes: nowMin }; // mutable so a test can advance the day
    const deps = {
      nowMinutes: () => clock.minutes,
      startPatrol: vi.fn(async () => { active = true; return true; }),
      stopPatrol: vi.fn(() => { active = false; }),
      isPatrolActive: () => active,
      onEvent: vi.fn(),
    };
    return {
      deps,
      clock,
      scheduler: new SecurityScheduler({ fromMinutes: at(19), toMinutes: at(6) }, deps),
    };
  }

  it('starts the patrol when the window opens', async () => {
    const { deps, scheduler } = make(at(20));
    await scheduler.tick();
    expect(deps.startPatrol).toHaveBeenCalledOnce();
    expect(scheduler.isSelfStarted).toBe(true);
  });

  it('does not start during office hours', async () => {
    const { deps, scheduler } = make(at(12));
    await scheduler.tick();
    expect(deps.startPatrol).not.toHaveBeenCalled();
  });

  it('does not start twice while already patrolling', async () => {
    const { deps, scheduler } = make(at(20));
    await scheduler.tick();
    await scheduler.tick();
    expect(deps.startPatrol).toHaveBeenCalledOnce();
  });

  it('stops its own patrol when the window closes', async () => {
    const { deps, clock, scheduler } = make(at(20));
    await scheduler.tick();
    expect(deps.startPatrol).toHaveBeenCalledOnce();

    clock.minutes = at(7); // morning — window closed
    await scheduler.tick();
    expect(deps.stopPatrol).toHaveBeenCalledOnce();
    expect(scheduler.isSelfStarted).toBe(false);
  });

  it('leaves an operator-started patrol alone, at open AND at close', async () => {
    // Patrol already running (started by a human) when the window opens.
    const { deps, clock, scheduler } = make(at(20), true);
    await scheduler.tick();
    expect(deps.startPatrol).not.toHaveBeenCalled();
    expect(scheduler.isSelfStarted).toBe(false);

    // Window closes — it must not stop a patrol it didn't start.
    clock.minutes = at(7);
    await scheduler.tick();
    expect(deps.stopPatrol).not.toHaveBeenCalled();
  });

  it('re-arms for the next night after the window closed', async () => {
    const { deps, clock, scheduler } = make(at(20));
    await scheduler.tick(); // night 1 start
    clock.minutes = at(7);
    await scheduler.tick(); // morning stop
    clock.minutes = at(20);
    await scheduler.tick(); // night 2 start
    expect(deps.startPatrol).toHaveBeenCalledTimes(2);
  });
});
