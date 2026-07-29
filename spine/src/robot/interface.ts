/**
 * robot/interface.ts — RobotSDK contract
 * Implemented by RealRobotSDK; the spine talks to the robot only through this.
 */

import { RobotStatus, RobotEvent, SensorEvent, RobotPosition } from '../types';

export interface RobotSDK {
  /**
   * Drive the chassis in a direction (continuous until stopDrive called)
   */
  drive(dir: 'forward' | 'back' | 'left' | 'right'): Promise<void>;

  /**
   * Stop all chassis movement
   */
  stopDrive(): Promise<void>;

  /**
   * Set head position (both LR and UD at once)
   * @param lr Left-Right: 0=left, 50=center, 100=right
   * @param ud Up-Down: 0=down, 50=center, 100=up
   */
  setHeadPosition(lr: number, ud: number): Promise<void>;

  /**
   * Set arm positions
   * @param left 0=down, 50=center, 100=up
   * @param right 0=down, 50=center, 100=up
   */
  setArmPosition(left: number, right: number): Promise<void>;

  /**
   * Start waving both arms
   */
  wave(): Promise<void>;

  /**
   * Stop waving
   */
  stopWave(): Promise<void>;

  /**
   * Reset body to neutral position (home)
   */
  resetBody(): Promise<void>;

  /**
   * Take a snapshot from the camera
   * @returns Image buffer (JPEG/PNG bytes)
   */
  takeSnapshot(): Promise<Buffer>;

  /**
   * Camera MJPEG stream URL — for consumers that need a URL rather than frames
   * (e.g. the ffmpeg recorder). The SDK is the only component that knows where
   * the robot's camera lives; nothing outside it may build robot URLs.
   */
  getCameraStreamUrl(): string;

  /**
   * Non-throwing snapshot with a timeout: one validated JPEG from the robot
   * camera, or null (unreachable / timed out / not a JPEG). Pollers that must
   * never crash the spine (the face recognizer) use this over takeSnapshot().
   */
  captureFrame(timeoutMs?: number): Promise<Buffer | null>;

  /**
   * Get current robot status (battery, position, movement state)
   */
  getStatus(): Promise<RobotStatus>;

  /**
   * Register a handler for robot events (face_detected, battery_update, etc.)
   */
  onEvent(handler: (event: RobotEvent) => void): void;

  /**
   * Register a handler for sensor/obstacle awareness events (Phase 1A).
   * RealRobotSDK receives them from the native bridge documented in
   * robot_app/docs/SENSOR_BRIDGE.md.
   */
  onSensorEvent(handler: (event: SensorEvent) => void): void;

  /**
   * Feed the REAL chassis charge in from an external source (the battery bridge
   * that tails robot-core's `robot_info` over adb). Overrides the head/tablet
   * battery that the 8090 endpoint reports. Optional — only RealRobotSDK has it.
   */
  setRealBattery?(level: number, charging: boolean): void;

  /** Capture the robot's current SLAM pose (for saving a nav point). */
  getPosition?(): Promise<RobotPosition>;

  /** Navigate to a saved point (needs a localized map + off-dock). */
  navi?(point: RobotPosition): Promise<void>;

  /** Cancel an in-progress navigation. */
  cancelNavi?(): Promise<void>;
  goDock?(): Promise<void>; // drive to the charging dock (vendor goHome)
}
