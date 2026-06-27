/**
 * robot/real.ts — RealRobotSDK
 * Forwards spine intents to actual robot WebSocket ports (8081/8082/8083).
 * Explicitly translates from spine intent format to robot command format.
 */

import { WebSocket } from 'ws';
import { RobotSDK } from './interface';
import { RobotStatus, RobotEvent, SensorEvent } from '../types';

export interface RealRobotSDKOptions {
  robotIP: string;
  headPort?: number; // default 8081
  chassisPort?: number; // default 8082
  armPort?: number; // default 8083
}

export class RealRobotSDK implements RobotSDK {
  private robotIP: string;
  private headPort: number;
  private chassisPort: number;
  private armPort: number;

  private ws_head: WebSocket | null = null;
  private ws_chassis: WebSocket | null = null;
  private ws_arms: WebSocket | null = null;

  private eventHandlers: Array<(event: RobotEvent) => void> = [];

  // Real chassis charge fed by the battery bridge (adb logcat → /robot/battery).
  // -1 = no bridge data yet; when >= 0 it overrides the head/tablet battery that
  // the robot_app 8090 endpoint reports.
  private realBattery = -1;

  private status: RobotStatus = {
    online: false,
    battery: -1, // -1 = unknown until the first real /battery fetch (admin shows "—")
    isCharging: false,
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

  constructor(options: RealRobotSDKOptions) {
    this.robotIP = options.robotIP;
    this.headPort = options.headPort ?? 8081;
    this.chassisPort = options.chassisPort ?? 8082;
    this.armPort = options.armPort ?? 8083;

    // Start periodic battery fetch from robot_app HTTP endpoint
    this.startBatteryFetch();
  }

  private async fetchBatteryOnce() {
    try {
      const response = await fetch(`http://${this.robotIP}:8090/battery`);
      if (response.ok) {
        // A successful HTTP response means the robot is reachable. This probe
        // runs on boot + every 30s and is the canonical liveness signal that
        // drives `online` (the flag the admin Control screen gates commands on).
        this.setOnline(true);
        const data = (await response.json()) as { battery?: number };
        const battery = data.battery as number;
        // The 8090 endpoint is the head/tablet battery. Only use it when the
        // bridge hasn't supplied the real chassis charge (realBattery < 0).
        if (this.realBattery < 0 && battery >= 0 && battery <= 100) {
          this.status.battery = battery;
          console.log(`[Real SDK] Battery (head/tablet) updated: ${battery}%`);
        }
      } else {
        this.setOnline(false);
      }
    } catch (err) {
      // Probe failed → robot unreachable. Mark offline so the admin UI greys
      // out controls instead of silently dropping commands.
      this.setOnline(false);
    }
  }

  /**
   * Update the cached online flag and emit a transition event so the server can
   * broadcast fresh status to admin clients the moment reachability changes.
   */
  private setOnline(online: boolean): void {
    if (this.status.online === online) return;
    this.status.online = online;
    console.log(`[Real SDK] Robot ${online ? 'online' : 'offline'}`);
    const event: RobotEvent = {
      type: online ? 'robot_online' : 'robot_offline',
      payload: {},
      timestamp: Date.now(),
    };
    this.eventHandlers.forEach(h => h(event));
  }

  private startBatteryFetch() {
    void this.fetchBatteryOnce(); // immediately, so we don't serve the seed 85 for a minute
    setInterval(() => void this.fetchBatteryOnce(), 30000); // then every 30s
  }

  /**
   * Ensure WebSocket is connected, with auto-reconnect
   */
  private async ensureConnected(type: 'head' | 'chassis' | 'arms'): Promise<WebSocket> {
    let ws: WebSocket | null;
    const port = type === 'head' ? this.headPort : type === 'chassis' ? this.chassisPort : this.armPort;

    if (type === 'head') {
      ws = this.ws_head;
    } else if (type === 'chassis') {
      ws = this.ws_chassis;
    } else {
      ws = this.ws_arms;
    }

    // If already connected, return it
    if (ws && ws.readyState === WebSocket.OPEN) {
      return ws;
    }

    // Create new connection
    return new Promise((resolve, reject) => {
      ws = new WebSocket(`ws://${this.robotIP}:${port}`);

      ws.onopen = () => {
        console.log(`[Real SDK] Connected to robot ${type} on port ${port}`);
        if (type === 'head') this.ws_head = ws;
        else if (type === 'chassis') this.ws_chassis = ws;
        else this.ws_arms = ws;
        // A successful control-port connection is definitive proof the robot is
        // reachable — mark online immediately rather than waiting for the probe.
        this.setOnline(true);
        resolve(ws!);
      };

      ws.onerror = (error) => {
        console.error(`[Real SDK] Connection error to ${type}:`, error);
        reject(error);
      };

      ws.onclose = () => {
        console.log(`[Real SDK] Connection closed: ${type}`);
        if (type === 'head') this.ws_head = null;
        else if (type === 'chassis') this.ws_chassis = null;
        else this.ws_arms = null;
      };

      ws.onmessage = (msg) => {
        this.handleRobotMessage(msg.data.toString());
      };

      // Timeout if connection takes too long
      setTimeout(() => {
        if (ws!.readyState !== WebSocket.OPEN) {
          reject(new Error(`Connection timeout to ${type}`));
        }
      }, 5000);
    });
  }

  /**
   * Handle incoming messages from robot
   */
  private handleRobotMessage(data: string): void {
    try {
      const msg = JSON.parse(data);
      console.log('[Real SDK] Received from robot:', msg);

      // Parse robot events and emit them
      if (msg.type === 'face_detected') {
        const event: RobotEvent = {
          type: 'face_detected',
          payload: msg.payload || {},
          timestamp: Date.now(),
        };
        this.eventHandlers.forEach(h => h(event));
      } else if (msg.type === 'battery_update') {
        const batteryLevel = msg.payload?.level ?? msg.level ?? this.status.battery;
        this.status.battery = batteryLevel;
        console.log(`[Real SDK] Battery updated: ${batteryLevel}%`);
        const event: RobotEvent = {
          type: 'battery_update',
          payload: { level: this.status.battery },
          timestamp: Date.now(),
        };
        console.log('[Real SDK] Emitting battery event:', event);
        this.eventHandlers.forEach(h => h(event));
      }
    } catch (err) {
      console.error('[Real SDK] Failed to parse robot message:', err);
    }
  }

  /**
   * TRANSLATION: Spine intent format → Robot command format
   * Drive: {"intent":"drive","dir":"forward"} → {"cmd":"move","dir":"forward"}
   */
  async drive(dir: 'forward' | 'back' | 'left' | 'right'): Promise<void> {
    const ws = await this.ensureConnected('chassis');
    const command = { cmd: 'move', dir };
    console.log(`[Real SDK] Translating drive → robot command:`, command);
    ws.send(JSON.stringify(command));
    this.status.isMoving = true;
  }

  /**
   * TRANSLATION: stopDrive → {"cmd":"stop"}
   */
  async stopDrive(): Promise<void> {
    const ws = await this.ensureConnected('chassis');
    const command = { cmd: 'stop' };
    console.log(`[Real SDK] Translating stopDrive → robot command:`, command);
    ws.send(JSON.stringify(command));
    this.status.isMoving = false;
  }

  /**
   * TRANSLATION: Head position
   * {"intent":"head","lr":40,"ud":60} → {"cmd":"head_both","lr":40,"ud":60}
   */
  async setHeadPosition(lr: number, ud: number): Promise<void> {
    const ws = await this.ensureConnected('head');
    const command = { cmd: 'head_both', lr, ud };
    console.log(`[Real SDK] Translating setHeadPosition → robot command:`, command);
    ws.send(JSON.stringify(command));
    this.status.headLR = lr;
    this.status.headUD = ud;
  }

  /**
   * TRANSLATION: Arm position
   * {"intent":"arm","left":80,"right":20} → {"cmd":"left_arm","value":80} + {"cmd":"right_arm","value":20}
   */
  async setArmPosition(left: number, right: number): Promise<void> {
    const ws = await this.ensureConnected('arms');
    const leftCmd = { cmd: 'left_arm', value: left };
    const rightCmd = { cmd: 'right_arm', value: right };
    console.log(`[Real SDK] Translating setArmPosition → robot commands:`, leftCmd, rightCmd);
    ws.send(JSON.stringify(leftCmd));
    ws.send(JSON.stringify(rightCmd));
    this.status.leftArm = left;
    this.status.rightArm = right;
  }

  /**
   * TRANSLATION: wave → {"cmd":"wave"}
   */
  async wave(): Promise<void> {
    const ws = await this.ensureConnected('arms');
    const command = { cmd: 'wave' };
    console.log(`[Real SDK] Translating wave → robot command:`, command);
    ws.send(JSON.stringify(command));
    this.status.isWaving = true;
  }

  /**
   * TRANSLATION: stopWave → (no specific command, check SDK docs)
   * For now, we'll send a reset to arms
   */
  async stopWave(): Promise<void> {
    const ws = await this.ensureConnected('arms');
    const command = { cmd: 'reset' };
    console.log(`[Real SDK] Translating stopWave → robot command:`, command);
    ws.send(JSON.stringify(command));
    this.status.isWaving = false;
  }

  /**
   * TRANSLATION: resetBody → reset on head + arms
   */
  async resetBody(): Promise<void> {
    try {
      const wsHead = await this.ensureConnected('head');
      const wsArms = await this.ensureConnected('arms');
      wsHead.send(JSON.stringify({ cmd: 'reset' }));
      wsArms.send(JSON.stringify({ cmd: 'reset' }));
      this.status.headLR = 50;
      this.status.headUD = 50;
      this.status.leftArm = 50;
      this.status.rightArm = 50;
      this.status.isWaving = false;
      this.status.isMoving = false;
      console.log('[Real SDK] resetBody sent');
    } catch (err) {
      console.error('[Real SDK] resetBody failed:', err);
    }
  }

  /**
   * Take snapshot from HTTP endpoint
   */
  async takeSnapshot(): Promise<Buffer> {
    try {
      const response = await fetch(`http://${this.robotIP}:8080/snapshot`);
      if (!response.ok) {
        throw new Error(`Snapshot failed: ${response.statusText}`);
      }
      const buffer = Buffer.from(await response.arrayBuffer());
      console.log(`[Real SDK] Snapshot taken (${buffer.length} bytes)`);
      return buffer;
    } catch (err) {
      console.error('[Real SDK] takeSnapshot failed:', err);
      throw err;
    }
  }

  /**
   * Feed the REAL chassis charge + charging state in from the battery bridge
   * (adb logcat → robot-core `robot_info`). This is the true drive battery,
   * unlike the head/tablet value the 8090 endpoint returns.
   */
  setRealBattery(level: number, charging: boolean): void {
    if (level >= 0 && level <= 100) {
      this.realBattery = level;
      this.status.battery = level;
    }
    this.status.isCharging = charging;
    console.log(`[Real SDK] Real chassis battery: ${level}% charging=${charging}`);
  }

  /**
   * Get status (static for now; could query robot)
   */
  async getStatus(): Promise<RobotStatus> {
    console.log('[Real SDK] getStatus:', this.status);
    return { ...this.status };
  }

  /**
   * Register event handler
   */
  onEvent(handler: (event: RobotEvent) => void): void {
    this.eventHandlers.push(handler);
  }

  /**
   * Register sensor/obstacle event handler.
   *
   * PLACEHOLDER — no-op until real hardware is wired in. The CSJBot SDK's
   * high-level obstacle/health/localization/person events are captured by the
   * native Android bridge and forwarded over the chassis WebSocket; that bridge
   * is documented (Kotlin + Dart) in robot_app/docs/SENSOR_BRIDGE.md. When the
   * bridge lands, parse those messages in handleRobotMessage() and invoke these
   * handlers here.
   */
  onSensorEvent(_handler: (event: SensorEvent) => void): void {
    // intentionally empty — see robot_app/docs/SENSOR_BRIDGE.md
  }
}
