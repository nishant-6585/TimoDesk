/**
 * security.ts — F9 after-hours patrol scheduling + intrusion detection.
 *
 * Two concerns, both pure/injected so they are testable without a robot, a
 * clock, or Supabase:
 *
 *   1. SCHEDULE — is "now" inside the after-hours window? Starts the patrol when
 *      the window opens, stops it when the window closes. The window may wrap
 *      midnight (19:00 → 06:00), which is the normal case.
 *
 *   2. INTRUSION — during an after-hours patrol, scan for a person at each
 *      waypoint. A single positive frame is NOT an intrusion: the confirmation
 *      rule requires N consecutive positive scans (blueprint F9 — cuts false
 *      alarms from a curtain moving or a reflection). Confirmed → siren +
 *      capture + alert fan-out, then a cooldown so one intruder walking the
 *      floor does not page the whole team every 30 seconds.
 *
 * Deliberately NOT here: the office-hours interlock (that's interlocks.ts) and
 * the patrol sequencer itself (server.ts). This module only decides WHEN to
 * patrol and WHETHER a scan means an intruder.
 */

/** "HH:MM" → minutes since midnight, or null when unparseable. */
export function parseTimeOfDay(value: string): number | null {
  const m = /^(\d{1,2}):(\d{2})$/.exec(value.trim());
  if (!m) return null;
  const h = Number(m[1]);
  const min = Number(m[2]);
  if (h > 23 || min > 59) return null;
  return h * 60 + min;
}

/**
 * Is `nowMinutes` inside the window [fromMinutes, toMinutes)?
 *
 * Handles the wrapping case that matters most: 19:00→06:00 means "evening OR
 * early morning", not the empty set. A window whose ends are equal is treated
 * as always-open (24h), since "19:00 to 19:00" more plausibly means "all day"
 * than "never" for a security patrol.
 */
export function isWithinWindow(nowMinutes: number, fromMinutes: number, toMinutes: number): boolean {
  if (fromMinutes === toMinutes) return true;
  if (fromMinutes < toMinutes) return nowMinutes >= fromMinutes && nowMinutes < toMinutes;
  return nowMinutes >= fromMinutes || nowMinutes < toMinutes; // wraps midnight
}

export interface SecurityWindow {
  fromMinutes: number;
  toMinutes: number;
}

/**
 * Parse `AFTER_HOURS_PATROL_WINDOW` ("19:00-06:00"). Returns null when unset or
 * malformed — the caller then leaves the scheduler OFF rather than guessing a
 * window and driving the robot around at an unexpected hour.
 */
export function parseWindow(raw: string | undefined): SecurityWindow | null {
  if (!raw) return null;
  const parts = raw.split('-');
  if (parts.length !== 2) return null;
  const from = parseTimeOfDay(parts[0]);
  const to = parseTimeOfDay(parts[1]);
  if (from === null || to === null) return null;
  return { fromMinutes: from, toMinutes: to };
}

export const INTRUSION_DEFAULTS = {
  /** Consecutive positive scans needed to call it an intrusion (false-alarm guard). */
  confirmScans: 2,
  /** Minimum gap between alerts, so one intruder doesn't spam every waypoint. */
  cooldownMs: 5 * 60_000,
};

export interface IntrusionConfig {
  confirmScans: number;
  cooldownMs: number;
}

/**
 * Consecutive-scan confirmation. Fed one scan result at a time; returns true
 * exactly on the scan that crosses the threshold (and then not again until the
 * cooldown expires), so the caller can fire the alarm once per incident.
 */
export class IntrusionDetector {
  private streak = 0;
  private lastAlertAt: number | null = null;

  constructor(
    private cfg: IntrusionConfig = INTRUSION_DEFAULTS,
    private now: () => number = Date.now
  ) {}

  /** Reset between patrols so a stale streak can't carry over. */
  reset(): void {
    this.streak = 0;
  }

  get streakLength(): number {
    return this.streak;
  }

  /**
   * @param personSeen outcome of one person scan
   * @returns true when this scan CONFIRMS a new intrusion (fire the alarm)
   */
  record(personSeen: boolean): boolean {
    if (!personSeen) {
      this.streak = 0; // a clean scan breaks the streak — that's the whole point
      return false;
    }
    this.streak++;
    if (this.streak < this.cfg.confirmScans) return false;

    const t = this.now();
    if (this.lastAlertAt !== null && t - this.lastAlertAt < this.cfg.cooldownMs) {
      return false; // same incident, still cooling down
    }
    this.lastAlertAt = t;
    return true;
  }
}

export interface SecuritySchedulerDeps {
  /** Minutes-since-midnight for "now" (injected so tests don't touch the clock). */
  nowMinutes: () => number;
  /** Start the after-hours patrol. Returns false when it couldn't start. */
  startPatrol: () => Promise<boolean>;
  /** Stop the patrol this scheduler started. */
  stopPatrol: () => void;
  /** True when a patrol is currently running (from any source). */
  isPatrolActive: () => boolean;
  onEvent?: (event: string, payload?: Record<string, unknown>) => void;
}

/**
 * Opens and closes the after-hours patrol on a window.
 *
 * Ownership rule: it only stops what IT started (`selfStarted`). If an operator
 * manually started a patrol during office hours, the scheduler leaves it alone —
 * silently killing a human's patrol at 06:00 would be surprising.
 */
export class SecurityScheduler {
  private selfStarted = false;
  private starting = false;

  constructor(
    private window: SecurityWindow,
    private deps: SecuritySchedulerDeps
  ) {}

  get isSelfStarted(): boolean {
    return this.selfStarted;
  }

  isActiveWindow(): boolean {
    return isWithinWindow(this.deps.nowMinutes(), this.window.fromMinutes, this.window.toMinutes);
  }

  /** One scheduler tick — safe to call on any cadence (a minute is plenty). */
  async tick(): Promise<void> {
    const inWindow = this.isActiveWindow();

    if (inWindow) {
      if (this.selfStarted || this.starting) return;
      // Don't hijack a patrol someone else is already running.
      if (this.deps.isPatrolActive()) return;
      this.starting = true;
      try {
        const ok = await this.deps.startPatrol();
        this.selfStarted = ok;
        this.deps.onEvent?.(ok ? 'after_hours_patrol_started' : 'after_hours_patrol_start_failed');
      } finally {
        this.starting = false;
      }
      return;
    }

    // Window closed.
    if (this.selfStarted) {
      this.selfStarted = false;
      this.deps.stopPatrol();
      this.deps.onEvent?.('after_hours_patrol_stopped', { reason: 'window_closed' });
    }
  }

  /** Called when something else (operator STOP, dock, escort) ended the patrol. */
  notePatrolEndedExternally(): void {
    this.selfStarted = false;
  }
}
