/**
 * spine-client.ts — talks to the spine (port 4000) the way every other client does:
 * intents over WebSocket (behind the safety interlocks) + a few HTTP endpoints
 * (/ask, /kb/status, /staff).
 *
 * The spine's WS protocol has no request IDs, so this client serializes: one
 * intent in flight at a time, matched against the response types that intent
 * can produce. Unsolicited broadcasts (navi_state, robot_status pushes,
 * voice_* events) that don't match the expected set are ignored.
 */

import WebSocket from 'ws';

export interface SpineMessage {
  type: string;
  [key: string]: unknown;
}

export interface Intent {
  intent: string;
  [key: string]: unknown;
}

/** Direct-response types each intent can produce (plus 'error', always accepted). */
const EXPECTED_RESPONSES: Record<string, string[]> = {
  drive: ['ack'],
  stop_drive: ['ack'],
  head: ['ack'],
  arm: ['ack'],
  wave: ['ack'],
  navi: ['ack'],
  dock: ['ack'],
  cancel_navi: ['ack'],
  snapshot: ['ack'],
  patrol_start: ['ack'],
  patrol_stop: ['ack'],
  stop: ['stopped'],
  resume: ['resumed'],
  get_status: ['robot_status'],
  get_position: ['position'],
};

const INTENT_TIMEOUT_MS = 20_000;
const CONNECT_TIMEOUT_MS = 8_000;

export class SpineClient {
  private ws: WebSocket | null = null;
  private connecting: Promise<WebSocket> | null = null;
  private queue: Promise<unknown> = Promise.resolve();

  constructor(
    private readonly wsUrl: string,
    private readonly httpUrl: string,
    private readonly token: string,
    private readonly fetchFn: typeof fetch = fetch
  ) {}

  /** Connect + authenticate, reusing an open socket. */
  private async connect(): Promise<WebSocket> {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) return this.ws;
    if (this.connecting) return this.connecting;

    this.connecting = new Promise<WebSocket>((resolve, reject) => {
      const ws = new WebSocket(this.wsUrl);
      const timer = setTimeout(() => {
        ws.terminate();
        reject(new Error(`Timed out connecting to spine at ${this.wsUrl}`));
      }, CONNECT_TIMEOUT_MS);

      ws.on('open', () => {
        ws.send(JSON.stringify({ type: 'auth', token: this.token }));
      });
      ws.on('message', (raw: WebSocket.RawData) => {
        let msg: SpineMessage;
        try {
          msg = JSON.parse(raw.toString()) as SpineMessage;
        } catch {
          return;
        }
        if (msg.type === 'authenticated') {
          clearTimeout(timer);
          this.ws = ws;
          resolve(ws);
        } else if (msg.type === 'error' && !this.ws) {
          clearTimeout(timer);
          reject(new Error(`Spine auth failed: ${String(msg.message ?? 'unknown')}`));
        }
      });
      ws.on('error', err => {
        clearTimeout(timer);
        reject(new Error(`Spine connection error: ${err.message}`));
      });
      ws.on('close', () => {
        if (this.ws === ws) this.ws = null;
      });
    }).finally(() => {
      this.connecting = null;
    });

    return this.connecting;
  }

  /** Send one intent and await its direct response (serialized). */
  sendIntent(intent: Intent): Promise<SpineMessage> {
    const run = this.queue.then(() => this.sendIntentNow(intent), () => this.sendIntentNow(intent));
    this.queue = run.catch(() => undefined);
    return run;
  }

  private async sendIntentNow(intent: Intent): Promise<SpineMessage> {
    const ws = await this.connect();
    const expected = EXPECTED_RESPONSES[intent.intent] ?? ['ack'];

    return new Promise<SpineMessage>((resolve, reject) => {
      const timer = setTimeout(() => {
        cleanup();
        reject(new Error(`Spine did not respond to '${intent.intent}' within ${INTENT_TIMEOUT_MS / 1000}s`));
      }, INTENT_TIMEOUT_MS);

      const onMessage = (raw: WebSocket.RawData) => {
        let msg: SpineMessage;
        try {
          msg = JSON.parse(raw.toString()) as SpineMessage;
        } catch {
          return;
        }
        if (expected.includes(msg.type) || msg.type === 'error') {
          cleanup();
          resolve(msg);
        }
        // anything else is a broadcast — keep waiting
      };
      const onClose = () => {
        cleanup();
        reject(new Error('Spine connection closed mid-request'));
      };
      const cleanup = () => {
        clearTimeout(timer);
        ws.off('message', onMessage);
        ws.off('close', onClose);
      };

      ws.on('message', onMessage);
      ws.on('close', onClose);
      ws.send(JSON.stringify({ type: 'intent', intent }));
    });
  }

  /** Authenticated HTTP call to a spine endpoint. */
  async http<T>(path: string, init?: { method?: string; body?: unknown }): Promise<T> {
    const resp = await this.fetchFn(`${this.httpUrl}${path}`, {
      method: init?.method ?? 'GET',
      headers: {
        Authorization: `Bearer ${this.token}`,
        ...(init?.body !== undefined ? { 'Content-Type': 'application/json' } : {}),
      },
      body: init?.body !== undefined ? JSON.stringify(init.body) : undefined,
    });
    const text = await resp.text();
    let json: unknown;
    try {
      json = JSON.parse(text);
    } catch {
      throw new Error(`Spine ${path} returned non-JSON (HTTP ${resp.status}): ${text.slice(0, 200)}`);
    }
    if (!resp.ok) {
      const reason = (json as { reason?: string }).reason ?? `HTTP ${resp.status}`;
      throw new Error(`Spine ${path} failed: ${reason}`);
    }
    return json as T;
  }

  close(): void {
    this.ws?.close();
    this.ws = null;
  }
}
