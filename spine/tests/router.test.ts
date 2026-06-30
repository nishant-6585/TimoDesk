/**
 * tests/router.test.ts — Command router tests
 * Verify intent → handler mapping and error handling
 */

import { describe, it, expect, vi, beforeEach } from 'vitest';
import { routeMessage } from '../src/commands/router';
import { Intent, AdminMessage } from '../src/types';
import { RobotSDK } from '../src/robot/interface';
import { resetState } from '../src/commands/interlocks';

// Mock SDK for testing
class MockTestSDK implements RobotSDK {
  calls: Array<{ method: string; args: any[] }> = [];

  async drive(dir: string) {
    this.calls.push({ method: 'drive', args: [dir] });
  }
  async stopDrive() {
    this.calls.push({ method: 'stopDrive', args: [] });
  }
  async setHeadPosition(lr: number, ud: number) {
    this.calls.push({ method: 'setHeadPosition', args: [lr, ud] });
  }
  async setArmPosition(left: number, right: number) {
    this.calls.push({ method: 'setArmPosition', args: [left, right] });
  }
  async wave() {
    this.calls.push({ method: 'wave', args: [] });
  }
  async stopWave() {
    this.calls.push({ method: 'stopWave', args: [] });
  }
  async resetBody() {
    this.calls.push({ method: 'resetBody', args: [] });
  }
  async takeSnapshot() {
    return Buffer.from('fake');
  }
  async getPosition() {
    this.calls.push({ method: 'getPosition', args: [] });
    return { x: 1.5, y: 2.25, z: 0, rotation: -109.35 };
  }
  async navi(point: any) {
    this.calls.push({ method: 'navi', args: [point] });
  }
  async cancelNavi() {
    this.calls.push({ method: 'cancelNavi', args: [] });
  }
  async getStatus() {
    return {
      online: true,
      battery: 80,
      isCharging: false,
      isMoving: false,
      headLR: 50,
      headUD: 50,
      leftArm: 50,
      rightArm: 50,
      isWaving: false,
    };
  }
  onEvent(handler: any) {}
}

describe('Command Router', () => {
  let sdk: MockTestSDK;
  const sessionId = 'test-session';
  const userId = 'test-user';

  beforeEach(() => {
    sdk = new MockTestSDK();
    resetState();
  });

  describe('Intent Routing', () => {
    it('drive intent → calls sdk.drive(dir)', async () => {
      const msg: AdminMessage = {
        type: 'intent',
        intent: { intent: 'drive', dir: 'forward' },
      };

      const response = await routeMessage(msg, sessionId, userId, sdk);

      expect(response.type).toBe('ack');
      expect(response.ok).toBe(true);
      expect(sdk.calls).toHaveLength(1);
      expect(sdk.calls[0].method).toBe('drive');
      expect(sdk.calls[0].args[0]).toBe('forward');
    });

    it('stop_drive intent → calls sdk.stopDrive(), returns ack', async () => {
      const msg: AdminMessage = {
        type: 'intent',
        intent: { intent: 'stop_drive' },
      };

      const response = await routeMessage(msg, sessionId, userId, sdk);

      expect(response.type).toBe('ack');
      expect(response.ok).toBe(true);
      expect(sdk.calls).toHaveLength(1);
      expect(sdk.calls[0].method).toBe('stopDrive');
    });

    it('get_position intent → returns the captured pose', async () => {
      const res = await routeMessage(
        { type: 'intent', intent: { intent: 'get_position' } },
        sessionId, userId, sdk
      );
      expect(res.type).toBe('position');
      expect(res.position).toEqual({ x: 1.5, y: 2.25, z: 0, rotation: -109.35 });
      expect(sdk.calls.some((c) => c.method === 'getPosition')).toBe(true);
    });

    it('navi intent → calls sdk.navi(point), ack', async () => {
      const point = { x: 1.5, y: 2.25, z: 0, rotation: -109.35 };
      const res = await routeMessage(
        { type: 'intent', intent: { intent: 'navi', point } },
        sessionId, userId, sdk
      );
      expect(res.type).toBe('ack');
      expect(res.ok).toBe(true);
      expect(sdk.calls.find((c) => c.method === 'navi')?.args[0]).toEqual(point);
    });

    it('navi intent without point → error', async () => {
      const res = await routeMessage(
        { type: 'intent', intent: { intent: 'navi' } },
        sessionId, userId, sdk
      );
      expect(res.type).toBe('error');
      expect(res.message).toContain('point');
    });

    it('head intent → calls sdk.setHeadPosition(lr, ud)', async () => {
      const msg: AdminMessage = {
        type: 'intent',
        intent: { intent: 'head', lr: 40, ud: 60 },
      };

      const response = await routeMessage(msg, sessionId, userId, sdk);

      expect(response.type).toBe('ack');
      expect(sdk.calls).toHaveLength(1);
      expect(sdk.calls[0].method).toBe('setHeadPosition');
      expect(sdk.calls[0].args).toEqual([40, 60]);
    });

    it('arm intent → calls sdk.setArmPosition(left, right)', async () => {
      const msg: AdminMessage = {
        type: 'intent',
        intent: { intent: 'arm', left: 80, right: 20 },
      };

      const response = await routeMessage(msg, sessionId, userId, sdk);

      expect(response.type).toBe('ack');
      expect(sdk.calls).toHaveLength(1);
      expect(sdk.calls[0].method).toBe('setArmPosition');
      expect(sdk.calls[0].args).toEqual([80, 20]);
    });

    it('ping → returns pong', async () => {
      const msg: AdminMessage = { type: 'ping' };

      const response = await routeMessage(msg, sessionId, userId, sdk);

      expect(response.type).toBe('pong');
      expect(sdk.calls).toHaveLength(0); // no SDK calls
    });
  });

  describe('Error Handling', () => {
    it('malformed JSON → returns error', async () => {
      const msg = { type: 'invalid' }; // not a valid AdminMessage

      const response = await routeMessage(msg, sessionId, userId, sdk);

      expect(response.type).toBe('error');
      expect(response.message).toBeDefined();
    });

    it('intent without required fields → returns error', async () => {
      const msg: AdminMessage = {
        type: 'intent',
        intent: { intent: 'drive' }, // missing 'dir'
      };

      const response = await routeMessage(msg, sessionId, userId, sdk);

      expect(response.type).toBe('error');
      expect(response.message).toContain('dir');
    });

    it('unknown intent type → returns error, no crash', async () => {
      const msg: AdminMessage = {
        type: 'intent',
        intent: { intent: 'unknown_command' } as any,
      };

      const response = await routeMessage(msg, sessionId, userId, sdk);

      expect(response.type).toBe('error');
      expect(response.message).toContain('unknown');
      expect(sdk.calls).toHaveLength(0); // SDK should not be called
    });

    it('null message → returns error', async () => {
      const response = await routeMessage(null, sessionId, userId, sdk);

      expect(response.type).toBe('error');
    });
  });

  describe('STOP Interlock Integration', () => {
    it('STOP intent → blocks subsequent movement', async () => {
      const stopMsg: AdminMessage = {
        type: 'intent',
        intent: { intent: 'stop' },
      };

      // Send STOP
      const stopResponse = await routeMessage(stopMsg, sessionId, userId, sdk);
      expect(stopResponse.type).toBe('stopped');

      // Try to drive
      const driveMsg: AdminMessage = {
        type: 'intent',
        intent: { intent: 'drive', dir: 'forward' },
      };

      const driveResponse = await routeMessage(driveMsg, sessionId, userId, sdk);
      expect(driveResponse.type).toBe('error');
      expect(driveResponse.message).toContain('stopped');
    });

    it('stop_drive is allowed while globally stopped and does NOT un-latch', async () => {
      // Latch global STOP
      await routeMessage({ type: 'intent', intent: { intent: 'stop' } }, sessionId, userId, sdk);

      // stop_drive must still go through (halting is always safe)
      const sd = await routeMessage(
        { type: 'intent', intent: { intent: 'stop_drive' } },
        sessionId,
        userId,
        sdk
      );
      expect(sd.type).toBe('ack');
      expect(sdk.calls.some((c) => c.method === 'stopDrive')).toBe(true);

      // …but it must NOT have un-latched the interlock: drive is still blocked.
      const drive = await routeMessage(
        { type: 'intent', intent: { intent: 'drive', dir: 'forward' } },
        sessionId,
        userId,
        sdk
      );
      expect(drive.type).toBe('error');
      expect(drive.message).toContain('stopped');
    });

    it('RESUME intent → allows movement again', async () => {
      // Send STOP
      const stopMsg: AdminMessage = {
        type: 'intent',
        intent: { intent: 'stop' },
      };
      await routeMessage(stopMsg, sessionId, userId, sdk);

      // Resume
      const resumeMsg: AdminMessage = {
        type: 'intent',
        intent: { intent: 'resume' },
      };
      const resumeResponse = await routeMessage(resumeMsg, sessionId, userId, sdk);
      expect(resumeResponse.type).toBe('resumed');

      // Drive should work now
      const driveMsg: AdminMessage = {
        type: 'intent',
        intent: { intent: 'drive', dir: 'forward' },
      };
      const driveResponse = await routeMessage(driveMsg, sessionId, userId, sdk);
      expect(driveResponse.type).toBe('ack');
    });
  });
});
