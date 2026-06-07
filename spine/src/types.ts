/**
 * types.ts — Shared TypeScript definitions for spine and SDK
 * This is the contract that MockRobotSDK and RealRobotSDK both implement
 */

// Admin client intents (what the app sends to the spine)
export interface Intent {
  intent: 'drive' | 'head' | 'arm' | 'wave' | 'stop' | 'resume' | 'snapshot' | 'get_status';
  dir?: 'forward' | 'back' | 'left' | 'right'; // for drive
  lr?: number; // 0–100, for head
  ud?: number; // 0–100, for head
  left?: number; // 0–100, for arm
  right?: number; // 0–100, for arm
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
  battery: number; // 0–100
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

// Sensor events emitted by the robot (or mock) — discriminated on `type`.
// Distinct from RobotEvent: these drive the new RobotStatus sensor fields.
export type SensorEvent =
  | { type: 'obstacle_event'; state: Exclude<ObstacleState, 'unknown'>; timestamp: number }
  | { type: 'sensor_health'; sensors: SensorHealth; timestamp: number }
  | { type: 'localization_lq'; quality: Exclude<LocalizationQuality, 'unknown'>; lq: number; timestamp: number }
  | { type: 'person_detected'; detected: boolean; timestamp: number };

// Events emitted by the robot (or mock)
export interface RobotEvent {
  type: 'face_detected' | 'battery_update' | 'robot_online' | 'robot_offline';
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
  type: 'authenticated' | 'ack' | 'error' | 'robot_status' | 'event' | 'stopped' | 'resumed' | 'pong';
  ok?: boolean;
  message?: string;
  intent?: string; // for ack
  status?: RobotStatus; // for robot_status
  event?: RobotEvent; // for event
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
