# Mikee — Project Context for Claude Code

> Smart reception app for the **Mikee robot platform** (Alpha Robotics / CSJBot). Built for **xboom Utilities Pvt. Ltd.** to staff their office reception autonomously.

> **⚡ Read [`HANDOFF.md`](./HANDOFF.md) FIRST.** It's the live session state — what shipped last, what's pending, what's blocking, what to start with on this machine. This `CLAUDE.md` is the durable architectural reference; `HANDOFF.md` is the per-session pulse.

---

## Architecture

**Three layers:**

| Layer | What | Where |
|---|---|---|
| **Edge** | Alpha Robotics Mikee SDK (Java/Kotlin) on the robot's Android 7.1.2 chest screen | `robot_app/` |
| **Cloud** | Node.js TypeScript broker (port 4000) + Supabase (Postgres + RLS + pgvector) | `spine/` · `supabase/` |
| **Client** | Flutter admin app (web + iOS + Android) + browser viewer + mobile viewer | `app/` · `viewer_web/` · `viewer_mobile/` |

**Other components:** `signaling_server/` (WebRTC signaling, port 3000) · `robot_app/` doubles as MJPEG camera streamer on port 8080.

## Component map

```
robot_app/          Flutter on Mikee chest screen — MJPEG server + (future) native SDK bridge for sensors
viewer_web/         Single-file HTML control UI — WebSocket to spine
viewer_mobile/      Flutter mobile camera viewer
signaling_server/   Node.js WebRTC signaling + serves viewer_web
spine/              ★ TypeScript broker — central safety layer. RealRobotSDK only. Tests: 46 passing.
supabase/           5 migrations · 8 tables · RLS everywhere · pgvector for face/KB embeddings · DPDP-compliant purge
app/                ★ Flutter admin — 7 features (auth, dashboard, control, live_feed, gallery, events, settings)
```

## Key architectural decisions

1. **Spine as the single broker.** Clients never talk to the robot SDK directly. All commands flow through `spine` on port 4000 so safety interlocks live in ONE place.
2. **Real robot only.** The spine talks exclusively to the physical Mikee via `RealRobotSDK` (WS ports 8081/8082/8083 + HTTP snapshot/battery). The old MockRobotSDK and `ROBOT_MODE` swap were removed (June 2026) — set `ROBOT_IP` and the spine connects on boot.
3. **Stateless Flutter client.** App sends intents, receives status. Spine + Supabase own state. Closing the app mid-session is safe.
4. **DPDP compliance baked in.** Staff face data isolated, opt-in only. Visitor table has zero biometric fields. Nightly auto-purge.

## Conventions to follow

**TypeScript (spine):**
- Strict mode. No `any` without justification.
- All async via promises (no callbacks).
- Errors logged via `Csjlogger`; events via `events.ts` helper to Supabase.
- Vitest for tests. New tests for every new behavior.

**Flutter (app, robot_app, viewer_mobile):**
- Riverpod for state — singleton providers via `keepAlive()`.
- Freezed for immutable state models. Run `build_runner` after changes.
- `go_router` for navigation, with `GoRouterRefreshStream` for auth redirects.
- Dark theme — background `#0F0F0F`, accent orange `#FF6B35`.
- Components under 300 lines; split larger.
- All commands as intents to spine. Never direct SDK calls from client.

**Supabase:**
- RLS on every table — non-negotiable.
- pgvector for ML embeddings (face, KB).
- DPDP retention via nightly purge function.

## Intent format (client → spine WebSocket)

```js
{ intent: 'drive', dir: 'forward'|'back'|'left'|'right' }
{ intent: 'head', lr: 0-100, ud: 0-100 }
{ intent: 'arm', left: 0-100, right: 0-100 }
{ intent: 'wave' }
{ intent: 'reset_body' }
{ intent: 'stop' }
{ intent: 'resume' }
{ intent: 'get_status' }
```

## Build / run commands

| Component | Command |
|---|---|
| Spine | `cd spine && npm install && npm run dev` (connects to `ROBOT_IP`) |
| Spine tests | `cd spine && npm test` |
| Flutter admin (web) | `cd app && flutter pub get && flutter run -d chrome` |
| Flutter admin (iOS) | `cd app && flutter run -d ios` |
| Flutter admin (Android) | `cd app && flutter run -d android` |
| Robot app (real hardware) | `cd robot_app && flutter build apk --debug && adb install build/app/outputs/flutter-apk/app-debug.apk` |
| Viewer web | open `viewer_web/index.html` in any browser |

## Current status (snapshot)

✅ **Working end-to-end (against the real robot):** Login → Dashboard → Control → joystick drag → spine routes through safety interlock → `RealRobotSDK` forwards to the robot WS ports → event logged to Supabase → realtime status update → STOP greys controls → RESUME re-enables. Drive, head, arm, wave, live MJPEG camera, and battery all run on hardware.

🔴 **Known blocker:** Supabase email rate limit on `@xboom.in` domain. Workaround: use Gmail / disable email confirmation in Supabase Auth settings for dev. Documented in `ISSUE_EMAIL_RATE_LIMIT.md`.

🟡 **Hardware gaps in `RealRobotSDK`:** `onSensorEvent` is still a no-op (the native sensor bridge in `robot_app/docs/SENSOR_BRIDGE.md` isn't wired yet, so obstacle/health/localization/person fields sit at their `unknown`/`null` defaults), and `getStatus` is static.

⬜ **Not yet built (Phase 2):** Face recognition, voice Q&A (STT + KB search + Claude RAG + TTS), autonomous patrol, Mission Control dashboard (in-progress per `MISSION_CONTROL_BUILD.md`).

## Status & background docs (read for deeper context)

- `PROJECT_STATUS.md` — definitive 400-line status snapshot.
- `FLUTTER_APP_SUMMARY.md` — Flutter admin app build details.
- `MISSION_CONTROL_BUILD.md` — Mission Control dashboard widget build.
- `ISSUE_EMAIL_RATE_LIMIT.md` — current blocker.
- `README.md` — quick-start for camera streaming.

## External memory files (extended project context, on this machine)

These persist across Claude sessions on this machine. Read for deeper architectural reasoning, decision history, and LIDAR research:

- `C:\Users\Nishant\.claude\projects\C--Program-Files-Git\memory\mikee-overview.md` — full architectural snapshot, component status, conventions
- `C:\Users\Nishant\.claude\projects\C--Program-Files-Git\memory\mikee-lidar-integration.md` — CSJBot SDK LIDAR research, exposed events, implementation plan
- `C:\Users\Nishant\.claude\projects\C--Program-Files-Git\memory\MEMORY.md` — index of all memory files

## Active work (June 2026)

**Current focus:** Wire CSJBot SDK obstacle / sensor / localization events through the native bridge into `RealRobotSDK.onSensorEvent` (currently a no-op) so the existing spine pipeline + Flutter admin UI light up on real hardware.

**Key finding from SDK research:** CSJBot does NOT expose raw LIDAR point cloud. It surfaces high-level obstacle events (`NAVI_ROBOT_BLOCKED_NTF`, `NAVI_ROBOT_WAITSHORT_NTF`, `LQ_LOW_NTF`, etc.) which are sufficient for reception robot use case. Full research in `mikee-lidar-integration.md`.

**Native bridge code:** documented in `robot_app/docs/SENSOR_BRIDGE.md`. The spine-side sensor pipeline (`sensors.ts`, types, Flutter `SensorStatusCard`) is fully built; it's just fed by nothing until the bridge forwards events over the chassis WebSocket and `RealRobotSDK` parses them.

## Engineering style

- **Honest reporting:** When something can't be done or is partially done, say so explicitly. Don't paper over gaps.
- **Real-robot only:** There is no mock SDK. New features are built and verified against the physical Mikee (`RealRobotSDK`); keep handlers behind the spine intent layer so untested hardware paths fail safe.
- **Minimal surface area:** Don't add new dependencies unless you make the case. Don't add Phase 2 features (face, voice, patrol) into Phase 1 work.
- **Test what's new:** Vitest for spine, Flutter test for app. Cover happy path + one failure mode minimum.
- **Read-before-write:** When in doubt about a file's existing shape, read it first. Don't pattern-match from memory.

## Team

**Nishant** — solo engineer, Flutter-strong, newer to backend/robotics. This repo is his.
**Vishal** — founder, owns hardware relationship + DPDP/legal + KB content.

xboom is building land + air + water robots for enterprise (JSW, Tata, Reliance, Indian Army). Mikee is the first product — reception robot MVP.
