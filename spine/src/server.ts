/**
 * server.ts — WebSocket server + HTTP endpoints (admin clients + enrollment)
 * Clients connect → auth → session established → route intents
 * POST /enroll → face enrollment (JWT auth + DPDP gates)
 */

import http from 'http';
import { spawn, ChildProcess } from 'child_process';
import fs from 'fs';
import path from 'path';
import { WebSocket, WebSocketServer } from 'ws';
import { RobotSDK } from './robot/interface';
import { SpineMessage, AdminMessage, RobotStatus, RobotEvent, RobotPosition } from './types';
import { routeMessage } from './commands/router';
import { verifyToken, authorizeRequest } from './auth/middleware';
import { logAdminSession, logEvent } from './supabase/events';
import { createSensorPipeline } from './sensors';
import { EscortController, EscortPoint } from './escort';
import { createPersonScanner } from './services/person-check';
import { getStoppedState } from './commands/interlocks';
import { IntrusionDetector, SecurityScheduler, parseWindow } from './security';
import { loadPatrolWaypoints, loadWelcomePoint } from './services/nav-points';
import { notifyIntrusion } from './services/notify';
import { saveIntrusionCapture } from './captures';
import { handleEnroll } from './handlers/enroll';
import { handleCheckFace } from './handlers/check-face';
import { handleVisit } from './handlers/visit';
import { handleVoiceLog } from './handlers/voice';
import { handleListStaff, handleUpdateStaff, handleDeleteStaff } from './handlers/staff';
import { handleListCaptures } from './handlers/captures';
import { deleteSnapshot } from './captures';
import { handleAsk } from './handlers/ask';
import {
  handleKbIngest,
  handleKbSyncStaff,
  handleKbIngestUrl,
  handleKbIngestFile,
  handleKbCrawlStart,
  handleKbCrawlList,
  handleKbCrawlGet,
  handleKbList,
  handleKbStatus,
  handleKbDelete,
  handleKbSourcesList,
  handleKbSourcePatch,
  handleKbSourceSync,
  handleKbSourceDelete,
  handleElevenLabsAsk,
} from './handlers/kb';
import { runDueSyncs } from './services/kb-sources';
import { handleEntraSync } from './handlers/entra';
import { handleMcpPlugins } from './handlers/mcp-plugins';
import { getMcpPluginRegistry } from './services/mcp-plugins';
import { handleKbProviders } from './handlers/kb-providers';
import { getKbProviderRegistry } from './services/kb-providers';
import { handleRecordings } from './handlers/recordings';
import { handleNavPoints } from './handlers/nav-points';
import { handleVoiceCommands } from './handlers/voice-commands';
import { handleXboomLead, handleXboomCatalog } from './handlers/xboom';
import { getSupabaseClient } from './supabase/client';
import { initializeFaceModels } from './services/face-embedding';
import { FaceRecognitionService } from './services/face-recognition';
import { maybeNotifyBatteryLow, maybeNotifyObstacleBlocked, maybeNotifyIntrusion } from './services/push';

const PORT = parseInt(process.env.SPINE_PORT || '4000', 10);

interface AuthenticatedSocket extends WebSocket {
  sessionId?: string;
  userId?: string;
}

export function startServer(sdk: RobotSDK): Promise<void> {
  return new Promise(async (resolve, reject) => {
    const supabase = getSupabaseClient();

    // Single broadcast path for RobotEvents → admin clients. Assigned once the
    // WebSocket server exists (below); declared here so HTTP route handlers
    // (e.g. /visit) can reference it. No-op until assigned (requests arrive after).
    let broadcastRobotEvent: (event: RobotEvent) => void = () => {};

    // Spine-owned navigation state, broadcast to ALL clients (admin + robot app)
    // so a Go To pressed on either platform shows its banner + Cancel on both.
    // Cleared on the robot's cancel_result; replaced by each new navi.
    let naviState: {
      active: boolean;
      point?: RobotPosition;
      name?: string;
      source?: string;
      startedAt?: number;
      cancelling?: boolean;
      arrived?: boolean;
      stalled?: boolean;
      arrivalText?: string;
    } = { active: false };
    let broadcastNaviState: () => void = () => {};

    // Latest ElevenLabs credential state the robot has reported (masked — the
    // API key is presence + last-4 only). Relayed to admin clients for the
    // robot→admin half of two-way key sync; in-memory (re-sent by the robot on
    // every reconnect, so a spine restart self-heals).
    let latestRobotEleven: Record<string, unknown> = {};

    // Arrival watcher: while a navi is active, poll the live pose against the
    // target. Within ARRIVE_DIST_M we're "there"; we then wait for the heading
    // to align (or ARRIVE_ROT_WAIT_MS of hunting) and CANCEL the residual goal —
    // the chassis otherwise keeps rotating at the point indefinitely. Broadcasts
    // navi_state {active:false, arrived:true} so both UIs show "complete".
    // The chassis's own goal tolerance stops it 0.5–0.8m short of the target
    // (measured repeatedly), so the arrival radius must be wider than that or
    // arrival never triggers — the robot then rotation-hunts forever and no
    // arrived/speech broadcast fires. 2026-07-28: 0.85 → 1.0 after a live nav
    // parked ~0.9m short (tight corner) and never "arrived" — the escort
    // reassurance then looped at the destination until the watch timeout.
    const ARRIVE_DIST_M = 1.0;
    // Loose heading tolerance + short grace: the chassis's own final alignment
    // usually lands within ~30°, and every second here is silence between the
    // robot stopping and it speaking. Announce fast; precision isn't the point.
    // 2026-07-22: tightened 35→20→12 per demo feedback — final heading must
    // closely match the captured pose. Trade-off: settles outside 12° waits the
    // 3s grace before announcing. Future: prefetch ElevenLabs audio mid-drive.
    const ARRIVE_ROT_TOL_DEG = 6;
    const ARRIVE_ROT_WAIT_MS = 3_000;
    const NAVI_WATCH_TIMEOUT_MS = 4 * 60_000;
    let naviWatchTimer: ReturnType<typeof setInterval> | null = null;
    // Invoked when the active navigation finishes (arrived/timeout/cancelled) —
    // the patrol sequencer uses this to advance to the next waypoint.
    let naviDone: ((reason: 'arrived' | 'timeout' | 'cancelled') => void) | null = null;
    let arrivalCancelPending = false; // arrival-triggered cancelNavi in flight
    let escortCancelPending = false; // escort checkpoint-pause cancelNavi in flight
    const fireNaviDone = (reason: 'arrived' | 'timeout' | 'cancelled') => {
      const cb = naviDone;
      naviDone = null;
      if (cb) cb(reason);
    };
    const stopNaviWatch = () => {
      if (naviWatchTimer) {
        clearInterval(naviWatchTimer);
        naviWatchTimer = null;
      }
    };
    const startNaviWatch = () => {
      stopNaviWatch();
      const target = naviState.point;
      if (!target || !sdk.getPosition) return;
      const watchStarted = Date.now();
      let nearSince: number | null = null;
      let lastPose: RobotPosition | null = null;
      let lastMovedAt = Date.now();
      naviWatchTimer = setInterval(async () => {
        if (!naviState.active) {
          stopNaviWatch();
          return;
        }
        try {
          const pos = await sdk.getPosition!();
          // Feed the escort's live distance tracking off this same poll (no
          // second get_position poller racing the SDK's single pose resolver).
          if (escort.state.active) escort.handlePose(pos);
          const dist = Math.hypot(pos.x - target.x, pos.y - target.y);

          // Stall detection: goal active but the robot has not TRANSLATED
          // (>0.15m) for 30s and isn't at the goal → either fully wedged (needs
          // power-cycle) or spinning in place because the planner can't find a
          // clear path out of its spot. Rotation deliberately does NOT count as
          // progress — endless rotate-in-place is exactly a failure mode.
          if (lastPose) {
            const translated = Math.hypot(pos.x - lastPose.x, pos.y - lastPose.y) > 0.15;
            if (translated) {
              lastMovedAt = Date.now();
              if (naviState.stalled) {
                naviState = { ...naviState, stalled: false };
                broadcastNaviState();
              }
            } else if (!naviState.stalled && dist > ARRIVE_DIST_M &&
                Date.now() - lastMovedAt > 30_000) {
              console.log('[Spine] Navi STALLED — goal active but robot not translating');
              naviState = { ...naviState, stalled: true };
              broadcastNaviState();
            }
          } else {
            lastMovedAt = Date.now();
          }
          lastPose = pos;
          if (dist <= ARRIVE_DIST_M) {
            nearSince = nearSince ?? Date.now();
            const rotDelta = Math.abs(((pos.rotation - target.rotation + 540) % 360) - 180);
            if (rotDelta <= ARRIVE_ROT_TOL_DEG || Date.now() - nearSince >= ARRIVE_ROT_WAIT_MS) {
              console.log(`[Spine] Navi arrival detected (dist ${dist.toFixed(2)}m, rotΔ ${rotDelta.toFixed(0)}°) — completing`);
              stopNaviWatch();
              const name = naviState.name;
              const arrivalText = naviState.arrivalText;
              naviState = { active: false, arrived: true, name, arrivalText };
              // Kill any residual rotation-hunting at the goal. This produces a
              // cancel_result from the robot that must NOT be read as a
              // user-cancel (it was ending every patrol after waypoint 1).
              arrivalCancelPending = true;
              try {
                await sdk.cancelNavi?.();
              } catch { /* best-effort */ }
              broadcastNaviState();
              naviState = { active: false }; // arrived is a one-shot flag
              fireNaviDone('arrived');
            }
          } else {
            nearSince = null;
          }
          if (naviState.active && Date.now() - watchStarted > NAVI_WATCH_TIMEOUT_MS) {
            console.log('[Spine] Navi watch timeout — clearing stale navi_state');
            stopNaviWatch();
            naviState = { active: false };
            broadcastNaviState();
            fireNaviDone('timeout');
          }
        } catch { /* pose read failed — skip this tick */ }
      }, 1000);
    };

    // ── Security sweep (F9 intrusion detection) ────────────────────────────────
    // At each waypoint of an AFTER-HOURS patrol, look around for a person. The
    // scan is the same face-detection-as-person-proxy the escort uses (boxes
    // only — no identity, nothing stored). One positive frame is not an
    // intruder; IntrusionDetector requires consecutive hits before alarming.
    const intrusionDetector = new IntrusionDetector();
    const securityScan = createPersonScanner(sdk);

    /** Sound the alarm on the robot: broadcast so the chest screen sirens. */
    const soundAlarm = (waypoint: string | null) => {
      const msg = JSON.stringify({ type: 'alarm', action: 'start', waypoint } as SpineMessage);
      wss.clients.forEach((c) => { if (c.readyState === WebSocket.OPEN) c.send(msg); });
    };

    const runSecuritySweep = async (waypoint: string | null): Promise<void> => {
      try {
        const seen = await securityScan();
        const confirmed = intrusionDetector.record(seen);
        if (seen) {
          console.log(`[Security] Person seen at "${waypoint}" (streak ${intrusionDetector.streakLength})`);
        }
        if (!confirmed) return;

        console.warn(`[Security] INTRUSION CONFIRMED near "${waypoint}"`);
        // 1. Siren first — the deterrent is the point, and it needs no network.
        soundAlarm(waypoint);
        // 2. Evidence + 3. alert, both best-effort and independent of each other.
        // Supabase may be unconfigured (dev spine) — the siren and the alert
        // still fire, we just have no stored frame.
        const frame = await sdk.captureFrame(3000).catch(() => null);
        const capture = frame && supabase ? await saveIntrusionCapture(supabase, frame) : null;
        await logEvent('intrusion_detected', {
          waypoint, capture_id: capture?.captureId ?? null,
        });
        broadcastRobotEvent({
          type: 'intrusion_detected',
          payload: { waypoint, capture_id: capture?.captureId ?? null },
          timestamp: Date.now(),
        });
        void notifyIntrusion({ waypoint, at: new Date(), captureId: capture?.captureId ?? null });
        if (supabase) void maybeNotifyIntrusion(supabase, waypoint);
      } catch (err) {
        // A failed sweep must never break the patrol loop.
        console.error('[Security] sweep failed:', err instanceof Error ? err.message : String(err));
      }
    };

    // ── Guided tour stop (F8) ──────────────────────────────────────────────────
    // The waypoint's arrival_text is already spoken by the robot's nav provider
    // when it arrives (that's the station narration). What a tour adds is a
    // PAUSE for questions: tell the chest screen to open its mic, wait a fixed
    // window, then move on. The existing /ask RAG brain answers whatever is
    // asked — no separate Q&A path, so tour answers stay KB-grounded.
    const TOUR_QUESTION_WINDOW_MS = parseInt(process.env.TOUR_QUESTION_WINDOW_MS || '20000', 10);

    const emitTourEvent = (event: string, payload: Record<string, unknown> = {}) => {
      broadcastRobotEvent({ type: 'tour_event', payload: { event, ...payload }, timestamp: Date.now() });
    };

    /**
     * Drive back to the 'welcome' nav point after a tour. Falls back to doing
     * nothing (rather than docking) when no welcome point is saved — parking on
     * the charger mid-day would strand the reception desk.
     */
    const returnToBase = async (): Promise<void> => {
      try {
        if (!supabase) return;
        const home = await loadWelcomePoint(supabase);
        if (!home) {
          console.log('[Tour] No welcome point saved — staying put after the tour');
          return;
        }
        if (getStoppedState()) return;
        console.log('[Tour] Returning to base');
        await sdk.navi?.(home);
        naviState = {
          active: true, point: home, name: home.name ?? 'Reception',
          arrivalText: home.arrivalText, source: 'tour_return', startedAt: Date.now(),
        };
        broadcastNaviState();
        startNaviWatch();
      } catch (err) {
        console.error('[Tour] return to base failed:', err instanceof Error ? err.message : String(err));
      }
    };

    const runTourStop = async (waypoint: string | null): Promise<void> => {
      try {
        emitTourEvent('questions_open', { waypoint, windowMs: TOUR_QUESTION_WINDOW_MS });
        await new Promise<void>(resolve => setTimeout(resolve, TOUR_QUESTION_WINDOW_MS));
        emitTourEvent('questions_closed', { waypoint });
      } catch (err) {
        console.error('[Tour] stop failed:', err instanceof Error ? err.message : String(err));
      }
    };

    // ── Patrol sequencer ────────────────────────────────────────────────────────
    // Walks the given waypoints with the normal navi pipeline (so banners,
    // departure/arrival announcements, and cancel all behave), dwells at each,
    // and loops until stopped. Low battery aborts the patrol and docks.
    const PATROL_DWELL_MS = 8_000;
    // mode distinguishes the three things this sequencer drives:
    //   'patrol'   — plain waypoint loop (manual)
    //   'security' — after-hours: person-scan at each waypoint (F9)
    //   'tour'     — guided office tour: narrate + pause for questions (F8)
    type PatrolMode = 'patrol' | 'security' | 'tour';
    const patrol = { active: false, index: 0, lap: 1, loop: true,
      mode: 'patrol' as PatrolMode,
      points: [] as (RobotPosition & { name?: string; arrivalText?: string })[] };

    const stopPatrol = (reason: string) => {
      if (!patrol.active) return;
      console.log(`[Spine] Patrol stopped (${reason})`);
      patrol.active = false;
      stopNaviWatch();
      naviDone = null;
      try { void sdk.cancelNavi?.(); } catch { /* best-effort */ }
      naviState = { active: false };
      broadcastNaviState();
    };

    const patrolNext = async () => {
      if (!patrol.active) return;
      // STOP wins mid-route too: a stop during a dwell must not dispatch the
      // next leg (mirrors the escort's navi/resumeNavi guards).
      if (getStoppedState()) { stopPatrol('system stopped'); return; }
      if (patrol.index >= patrol.points.length) {
        if (!patrol.loop) {
          // A tour ends by taking the guest back where it started, rather than
          // abandoning them at the last station (blueprint F8).
          const wasTour = patrol.mode === 'tour';
          stopPatrol('route complete');
          if (wasTour) {
            emitTourEvent('finished');
            void returnToBase();
          }
          return;
        }
        patrol.index = 0;
        patrol.lap++;
      }
      const p = patrol.points[patrol.index];
      const name = p.name ?? `Waypoint ${patrol.index + 1}`;
      console.log(`[Spine] Patrol → ${name} (lap ${patrol.lap}, ${patrol.index + 1}/${patrol.points.length})`);
      try {
        await sdk.navi?.(p);
      } catch (err) {
        console.error('[Spine] Patrol navi failed:', err);
      }
      naviState = {
        active: true, point: p, name, arrivalText: p.arrivalText,
        source: 'patrol', startedAt: Date.now(),
      };
      broadcastNaviState();
      naviDone = () => {
        if (!patrol.active) return;
        const arrivedAt = name;
        patrol.index++;
        setTimeout(() => {
          // What happens at a waypoint depends on the mode. Both branches are
          // fail-safe: they never throw and always continue the route.
          if (patrol.mode === 'security') {
            void runSecuritySweep(arrivedAt).finally(() => void patrolNext());
          } else if (patrol.mode === 'tour') {
            void runTourStop(arrivedAt).finally(() => void patrolNext());
          } else {
            void patrolNext();
          }
        }, PATROL_DWELL_MS);
      };
      startNaviWatch();
    };

    const startPatrol = (
      points: (RobotPosition & { name?: string; arrivalText?: string })[],
      loop: boolean,
      mode: PatrolMode = 'patrol',
    ) => {
      stopPatrol('restart');
      escort.stop(); // patrol supersedes an active escort
      patrol.active = true;
      patrol.points = points;
      patrol.index = 0;
      patrol.lap = 1;
      patrol.loop = loop;
      patrol.mode = mode;
      if (mode === 'security') intrusionDetector.reset();
      void patrolNext();
    };

    // ── Escort sequencer (Follow-Me) ────────────────────────────────────────────
    // Person-verified waypoint walking: like patrol, but every leg pauses at a
    // ~2m distance interval AND at each arrival to verify the visitor is still
    // there (head-sweep + face-detection-only frames — no identity, nothing
    // stored). Nobody within the timeout → the escort stops in place. Logic
    // lives in escort.ts (testable); this block is the robot/socket wiring.
    const escort = new EscortController({
      navi: async (p: EscortPoint, i: number) => {
        if (getStoppedState()) throw new Error('system stopped');
        await sdk.navi?.(p);
        naviState = {
          active: true, point: p, name: p.name ?? `Waypoint ${i + 1}`,
          arrivalText: p.arrivalText, source: 'escort', startedAt: Date.now(),
        };
        broadcastNaviState();
        naviDone = (reason) => escort.handleNaviDone(reason);
        startNaviWatch();
      },
      pauseNavi: async () => {
        // Checkpoint pause: stop the watch first so the static pose can't
        // trip stall/arrival, and flag the cancel so its cancel_result isn't
        // read as a user cancel (same trick as arrivalCancelPending).
        stopNaviWatch();
        escortCancelPending = true;
        try {
          await sdk.cancelNavi?.();
        } catch { /* best-effort */ }
      },
      resumeNavi: async (p: EscortPoint) => {
        if (getStoppedState()) throw new Error('system stopped');
        await sdk.navi?.(p);
        naviDone = (reason) => escort.handleNaviDone(reason);
        startNaviWatch();
      },
      scanForPerson: createPersonScanner(sdk),
      onCheckState: () => broadcastNaviState(), // escort.state rides on navi_state
      onFinish: (reason, goalActive) => {
        console.log(`[Spine] Escort finished (${reason})`);
        stopNaviWatch();
        naviDone = null;
        if (goalActive) {
          // Escort-initiated cleanup cancel — flag it so its cancel_result
          // isn't read as a user cancel (which would kill a superseding
          // patrol/dock). The chassis keeps un-cancelled goals alive.
          escortCancelPending = true;
          try { void sdk.cancelNavi?.(); } catch { /* best-effort */ }
        }
        // nav_cancelled arrives FROM the cancel_result path, which has already
        // cleared + broadcast naviState — don't double-clear an unrelated nav.
        if (reason !== 'nav_cancelled') {
          naviState = { active: false };
          broadcastNaviState();
        }
        void logEvent('escort_finished', { reason });
      },
      onEvent: (event, payload) => {
        broadcastRobotEvent({
          type: 'escort_event',
          payload: { event, ...(payload ?? {}) },
          timestamp: Date.now(),
        });
      },
    });

    // ── Charging dock ───────────────────────────────────────────────────────────
    // The dock has no known map coordinates, so arrival = isCharging flipping
    // true (polled), not the distance watcher. 6-min timeout clears stale state.
    let dockWatch: ReturnType<typeof setInterval> | null = null;
    const stopDockWatch = () => { if (dockWatch) { clearInterval(dockWatch); dockWatch = null; } };
    const startDockState = (source: string) => {
      stopPatrol('docking');
      escort.stop(); // docking supersedes an active escort
      stopNaviWatch();
      naviState = {
        active: true, name: 'Charging Dock',
        arrivalText: 'I have docked, and I am charging now.',
        source, startedAt: Date.now(),
      };
      broadcastNaviState();
      stopDockWatch();
      const started = Date.now();
      dockWatch = setInterval(async () => {
        if (!naviState.active) { stopDockWatch(); return; }
        try {
          const st = await sdk.getStatus();
          if (st.isCharging) {
            console.log('[Spine] Docked — charging confirmed');
            stopDockWatch();
            naviState = { active: false, arrived: true, name: 'Charging Dock',
              arrivalText: 'I have docked, and I am charging now.' };
            broadcastNaviState();
            naviState = { active: false };
          } else if (Date.now() - started > 6 * 60_000) {
            console.log('[Spine] Dock watch timeout');
            stopDockWatch();
            naviState = { active: false };
            broadcastNaviState();
          }
        } catch { /* skip tick */ }
      }, 3000);
    };

    // ── After-hours security patrol scheduler (F9) ─────────────────────────────
    // OFF unless AFTER_HOURS_PATROL_WINDOW is set (e.g. "19:00-06:00") — a robot
    // that starts driving around at night must be an explicit deployment choice.
    const securityWindow = parseWindow(process.env.AFTER_HOURS_PATROL_WINDOW);
    if (securityWindow) {
      const scheduler = new SecurityScheduler(securityWindow, {
        nowMinutes: () => {
          const d = new Date();
          return d.getHours() * 60 + d.getMinutes();
        },
        isPatrolActive: () => patrol.active,
        startPatrol: async () => {
          // STOP still wins — never start a scheduled patrol on a stopped robot.
          if (getStoppedState()) {
            console.warn('[Security] Window open but system is STOPPED — not starting patrol');
            return false;
          }
          if (!supabase) {
            console.warn('[Security] Window open but Supabase is unconfigured — no waypoints to load');
            return false;
          }
          const points = await loadPatrolWaypoints(supabase);
          if (points.length === 0) {
            console.warn('[Security] Window open but no nav points saved — nothing to patrol');
            return false;
          }
          console.log(`[Security] After-hours window open — starting patrol over ${points.length} points`);
          await logEvent('after_hours_patrol_started', { points: points.length });
          startPatrol(points, true, 'security');
          return true;
        },
        stopPatrol: () => {
          console.log('[Security] After-hours window closed — stopping patrol');
          stopPatrol('after-hours window closed');
          void logEvent('after_hours_patrol_stopped', { reason: 'window_closed' });
        },
      });
      console.log(
        `[Security] After-hours patrol scheduled ${process.env.AFTER_HOURS_PATROL_WINDOW}`
      );
      setInterval(() => void scheduler.tick(), 60_000);
      void scheduler.tick(); // evaluate immediately on boot, don't wait a minute
    }

    // Auto-dock on low battery (AUTO_DOCK_BATTERY env, 0 disables; default 15%).
    const AUTO_DOCK_AT = parseInt(process.env.AUTO_DOCK_BATTERY || '15', 10);
    let lastAutoDock = 0;
    if (AUTO_DOCK_AT > 0) {
      setInterval(async () => {
        if (naviState.active || patrol.active) return;
        if (Date.now() - lastAutoDock < 10 * 60_000) return;
        try {
          const st = await sdk.getStatus();
          if (st.online && !st.isCharging && st.battery > 0 && st.battery <= AUTO_DOCK_AT) {
            console.log(`[Spine] Battery ${st.battery}% ≤ ${AUTO_DOCK_AT}% — auto-docking`);
            lastAutoDock = Date.now();
            await sdk.goDock?.();
            startDockState('auto');
            await logEvent('command_dock', { session_id: 'auto', reason: 'low_battery', battery: st.battery });
          }
        } catch { /* skip */ }
      }, 60_000);
    }

    // KB auto-sync: periodically re-crawl/re-ingest managed sources whose
    // interval has elapsed. Env-gated like AUTO_DOCK_BATTERY (KB_AUTOSYNC unset =
    // off). One source at a time (Voyage free-tier rate limit) — see
    // services/kb-sources.ts. We poll every 30 min; each source's own
    // sync_interval_hours decides whether it's actually due.
    if (process.env.KB_AUTOSYNC && supabase) {
      const kbSupabase = supabase; // narrowed non-null for the closures below
      const KB_AUTOSYNC_CHECK_MS = 30 * 60_000;
      const runKbAutoSync = async () => {
        try {
          const r = await runDueSyncs(kbSupabase);
          if (r.due > 0) {
            console.log(
              `[KB] auto-sync: ${r.synced}/${r.due} sources refreshed` +
                (r.failed ? `, ${r.failed} failed` : '')
            );
          }
        } catch (err) {
          console.error('[KB] auto-sync tick failed:', err instanceof Error ? err.message : String(err));
        }
      };
      setInterval(() => void runKbAutoSync(), KB_AUTOSYNC_CHECK_MS);
      void runKbAutoSync(); // evaluate on boot, don't wait 30 min
      console.log('[KB] auto-sync enabled (KB_AUTOSYNC set)');
    }

    // ── Video recording (spine-side, ffmpeg over the MJPEG stream) ─────────────
    // The ffmpeg process lives here, so a recording KEEPS RUNNING no matter what
    // the admin UI navigates to. Recording state is broadcast to all clients so
    // every screen shows the live status + a Stop control on return.
    const RECORDINGS_DIR = path.join(process.cwd(), 'recordings');
    const RECORD_MAX_MS = 5 * 60_000; // safety cap — auto-stop a forgotten recording
    let recorder: { proc: ChildProcess; file: string; startedAt: number } | null = null;
    let recordAutoStop: ReturnType<typeof setTimeout> | null = null;

    const recordStatus = () => ({
      recording: !!recorder,
      file: recorder ? path.basename(recorder.file) : null,
      startedAt: recorder?.startedAt ?? undefined,
      maxMs: RECORD_MAX_MS,
    });
    const broadcastRecordState = () => {
      const msg = { type: 'recording_state', ...recordStatus() } as SpineMessage;
      wss.clients.forEach((c) => {
        if (c.readyState === WebSocket.OPEN) c.send(JSON.stringify(msg));
      });
    };

    const startRecording = (): { ok: boolean; file?: string; error?: string } => {
      if (recorder) return { ok: false, error: 'already recording' };
      try {
        fs.mkdirSync(RECORDINGS_DIR, { recursive: true });
        const file = path.join(RECORDINGS_DIR, `rec-${new Date().toISOString().replace(/[:.]/g, '-')}.mp4`);
        const streamUrl = sdk.getCameraStreamUrl();
        const proc = spawn('ffmpeg', ['-y', '-i', streamUrl, '-c:v', 'libx264',
          '-preset', 'veryfast', '-pix_fmt', 'yuv420p', '-r', '15', file],
          { stdio: 'ignore' });
        proc.on('exit', (code) => {
          console.log(`[Spine] Recording ended (ffmpeg exit ${code})`);
          recorder = null;
          if (recordAutoStop) { clearTimeout(recordAutoStop); recordAutoStop = null; }
          broadcastRecordState();
        });
        recorder = { proc, file, startedAt: Date.now() };
        // Safety auto-stop so a forgotten recording can't grow forever.
        recordAutoStop = setTimeout(() => {
          console.log('[Spine] Recording hit max duration — auto-stopping');
          stopRecording();
        }, RECORD_MAX_MS);
        console.log(`[Spine] Recording started → ${file}`);
        broadcastRecordState();
        return { ok: true, file: path.basename(file) };
      } catch (err) {
        return { ok: false, error: String(err) };
      }
    };
    const stopRecording = (): { ok: boolean; file?: string } => {
      if (!recorder) return { ok: false };
      const file = path.basename(recorder.file);
      recorder.proc.kill('SIGINT'); // lets ffmpeg finalize the mp4 (exit handler broadcasts)
      return { ok: true, file };
    };

    // Initialize face-api models BEFORE server starts (required for enrollment)
    try {
      console.log('[Spine] Loading face-api models...');
      const modelUrl = process.env.FACE_API_MODEL_URL || 'https://cdn.jsdelivr.net/npm/@vladmandic/face-api@latest/model';
      await initializeFaceModels(modelUrl);
      console.log('[Spine] ✓ Face-api models loaded');
    } catch (err) {
      console.error('[Spine] Failed to load face-api models:', err);
      // Non-fatal: server starts but /enroll will fail with clearer error
    }

    // Create HTTP server (used for both WebSocket + HTTP routes)
    const httpServer = http.createServer(async (req, res) => {
      // CORS headers on every response
      res.setHeader('Access-Control-Allow-Origin', '*');
      res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PATCH, DELETE, OPTIONS');
      res.setHeader('Access-Control-Allow-Headers', 'authorization, content-type');

      // Handle preflight OPTIONS
      if (req.method === 'OPTIONS') {
        res.writeHead(204);
        res.end();
        return;
      }

      // Handle HTTP routes
      const url = req.url || '';

      // Battery bridge: real chassis charge fed from adb logcat (robot-core
      // robot_info). Doesn't need Supabase. Body: { battery: 0-100, charging: bool }.
      // Authed like every other route — an unauthenticated writer could fake a full
      // battery and keep the robot driving until it dies mid-escort.
      if (url === '/robot/battery' && req.method === 'POST') {
        const auth = await authorizeRequest(req);
        if (!auth.ok) {
          res.writeHead(auth.status, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ ok: false, reason: auth.reason }));
          return;
        }
        let body = '';
        req.on('data', (c) => (body += c));
        req.on('end', () => {
          try {
            const { battery, charging } = JSON.parse(body || '{}');
            if (typeof battery === 'number' && sdk.setRealBattery) {
              sdk.setRealBattery(battery, !!charging);
            }
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ ok: true }));
          } catch {
            res.writeHead(400, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ ok: false, reason: 'bad body' }));
          }
        });
        return;
      }

      // Showroom Order/Enquiry capture (face-screen FABs) → XBoom Workflow OS
      // sales pipeline. Talks to the XBOOM_* project, not spine's own Supabase.
      if (url === '/xboom/lead' && req.method === 'POST') {
        await handleXboomLead(req, res, broadcastRobotEvent);
        return;
      }
      if (url.startsWith('/xboom/catalog') && req.method === 'GET') {
        await handleXboomCatalog(req, res);
        return;
      }

      // Robot network config for clients (the admin camera viewer). The camera
      // MJPEG/snapshot server runs ON the robot at robotIp:8080, and the spine
      // already knows ROBOT_IP (it dials the robot). So clients FETCH the IP here
      // instead of hardcoding it: when the robot's DHCP lease moves, find_robot.sh
      // updates spine/.env + restarts the spine, and every client repoints on next
      // load — no rebuild, no editing settings in four places. Unauthed on purpose:
      // it's a LAN IP the open camera port already exposes, and the admin needs it
      // before a session exists in dev-bypass mode.
      if (url === '/robot/config' && req.method === 'GET') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
          robotIp: process.env.ROBOT_IP ?? null,
          cameraPort: 8080,
          // Masked ElevenLabs state the robot last reported (two-way key sync).
          eleven: latestRobotEleven,
        }));
        return;
      }

      // MCP plugin platform: add/remove/toggle external MCP servers (Slack,
      // Microsoft 365, CRM, …) via config — no Supabase dependency.
      if (url.startsWith('/mcp/plugins')) {
        await handleMcpPlugins(req, res, getMcpPluginRegistry());
        return;
      }

      // All HTTP routes need Supabase; fail clearly if it isn't configured.
      if (!supabase) {
        res.writeHead(503, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: false, reason: 'Supabase not configured' }));
        return;
      }

      if (url === '/enroll' && req.method === 'POST') {
        await handleEnroll(req, res, supabase);
        return;
      }

      if (url === '/check-face' && req.method === 'POST') {
        await handleCheckFace(req, res, supabase);
        return;
      }

      if (url === '/visit' && req.method === 'POST') {
        await handleVisit(req, res, supabase, broadcastRobotEvent, () => sdk.captureFrame(3000));
        return;
      }

      if (url === '/voice/log' && req.method === 'POST') {
        await handleVoiceLog(req, res, supabase);
        return;
      }

      // Recording + clip routes (start/stop/status/list/stream/delete). All of
      // them authenticate inside the handler — see handlers/recordings.ts.
      if (
        await handleRecordings(req, res, {
          dir: RECORDINGS_DIR,
          status: recordStatus,
          start: startRecording,
          stop: stopRecording,
          activeFile: () => (recorder ? path.basename(recorder.file) : null),
        })
      ) {
        return;
      }

      // Nav points — brokered here so the robot_app doesn't need the Supabase
      // anon key (migration 017 takes anon off the nav_points table).
      if (await handleNavPoints(req, res, supabase)) {
        return;
      }

      // Voice command catalog (Admin "Voice Commands" screen). Brokered like
      // nav_points — the table has no anon/authenticated RLS.
      if (await handleVoiceCommands(req, res, supabase)) {
        return;
      }

      if (url === '/staff' && req.method === 'GET') {
        await handleListStaff(req, res, supabase);
        return;
      }

      if (url === '/captures' && req.method === 'GET') {
        await handleListCaptures(req, res, supabase);
        return;
      }
      // Delete a snapshot (storage object + capture row).
      const capDelMatch = (req.url ?? '').match(/^\/captures\/([^/?]+)$/);
      if (capDelMatch && req.method === 'DELETE') {
        const auth = await authorizeRequest(req);
        if (!auth.ok) {
          res.writeHead(auth.status, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ ok: false, reason: auth.reason }));
          return;
        }
        try {
          await deleteSnapshot(supabase, decodeURIComponent(capDelMatch[1]));
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ ok: true }));
        } catch (err) {
          res.writeHead(500, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ ok: false, reason: String(err) }));
        }
        return;
      }

      if (url === '/ask' && req.method === 'POST') {
        await handleAsk(req, res, supabase);
        return;
      }

      // KB platform — manage the knowledge base the voice brain answers from.
      // 3rd-party KB sources (local-first fallback chain) — prefix router.
      if (await handleKbProviders(req, res, getKbProviderRegistry())) {
        return;
      }
      if (url === '/kb/ingest' && req.method === 'POST') {
        await handleKbIngest(req, res, supabase);
        return;
      }
      if (url === '/kb/sync-staff' && req.method === 'POST') {
        await handleKbSyncStaff(req, res, supabase);
        return;
      }
      if (url === '/kb/ingest-url' && req.method === 'POST') {
        await handleKbIngestUrl(req, res, supabase);
        return;
      }
      if (url === '/kb/ingest-file' && req.method === 'POST') {
        await handleKbIngestFile(req, res, supabase);
        return;
      }
      if (url === '/kb/crawl' && req.method === 'POST') {
        await handleKbCrawlStart(req, res, supabase);
        return;
      }
      if (url === '/kb/crawl' && req.method === 'GET') {
        await handleKbCrawlList(req, res);
        return;
      }
      const crawlMatch = url.match(/^\/kb\/crawl\/([^/]+)$/);
      if (crawlMatch && req.method === 'GET') {
        await handleKbCrawlGet(req, res, decodeURIComponent(crawlMatch[1]));
        return;
      }
      // Managed KB sources (URL/crawl) + auto-sync. `/sync` matched before {id}.
      if (url === '/kb/sources' && req.method === 'GET') {
        await handleKbSourcesList(req, res, supabase);
        return;
      }
      const sourceSyncMatch = url.match(/^\/kb\/sources\/([^/]+)\/sync$/);
      if (sourceSyncMatch && req.method === 'POST') {
        await handleKbSourceSync(req, res, supabase, decodeURIComponent(sourceSyncMatch[1]));
        return;
      }
      const sourceMatch = url.match(/^\/kb\/sources\/([^/]+)$/);
      if (sourceMatch && req.method === 'PATCH') {
        await handleKbSourcePatch(req, res, supabase, decodeURIComponent(sourceMatch[1]));
        return;
      }
      if (sourceMatch && req.method === 'DELETE') {
        await handleKbSourceDelete(req, res, supabase, decodeURIComponent(sourceMatch[1]));
        return;
      }
      if (url === '/kb/chunks' && req.method === 'GET') {
        await handleKbList(req, res, supabase);
        return;
      }
      if (url === '/kb/status' && req.method === 'GET') {
        await handleKbStatus(req, res, supabase);
        return;
      }
      const kbMatch = url.match(/^\/kb\/chunks\/([^/]+)$/);
      if (kbMatch && req.method === 'DELETE') {
        await handleKbDelete(req, res, supabase, decodeURIComponent(kbMatch[1]));
        return;
      }

      // ElevenLabs server-tool webhook → grounded RAG answer (two-brains fix).
      if (url === '/elevenlabs/ask' && req.method === 'POST') {
        await handleElevenLabsAsk(req, res, supabase);
        return;
      }

      // Microsoft Entra ID (Azure AD) → staff directory sync.
      if (url === '/entra/sync' && req.method === 'POST') {
        await handleEntraSync(req, res, supabase);
        return;
      }

      const staffMatch = url.match(/^\/staff\/([^/]+)$/);
      if (staffMatch) {
        const staffId = decodeURIComponent(staffMatch[1]);
        if (req.method === 'PATCH') {
          await handleUpdateStaff(req, res, supabase, staffId);
          return;
        }
        if (req.method === 'DELETE') {
          await handleDeleteStaff(req, res, supabase, staffId);
          return;
        }
      }

      // 404 for unknown routes
      res.writeHead(404);
      res.end(JSON.stringify({ error: 'Not found' }));
    });

    // Attach WebSocket server to HTTP server
    const wss = new WebSocketServer({ server: httpServer });

    console.log(`[Spine] WebSocket server starting on port ${PORT}`);

    wss.on('connection', (ws: AuthenticatedSocket) => {
      const tempSessionId = Math.random().toString(36).substring(7);
      console.log(`[Spine] Client connected: ${tempSessionId}`);

      let authenticated = false;

      // Timeout: client must auth within 5s
      const authTimeout = setTimeout(() => {
        if (!authenticated) {
          console.log(`[Spine] Auth timeout: ${tempSessionId}`);
          ws.close(1000, 'Auth timeout');
        }
      }, 5000);

      ws.on('message', async (rawData: Buffer | ArrayBuffer | Buffer[]) => {
        try {
          const data = Array.isArray(rawData)
            ? Buffer.concat(rawData).toString()
            : rawData.toString();

          console.log(`[Spine WebSocket] ======== MESSAGE RECEIVED ========`);
          console.log(`[Spine WebSocket] Session: ${tempSessionId} (authenticated: ${authenticated})`);
          console.log(`[Spine WebSocket] Raw data: ${data}`);

          const msg = JSON.parse(data) as AdminMessage;
          console.log(`[Spine WebSocket] Parsed message type: ${msg.type}`);

          // 1. AUTH — must be first message
          if (msg.type === 'auth') {
            console.log(`[Spine WebSocket] Processing AUTH message`);
            clearTimeout(authTimeout);

            const token = msg.token || '';
            const auth = await verifyToken(token);

            if (!auth.valid) {
              console.log(`[Spine WebSocket] Auth failed: ${auth.reason}`);
              ws.send(
                JSON.stringify({
                  type: 'error',
                  message: `Auth failed: ${auth.reason}`,
                } as SpineMessage)
              );
              ws.close(1000, 'Auth failed');
              return;
            }

            authenticated = true;
            ws.sessionId = tempSessionId;
            ws.userId = auth.userId;

            console.log(`[Spine WebSocket] Authenticated: ${ws.userId} (session ${ws.sessionId})`);
            await logAdminSession(ws.sessionId, 'connected', ws.userId);

            const authResponse = {
              type: 'authenticated',
              message: `Welcome ${ws.userId}`,
            } as SpineMessage;
            console.log(`[Spine WebSocket] Sending auth response: ${JSON.stringify(authResponse)}`);
            ws.send(JSON.stringify(authResponse));

            // Emit initial robot status
            console.log(`[Spine WebSocket] Fetching and sending initial robot status`);
            const status = await sdk.getStatus();
            const statusResponse = { type: 'robot_status', status } as SpineMessage;
            ws.send(JSON.stringify(statusResponse));

            // Emit current navigation state so a client joining mid-nav shows the banner.
            ws.send(JSON.stringify({ type: 'navi_state', ...naviState } as SpineMessage));

            return;
          }

          // 2. All other messages require auth
          if (!authenticated) {
            console.log(`[Spine WebSocket] Received non-auth message but not authenticated`);
            ws.send(
              JSON.stringify({
                type: 'error',
                message: 'Not authenticated — send auth message first',
              } as SpineMessage)
            );
            return;
          }

          // Voice phase (#80): robot_app broadcasts its voice state → re-broadcast
          // to ALL clients (admin app) as a voice_* event. Not a robot command, so
          // it bypasses the interlock/handler path. Payload shape mirrors the other
          // events (eventPayload.payload.state), consistent with face_detected.
          if (msg.type === 'intent' && msg.intent?.intent === 'voice_state') {
            const vs = msg.intent.voiceState;
            if (vs === 'listening' || vs === 'thinking' || vs === 'speaking' || vs === 'idle') {
              broadcastRobotEvent({ type: `voice_${vs}`, payload: { state: vs } });
            }
            ws.send(JSON.stringify({ type: 'ack', intent: 'voice_state', ok: true } as SpineMessage));
            return;
          }

          // Robot→admin key sync: the robot reports its (masked) ElevenLabs
          // credential state. Store it (for GET /robot/config) and re-broadcast
          // as config_state so an open admin Settings screen updates live.
          if (msg.type === 'intent' && (msg.intent as { intent?: string })?.intent === 'config_report') {
            latestRobotEleven = (msg.intent as { config?: Record<string, unknown> }).config ?? {};
            const cs = { type: 'config_state', config: latestRobotEleven } as SpineMessage;
            wss.clients.forEach((c) => {
              if (c.readyState === WebSocket.OPEN) c.send(JSON.stringify(cs));
            });
            ws.send(JSON.stringify({ type: 'ack', intent: 'config_report', ok: true } as SpineMessage));
            return;
          }

          // Patrol runs entirely in the spine (sequencer above) — intercept.
          if (msg.type === 'intent' && msg.intent?.intent === 'patrol_start') {
            const pts = msg.intent.points ?? [];
            if (!pts.length) {
              ws.send(JSON.stringify({ type: 'error', message: 'patrol_start needs points' } as SpineMessage));
              return;
            }
            // Safety: STOP must always win — check before starting any autonomous motion.
            if (getStoppedState()) {
              ws.send(JSON.stringify({ type: 'error', message: 'System stopped. Send resume to continue.' } as SpineMessage));
              return;
            }
            startPatrol(pts, msg.intent.loop !== false);
            ws.send(JSON.stringify({ type: 'ack', intent: 'patrol_start', ok: true } as SpineMessage));
            return;
          }
          if (msg.type === 'intent' && msg.intent?.intent === 'patrol_stop') {
            stopPatrol('user');
            ws.send(JSON.stringify({ type: 'ack', intent: 'patrol_stop', ok: true } as SpineMessage));
            return;
          }

          // Guided tour (F8) — the patrol sequencer in 'tour' mode: narrate at
          // each station, pause for questions, then return to base. Never loops.
          if (msg.type === 'intent' && msg.intent?.intent === 'tour_start') {
            const pts = msg.intent.points ?? [];
            if (!pts.length) {
              ws.send(JSON.stringify({ type: 'error', message: 'tour_start needs points' } as SpineMessage));
              return;
            }
            if (getStoppedState()) {
              ws.send(JSON.stringify({ type: 'error', message: 'System stopped. Send resume to continue.' } as SpineMessage));
              return;
            }
            void logEvent('tour_start', { session_id: ws.sessionId, points: pts.length });
            emitTourEvent('started', { total: pts.length });
            startPatrol(pts, false, 'tour');
            ws.send(JSON.stringify({ type: 'ack', intent: 'tour_start', ok: true } as SpineMessage));
            return;
          }
          if (msg.type === 'intent' && msg.intent?.intent === 'tour_stop') {
            const wasTour = patrol.mode === 'tour';
            stopPatrol('user');
            if (wasTour) emitTourEvent('finished', { reason: 'stopped' });
            ws.send(JSON.stringify({ type: 'ack', intent: 'tour_stop', ok: true } as SpineMessage));
            return;
          }

          // Escort (Follow-Me) also runs entirely in the spine — intercept.
          if (msg.type === 'intent' && msg.intent?.intent === 'escort_start') {
            const pts = msg.intent.points ?? [];
            if (!pts.length) {
              ws.send(JSON.stringify({ type: 'error', message: 'escort_start needs points' } as SpineMessage));
              return;
            }
            // Same guard the interlocks apply to movement intents (patrol/escort
            // are intercepted before the router, so check STOP here).
            if (getStoppedState()) {
              ws.send(JSON.stringify({ type: 'error', message: 'System stopped. Send resume to continue.' } as SpineMessage));
              return;
            }
            stopPatrol('escort');
            void logEvent('escort_start', { session_id: ws.sessionId, points: pts.length });
            escort.start(pts);
            ws.send(JSON.stringify({ type: 'ack', intent: 'escort_start', ok: true } as SpineMessage));
            return;
          }
          if (msg.type === 'intent' && msg.intent?.intent === 'escort_stop') {
            escort.stop();
            ws.send(JSON.stringify({ type: 'ack', intent: 'escort_stop', ok: true } as SpineMessage));
            return;
          }

          // 3. Route the message
          console.log(`[Spine WebSocket] Authenticated message, routing to handler...`);
          const response = await routeMessage(msg, ws.sessionId!, ws.userId!, sdk);
          console.log(`[Spine WebSocket] Handler returned response type: ${response.type}`);
          console.log(`[Spine WebSocket] Sending response to client: ${JSON.stringify(response)}`);
          ws.send(JSON.stringify(response));

          // STOP must halt AUTONOMOUS motion too, not just teleop drive. The
          // routed handler calls sdk.stopDrive(), which does nothing to a running
          // navi goal — and the chassis silently resumes goals it merely blocked.
          // So abort patrol/escort and cancel the goal here.
          if (msg.type === 'intent' && msg.intent?.intent === 'stop' && response.type === 'stopped') {
            const hadAutonomousGoal = patrol.active || escort.state.active || naviState.active;
            stopPatrol('system stopped');
            escort.stop();
            if (hadAutonomousGoal) {
              stopNaviWatch();
              naviDone = null;
              try { await sdk.cancelNavi?.(); } catch { /* best-effort — drive is already stopped */ }
              naviState = { active: false };
              broadcastNaviState();
              void logEvent('autonomous_motion_aborted', { session_id: ws.sessionId, reason: 'stop' });
            }
          }

          // Navigation state sync: a successfully-acked navi/cancel_navi updates
          // the shared navi_state and pushes it to every connected client.
          if (msg.type === 'intent' && response.type === 'ack' && response.ok) {
            const it = msg.intent?.intent;
            if (it === 'navi') {
              naviState = {
                active: true,
                point: msg.intent?.point,
                name: msg.intent?.name,
                source: msg.intent?.source ?? 'admin',
                arrivalText: msg.intent?.arrivalText,
                startedAt: Date.now(),
              };
              broadcastNaviState();
              startNaviWatch();
            } else if (it === 'dock') {
              startDockState(msg.intent?.source ?? 'admin');
            } else if (it === 'stop_voice') {
              // Admin wants to stop the robot's active voice/listening session.
              // The session lives on the robot app (ElevenLabs), so broadcast a
              // voice_control command to ALL clients — the robot app's SpineClient
              // picks it up and ends its session.
              const vc = { type: 'voice_control', action: 'stop' } as SpineMessage;
              console.log('[Spine] Broadcasting voice_control: stop (admin request)');
              wss.clients.forEach((c) => {
                if (c.readyState === WebSocket.OPEN) c.send(JSON.stringify(vc));
              });
            } else if (it === 'set_config') {
              // Relay robot-side config (name / behaviour toggles / speed) to the
              // robot app, which persists + applies it.
              const cfg = (msg.intent as { config?: Record<string, unknown> })?.config ?? {};
              const cu = { type: 'config_update', config: cfg } as SpineMessage;
              console.log(`[Spine] Broadcasting config_update: ${JSON.stringify(cfg)}`);
              wss.clients.forEach((c) => {
                if (c.readyState === WebSocket.OPEN) c.send(JSON.stringify(cu));
              });
            } else if (it === 'cancel_navi' && naviState.active) {
              naviState = { ...naviState, cancelling: true };
              broadcastNaviState();
            }
          }
          console.log(`[Spine WebSocket] ======== MESSAGE COMPLETE ========`);
        } catch (err) {
          console.error('[Spine WebSocket] !!!! MESSAGE HANDLING ERROR !!!!');
          console.error('[Spine WebSocket] Error:', err);
          ws.send(
            JSON.stringify({
              type: 'error',
              message: 'Internal server error',
            } as SpineMessage)
          );
        }
      });

      ws.on('close', async () => {
        clearTimeout(authTimeout);
        if (authenticated && ws.sessionId) {
          console.log(`[Spine] Client disconnected: ${ws.sessionId}`);
          await logAdminSession(ws.sessionId, 'disconnected', ws.userId);
        }
      });

      ws.on('error', (err) => {
        console.error('[Spine] WebSocket error:', err);
      });
    });

    httpServer.listen(PORT, () => {
      console.log(`✓ Spine server listening on port ${PORT} (WebSocket + HTTP routes)`);
      resolve();
    });

    httpServer.on('error', (err) => {
      console.error('[Spine] Server error:', err);
      reject(err);
    });

    // CRITICAL: Process-level safety nets to prevent enrollment crashes from killing the broker
    // These MUST stay in place: a bad face image must not take down robot control/camera/WS
    process.on('unhandledRejection', (err) => {
      console.error('[Spine] UNHANDLED REJECTION:', err);
      // Log but don't exit — /enroll handler should still return 500
    });

    process.on('uncaughtException', (err) => {
      console.error('[Spine] UNCAUGHT EXCEPTION:', err);
      // Log but don't exit — keep server alive for robot control
    });

    broadcastNaviState = () => {
      const msg = {
        type: 'navi_state',
        ...naviState,
        ...(escort.state.active ? { escort: escort.state } : {}),
      } as SpineMessage;
      console.log(`[Spine] Broadcasting navi_state: ${JSON.stringify(msg)}`);
      wss.clients.forEach((client) => {
        if (client.readyState === WebSocket.OPEN) {
          client.send(JSON.stringify(msg));
        }
      });
    };

    // Single broadcast path for all RobotEvents → { type:'event', event, eventPayload }.
    broadcastRobotEvent = (event: RobotEvent) => {
      const { type: eventType, ...rest } = event;
      const msg: SpineMessage = {
        type: 'event',
        event: eventType,
        eventPayload: rest,
      };
      wss.clients.forEach((client) => {
        if (client.readyState === WebSocket.OPEN) {
          client.send(JSON.stringify(msg));
        }
      });
      // The robot confirmed a navigation cancel → clear the shared navi state.
      if (eventType === 'navi_event' && (event.payload as Record<string, any>)?.event === 'cancel_result') {
        if (arrivalCancelPending) {
          arrivalCancelPending = false; // arrival cleanup, not a user cancel
          return;
        }
        if (escortCancelPending) {
          escortCancelPending = false; // escort checkpoint pause/cleanup, not a user cancel
          return;
        }
        patrol.active = false; // a confirmed USER cancel ends any patrol
        stopDockWatch();
        if (naviState.active || naviState.cancelling) {
          naviState = { active: false };
          broadcastNaviState();
        }
        fireNaviDone('cancelled');
      }
      // Push trigger (#90): battery low → notify admins (best-effort, never throws).
      if (eventType === 'battery_update' && supabase) {
        const level = Number(event.payload?.level);
        if (Number.isFinite(level)) void maybeNotifyBatteryLow(supabase, level);
      }
    };

    // Robot-originated events (battery, etc.) go through it…
    sdk.onEvent(broadcastRobotEvent);

    // …and so does the autonomous face recognizer (same path, one event shape).
    if (supabase) {
      // Frames come from the SDK — the recognizer never builds robot URLs.
      const recognizer = new FaceRecognitionService(
        (timeoutMs) => sdk.captureFrame(timeoutMs),
        supabase,
        broadcastRobotEvent
      );
      recognizer.start().catch((err) => {
        console.error('[Spine] Face recognizer failed to start:', err);
        // Non-fatal: robot control/camera/WS keep running.
      });
    } else {
      console.log('[Spine] Face recognizer disabled — Supabase not configured.');
    }

    // Sensor/obstacle awareness (Phase 1A): each SensorEvent updates the cached
    // RobotStatus, broadcasts it to all clients, and logs to Supabase.
    const broadcastStatus = (status: RobotStatus) => {
      const msg: SpineMessage = { type: 'robot_status', status };
      wss.clients.forEach((client: WebSocket) => {
        if (client.readyState === WebSocket.OPEN) {
          client.send(JSON.stringify(msg));
        }
      });
      // Push trigger (#90): obstacle blocked → notify admins (best-effort).
      // Fires once the CSJBot nav events feed the pipeline (#81).
      if (supabase && status.obstacleState) {
        void maybeNotifyObstacleBlocked(supabase, status.obstacleState);
      }
    };

    void sdk.getStatus().then((initialStatus) => {
      const handleSensorEvent = createSensorPipeline(
        initialStatus,
        broadcastStatus,
        (type, payload) => {
          void logEvent(type, payload);
        }
      );
      sdk.onSensorEvent(handleSensorEvent);
    });

    // Status heartbeat: clients only request robot_status once (at auth), so
    // without this they'd never see the robot come online/offline or battery
    // change after connecting. Poll the SDK and broadcast every 5s. getStatus()
    // is a cheap read of cached state (no robot round-trip), so this is light.
    setInterval(() => {
      void sdk.getStatus().then(broadcastStatus);
    }, 5000);
  });
}
