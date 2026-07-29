# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> Smart reception app for the **Mikee robot** (Alpha Robotics / CSJBot platform), built for **xboom Utilities Pvt. Ltd.** — greet visitors, recognize staff, answer questions by voice, navigate/escort, and be driven/monitored remotely.

> **⚡ Read [`HANDOFF.md`](./HANDOFF.md) FIRST.** It is the live session state — what shipped last, what's pending hardware verification, what's blocking. This file is the durable architectural reference; do not trust status claims here over HANDOFF.md.

## Architecture

Three layers with a single safety broker in the middle. **Clients never talk to the robot SDK directly** — every command flows through the spine so safety interlocks live in one place.

| Layer | What | Where |
|---|---|---|
| **Edge** | Flutter + CSJBot SDK (Java plugins) on the robot's Android 7.1.2 chest screen | `robot_app/` |
| **Broker** | Node.js + TypeScript spine (:4000) + Supabase (Postgres · RLS · pgvector) | `spine/` · `supabase/` |
| **Client** | Flutter admin app (web + mobile, adaptive phone remote) + camera viewers + MCP server | `app/` · `viewer_web/` · `viewer_mobile/` · `mcp_server/` |

```
robot_app/          Chest-screen Flutter app — ambient personality face, dashboard, nav points,
                    voice (ElevenLabs Conversational AI), staff enrollment. Java plugins serve
                    MJPEG camera (:8080), battery (:8090), and motor-control WS receivers
                    (:8081 head / :8082 chassis / :8083 arm). Also dials OUT to the spine
                    (SpineClient WS, kiosk-token auth) for events + intents.
spine/              ★ TypeScript broker (:4000) — safety interlocks (global STOP wins), intent
                    routing, RealRobotSDK (WS client to :8081-3 + HTTP snapshot/battery),
                    face recognition (@vladmandic/face-api), navigation/patrol/escort state
                    machines, voice brain (Voyage embeddings + Claude RAG + ElevenLabs webhook),
                    KB platform (ingest/crawl/providers), MCP plugin registry, notifications
                    (Slack/WhatsApp/email/FCM), JWKS auth.
supabase/           Migrations · RLS on every table · pgvector (face 128-d, KB 1024-d) ·
                    DPDP-compliant nightly purge.
app/                ★ Flutter admin — auth, dashboard, live feed, control, navigation + escort,
                    gallery, events, staff, KB, MCP plugins, settings. Phones get a remote layout.
mcp_server/         mikee-mcp-server (stdio) — exposes robot + KB tools to any MCP client.
                    It is a CLIENT of the spine (WS intents + HTTP), so interlocks apply to AI agents.
signaling_server/   WebRTC signaling (:3000) + serves viewer_web.
viewer_web/         Single-file browser camera viewer.  viewer_mobile/  Flutter camera viewer.
scripts/            find_robot.sh (auto-find robot IP + repoint spine/app after DHCP churn),
                    robot_bringup.sh (post-reboot order that keeps mic + chassis both working).
```

### Key decisions

1. **Spine is the single broker.** All intents flow through :4000; STOP/RESUME interlocks are checked first in `spine/src/commands/interlocks.ts` and always win.
2. **Real robot only.** No mock SDK. `RealRobotSDK` connects to `ROBOT_IP` on boot. New hardware paths stay behind the spine intent layer so they fail safe.
3. **Stateless clients.** Apps send intents and render broadcast state; spine + Supabase own state.
4. **DPDP compliance.** Only staff faces stored, opt-in with consent timestamp; the `visitor` table has zero biometric fields; escort person-checks are detection-only (no identity, nothing stored).
5. **MCP two ways.** `mcp_server/` exposes Mikee *to* AI agents; the spine's plugin registry (`/mcp/plugins`, file-backed, tokens never returned over HTTP) lets the voice brain consume *external* MCP servers — only when `MCP_TOOLS_ENABLED=true` (default off).

## Intent format (client → spine WS)

Movement: `drive` (dir), `stop_drive`, `head` (lr/ud 0-100), `arm` (left/right 0-100), `wave`, `reset_body`.
Navigation: `get_position`, `navi` (point), `cancel_navi`, `dock`, `patrol_start`/`patrol_stop`, `escort_start`/`escort_stop`.
Safety/state: `stop`, `resume`, `get_status`, `snapshot`, `voice_state`.
See `spine/src/commands/handlers.ts` and `spine/src/server.ts` for the authoritative list.

## Build / run / test

| Task | Command |
|---|---|
| Spine dev | `cd spine && npm run dev` (needs `.env` — see `.env.example`; `ROBOT_IP` required) |
| Spine tests | `cd spine && npm test` · single file: `npx vitest run tests/escort.test.ts` |
| Spine typecheck | `cd spine && npx tsc --noEmit` |
| Secrets | `cd spine && npm run secrets:pull` / `secrets:push` (sops, `.env` ↔ committed `.env.enc`) |
| Admin app (web) | `cd app && flutter run -d chrome` · ship: `flutter build web` |
| Robot APK | `cd robot_app && flutter build apk --debug --flavor robot` → `adb install build/app/outputs/flutter-apk/app-robot-debug.apk` |
| Robot APK (emulator/dev) | `--flavor remote` (points the CSJBot SDK at a remote address instead of on-robot 127.0.0.1) |
| ElevenLabs key in APK | `--dart-define=ELEVENLABS_API_KEY=sk_...` (otherwise must be saved in the app's Settings) |
| MCP server | `cd mcp_server && npm run build` · tests: `npm test` · env: `SPINE_URL`, `SPINE_TOKEN`, `SUPABASE_URL`, `SUPABASE_ANON_KEY` |
| Supabase migrations | via Supabase CLI from `~/.local/share/supabase`, **Session pooler** (Direct conn is IPv6-only and won't route from this Mac) |

### Machine/hardware gotchas (this Mac + this robot)

- **`flutter analyze` wrapper crashes on this Mac** (analysis server exit 64). Use `~/development/downloads/flutter/bin/dart analyze` instead.
- Robot connection: classic `adb connect <ip>:5555` persists across reboots; wireless-debug port does not.
- DHCP churn breaks robot↔spine↔app wiring (IPs are configured in `spine/.env`, admin settings, robot's `spine_base_url` pref) — run `scripts/find_robot.sh`.
- After any robot reboot follow `scripts/robot_bringup.sh` — start order determines whether mic AND chassis both work; restarting `com.csjbot.robotsdk.ten` while the Mikee app runs kills the app's SDK binder → bounce the app.
- The spine host must be on the robot's LAN (spine dials the robot). Public exposure is via tunnel (ngrok today; see HANDOFF).

## Conventions

**TypeScript (spine, mcp_server):** strict mode; Vitest test for every new behavior (happy path + one failure mode minimum); keep `tsc --noEmit` clean.

**Flutter (app, robot_app):** Riverpod with `keepAlive` singleton providers; `go_router`; dark theme (background `#0F0F0F`, accent orange `#FF6B35`); components under ~300 lines; all robot commands as spine intents — never direct SDK calls from a client.

**Supabase:** RLS on every table — non-negotiable. Note both the robot app (anon key) and the dev admin (`devSkipAuth`) hit Postgres as `anon`: tables they write need public RLS policies, not `TO authenticated`, or you get 42501.

**Engineering style:** honest reporting — say explicitly what is unverified on hardware (HANDOFF marks these ⬜/⚠️); read-before-write; minimal new dependencies; features verified against the physical robot before being called done.

## Auth model

Three credentials, all verified by the spine: Supabase user JWTs (ES256 via project JWKS) for admin clients; `KIOSK_TOKEN` static secret for the chest-screen app (works in production); `DEV_AUTH_BYPASS=1` for local dev only (forced off when `NODE_ENV=production`). `ELEVENLABS_TOOL_SECRET` gates the `/elevenlabs/ask` webhook (fail-closed when unset).

## Team

**Nishant** — solo engineer, Flutter-strong, newer to backend/robotics. This repo is his.
**Vishal** — founder, owns hardware relationship + DPDP/legal + KB content.
