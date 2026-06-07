/**
 * sensors.ts — Sensor/obstacle event pipeline (Phase 1A)
 *
 * Turns a SensorEvent (from the SDK) into:
 *   1. an updated RobotStatus (immutable)
 *   2. a list of Supabase robot_event records to log
 *
 * `applySensorEvent` is pure (no I/O) so it can be unit-tested directly.
 * `createSensorPipeline` wires it to broadcast + log side effects, holding the
 * server-side status cache (the server itself keeps no status — see server.ts).
 */

import { RobotStatus, SensorEvent } from './types';

export interface SensorLog {
  type: string;
  payload?: Record<string, any>;
}

export interface SensorApplyResult {
  status: RobotStatus;
  logs: SensorLog[];
}

/**
 * Apply a single sensor event to a status snapshot.
 * Returns a NEW status object and the events that should be logged to Supabase.
 *
 * person_detected only produces a log on a TRANSITION (the prev value lives in
 * `status.personDetected`), so a steady stream of identical readings is silent.
 */
export function applySensorEvent(status: RobotStatus, event: SensorEvent): SensorApplyResult {
  switch (event.type) {
    case 'obstacle_event': {
      return {
        status: {
          ...status,
          obstacleState: event.state,
          lastObstacleEventAt: new Date(event.timestamp).toISOString(),
        },
        logs: [{ type: `obstacle.${event.state}`, payload: { state: event.state } }],
      };
    }

    case 'sensor_health': {
      return {
        status: { ...status, sensorHealth: event.sensors },
        logs: [{ type: 'sensor.health', payload: { ...event.sensors } }],
      };
    }

    case 'localization_lq': {
      return {
        status: { ...status, localizationQuality: event.quality },
        logs: [
          {
            type: event.quality === 'low' ? 'localization.lq_low' : 'localization.lq_normal',
            payload: { lq: event.lq },
          },
        ],
      };
    }

    case 'person_detected': {
      const transitioned = status.personDetected !== event.detected;
      return {
        status: { ...status, personDetected: event.detected },
        logs: transitioned
          ? [{ type: event.detected ? 'person.detected_on' : 'person.detected_off' }]
          : [],
      };
    }
  }
}

/**
 * Build a handler that owns a rolling status cache, applies each incoming sensor
 * event, broadcasts the updated status, and logs the resulting robot_events.
 * Returns the handler to register via sdk.onSensorEvent().
 */
export function createSensorPipeline(
  initial: RobotStatus,
  broadcast: (status: RobotStatus) => void,
  log: (type: string, payload?: Record<string, any>) => void
): (event: SensorEvent) => RobotStatus {
  let status = initial;
  return (event: SensorEvent): RobotStatus => {
    const result = applySensorEvent(status, event);
    status = result.status;
    broadcast(status);
    for (const entry of result.logs) {
      log(entry.type, entry.payload);
    }
    return status;
  };
}
