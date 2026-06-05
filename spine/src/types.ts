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
}

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
