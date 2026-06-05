/**
 * robot/mock.ts — MockRobotSDK for development and testing
 * Emulates robot behavior without hardware.
 * Configurable event intervals for fast tests.
 */

import { RobotSDK } from './interface';
import { RobotStatus, RobotEvent } from '../types';

export interface MockRobotSDKOptions {
  eventIntervalMs?: number; // default 10000 (production), override for tests
}

export class MockRobotSDK implements RobotSDK {
  private status: RobotStatus = {
    online: true,
    battery: 85,
    isMoving: false,
    headLR: 50,
    headUD: 50,
    leftArm: 50,
    rightArm: 50,
    isWaving: false,
  };

  private eventHandlers: Array<(event: RobotEvent) => void> = [];
  private eventIntervals: NodeJS.Timeout[] = [];
  private eventIntervalMs: number;

  constructor(options?: MockRobotSDKOptions) {
    this.eventIntervalMs = options?.eventIntervalMs ?? 10000; // default 10s for production
  }

  async drive(dir: 'forward' | 'back' | 'left' | 'right'): Promise<void> {
    this.status.isMoving = true;
    console.log(`[Mock SDK] Drive: ${dir}`);
  }

  async stopDrive(): Promise<void> {
    this.status.isMoving = false;
    console.log('[Mock SDK] Stop driving');
  }

  async setHeadPosition(lr: number, ud: number): Promise<void> {
    this.status.headLR = Math.max(0, Math.min(100, lr));
    this.status.headUD = Math.max(0, Math.min(100, ud));
    console.log(`[Mock SDK] Head position: LR=${this.status.headLR}, UD=${this.status.headUD}`);
  }

  async setArmPosition(left: number, right: number): Promise<void> {
    this.status.leftArm = Math.max(0, Math.min(100, left));
    this.status.rightArm = Math.max(0, Math.min(100, right));
    console.log(`[Mock SDK] Arm position: L=${this.status.leftArm}, R=${this.status.rightArm}`);
  }

  async wave(): Promise<void> {
    this.status.isWaving = true;
    console.log('[Mock SDK] Wave started');
  }

  async stopWave(): Promise<void> {
    this.status.isWaving = false;
    console.log('[Mock SDK] Wave stopped');
  }

  async resetBody(): Promise<void> {
    this.status.headLR = 50;
    this.status.headUD = 50;
    this.status.leftArm = 50;
    this.status.rightArm = 50;
    this.status.isWaving = false;
    this.status.isMoving = false;
    console.log('[Mock SDK] Body reset to neutral');
  }

  async takeSnapshot(): Promise<Buffer> {
    console.log('[Mock SDK] Snapshot taken');
    // Return a minimal valid JPEG header (fake image)
    return Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10]);
  }

  async getStatus(): Promise<RobotStatus> {
    console.log('[Mock SDK] Status requested', this.status);
    return { ...this.status };
  }

  onEvent(handler: (event: RobotEvent) => void): void {
    this.eventHandlers.push(handler);

    // Emit face_detected every eventIntervalMs
    const faceInterval = setInterval(() => {
      const event: RobotEvent = {
        type: 'face_detected',
        payload: { count: Math.floor(Math.random() * 3) + 1 },
        timestamp: Date.now(),
      };
      this.eventHandlers.forEach(h => h(event));
    }, this.eventIntervalMs);

    // Emit battery_update every 3x eventIntervalMs
    const batteryInterval = setInterval(() => {
      this.status.battery = Math.max(10, this.status.battery - 2); // slowly drain
      const event: RobotEvent = {
        type: 'battery_update',
        payload: { level: this.status.battery },
        timestamp: Date.now(),
      };
      this.eventHandlers.forEach(h => h(event));
    }, this.eventIntervalMs * 3);

    this.eventIntervals.push(faceInterval, batteryInterval);
  }

  /**
   * Clean up intervals (for tests)
   */
  cleanup(): void {
    this.eventIntervals.forEach(interval => clearInterval(interval));
    this.eventIntervals = [];
    this.eventHandlers = [];
  }
}
