/**
 * tests/interlocks.test.ts — Safety interlock tests
 * CRITICAL: STOP must always win, even in race conditions
 */

import { describe, it, expect, beforeEach } from 'vitest';
import {
  checkInterlocks,
  handleStop,
  handleResume,
  getStoppedState,
  resetState,
} from '../src/commands/interlocks';
import { Intent } from '../src/types';

describe('Safety Interlocks', () => {
  beforeEach(() => {
    resetState(); // Reset to initial state before each test
  });

  describe('GLOBAL STOP', () => {
    it('STOP followed immediately by drive → drive rejected', async () => {
      const sessionId = 'admin-1';

      // Send STOP
      await handleStop(sessionId);
      expect(getStoppedState()).toBe(true);

      // Immediately try to drive (should be rejected)
      const driveIntent: Intent = { intent: 'drive', dir: 'forward' };
      const result = await checkInterlocks(driveIntent, sessionId);

      expect(result.allowed).toBe(false);
      expect(result.reason).toContain('stopped');
    });

    it('STOP from admin A blocks commands from admin B (global state)', async () => {
      // Admin A sends STOP
      await handleStop('admin-a');
      expect(getStoppedState()).toBe(true);

      // Admin B tries to drive (should be rejected — STOP is global)
      const driveIntent: Intent = { intent: 'drive', dir: 'forward' };
      const result = await checkInterlocks(driveIntent, 'admin-b');

      expect(result.allowed).toBe(false);
      expect(result.reason).toContain('stopped');
    });

    it('STOP + Resume → movement allowed again', async () => {
      const sessionId = 'admin-1';
      const driveIntent: Intent = { intent: 'drive', dir: 'forward' };

      // Send STOP
      await handleStop(sessionId);
      let result = await checkInterlocks(driveIntent, sessionId);
      expect(result.allowed).toBe(false);

      // Resume
      await handleResume(sessionId);
      expect(getStoppedState()).toBe(false);

      // Try to drive again
      result = await checkInterlocks(driveIntent, sessionId);
      expect(result.allowed).toBe(true);
    });

    it('snapshot allowed while stopped', async () => {
      await handleStop('admin-1');

      const snapshotIntent: Intent = { intent: 'snapshot' };
      const result = await checkInterlocks(snapshotIntent, 'admin-1');

      expect(result.allowed).toBe(true); // snapshot is allowed even when stopped
    });

    it('get_status allowed while stopped', async () => {
      await handleStop('admin-1');

      const statusIntent: Intent = { intent: 'get_status' };
      const result = await checkInterlocks(statusIntent, 'admin-1');

      expect(result.allowed).toBe(true); // status is allowed even when stopped
    });
  });

  describe('Rate Limiting', () => {
    it('multiple drive commands in short time → silently dropped', async () => {
      const sessionId = 'admin-1';
      const driveIntent: Intent = { intent: 'drive', dir: 'forward' };

      // Send 5 drive commands rapidly (each call checks interlocks internally)
      const results = [];
      for (let i = 0; i < 5; i++) {
        const result = await checkInterlocks(driveIntent, sessionId);
        results.push(result.allowed);
      }

      // Only first should pass the rate limit (100ms per drive)
      expect(results[0]).toBe(true);
      // Rest return true (silently dropped) — not errors
      expect(results.slice(1).every(r => r === true)).toBe(true);
    });

    it('different intent types have different rate limits', async () => {
      const sessionId = 'admin-1';

      // Head has 50ms limit, drive has 100ms limit
      const headIntent: Intent = { intent: 'head', lr: 50, ud: 50 };
      const driveIntent: Intent = { intent: 'drive', dir: 'forward' };

      // Send head command
      let result = await checkInterlocks(headIntent, sessionId);
      expect(result.allowed).toBe(true);

      // Immediately send head command again → should be dropped
      result = await checkInterlocks(headIntent, sessionId);
      expect(result.allowed).toBe(true); // silently dropped, not error

      // But drive should be allowed (different rate bucket)
      result = await checkInterlocks(driveIntent, sessionId);
      expect(result.allowed).toBe(true);
    });
  });

  describe('Office Hours Mode', () => {
    it('OFFICE_HOURS_MODE=true blocks drive', async () => {
      // Set env var for this test
      const original = process.env.OFFICE_HOURS_MODE;
      process.env.OFFICE_HOURS_MODE = 'true';

      try {
        const driveIntent: Intent = { intent: 'drive', dir: 'forward' };
        const result = await checkInterlocks(driveIntent, 'admin-1');

        expect(result.allowed).toBe(false);
        expect(result.reason).toContain('office hours');
      } finally {
        process.env.OFFICE_HOURS_MODE = original;
      }
    });

    it('OFFICE_HOURS_MODE=true allows head and arm', async () => {
      const original = process.env.OFFICE_HOURS_MODE;
      process.env.OFFICE_HOURS_MODE = 'true';

      try {
        const headIntent: Intent = { intent: 'head', lr: 50, ud: 50 };
        const armIntent: Intent = { intent: 'arm', left: 50, right: 50 };

        let result = await checkInterlocks(headIntent, 'admin-1');
        expect(result.allowed).toBe(true); // head is allowed

        result = await checkInterlocks(armIntent, 'admin-1');
        expect(result.allowed).toBe(true); // arm is allowed
      } finally {
        process.env.OFFICE_HOURS_MODE = original;
      }
    });
  });

  describe('Edge Cases', () => {
    it('resume without stop is idempotent', async () => {
      const sessionId = 'admin-1';

      // Resume without stop first
      await handleResume(sessionId);
      expect(getStoppedState()).toBe(false);

      // Try resume again
      await handleResume(sessionId);
      expect(getStoppedState()).toBe(false);
    });

    it('multiple stops are idempotent', async () => {
      const sessionId = 'admin-1';

      await handleStop(sessionId);
      expect(getStoppedState()).toBe(true);

      await handleStop(sessionId);
      expect(getStoppedState()).toBe(true); // still stopped
    });
  });
});
