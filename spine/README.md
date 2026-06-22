# Mikee Spine — Integration Gateway

**The central broker between admin clients and the Mikee reception robot.**

## What it does

- **WebSocket server** (port 4000) for admin clients (web/mobile)
- **Command routing** with safety interlocks (global STOP always wins)
- **SDK interface** — swap between mock (dev) and real (production) implementations
- **Event normalization** — broadcasts robot events to all connected clients
- **Supabase logging** — logs all commands, events, and sessions (optional)
- **JWT authentication** — verifies admin tokens (optional for dev)

## Quick Start

### 1. Install dependencies

```bash
cd spine
npm install
```

### 2. Create `.env` from `.env.example`

```bash
cp .env.example .env
```

### 3. Run in mock mode (no robot required)

```bash
npm run dev
```

Output:
```
═══════════════════════════════════════════════════════════════
    TIMO RECEPTION ROBOT — SPINE (Integration Gateway)
═══════════════════════════════════════════════════════════════

🤖 ROBOT_MODE=mock — Using MockRobotSDK (no hardware required)
⚠️  Supabase not configured — events will be logged to console only
⚠️  JWT auth disabled — DEV MODE ONLY

✓ Spine is running and ready for admin clients
```

Then in another terminal, test with:

```bash
# Connect and authenticate (dev mode accepts any token)
# Send: {"type":"auth","token":"dev-token"}

# Send a drive command
# Send: {"type":"intent","intent":{"intent":"drive","dir":"forward"}}

# Trigger STOP
# Send: {"type":"intent","intent":{"intent":"stop"}}

# Resume
# Send: {"type":"intent","intent":{"intent":"resume"}}
```

### 4. Run against real robot

Set `ROBOT_MODE=real` and `ROBOT_IP=192.168.99.101` in `.env`, then:

```bash
ROBOT_MODE=real npm start
```

The spine will connect to the robot's WebSocket servers:
- Port 8081 (head control)
- Port 8082 (chassis control)
- Port 8083 (arm control)

**Note:** Cloud deployments can't reach 192.168.99.101 directly — Phase 2 work will add a tunnel.

## Architecture

```
Admin App (web/mobile)
    ↓ WebSocket
    ├─ intents: {"intent":"drive","dir":"forward"}
    └─ auth: {"type":"auth","token":"..."}
            ↓
        SPINE (port 4000)
        ├─ checkInterlocks() [STOP, rate-limit, office hours]
        ├─ routeMessage() [parse → handler]
        └─ handleIntent() [call SDK]
            ↓
        RobotSDK (interface)
        ├─ MockRobotSDK [fake, emits events]
        └─ RealRobotSDK [forwards to robot ports]
            ↓
        Mikee Robot (192.168.99.101)
        ├─ port 8081 (head)
        ├─ port 8082 (chassis)
        └─ port 8083 (arm)
```

## File Structure

```
spine/
├── src/
│   ├── index.ts                 # Entry point
│   ├── server.ts                # WebSocket server
│   ├── types.ts                 # TypeScript definitions
│   ├── robot/
│   │   ├── interface.ts         # RobotSDK contract
│   │   ├── mock.ts              # MockRobotSDK (dev)
│   │   └── real.ts              # RealRobotSDK (prod)
│   ├── commands/
│   │   ├── router.ts            # Intent → handler
│   │   ├── interlocks.ts        # Safety: STOP, rate-limit
│   │   └── handlers.ts          # Intent handlers
│   ├── supabase/
│   │   ├── client.ts            # Supabase init
│   │   └── events.ts            # Event logging
│   └── auth/
│       └── middleware.ts        # JWT verification
├── tests/
│   ├── interlocks.test.ts       # STOP always wins
│   ├── router.test.ts           # Intent routing
│   └── mock-sdk.test.ts         # Mock behavior
├── package.json
├── tsconfig.json
├── vitest.config.ts
└── .env.example
```

## Safety Interlocks

### GLOBAL STOP

```javascript
// Trigger STOP from any admin
{"type":"intent","intent":{"intent":"stop"}}

// ALL movement intents (drive, head, arm, wave) are rejected
// Non-movement intents (snapshot, status, resume) are allowed

// Resume (requires auth)
{"type":"intent","intent":{"intent":"resume"}}
```

**Critical:** STOP wins even in a race with resume. Test: `tests/interlocks.test.ts`.

### Rate Limiting (per session, per intent type)

- `drive`: max 1 per 100ms
- `head`: max 1 per 50ms
- `arm`: max 1 per 50ms
- `snapshot`: max 1 per 2s (global)

Excess commands are silently dropped (not errors).

### Office Hours Mode

Set `OFFICE_HOURS_MODE=true` in `.env` to disable chassis movement while allowing head + arm. For future scheduling UI.

## Testing

```bash
# Run all tests
npm test

# Watch mode
npm run test:watch
```

Key tests:
- **interlocks.test.ts** — STOP always wins, even in race conditions
- **router.test.ts** — Intent → handler mapping, malformed input safety
- **mock-sdk.test.ts** — Mock emits events correctly

## WebSocket Protocol

### Client → Spine

**Auth (must be first message):**
```json
{
  "type": "auth",
  "token": "<jwt-token>"
}
```

**Intent:**
```json
{
  "type": "intent",
  "intent": {
    "intent": "drive|head|arm|wave|stop|resume|snapshot|get_status",
    "dir": "forward|back|left|right",  // for drive
    "lr": 0-100,                        // for head
    "ud": 0-100,                        // for head
    "left": 0-100,                      // for arm
    "right": 0-100                      // for arm
  }
}
```

**Ping:**
```json
{
  "type": "ping"
}
```

### Spine → Client

**Authenticated:**
```json
{
  "type": "authenticated",
  "message": "Welcome user-123"
}
```

**Ack:**
```json
{
  "type": "ack",
  "intent": "drive",
  "ok": true
}
```

**Robot Status:**
```json
{
  "type": "robot_status",
  "status": {
    "online": true,
    "battery": 85,
    "isMoving": false,
    "headLR": 50,
    "headUD": 50,
    "leftArm": 50,
    "rightArm": 50,
    "isWaving": false
  }
}
```

**Event:**
```json
{
  "type": "event",
  "event": "face_detected|battery_update|robot_online|robot_offline",
  "payload": {...}
}
```

**Stopped (broadcast to all clients):**
```json
{
  "type": "stopped"
}
```

**Error:**
```json
{
  "type": "error",
  "message": "..."
}
```

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `ROBOT_MODE` | `mock` | `mock` or `real` |
| `ROBOT_IP` | `192.168.99.101` | Robot IP (for real mode) |
| `SPINE_PORT` | `4000` | Server port |
| `SUPABASE_URL` | (unset) | Supabase project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | (unset) | Supabase service role |
| `JWT_SECRET` | (unset) | JWT signing key (dev mode if unset) |
| `OFFICE_HOURS_MODE` | `false` | Disable chassis movement |

## Development Notes

### MockRobotSDK emits events every 10 seconds

- `face_detected`: every 10s
- `battery_update`: every 30s

For tests, use `eventIntervalMs: 100` to speed up.

### RealRobotSDK translates spine intents to robot commands

Example: `{"intent":"drive","dir":"forward"}` → `{"cmd":"move","dir":"forward"}`

See `src/robot/real.ts` for the full translation layer.

### Supabase is optional

Leave `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` empty in dev. The spine logs to console instead.

At production, fill in both and the spine persists all events to the `robot_event` table.

## Next Steps

1. **Phase 1 (current):** Spine + mock SDK ✓
2. **Phase 2:** Add WebRTC for real-time video
3. **Phase 3:** Add voice pipeline (STT + LLM + TTS)
4. **Phase 4:** Add face recognition + visitor greeting
5. **Cloud deployment:** Add tunnel for remote robot access

---

**xboom · Mikee · Land + Air + Water · Keep the spine small**
