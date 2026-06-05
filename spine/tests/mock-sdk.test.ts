/**
 * tests/mock-sdk.test.ts — MockRobotSDK behavior tests
 * Verify mock emits correct events and responds correctly
 */

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { MockRobotSDK } from '../src/robot/mock';
import { RobotEvent, RobotStatus } from '../src/types';

describe('MockRobotSDK', () => {
  let mock: MockRobotSDK;

  beforeEach(() => {
    // Use fast intervals for tests (100ms instead of 10s)
    mock = new MockRobotSDK({ eventIntervalMs: 100 });
  });

  afterEach(() => {
    mock.cleanup();
  });

  describe('Event Emission', () => {
    it('emits face_detected event', async () => {
      return new Promise<void>((done) => {
        const events: RobotEvent[] = [];

        mock.onEvent((event) => {
          events.push(event);

          // Check for face_detected event
          if (event.type === 'face_detected') {
            expect(event.payload?.count).toBeGreaterThan(0);
            mock.cleanup();
            done();
          }
        });

        // Timeout if event doesn't fire (should be ~100ms)
        setTimeout(() => {
          if (events.length === 0) {
            mock.cleanup();
            done(new Error('No events emitted within timeout'));
          }
        }, 500);
      });
    });

    it('emits battery_update event', async () => {
      return new Promise<void>((done) => {
        const events: RobotEvent[] = [];

        mock.onEvent((event) => {
          events.push(event);

          // Battery is emitted at 3x interval (300ms)
          if (event.type === 'battery_update') {
            expect(event.payload?.level).toBeDefined();
            expect(event.payload!.level).toBeGreaterThanOrEqual(0);
            expect(event.payload!.level).toBeLessThanOrEqual(100);
            mock.cleanup();
            done();
          }
        });

        // Timeout if event doesn't fire
        setTimeout(() => {
          if (events.filter(e => e.type === 'battery_update').length === 0) {
            mock.cleanup();
            done(new Error('Battery event not emitted within timeout'));
          }
        }, 1000);
      });
    });

    it('configurable event interval affects emission rate', async () => {
      mock.cleanup(); // clean up default mock

      // Create mock with very slow interval
      const slowMock = new MockRobotSDK({ eventIntervalMs: 50 });
      let faceCount = 0;

      return new Promise<void>((done) => {
        slowMock.onEvent((event) => {
          if (event.type === 'face_detected') {
            faceCount++;
          }
        });

        // In 200ms with 50ms interval, should get ~4 events
        setTimeout(() => {
          slowMock.cleanup();
          expect(faceCount).toBeGreaterThanOrEqual(2); // at least 2
          done();
        }, 200);
      });
    });
  });

  describe('Commands', () => {
    it('drive command succeeds', async () => {
      const result = await mock.drive('forward');
      expect(result).toBeUndefined(); // resolves without error
    });

    it('stopDrive command succeeds', async () => {
      await mock.drive('forward');
      const result = await mock.stopDrive();
      expect(result).toBeUndefined();
    });

    it('setHeadPosition updates status', async () => {
      await mock.setHeadPosition(40, 60);
      const status = await mock.getStatus();
      expect(status.headLR).toBe(40);
      expect(status.headUD).toBe(60);
    });

    it('setArmPosition updates status', async () => {
      await mock.setArmPosition(80, 20);
      const status = await mock.getStatus();
      expect(status.leftArm).toBe(80);
      expect(status.rightArm).toBe(20);
    });

    it('wave sets isWaving flag', async () => {
      await mock.wave();
      const status = await mock.getStatus();
      expect(status.isWaving).toBe(true);
    });

    it('stopWave clears isWaving flag', async () => {
      await mock.wave();
      await mock.stopWave();
      const status = await mock.getStatus();
      expect(status.isWaving).toBe(false);
    });

    it('resetBody resets all positions', async () => {
      await mock.setHeadPosition(40, 60);
      await mock.setArmPosition(80, 20);
      await mock.wave();
      await mock.drive('forward');

      await mock.resetBody();

      const status = await mock.getStatus();
      expect(status.headLR).toBe(50);
      expect(status.headUD).toBe(50);
      expect(status.leftArm).toBe(50);
      expect(status.rightArm).toBe(50);
      expect(status.isWaving).toBe(false);
      expect(status.isMoving).toBe(false);
    });

    it('takeSnapshot returns buffer', async () => {
      const buffer = await mock.takeSnapshot();
      expect(buffer).toBeInstanceOf(Buffer);
      expect(buffer.length).toBeGreaterThan(0);
    });

    it('getStatus returns valid RobotStatus', async () => {
      const status = await mock.getStatus();

      expect(status.online).toBe(true);
      expect(status.battery).toBeGreaterThanOrEqual(0);
      expect(status.battery).toBeLessThanOrEqual(100);
      expect(typeof status.isMoving).toBe('boolean');
      expect(status.headLR).toBeGreaterThanOrEqual(0);
      expect(status.headLR).toBeLessThanOrEqual(100);
      expect(status.headUD).toBeGreaterThanOrEqual(0);
      expect(status.headUD).toBeLessThanOrEqual(100);
    });
  });

  describe('Position Clamping', () => {
    it('clamps head position to 0–100', async () => {
      await mock.setHeadPosition(-10, 150);
      const status = await mock.getStatus();
      expect(status.headLR).toBe(0);
      expect(status.headUD).toBe(100);
    });

    it('clamps arm position to 0–100', async () => {
      await mock.setArmPosition(-5, 105);
      const status = await mock.getStatus();
      expect(status.leftArm).toBe(0);
      expect(status.rightArm).toBe(100);
    });
  });
});
