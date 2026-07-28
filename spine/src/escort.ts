/**
 * escort.ts — Follow-Me escort sequencer (person-verified waypoint walking)
 *
 * Walks a sequence of saved waypoints like the patrol sequencer, but instead of
 * advancing on a dwell timer it verifies a person is actually present before
 * proceeding — at every waypoint arrival AND at a bounded distance interval
 * mid-leg (~2m of actual travel). If nobody is found within the check timeout,
 * the escort stops rather than walking off without the visitor.
 *
 * Checkpoint spacing is LIVE distance tracking, not pre-computed geometry: the
 * controller is fed the same pose samples the navi arrival watcher already
 * polls (server.ts startNaviWatch → handlePose), accumulates distance actually
 * traveled, and on crossing the threshold pauses the goal (cancelNavi), runs
 * the person check, and re-issues the SAME goal — the cancel→navi round-trip
 * is the same one patrol arrival cleanup uses on hardware.
 *
 * All robot/socket side effects are injected (EscortDeps) so this stays a pure
 * state machine — server.ts owns the wiring, tests own fake deps.
 */

import { RobotPosition } from './types';

export type EscortPoint = RobotPosition & { name?: string; arrivalText?: string };

export type EscortFinishReason =
  | 'complete' // final waypoint reached
  | 'visitor_lost' // no person found within checkTimeoutMs
  | 'stopped' // escort_stop intent (or superseded by patrol/dock)
  | 'nav_timeout' // a leg never arrived (navi watch timeout)
  | 'nav_cancelled' // user cancelled the active goal
  | 'nav_failed'; // goal dispatch threw (interlock stop, robot offline)

export interface EscortDeps {
  /** Dispatch a leg goal (navi + naviState broadcast + arrival watch). */
  navi(point: EscortPoint, index: number): Promise<void>;
  /** Cancel the active goal for a checkpoint pause — must NOT read as a user cancel. */
  pauseNavi(): Promise<void>;
  /** Re-issue the same goal after a passed check (navi + restart arrival watch). */
  resumeNavi(point: EscortPoint): Promise<void>;
  /** One active scan for a person (head sweep + frames). Errors → false. */
  scanForPerson(): Promise<boolean>;
  /** Person-check started/ended — broadcast so UIs can show "checking". */
  onCheckState(checking: boolean): void;
  /**
   * Escort ended, for any reason. `goalActive` = a chassis goal is (likely)
   * still live and needs a cleanup cancel — false when the goal was already
   * cancelled (checkpoint pause, arrival) or never dispatched.
   */
  onFinish(reason: EscortFinishReason, goalActive: boolean): void;
  /** Lifecycle breadcrumbs (escort_event broadcast + audit log). */
  onEvent(event: string, payload?: Record<string, unknown>): void;
}

export interface EscortConfig {
  checkIntervalM: number; // cumulative meters traveled between mid-leg checks
  checkTimeoutMs: number; // give up if nobody appears within this window
  scanRetryMs: number; // pause between scans inside the timeout window
}

export const ESCORT_DEFAULTS: EscortConfig = {
  checkIntervalM: 2,
  checkTimeoutMs: 30_000,
  scanRetryMs: 1_500,
};

const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

export class EscortController {
  private deps: EscortDeps;
  private cfg: EscortConfig;

  private active = false;
  private points: EscortPoint[] = [];
  private index = 0;
  private checking = false; // a person check is in progress
  private paused = false; // goal cancelled for a check — ignore poses/arrivals
  private cumDist = 0; // meters traveled since the last check
  private lastPose: RobotPosition | null = null;

  constructor(deps: EscortDeps, cfg: EscortConfig = ESCORT_DEFAULTS) {
    this.deps = deps;
    this.cfg = cfg;
  }

  get state(): { active: boolean; index: number; total: number; checking: boolean } {
    return {
      active: this.active,
      index: this.index,
      total: this.points.length,
      checking: this.checking,
    };
  }

  start(points: EscortPoint[]): void {
    if (this.active) this.finish('stopped'); // restart supersedes
    this.active = true;
    this.points = points;
    this.index = 0;
    this.checking = false;
    this.paused = false;
    this.deps.onEvent('started', { total: points.length });
    void this.startLeg();
  }

  /** External stop: escort_stop intent, or patrol/dock taking over. */
  stop(): void {
    if (!this.active) return;
    this.finish('stopped');
  }

  /**
   * Pose sample from the navi arrival watcher (~1s cadence while a goal is
   * active). Accumulates distance actually traveled; crossing the threshold
   * triggers a mid-leg checkpoint.
   */
  handlePose(pos: RobotPosition): void {
    if (!this.active || this.checking || this.paused) return;
    if (this.lastPose) {
      this.cumDist += Math.hypot(pos.x - this.lastPose.x, pos.y - this.lastPose.y);
    }
    this.lastPose = pos;
    if (this.cumDist >= this.cfg.checkIntervalM) void this.runCheckpoint();
  }

  /** Leg outcome from the navi pipeline (server.ts naviDone). */
  handleNaviDone(reason: 'arrived' | 'timeout' | 'cancelled'): void {
    if (!this.active) return;
    // A cancel_result reaching here is a USER cancel (checkpoint pauses are
    // flagged escortCancelPending in server.ts and never fire naviDone).
    if (reason === 'cancelled') {
      this.finish('nav_cancelled');
      return;
    }
    if (this.paused) return; // stale watch artifact during our own pause
    if (reason === 'timeout') {
      this.finish('nav_timeout');
      return;
    }
    void this.handleArrival();
  }

  private async startLeg(): Promise<void> {
    const p = this.points[this.index];
    this.cumDist = 0;
    this.lastPose = null;
    try {
      await this.deps.navi(p, this.index);
    } catch (err) {
      console.error('[Escort] leg dispatch failed:', err);
      this.finish('nav_failed');
    }
  }

  /** Mid-leg checkpoint: pause the goal, verify the visitor, resume or stop. */
  private async runCheckpoint(): Promise<void> {
    if (this.checking) return;
    this.checking = true;
    this.paused = true;
    this.deps.onCheckState(true);
    this.deps.onEvent('checkpoint', {
      index: this.index,
      traveled_m: Number(this.cumDist.toFixed(2)),
    });
    try {
      await this.deps.pauseNavi();
    } catch { /* best-effort — check proceeds either way */ }

    const found = await this.checkLoop();
    if (!this.active) return; // stopped mid-check
    if (!found) {
      this.finish('visitor_lost');
      return;
    }

    this.deps.onEvent('person_confirmed', { index: this.index, at: 'checkpoint' });
    this.cumDist = 0;
    this.lastPose = null;
    try {
      await this.deps.resumeNavi(this.points[this.index]);
    } catch (err) {
      console.error('[Escort] resume dispatch failed:', err);
      this.finish('nav_failed');
      return;
    }
    this.paused = false;
    this.checking = false;
    this.deps.onCheckState(false);
  }

  /** Arrived at a waypoint: verify the visitor before the next leg (or finish). */
  private async handleArrival(): Promise<void> {
    if (this.index >= this.points.length - 1) {
      this.finish('complete');
      return;
    }
    this.checking = true;
    this.paused = true; // no goal is active (arrival already cancelled it)
    this.deps.onCheckState(true);
    this.deps.onEvent('arrival_check', { index: this.index });

    const found = await this.checkLoop();
    if (!this.active) return;
    if (!found) {
      this.finish('visitor_lost');
      return;
    }

    this.deps.onEvent('person_confirmed', { index: this.index, at: 'arrival' });
    this.checking = false;
    this.paused = false;
    this.deps.onCheckState(false);
    this.index++;
    await this.startLeg();
  }

  /** Scan repeatedly until a person is found or the timeout window closes. */
  private async checkLoop(): Promise<boolean> {
    const deadline = Date.now() + this.cfg.checkTimeoutMs;
    while (this.active) {
      let found = false;
      try {
        found = await this.deps.scanForPerson();
      } catch { /* a failed scan is a miss, not a crash */ }
      if (found) return true;
      if (Date.now() >= deadline) return false;
      await sleep(this.cfg.scanRetryMs);
    }
    return false;
  }

  private finish(reason: EscortFinishReason): void {
    if (!this.active) return;
    // A goal is only still live when we're ending mid-drive: 'stopped' outside
    // a pause, or a watch timeout. Every other reason means the goal was
    // already cancelled (pause/arrival/user cancel) or never dispatched.
    const goalActive = !this.paused && (reason === 'stopped' || reason === 'nav_timeout');
    this.active = false;
    this.checking = false;
    this.paused = false;
    this.deps.onCheckState(false);
    this.deps.onEvent('finished', { reason });
    this.deps.onFinish(reason, goalActive);
  }
}
