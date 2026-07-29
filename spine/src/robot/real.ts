/**
 * robot/real.ts — RealRobotSDK
 * Forwards spine intents to actual robot WebSocket ports (8081/8082/8083).
 * Explicitly translates from spine intent format to robot command format.
 */

import { WebSocket } from 'ws';
import { RobotSDK } from './interface';
import { RobotStatus, RobotEvent, SensorEvent, RobotPosition } from '../types';

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

  // Resolver for an in-flight getPosition() — the chassis WS replies async with
  // {type:'position', x,y,z,rotation}.
  private pendingPosition: ((pos: RobotPosition) => void) | null = null;

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
    // Keep the chassis dead-man fed while a connection exists (see below).
    this.startChassisPing();
  }

  /**
   * Dead-man heartbeat: ChassisControlPlugin halts WS-commanded motion when no
   * client traffic arrives for ~8s (spine host died, Wi-Fi dropped). Commands
   * alone don't prove liveness during a held joystick or a long navi leg, so
   * ping every 2s whenever the chassis socket is open. The plugin answers with
   * a pong, which handleRobotMessage drops silently.
   */
  private startChassisPing() {
    setInterval(() => {
      const ws = this.ws_chassis;
      if (ws && ws.readyState === WebSocket.OPEN) {
        try {
          ws.send(JSON.stringify({ cmd: 'ping' }));
        } catch {
          /* socket died mid-send — ensureConnected will rebuild it */
        }
      }
    }, 2000);
  }

  private async fetchBatteryOnce() {
    try {
      const response = await fetch(`http://${this.robotIP}:8090/battery`);
      if (response.ok) {
        // A successful HTTP response means the robot is reachable. This probe
        // runs on boot + every 30s and is the canonical liveness signal that
        // drives `online` (the flag the admin Control screen gates commands on).
        this.setOnline(true);
        const data = (await response.json()) as { battery?: number; charging?: boolean };
        const battery = data.battery as number;
        // The 8090 endpoint is the head/tablet battery. Only use it when the
        // bridge hasn't supplied the real chassis charge (realBattery < 0).
        if (this.realBattery < 0 && battery >= 0 && battery <= 100) {
          this.status.battery = battery;
          console.log(`[Real SDK] Battery (head/tablet) updated: ${battery}%`);
        }
        // Charging state from the robot's SDK charge_status — drives the admin's
        // ⚡ indicator. Report a transition so it's visible in the logs.
        if (typeof data.charging === 'boolean' && data.charging !== this.status.isCharging) {
          this.status.isCharging = data.charging;
          console.log(`[Real SDK] Charging state: ${data.charging}`);
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
      if (msg.type === 'pong') return; // dead-man ping reply — every 2s, don't log
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
      } else if (msg.type === 'position') {
        // Response to get_position — resolve the pending request.
        if (this.pendingPosition) {
          this.pendingPosition({
            x: msg.x ?? 0,
            y: msg.y ?? 0,
            z: msg.z ?? 0,
            rotation: msg.rotation ?? 0,
          });
          this.pendingPosition = null;
        }
      } else if (msg.type === 'navi') {
        // Navigation lifecycle event (move_result / arrived / cancel) → admin.
        const event: RobotEvent = {
          type: 'navi_event',
          payload: { event: msg.event, data: msg.data },
          timestamp: Date.now(),
        };
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
   * Capture the robot's current SLAM pose (for saving a navigation point).
   * Sends {cmd:get_position}; the chassis WS replies async with {type:position}.
   */
  async getPosition(): Promise<RobotPosition> {
    const ws = await this.ensureConnected('chassis');
    return new Promise<RobotPosition>((resolve, reject) => {
      this.pendingPosition = resolve;
      ws.send(JSON.stringify({ cmd: 'get_position' }));
      setTimeout(() => {
        if (this.pendingPosition === resolve) {
          this.pendingPosition = null;
          reject(new Error('get_position timed out'));
        }
      }, 6000);
    });
  }

  /**
   * Navigate to a saved point. Needs a loaded+localized SLAM map and the robot
   * off the dock. navi lifecycle events come back as 'navi_event' robot events.
   */
  async navi(point: RobotPosition): Promise<void> {
    const ws = await this.ensureConnected('chassis');
    const command = { cmd: 'navi', x: point.x, y: point.y, z: point.z, rotation: point.rotation };
    console.log('[Real SDK] navi →', command);
    ws.send(JSON.stringify(command));
    this.status.isMoving = true;
  }

  /** Drive to the charging dock (vendor goHome; the dock self-aligns via IR). */
  async goDock(): Promise<void> {
    const ws = await this.ensureConnected('chassis');
    console.log('[Real SDK] goDock → {cmd: go_home}');
    ws.send(JSON.stringify({ cmd: 'go_home' }));
    this.status.isMoving = true;
  }

  /** Cancel an in-progress navigation. */
  async cancelNavi(): Promise<void> {
    const ws = await this.ensureConnected('chassis');
    ws.send(JSON.stringify({ cmd: 'cancel_navi' }));
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
   * Camera MJPEG stream URL (robot_app CameraStreamPlugin, port 8080). The only
   * place outside this class that used to build robot URLs was the recorder —
   * it now asks the SDK instead.
   */
  getCameraStreamUrl(): string {
    return `http://${this.robotIP}:8080/stream`;
  }

  /**
   * One validated JPEG from /snapshot, or null on any failure (unreachable,
   * timeout, non-200, not a JPEG). Never throws — safe for tight poll loops.
   */
  async captureFrame(timeoutMs = 5000): Promise<Buffer | null> {
    try {
      const response = await fetch(`http://${this.robotIP}:8080/snapshot`, {
        signal: AbortSignal.timeout(timeoutMs),
      });
      if (!response.ok) return null;
      const buffer = Buffer.from(await response.arrayBuffer());
      // Validate JPEG SOI marker before handing to consumers (face-api chokes
      // on truncated frames).
      if (buffer.length < 4 || buffer[0] !== 0xff || buffer[1] !== 0xd8) return null;
      return buffer;
    } catch {
      return null;
    }
  }

  /**
   * Take snapshot from HTTP endpoint (throwing variant — snapshot intent,
   * person-check). Same fetch path as captureFrame.
   */
  async takeSnapshot(): Promise<Buffer> {
    const buffer = await this.captureFrame();
    if (!buffer) {
      console.error('[Real SDK] takeSnapshot failed: camera unreachable or bad frame');
      throw new Error('Snapshot failed: camera unreachable or bad frame');
    }
    console.log(`[Real SDK] Snapshot taken (${buffer.length} bytes)`);
    return buffer;
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
