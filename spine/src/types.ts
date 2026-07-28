/**
 * types.ts — Shared TypeScript definitions for spine and SDK
 * This is the contract that RealRobotSDK implements
 */

// Admin client intents (what the app sends to the spine)
export interface Intent {
  intent:
    | 'drive'
    | 'stop_drive' // halt the wheels on joystick release — does NOT latch the global STOP interlock
    | 'get_position' // capture current SLAM pose (for saving a nav point)
    | 'navi' // navigate to a saved point
    | 'cancel_navi' // cancel an in-progress navigation
    | 'dock' // drive to the charging dock (SDK goHome; dock auto-aligns)
    | 'patrol_start' // loop through saved points (spine-side sequencer)
    | 'patrol_stop' // stop the patrol (cancels the active leg)
    | 'escort_start' // walk saved points, person-verified at each step (spine-side sequencer)
    | 'escort_stop' // stop the escort (cancels the active leg)
    | 'head'
    | 'arm'
    | 'wave'
    | 'stop'
    | 'resume'
    | 'snapshot'
    | 'get_status'
    | 'voice_state' // robot_app → spine: broadcast current voice phase (#80)
    | 'voice_log'; // robot_app → spine: log a completed conversation turn (#80)
  dir?: 'forward' | 'back' | 'left' | 'right'; // for drive
  lr?: number; // 0–100, for head
  ud?: number; // 0–100, for head
  left?: number; // 0–100, for arm
  right?: number; // 0–100, for arm
  // Voice (#80)
  voiceState?: 'listening' | 'thinking' | 'speaking' | 'idle'; // for voice_state
  transcript?: { role: 'user' | 'assistant'; text: string; ts: string }[]; // for voice_log
  resolvedBy?: 'elevenlabs';
  point?: RobotPosition; // for navi
  points?: (RobotPosition & { name?: string; arrivalText?: string })[]; // for patrol_start / escort_start
  loop?: boolean; // for patrol_start — repeat the route until stopped
  name?: string; // for navi — display name of the target point (broadcast to all clients)
  source?: 'admin' | 'robot'; // for navi — which UI initiated it
  arrivalText?: string; // for navi — custom phrase the robot speaks on arrival
}

// A SLAM pose / navigation point.
export interface RobotPosition {
  x: number;
  y: number;
  z: number;
  rotation: number;
}

// ── Sensor / obstacle awareness (Phase 1A) ──────────────────────────────────
// Sourced from CSJBot high-level nav events (raw LIDAR scan is NOT exposed).
// See robot_app/docs/SENSOR_BRIDGE.md for the native bridge that produces these.

export type ObstacleState = 'running' | 'blocked' | 'wait_short' | 'wait_long' | 'unknown';
export type LocalizationQuality = 'low' | 'normal' | 'unknown';
export type SensorState = 'ok' | 'warn' | 'error';

export interface SensorHealth {
  lidar: SensorState;
  rgbd: SensorState;
  sonar: SensorState;
}

// Robot status (what the robot reports back)
export interface RobotStatus {
  online: boolean;
  battery: number; // 0–100 — real chassis charge when available (via battery bridge), else head/tablet
  isCharging: boolean; // robot on charger / charge_status != 0
  isMoving: boolean;
  headLR: number; // 0–100
  headUD: number; // 0–100
  leftArm: number; // 0–100
  rightArm: number; // 0–100
  isWaving: boolean;
  // Sensor awareness (Phase 1A)
  obstacleState: ObstacleState;
  localizationQuality: LocalizationQuality;
  sensorHealth: SensorHealth | null;
  personDetected: boolean;
  lastObstacleEventAt: string | null; // ISO-8601
}

// Sensor events emitted by the robot — discriminated on `type`.
// Distinct from RobotEvent: these drive the new RobotStatus sensor fields.
export type SensorEvent =
  | { type: 'obstacle_event'; state: Exclude<ObstacleState, 'unknown'>; timestamp: number }
  | { type: 'sensor_health'; sensors: SensorHealth; timestamp: number }
  | { type: 'localization_lq'; quality: Exclude<LocalizationQuality, 'unknown'>; lq: number; timestamp: number }
  | { type: 'person_detected'; detected: boolean; timestamp: number };

// Events emitted by the robot
export interface RobotEvent {
  type:
    | 'face_detected'
    | 'battery_update'
    | 'robot_online'
    | 'robot_offline'
    | 'navi_event'
    | 'escort_event' // escort lifecycle (started / checkpoint / person_confirmed / finished)
    | 'visitor_arrived'
    // Voice phase, broadcast to the admin app (#80)
    | 'voice_listening'
    | 'voice_thinking'
    | 'voice_speaking'
    | 'voice_idle';
  payload?: Record<string, any>;
  timestamp?: number;
}

// Admin WebSocket message (inbound from app)
export interface AdminMessage {
  type: 'auth' | 'intent' | 'ping';
  token?: string; // for auth
  intent?: Intent; // for intent
}

// Spine WebSocket message (outbound to app)
export interface SpineMessage {
  type: 'authenticated' | 'ack' | 'error' | 'robot_status' | 'event' | 'stopped' | 'resumed' | 'pong' | 'position' | 'navi_state';
  ok?: boolean;
  message?: string;
  intent?: string; // for ack
  captureId?: string; // for snapshot ack — the stored capture row id
  status?: RobotStatus; // for robot_status
  position?: RobotPosition; // for get_position response
  event?: string; // for event — the event type name (e.g. 'face_detected')
  eventPayload?: Record<string, any>; // for event — the event payload fields
  // navi_state — spine-owned cross-client navigation state (Go To / Cancel sync)
  active?: boolean;
  name?: string; // target point display name
  point?: RobotPosition;
  source?: string; // 'admin' | 'robot'
  cancelling?: boolean;
  startedAt?: number;
  arrived?: boolean; // one-shot: navigation completed (sent with active:false)
  stalled?: boolean; // goal active but robot not moving — nav service likely wedged
  arrivalText?: string; // custom arrival phrase (spoken by the robot on arrived)
  patrol?: { active: boolean; index: number; total: number; lap: number }; // patrol progress
  escort?: { active: boolean; index: number; total: number; checking: boolean }; // escort progress
}

// Session tracking (spine-internal)
export interface AdminSession {
  id: string;
  userId: string;
  connectedAt: number;
  lastCommandTime: Record<string, number>; // intent → timestamp
}

// Robot command format (what RealRobotSDK sends to actual robot)
export interface RobotCommand {
  cmd: string; // 'move', 'stop', 'head_both', 'left_arm', 'wave', etc.
  [key: string]: any; // flexible for different commands
}
