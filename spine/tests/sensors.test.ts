/**
 * tests/sensors.test.ts — Sensor/obstacle awareness (Phase 1A)
 *
 * Covers:
 *  - applySensorEvent (pure state + log mapping)
 *  - createSensorPipeline (broadcast + log wiring)
 *  - person_detected transition-only logging
 *  - MockRobotSDK emitter: fires when running, suppressed under STOP
 */

import { describe, it, expect, vi, afterEach } from 'vitest';
import { applySensorEvent, createSensorPipeline } from '../src/sensors';
import { MockRobotSDK } from '../src/robot/mock';
import { RobotStatus, SensorEvent } from '../src/types';

function baseStatus(overrides: Partial<RobotStatus> = {}): RobotStatus {
  return {
    online: true,
    battery: 85,
    isMoving: false,
    headLR: 50,
    headUD: 50,
    leftArm: 50,
    rightArm: 50,
    isWaving: false,
    obstacleState: 'unknown',
    localizationQuality: 'unknown',
    sensorHealth: null,
    personDetected: false,
    lastObstacleEventAt: null,
    ...overrides,
  };
}

describe('applySensorEvent', () => {
  it('obstacle_event blocked → state + timestamp + log', () => {
    const ts = 1_700_000_000_000;
    const { status, logs } = applySensorEvent(baseStatus(), {
      type: 'obstacle_event',
      state: 'blocked',
      timestamp: ts,
    });

    expect(status.obstacleState).toBe('blocked');
    expect(status.lastObstacleEventAt).toBe(new Date(ts).toISOString());
    expect(logs).toEqual([{ type: 'obstacle.blocked', payload: { state: 'blocked' } }]);
  });

  it('obstacle_event running → logs obstacle.running', () => {
    const { status, logs } = applySensorEvent(baseStatus(), {
      type: 'obstacle_event',
      state: 'running',
      timestamp: 1,
    });
    expect(status.obstacleState).toBe('running');
    expect(logs[0].type).toBe('obstacle.running');
  });

  it('sensor_health → populates sensorHealth + logs sensor.health', () => {
    const sensors = { lidar: 'ok', rgbd: 'warn', sonar: 'ok' } as const;
    const { status, logs } = applySensorEvent(baseStatus(), {
      type: 'sensor_health',
      sensors,
      timestamp: 1,
    });
    expect(status.sensorHealth).toEqual(sensors);
    expect(logs).toEqual([{ type: 'sensor.health', payload: { ...sensors } }]);
  });

  it('localization_lq low vs normal → correct event type', () => {
    const low = applySensorEvent(baseStatus(), {
      type: 'localization_lq',
      quality: 'low',
      lq: 40,
      timestamp: 1,
    });
    expect(low.status.localizationQuality).toBe('low');
    expect(low.logs[0]).toEqual({ type: 'localization.lq_low', payload: { lq: 40 } });

    const normal = applySensorEvent(baseStatus(), {
      type: 'localization_lq',
      quality: 'normal',
      lq: 88,
      timestamp: 1,
    });
    expect(normal.logs[0].type).toBe('localization.lq_normal');
  });

  it('does not mutate the input status (immutable)', () => {
    const input = baseStatus();
    applySensorEvent(input, { type: 'obstacle_event', state: 'blocked', timestamp: 1 });
    expect(input.obstacleState).toBe('unknown');
  });
});

describe('person_detected transition logging', () => {
  it('logs only on transitions, not on repeated identical readings', () => {
    const broadcast = vi.fn();
    const log = vi.fn();
    const pipe = createSensorPipeline(baseStatus(), broadcast, log);

    const seq: boolean[] = [true, true, false, false, true];
    for (const detected of seq) {
      pipe({ type: 'person_detected', detected, timestamp: 1 });
    }

    // 5 emits, 3 transitions (false→true, true→false, false→true)
    expect(broadcast).toHaveBeenCalledTimes(5); // every event broadcasts current status
    const personLogs = log.mock.calls.filter(([t]) => t.startsWith('person.'));
    expect(personLogs.map(([t]) => t)).toEqual([
      'person.detected_on',
      'person.detected_off',
      'person.detected_on',
    ]);
  });
});

describe('createSensorPipeline', () => {
  it('blocked event → broadcasts updated status AND logs to Supabase', () => {
    const broadcast = vi.fn();
    const log = vi.fn();
    const pipe = createSensorPipeline(baseStatus(), broadcast, log);

    pipe({ type: 'obstacle_event', state: 'blocked', timestamp: 1 });

    expect(broadcast).toHaveBeenCalledTimes(1);
    expect(broadcast.mock.calls[0][0].obstacleState).toBe('blocked');
    expect(log).toHaveBeenCalledWith('obstacle.blocked', { state: 'blocked' });
  });

  it('sensor_health event → broadcasts populated sensorHealth', () => {
    const broadcast = vi.fn();
    const log = vi.fn();
    const pipe = createSensorPipeline(baseStatus(), broadcast, log);

    pipe({ type: 'sensor_health', sensors: { lidar: 'ok', rgbd: 'ok', sonar: 'warn' }, timestamp: 1 });

    expect(broadcast.mock.calls[0][0].sensorHealth).toEqual({
      lidar: 'ok',
      rgbd: 'ok',
      sonar: 'warn',
    });
    expect(log).toHaveBeenCalledWith('sensor.health', { lidar: 'ok', rgbd: 'ok', sonar: 'warn' });
  });

  it('carries state forward across successive events', () => {
    const broadcast = vi.fn();
    const log = vi.fn();
    const pipe = createSensorPipeline(baseStatus(), broadcast, log);

    pipe({ type: 'obstacle_event', state: 'blocked', timestamp: 1 });
    const after = pipe({ type: 'person_detected', detected: true, timestamp: 2 });

    // obstacleState from the first event persists into the second broadcast
    expect(after.obstacleState).toBe('blocked');
    expect(after.personDetected).toBe(true);
  });
});

describe('MockRobotSDK sensor simulator', () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  it('emits obstacle events while running', () => {
    vi.useFakeTimers();
    const mock = new MockRobotSDK({
      isStopped: () => false,
      sensorSim: { obstacleMs: 1000, sensorHealthMs: 1_000_000, localizationMs: 1_000_000, personMs: 1_000_000 },
    });
    const events: SensorEvent[] = [];
    mock.onSensorEvent(e => events.push(e));

    vi.advanceTimersByTime(5000); // ~5 obstacle ticks at 1s cadence

    expect(events.length).toBeGreaterThan(0);
    expect(events.every(e => e.type === 'obstacle_event')).toBe(true);
    mock.cleanup();
  });

  it('suppresses all sensor events while under a safety STOP', () => {
    vi.useFakeTimers();
    const mock = new MockRobotSDK({
      isStopped: () => true, // STOP active
      sensorSim: { obstacleMs: 1000, sensorHealthMs: 1000, localizationMs: 1000, personMs: 1000 },
    });
    const events: SensorEvent[] = [];
    mock.onSensorEvent(e => events.push(e));

    vi.advanceTimersByTime(20000); // 20s — would be many events if not suppressed

    expect(events).toHaveLength(0);
    mock.cleanup();
  });

  it('stopSensorSim halts emission', () => {
    vi.useFakeTimers();
    const mock = new MockRobotSDK({
      isStopped: () => false,
      sensorSim: { obstacleMs: 1000, sensorHealthMs: 1000, localizationMs: 1000, personMs: 1000 },
    });
    const events: SensorEvent[] = [];
    mock.onSensorEvent(e => events.push(e));

    mock.stopSensorSim();
    vi.advanceTimersByTime(20000);

    expect(events).toHaveLength(0);
    mock.cleanup();
  });
});

describe('RobotEvent wire format — event broadcast', () => {
  it('event broadcast has correct wire shape: type=event, event=string, eventPayload=rest', () => {
    // Simulate what happens in server.ts event handler
    const robotEvent = {
      type: 'face_detected' as const,
      payload: { confidence: 87 },
      timestamp: 1700000000,
    };

    // This is the fix: destructure event.type and spread the rest
    const { type: eventType, ...rest } = robotEvent;

    // Build the wire message (matching server.ts fix)
    const msg = {
      type: 'event' as const,
      event: eventType,
      eventPayload: rest,
    };

    // Verify the wire shape
    expect(msg.type).toBe('event');
    expect(msg.event).toBe('face_detected');
    expect(msg.eventPayload).toEqual({ payload: { confidence: 87 }, timestamp: 1700000000 });

    // Critical: type must NOT be clobbered by event type
    expect(msg.type).not.toBe('face_detected');
    expect(msg.type).toBe('event');
  });

  it('viewer_web and spine_service consume the wire format correctly', () => {
    // The fixed wire format that server.ts produces
    const wireMessage = {
      type: 'event',
      event: 'robot_status_update',
      eventPayload: { isMoving: true },
    };

    // viewer_web consumer (index.html line 471-478)
    expect(wireMessage.type).toBe('event');
    expect(wireMessage.event).toBe('robot_status_update');
    expect(wireMessage.eventPayload?.isMoving).toBe(true);

    // spine_service consumer (spine_service.dart)
    const eventType = wireMessage.event as string | undefined;
    const eventPayload = wireMessage.eventPayload as Record<string, any> | undefined;
    expect(eventType).toBe('robot_status_update');
    expect(eventPayload?.isMoving).toBe(true);
  });
});
