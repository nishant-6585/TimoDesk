/**
 * robot/interface.ts — RobotSDK contract
 * Both MockRobotSDK and RealRobotSDK implement this interface.
 * Allows swapping between mock (dev) and real (production) via .env
 */

import { RobotStatus, RobotEvent, SensorEvent } from '../types';

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
   * Get current robot status (battery, position, movement state)
   */
  getStatus(): Promise<RobotStatus>;

  /**
   * Register a handler for robot events (face_detected, battery_update, etc.)
   */
  onEvent(handler: (event: RobotEvent) => void): void;

  /**
   * Register a handler for sensor/obstacle awareness events (Phase 1A).
   * Mock synthesizes these on a timer; Real receives them from the native
   * bridge documented in robot_app/docs/SENSOR_BRIDGE.md.
   */
  onSensorEvent(handler: (event: SensorEvent) => void): void;
}
