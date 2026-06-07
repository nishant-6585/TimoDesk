/**
 * robot/mock.ts — MockRobotSDK for development and testing
 * Emulates robot behavior without hardware.
 * Configurable event intervals for fast tests.
 */

import { RobotSDK } from './interface';
import { RobotStatus, RobotEvent, SensorEvent, ObstacleState, SensorHealth } from '../types';
import { getStoppedState } from '../commands/interlocks';

export interface MockSensorSimOptions {
  enabled?: boolean; // default true — auto-start in constructor; set false in tests
  obstacleMs?: number; // override the 8–15s random obstacle cadence (tests)
  sensorHealthMs?: number; // default 30000
  localizationMs?: number; // default 45000
  personMs?: number; // default 20000
}

export interface MockRobotSDKOptions {
  eventIntervalMs?: number; // default 10000 (production), override for tests
  // Predicate for "is the robot under a safety STOP?". Sensor emitters are
  // suppressed when true. Defaults to the interlocks module's global STOP state
  // (the single source of truth — see commands/interlocks.ts).
  isStopped?: () => boolean;
  sensorSim?: MockSensorSimOptions;
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
    obstacleState: 'unknown',
    localizationQuality: 'unknown',
    sensorHealth: null,
    personDetected: false,
    lastObstacleEventAt: null,
  };

  private eventHandlers: Array<(event: RobotEvent) => void> = [];
  private eventIntervals: NodeJS.Timeout[] = [];
  private eventIntervalMs: number;

  // Sensor sim state
  private sensorHandlers: Array<(event: SensorEvent) => void> = [];
  private sensorTimers: NodeJS.Timeout[] = [];
  private obstacleTimer: NodeJS.Timeout | null = null;
  private sensorSimRunning = false;
  private readonly isStopped: () => boolean;
  private readonly sensorSim: Required<MockSensorSimOptions>;

  constructor(options?: MockRobotSDKOptions) {
    this.eventIntervalMs = options?.eventIntervalMs ?? 10000; // default 10s for production
    this.isStopped = options?.isStopped ?? getStoppedState;
    this.sensorSim = {
      enabled: options?.sensorSim?.enabled ?? true,
      obstacleMs: options?.sensorSim?.obstacleMs ?? 0, // 0 → use random 8–15s
      sensorHealthMs: options?.sensorSim?.sensorHealthMs ?? 30000,
      localizationMs: options?.sensorSim?.localizationMs ?? 45000,
      personMs: options?.sensorSim?.personMs ?? 20000,
    };

    if (this.sensorSim.enabled) {
      this.startSensorSim();
    }
  }

  async drive(dir: 'forward' | 'back' | 'left' | 'right'): Promise<void> {
    this.status.isMoving = true;
    console.log(`[Mock SDK] Drive: ${dir}`);
    // Emit movement event so browser gets real-time feedback
    this.eventHandlers.forEach(h => h({
      type: 'robot_status_update',
      payload: { isMoving: true, direction: dir },
      timestamp: Date.now(),
    } as any));
  }

  async stopDrive(): Promise<void> {
    this.status.isMoving = false;
    console.log('[Mock SDK] Stop driving');
    // Emit stop event so browser knows robot stopped
    this.eventHandlers.forEach(h => h({
      type: 'robot_status_update',
      payload: { isMoving: false },
      timestamp: Date.now(),
    } as any));
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

  onSensorEvent(handler: (event: SensorEvent) => void): void {
    this.sensorHandlers.push(handler);
  }

  // ── Synthetic sensor simulator ────────────────────────────────────────────
  // Mimics the high-level obstacle / health / localization / person events the
  // CSJBot SDK surfaces (raw LIDAR scan is not exposed). All emitters are
  // suppressed while the robot is under a safety STOP.

  /**
   * Start the synthetic sensor emitters. Auto-called in the constructor unless
   * sensorSim.enabled is false. Idempotent.
   */
  startSensorSim(): void {
    if (this.sensorSimRunning) return;
    this.sensorSimRunning = true;

    this.scheduleObstacle();

    this.sensorTimers.push(
      // sensor health — every 30s (95% all-ok, 5% one sensor degraded to 'warn')
      setInterval(() => {
        this.emitSensorEvent({
          type: 'sensor_health',
          sensors: this.pickSensorHealth(),
          timestamp: Date.now(),
        });
      }, this.sensorSim.sensorHealthMs),

      // localization quality — every 45s (90% normal lq 70–95, 10% low lq 30–55)
      setInterval(() => {
        const { quality, lq } = this.pickLocalization();
        this.emitSensorEvent({ type: 'localization_lq', quality, lq, timestamp: Date.now() });
      }, this.sensorSim.localizationMs),

      // person detection — every 20s (30% detected)
      setInterval(() => {
        this.emitSensorEvent({
          type: 'person_detected',
          detected: Math.random() < 0.3,
          timestamp: Date.now(),
        });
      }, this.sensorSim.personMs)
    );
  }

  /**
   * Stop the synthetic sensor emitters and clear their timers.
   */
  stopSensorSim(): void {
    this.sensorSimRunning = false;
    if (this.obstacleTimer) {
      clearTimeout(this.obstacleTimer);
      this.obstacleTimer = null;
    }
    this.sensorTimers.forEach(t => clearInterval(t));
    this.sensorTimers = [];
  }

  /**
   * Obstacle events fire on a random 8–15s cadence (self-rescheduling), or a
   * fixed cadence when sensorSim.obstacleMs is set (tests).
   */
  private scheduleObstacle(): void {
    const delay = this.sensorSim.obstacleMs || 8000 + Math.floor(Math.random() * 7001); // 8–15s
    this.obstacleTimer = setTimeout(() => {
      this.emitSensorEvent({
        type: 'obstacle_event',
        state: this.pickObstacleState(),
        timestamp: Date.now(),
      });
      if (this.sensorSimRunning) this.scheduleObstacle();
    }, delay);
  }

  /**
   * Emit a sensor event to all handlers — unless suppressed by a safety STOP.
   */
  private emitSensorEvent(event: SensorEvent): void {
    if (this.isStopped()) return; // suppressed while stopped
    this.sensorHandlers.forEach(h => h(event));
  }

  // weighted: 60% running, 20% wait_short, 12% blocked, 8% wait_long
  private pickObstacleState(): Exclude<ObstacleState, 'unknown'> {
    const r = Math.random();
    if (r < 0.6) return 'running';
    if (r < 0.8) return 'wait_short';
    if (r < 0.92) return 'blocked';
    return 'wait_long';
  }

  private pickSensorHealth(): SensorHealth {
    if (Math.random() < 0.95) return { lidar: 'ok', rgbd: 'ok', sonar: 'ok' };
    const sensors: Array<keyof SensorHealth> = ['lidar', 'rgbd', 'sonar'];
    const degraded = sensors[Math.floor(Math.random() * sensors.length)];
    const health: SensorHealth = { lidar: 'ok', rgbd: 'ok', sonar: 'ok' };
    health[degraded] = 'warn';
    return health;
  }

  private pickLocalization(): { quality: 'low' | 'normal'; lq: number } {
    if (Math.random() < 0.9) {
      return { quality: 'normal', lq: 70 + Math.floor(Math.random() * 26) }; // 70–95
    }
    return { quality: 'low', lq: 30 + Math.floor(Math.random() * 26) }; // 30–55
  }

  /**
   * Clean up intervals (for tests)
   */
  cleanup(): void {
    this.eventIntervals.forEach(interval => clearInterval(interval));
    this.eventIntervals = [];
    this.eventHandlers = [];
    this.stopSensorSim();
    this.sensorHandlers = [];
  }
}
