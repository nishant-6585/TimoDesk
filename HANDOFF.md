# Session Handoff

> **Last updated:** 2026-06-19 (**auth go-live: JWKS/ES256 verification + real login gate**; #70 host notification, #87 battery, enrollment UX done; #83 mapping note; **#89 chest-screen redesign** — design doc + decisions locked, P1 next; **#90 mobile admin / remote-control app added to pipeline** — arch decision open: adaptive-single-app (recommended) vs separate app) · **For:** Claude Code on any future session picking up TimoDesk work
>
> **Read this BEFORE `PROJECT_STATUS.md` / `FLUTTER_APP_SUMMARY.md`** — those are older. This file is the live state.

---

## TL;DR — Where things stand right now

- **Phase 1A** (spine-side LIDAR/obstacle awareness against `MockRobotSDK`) — **SHIPPED.** 49/49 vitest passing, `tsc --noEmit` clean of wire-format errors (only an unrelated `moduleResolution=node10` deprecation warning remains).
- **#53** (spine wire-format spread bug at `server.ts:145-146`) — **FIXED & VERIFIED** in commit `7a19c83`. The 3 `tsc` errors are gone; Flutter `spine_service.dart` + `viewer_web/index.html` consumers were updated to read `eventPayload`.
- **Phase 1B** (Flutter admin UI consuming the new sensor events, task #42 — `SensorStatusCard` + `BlockedOverlay`) — **NOT STARTED.** Gated on Flutter SDK install. Check `flutter --version`; if missing, install before tackling #42. Root gap: Flutter `RobotStatus.fromJson` still drops the 5 Phase 1A sensor fields.
- **Phase 1.5** (5 more SDK listener integrations — battery, errors, snapshot, head touch, expressions) — **NOT STARTED.** Blocked on resolving the Windows-only orphan-rewriter (task #54).
- **Phase 1.7, Phase 2, Phase 3** — queued.

> **⚠️ 2026-06 reality update (much of the detail below is stale).** The project has moved well past Phase 1B: it now runs against the **real Timo robot (192.168.10.18)** — joystick drive, head, live MJPEG camera, and battery all work on hardware. **Phase 2 face recognition is in progress:** staff enrollment works end-to-end (browser face-api live detection on the robot feed → `/enroll` → spine `@vladmandic/face-api` → 128-d vector in `staff_face_embedding`, migrations 006=vector(128) + 007=phone/person_type). Enrollment is **staff/employee only** (no customer biometrics — DPDP). **Milestone C DONE (2026-06-16):** L2 threshold calibrated on real faces via nearest-neighbor (leave-one-out) metric — `face-recognition.ts threshold = 0.53` (6 people/28 poses now OVERLAP slightly; 0.53 chosen for precision — reject the closest impostor, occasional "unknown" over a wrong name). Rank-1 100%, but the gap is **thin (~0.014)** — two enrolled people are embedding-close, so Milestone D uses a margin guard + temporal voting (see below), not a bare single-frame threshold. Re-run `calibrate.js` as more staff enroll to widen the gap. **Staff view/edit/delete (DPDP erasure) DONE** (`e16c985`). **Enrollment UX #88 DONE (both parts)** — Part 1: laptop-webcam source in the admin web app (getUserMedia `<video>` + camera-source toggle). Part 2 (`033526b`): **robot_app chest-screen enrollment** — `EnrollScreen` reachable from `StreamScreen`, form-first kiosk flow, REUSES the robot's `/snapshot` (no second camera consumer — CameraStreamPlugin owns camera2), ML Kit `google_mlkit_face_detection` on the frame bytes (head Euler angles for pose gates, never opens the camera), same 5-pose flow + `/check-face` duplicate guard, POSTs each pose to spine `/enroll`. Debug APK builds with ML Kit. Configurable `kCameraBaseUrl`/`kSpineBaseUrl`/`kAuthToken` at the top of `robot_app/lib/enroll_screen.dart`. **Duplicate-face detection DONE** — a `/check-face` endpoint reuses the shared `extractEmbedding` + nearest-neighbor matcher + calibrated threshold; it runs LIVE during enrollment (fired right after the first frontal pose, not after all 5) with a **Stop / Continue-anyway** override. Fails open on error/no-face. **Milestone D — autonomous spine recognizer DONE (2026-06-17):** recognizer wired into `server.ts` (started via the single `broadcastRobotEvent` path, after `sdk.onEvent`); the rot is gone (no more `axios`/`sharp`/dead `detectFacesInFrame`/mock generator); it reuses the SHARED `extractEmbedding` (one face-api pipeline, not a divergent path); grabs frames from the robot **`/snapshot`** endpoint (clean complete JPEG — proven 6/6, sidesteps the MJPEG corrupted-boundary risk entirely); matches by NEAREST enrolled embedding < threshold with a **margin guard + temporal voting** (config `match_margin` 0.06, `vote_window`/`vote_min` 5/3, cadence 1.0s). Emits real `face_detected{staff_id,name,distance}` → `broadcastRobotEvent` → `{type:'event',event:'face_detected',eventPayload}` → Flutter `spine_service.dart` parses `eventPayload.payload` → `faceDetectionProvider` → **live dashboard card** (green match w/ name+L2+time, amber unknown, auto-dismiss 6s) + activity feed; the hardcoded mock `face_detected` rows in `dashboard_screen.dart`/`event_log_screen.dart` were removed. **Proven in spine logs against the real robot** (enrolled→real name at L2 0.46–0.52, unknown→unknown). *Verify-on-origin checklist for the next session: recognizer started in `server.ts`; no `axios`/`sharp` imports; shared `extractEmbedding` (not a 2nd path); margin-guard + voting present in `face-recognition.ts`; real `face_detected` reaches the dashboard card.* **Auth GATED (2026-06-17, `aae75bf`):** the `test-token` + no-JWT-secret bypass that spanned `/enroll`, `/check-face`, `/staff` and the WebSocket is now **fail-CLOSED by default** — active ONLY when `DEV_AUTH_BYPASS=1` AND `NODE_ENV!=='production'` (production forces it off even if the flag is set). Centralized in `authorizeRequest()` (`auth/middleware.ts`); `verifyToken`'s no-secret path also fails closed now. Dev still works behind the flag (`.env` has `DEV_AUTH_BYPASS=1`). Verified by curl (401 everywhere by default; passes with flag; prod rejects). **BUT the app isn't actually production-ready yet — see the Production auth go-live checklist immediately below.** The numbered tasks (#42–#64) and "branch `claude/clever-brown-8kLaJ`" references below are historical — that branch was deleted; work now happens directly on `main`.

> **🔐 Production auth go-live checklist — auth is now JWKS/ES256 verified end-to-end (2026-06-18, `bf03009`+).** STEP 0 finding: the Supabase project signs user tokens with **ES256 (asymmetric)**, not legacy HS256 — so verification was switched to **JWKS via `jose`** (verify against `{SUPABASE_URL}/auth/v1/.well-known/jwks.json`, `aud:'authenticated'` + `iss:{SUPABASE_URL}/auth/v1`). Proven prod-mode (`NODE_ENV=production`): no-token → 401, `test-token` → 401, real ES256 token → 200; WS rejects `test-token`, accepts a real token.
> - ✅ **(1) Real login restored** — `router.dart` `_isLoggedIn()` now checks `currentSession` (no more `return true`). Login screen already does `signInWithPassword`.
> - ✅ **(2) Verification path** — spine verifies ES256 via JWKS; needs **`SUPABASE_URL`** set (it already is, for the supabase client). The legacy HS256 `JWT_SECRET` is gone. The app already sends `currentSession.accessToken` (a real ES256 JWT).
> - ✅ **(3) Bypass gating** — `DEV_AUTH_BYPASS` only works when `=1` AND `NODE_ENV!=='production'`; prod forces it off (verified). For prod deploy: leave `DEV_AUTH_BYPASS` unset + `NODE_ENV=production`.
> - ⬜ **(4) REMAINING: robot_app kiosk credential.** Chest-screen enrollment sends `kKioskDevToken='test-token'` (`robot_app/lib/enroll_screen.dart`), which dies once the bypass is off. Per decision, the kiosk needs a **real Supabase operator account** — sign in a dedicated kiosk user, send its ES256 `access_token` (same JWKS path), refresh it. Not built this pass; TODO is in the file.
>
> **Prod deploy checklist:** set `SUPABASE_URL`, `NODE_ENV=production`, leave `DEV_AUTH_BYPASS` unset → all biometric/PII endpoints + WS require a real Supabase JWT. Only the kiosk (4) still needs its operator credential.

---

## What just shipped

### Since last handoff (commits after `901f3bb`, mostly Flutter UI + the #53 fix)

| Commit | Message | Notes |
|---|---|---|
| `7a19c83` | `feat(spine): implement event handling and update message structure for robot events` | ✅ **The #53 fix.** Destructures `{ type, ...rest }` → `{ event, eventPayload }`; updates `SpineMessage` type; updates Flutter + viewer_web consumers; +2 vitest cases (47→49). |
| `6b5ff75` | `feat(events): rename events route to event-log and update event details` | Flutter |
| `4bc6e56` | `Add MapCanvas and PatrolPanels for route management and waypoint editing` | Flutter — new `patrol_routes` feature |
| `74d0271` | `feat(settings): add new bash commands for project file searching and reading` | tooling |
| `6fcad3d` | `Refactor Gallery and Settings Screens for Improved UI and Functionality` | Flutter |
| `536e375` | `feat: Refactor dashboard and live feed screens with navigation and layout improvements` | Flutter |
| `ec1157b` | `feat(dashboard): refactor header layout and enhance battery card animation` | Flutter |
| `eeff972` | `feat: Update settings and add design verification checklist` | + `DESIGN_VERIFICATION.md` |
| `76dc96a` | `chore: add HANDOFF.md for cross-machine session continuity` | this file |

> Note: the orphan-rewriter hazard (#54) was Windows-only. This session runs in a fresh Linux cloud container — no orphan, commit messages land verbatim.

### Earlier (Windows session, 2026-06-08) — Phase 1A foundation

| Commit | Intended message | Notes |
|---|---|---|
| `a227e91` | `docs: add CLAUDE.md project context for Claude Code` | ✅ Clean |
| `d604c8b` | (was `feat(spine): obstacle awareness + sensor events (Phase 1A)`) | ⚠️ Message auto-rewritten by orphan to `feat: Implement sensor event handling...`. Content intact. |
| `0a369b6` | `chore(spine): add missing @types devDeps to unblock tsc` | ✅ Clean |
| `901f3bb` | `chore(spine): fix unused imports + real.ts placeholder bugs` | ✅ Clean |

**Additional artifacts in the history from the orphan-rewriter:**
- `2c41506 feat: Add project context documentation...` — duplicate of `a227e91`, AI-generated by the orphan.
- `cc8d401 Merge branch 'main'...` — an unrequested merge the orphan injected.

These are noise but harmless — the code state is correct. Optionally clean up under task #54 once the orphan is dead. **Do not try to rewrite published history if these have been pushed to origin.**

### Phase 1A — what was actually built

**Files added:**
- `spine/src/sensors.ts` (~96 lines) — pure `applySensorEvent` + `createSensorPipeline` (broadcast + Supabase log wiring)
- `spine/tests/sensors.test.ts` (~211 lines, 12 tests)
- `robot_app/docs/SENSOR_BRIDGE.md` (~241 lines) — Kotlin `TimoSensorBridge` + Dart MethodChannel receiver + deploy checklist. **Reference code only, NOT deployed.** Verify against real CSJBot SDK when hardware arrives.

**Files modified:**
- `spine/src/types.ts` — 5 new `RobotStatus` fields: `obstacleState`, `localizationQuality`, `sensorHealth`, `personDetected`, `lastObstacleEventAt`; new `SensorEvent` discriminated union
- `spine/src/robot/interface.ts` — added `onSensorEvent(...)` to the SDK contract
- `spine/src/robot/mock.ts` — synthetic emitter (obstacle 8–15s weighted 60/20/12/8, health 30s, lq 45s, person 20s); STOP suppression; `start/stopSensorSim()`; auto-start
- `spine/src/robot/real.ts` — no-op `onSensorEvent` pointing at `SENSOR_BRIDGE.md`
- `spine/src/server.ts` — registers the pipeline: seed status → broadcast `robot_status` → `logEvent`

**Critical gotcha discovered:** STOP state is a module global in `spine/src/commands/interlocks.ts` via `getStoppedState()`, NOT in the SDK. The sensor pipeline accepts an injected `isStopped` predicate defaulting to `getStoppedState` — keeps safety state in one home, stays testable.

---

## Pipeline status

### ✅ Done (8 tracked tasks + Phase 1A code)

- All TimoDesk LIDAR research tasks (#35–#40)
- Add `@types/ws` + `@types/node` devDeps (#41)
- **#53 — spine wire-format spread bug — FIXED & VERIFIED (commit `7a19c83`).** Both consumers (Flutter `spine_service.dart`, `viewer_web/index.html`) updated to `eventPayload`. tsc clean of those 3 errors; 49/49 vitest.
- Plus the 4 Phase 1A commits above (delivered against #38–#40 in real time, not tracked as discrete tasks)

### ⏳ Remaining (16 tasks)

**🔴 Blocking — investigate first (Windows only):**

- **#54** — Orphan `claude.exe` processes on the Windows machine auto-rewriting commits + injecting pulls. 9 orphans from 2026-06-03 14:19. **Does NOT affect iMac.** Only relevant when working on Windows. Diagnostic command:
  ```powershell
  Get-CimInstance Win32_Process -Filter "Name='claude.exe'" | Select ProcessId, ParentProcessId, CreationDate, CommandLine | Format-List
  ```
  Confirm with user before terminating any. Then verify with a test commit + reflog scan.

**🟡 Phase 1B — Flutter UI consumer (the natural next work):**

- **#42** — Flutter admin UI for sensor / obstacle events. Gated on Flutter SDK install. Adds `SensorStatusCard`, `BlockedOverlay`, event log filter chip, toast on blocked transitions, widget tests. Estimated 3–4h. **Root gap:** Flutter `RobotStatus.fromJson` (`app/lib/services/spine/spine_state.dart`) still drops the 5 Phase 1A sensor fields (`obstacleState`, `localizationQuality`, `sensorHealth`, `personDetected`, `lastObstacleEventAt`) — extend the freezed model first, then build the two widgets, then wire into `control_screen.dart`. A detailed VS Code Claude Code prompt was drafted for this in the 2026-06-08 cloud session.
- ~~**#53**~~ — ✅ DONE in `7a19c83` (see "Done" above). Was on the `event` message path, separate from the `robot_status` sensor path — Phase 1B is independent of it.

**🟢 Phase 1.5 — ~10h spine + ~5h Flutter, gated by #54:**

- **#43** Battery + charge telemetry (`OnPowerStatusListener` / `OnChargetStateListener` / `OnChargeFailureListener` / `OnRobotDockStateListener`)
- **#44** Self-check + error info events (`OnWarningCheckSelfListener` / `OnErrorInfoListener` / `OnMotoOverloadListener`)
- **#45** Snapshot API (`OnSnapshotoListener` + `takeSnapshot()` intent)
- **#46** Head touch interaction (`OnHeadTouchListener`)
- **#47** Robot facial expressions (`OnExpressionListener` + `setExpression()`)

**🔵 Phase 1.7 — free to start anytime, no #54 dependency:**

- **#48** Microphone volume monitoring (transient — NOT logged to Supabase)
- **#49** OTA upgrade + shutdown lifecycle
- **#50** Wake word / hotword detection (gated by #46 — touch is one wake source)
- **#51** SDK authentication state visibility

**⚪ Long tail:**

- **#52** SDK API integration roadmap — quarterly review of deferred listeners (elevator, door, MQTT, remote — site-specific)

**🛑 Hardware bring-up epic (#60–#64) — BLOCKED: awaiting physical Timo robot.** Real camera + real movement against actual hardware. The plumbing is mostly built; this epic is verification + the last-mile native bridges. Cannot be validated without the robot on the desk, so it stays parked, not scheduled.

- **#60** Verify `RealRobotSDK` (`spine/src/robot/real.ts`) end-to-end: `ROBOT_MODE=real` + `ROBOT_IP`, intents → robot WS ports 8081/8082/8083, confirm drive/head/arm/wave actually move the chassis. SDK is implemented but **never run against hardware.**
- **#61** Confirm `robot_app` native plugins (`ChassisControlPlugin` / `HeadControlPlugin` / `ArmControlPlugin`) actually call the CSJBot **motor** SDK — right now they're WebSocket command receivers; the real motor bridge is the "(future) native SDK bridge."
- **#62** Swap the **mock camera** (cycling RGB frames, per `README.md:96`) for the real CSJBot camera feed in `CameraStreamPlugin`. MJPEG server + admin-app `MjpegView` already work against the mock; this swaps the source.
- **#63** Wire the native sensor bridge (`robot_app/docs/SENSOR_BRIDGE.md`) into `RealRobotSDK.onSensorEvent` (currently a no-op) so Phase 1A obstacle/health/localization events flow from real hardware.
- **#64** Real-hardware safety pass: STOP interlock + obstacle-blocked behaviour validated with the robot physically moving. Highest-risk item — do last, supervised.

**🟫 Dual-source face enrollment — laptop webcam + robot chest-screen (#88). NEAR-TERM UX rework. Added 2026-06 per user request.**

Problem: current enrollment uses the ROBOT camera (MJPEG) feed but shows the move-closer/turn-left instructions on the LAPTOP browser — the person stands at the robot but the guidance is on a screen they can't see. Disconnect.

Solution — **ONE backend, TWO capture sources** (preserve the single embedding pipeline — both POST the IMAGE to `/enroll`, spine extracts the 128-d):
  - **Web app (laptop): use the laptop's OWN webcam** (`getUserMedia` → `<video>` → face-api), guidance on the laptop screen. Person + screen + camera co-located. Convenient for REMOTE enrollment (employee far from robot). Bonus: webcam avoids the MJPEG/CORS-canvas fragility the robot-feed path fought through. Add a camera-source picker (this device / robot); default to device webcam on laptop.
  - **robot_app (chest screen): build a NEW native enrollment screen** on the robot — robot camera preview + instructions shown ON the chest screen + capture → POST `/enroll`. For enrolling when the employee is physically at the robot. Needs camera preview + on-device face detection (`google_mlkit_face_detection`) in robot_app (Flutter/Android).
  - **Honest nuance (cross-camera domain gap):** recognition runs on the ROBOT camera, but laptop-enrolled embeddings come from a different camera/lighting. face-api embeddings are mostly camera-invariant so it generally works, but robot-camera enrollment gives best accuracy; the thin ~0.014 gap makes cross-camera matches more wobble-prone — multi-pose + margin guard + temporal voting mitigate. Optionally add a `capture_source` ('robot'|'webcam') column to `staff_face_embedding` for later analysis.
  - Effort: medium. Web = small rework (MJPEG→webcam + picker). robot_app = new screen (camera + ML Kit + form + POST).

**🔋 Battery telemetry (#87) — DONE (2026-06-17, `21efd4a`), proven on the real robot.** Robot was reporting a static 85% (hardcoded `BatteryService._currentBattery=85` + one-time `setBattery(85)`). Now wired to the REAL battery end-to-end:
- **#87a fixed** — new native `BatteryPlugin.java` registers the CSJBot SDK `OnRobotStateListener` via `CsjRobot.setOnRobotStateBatteryListener` (the SDK's internal loop reports the robot's real main battery ~every 5s; `OnPowerStatusListener` turned out to be the power BUTTON, not battery). Android `BatteryManager` fallback if the SDK never reports. Forwarded over an EventChannel → Dart `BatteryNotifier` → `BatteryService` (:8090) + UI. Also `real.ts`: the `/battery` poll was `setInterval(60s)` so it served the seed 85 for the first minute — now fetches immediately + every 30s; seed 85→-1 (unknown). Admin: dropped the fake `?? 78` (battery is `int?`, shows real or "—"); removed the mock `battery_low` rows from dashboard + event-log.
- **#87b DONE** — battery indicator added to the robot_app `StreamScreen` app bar.
- **PROVEN:** `:8090/battery` returned a real, CHANGING value from the SDK (22→25→29→32→33% while charging, `source='sdk'`, not 85); spine relayed it; the admin app received `battery:32` in `robot_status`. NOTE: spine reaches the robot via `ROBOT_IP` in `.env` (DHCP — was `192.168.1.17` this session, gitignored).

**Original #87 notes (historical, now resolved):**

- **#87a — Admin app shows INCORRECT battery (bug).** Likely root cause traced:
  - `robot_app/lib/battery_service.dart` serves `_currentBattery` on port **8090**, but it's **hardcoded to 85** and only changes via `setBattery(level)`. **Nothing appears to feed the real CSJBot battery into `setBattery()`** — so the robot reports a static 85% regardless of actual charge. This is almost certainly the wrong value. Fix: in `robot_app` native, subscribe to the CSJBot battery API (`OnPowerStatusListener` / charge listeners — Phase 1.5 #43) and call `BatteryService.setBattery(realLevel)` so 8090 reports real charge.
  - Chain is otherwise fine: `spine/src/robot/real.ts:58` correctly polls `http://<ip>:8090/battery` and updates `status.battery` → broadcast → admin. So spine faithfully relays whatever robot_app reports (the static 85).
  - **Also clean up admin-side fallbacks that mask/fake the value:** `dashboard_screen.dart:205` does `spineState.status?.battery ?? 78` (shows a hardcoded **78** when status is missing), and there's a **mock** `battery_low level: 20%` event hardcoded in the dashboard events list. Remove/replace these so the UI reflects real telemetry only.
- **#87b — Display battery in the robot_app (chest-screen) UI (feature).** The `robot_app` Flutter app runs the battery HTTP server but doesn't show the level on its own screen. Add a battery indicator to the robot_app UI (`robot_app/lib/main.dart`), reading the same real source (`BatteryService` / CSJBot SDK) — so the chest screen shows charge too.
- Effort: small–medium. The real unlock is wiring the actual CSJBot battery level (#43) — until then everything downstream shows the placeholder 85.

**🟦 Reception workflow epic (#70–#71) — "customer arrived → tell the right staff member." #70 DONE; #71 NOT built.**

The reception robot's core job: when a visitor/customer arrives, inform the staff member they're here to see. Two features, do them in this order — notification is the reliable baseline, navigate-and-announce is the premium layer on top.

> **✅ #70 — Host notification on visitor arrival DONE (2026-06-18, `6a65d71`+`cc1071d`).** Spine `POST /visit` (auth fail-closed) → loads host → inserts a `visitor` row FIRST (DPDP: **name + timestamps only, no biometrics**, `purge_after` = 30 days) → `notifyStaff` once → audit `logEvent` + broadcast a `visitor_arrived` event. `services/notify.ts` sends via the host's `notify_channel`. Admin Live Feed has a collapsible **Visitor check-in card** (staff dropdown from `GET /staff` + name field → `POST /visit`) and a dismissible **arrival banner**; arrivals also land in the dashboard activity feed. 4 vitest pass, tsc clean. Proven live (POST /visit → 200, email logged, visitor row + 30d purge, `visitor_arrived` reached the admin app).
> - **`notify_channel` format convention: `prefix:value`** — `slack:U0ABC123`, `whatsapp:+9198…`, `email:john@xboom.in`. Unknown/missing channel → warn + return (visit still logged).
> - **Env (now in `.env.example`):** `SLACK_WEBHOOK_URL` (Slack Incoming Webhook), `INTERAKT_API_KEY` (WhatsApp via Interakt, Basic auth).
> - **Known gaps:** email channel is **log-only** (`TODO: wire SMTP in Phase 3`); WhatsApp/Interakt path is **untested against a live key** (text-message shape may need an approved template); **hosts must have a real `notify_channel` set** before #70 fires for them (today most are NULL — set them in Manage Staff / DB).

- **#70 — Host notification on visitor arrival — ✅ DONE (see callout above).** Original plan retained below for context.
  - **Data model already exists — NO schema change:** `visitor.host_staff_id` (FK→staff) links a visitor to their host; `staff.notify_channel` holds `slack_id` / `whatsapp_phone` / `email` (the comment literally says "for host handoff").
  - **What's missing:** (a) a visitor-intake step that sets `host_staff_id` — either face recognition (Phase 2 recognizer, in progress) identifies a pre-booked visitor, OR a simple "who are you here to see?" check-in UI; (b) a **notification SENDER in spine** — none exists today; `notify_channel` is only *stored* (it appears in `handlers/enroll.ts` as a field, never sent). Build a sender keyed off the channel type (Slack webhook / WhatsApp / email).
  - **Reuse:** `xboom-flow` (separate repo) already sends WhatsApp via Interakt/MyOperator — reuse that for the WhatsApp channel rather than rebuilding.
  - **Can ship without recognition:** start with manual check-in (visitor picks/says the host) → notify. Recognition just automates the "who" later.

- **#71 — Navigate to the employee's desk and announce (Phase 3, large effort, multi-track).** Robot physically drives to the staff member's location and announces the customer.
  - **CRITICAL design rule:** navigate to the staff member's **assigned location/desk (a fixed waypoint)** and announce — do **NOT** "roam and hunt for a moving person by face." Hunting is the unreliable anti-pattern; a notification reaches a wandering person far faster. Model it as "go to John's sales desk = waypoint 5," not "search the building for John."
  - **Dependencies — none exist today:**
    1. **Navigation integration in spine.** There is currently **NO** navigate/goto/waypoint intent — spine only accepts `drive | head | arm | wave | stop | resume | snapshot | get_status` (`spine/src/types.ts`). Must add a `navigate`/`goto` intent + wire `RealRobotSDK` to CSJBot's point-to-point navigation API. This is the biggest missing piece.
    2. **A mapped office** built with the CSJBot mapping tool (the robot needs a floor map). CSJBot *can* navigate (it's a delivery/guidance platform) but uses its high-level nav API + a pre-built map — raw LIDAR is not exposed (see LIDAR research notes).
    3. **Staff → location mapping** ("John = sales zone / waypoint 5"). New small data — add a location/waypoint field to `staff` or a `staff_location` table.
    4. **Arrival announcement** — TTS/voice or chest-screen message.
    5. **Obstacle avoidance / localization** — ties to the Hardware bring-up epic (#63 sensor bridge); the sensor pipeline is scaffolded but not wired to real hardware.
  - **Relationship to #70:** layered on top. #70 (notification) is the dependable baseline that works even when the robot is busy, blocked, or the person isn't at their desk. Build #70 first; #71 is the Phase-3 "escort/announce" premium experience.

**🟪 Voice interaction epic (#80) — voice Q&A / conversational reception. Added to pipeline 2026-06 per user request. NOT built.**

Visitor/staff asks a question out loud → robot answers from the knowledge base, grounded by Claude. Pipeline: **wake word → STT → KB vector search → Claude RAG → TTS.**
  - **Groundwork already exists:** `kb_chunk` table with `embedding vector(1536)` (comment: *"NULL until voice pipeline populates it"*) + IVFFlat cosine index (migration 004) for FAQ/Q&A retrieval; `conversation` table for transcript logging. So the retrieval half of RAG is schema-ready.
  - **What's missing (all of it):**
    1. **KB ingestion** — chunk xboom's FAQ/KB content (Vishal owns KB content), embed each chunk (text-embedding model, 1536-dim to match), populate `kb_chunk.embedding`.
    2. **STT (speech-to-text)** — capture mic audio from the CSJBot SDK and transcribe (Deepgram or similar). Relates to old roadmap #48 (mic volume) + #50 (wake word / hotword — CSJBot exposes a wake-word listener).
    3. **Retrieval + RAG** — embed the question → pgvector cosine search over `kb_chunk` → feed top chunks to **Claude** (`claude-opus-4-8` / latest) as grounding context → generate the answer. Use the latest Claude model; read the claude-api skill before wiring the API.
    4. **TTS (text-to-speech)** — speak the answer through the robot speaker (CSJBot SDK audio out).
    5. **Conversation logging** — write turns to `conversation` (retention-bound, DPDP).
  - **Sequencing:** KB ingestion + retrieval can be built/tested in spine against text input FIRST (no audio), then bolt on STT/TTS/wake-word once the RAG answers are good. Mic/speaker pieces depend on real-hardware audio access (ties to Hardware bring-up).
  - **Effort:** large, multi-part (a Phase-2/3 track of its own).

**🟩 Animated avatar face — full-screen "robot personality" UI (#82). Pairs with #80 voice. Added 2026-06 per user request. NOT built.**

A full-screen animated face on the **robot's chest screen** (`robot_app/`, Flutter on Android 7.1.2) so interacting with Timo *feels like talking to a being* — **eyes that look/blink + lip-sync to speech.** This is the visible "personality" layer over the voice pipeline.
  - **Where:** `robot_app/` (the chest screen), NOT the admin app. Currently `robot_app` is the MJPEG streamer + control plugins; this adds a foreground avatar UI.
  - **State machine driven by the #80 voice pipeline:**
    - **Idle** — gentle blink + subtle look-around / breathing.
    - **Attentive** — eyes track the detected person (drive gaze from the face-detection bounding-box position when someone is recognized/present).
    - **Listening** — visual cue while STT is capturing (e.g. pulsing).
    - **Thinking** — during KB retrieval + Claude RAG.
    - **Speaking** — **lip-sync** the mouth to the TTS audio.
  - **Lip-sync approach:** start with **amplitude-driven** mouth open/close synced to TTS audio playback (simple, "good enough" and robust). Phoneme/viseme-accurate lip-sync is a later upgrade (needs phoneme timing from the TTS engine).
  - **Tech suggestion:** **Rive** is well-suited — a state-machine-driven interactive character with named inputs (gaze x/y, blink, mouth-open level, state), lightweight enough for the modest chest-screen hardware. Lottie or Flutter `CustomPainter` are alternatives. Keep it GPU-light (Android 7.1.2, modest device).
  - **Dependencies:** the avatar *states* come from #80's pipeline events (listening/thinking/speaking) and from #42/face recognition (who/where the person is). Build the avatar with **mock state inputs first** (a debug toggle to cycle idle→listening→thinking→speaking), then wire it to the real voice/recognition events once #80 lands.
  - **Effort:** medium (animation + state wiring); the heavy lifting is the #80 voice pipeline it visualizes.

**🟪 Robot chest-screen experience redesign — front-of-house app shell (#89). The "proper robot" UX. Added 2026-06-19 per user request. NOT built.**

Turn `robot_app` from a utility (MJPEG streamer + battery server + control receivers + enrollment) into the robot's **front-of-house personality + interaction shell**. Goal: a chest screen that *behaves like a being* — an ambient face when idle, reacts to people walking by, greets identified staff by name, and on tap opens a feature dashboard driven by tap + (later) voice. **#89 is the CONTAINER**; #82 (the animated face) and #80 (voice) are the engines that plug into it.
  - **Where:** `robot_app/` (chest screen, Flutter on Android 7.1.2). The existing background servers (MJPEG :8080, battery :8090, control WS receivers) **keep running** — this redesigns only the FOREGROUND `main.dart` UI into a stateful shell.
  - **Two screens, one shell (the app-shell redesign — this is the NEW part beyond #82/#80):**
    - **Ambient Face screen (default)** — full-screen animated face (#82). Idle = blink + subtle look-around. Reacts to presence/motion (eyes track a passerby) and to identity (greet a recognized staff member). This is the resting state the robot sits in 99% of the time.
    - **Dashboard screen (on tap/voice)** — tapping the face opens a feature dashboard: the actual features (live status, enrollment, settings, control) as large tap targets + placeholders for future features (voice Q&A, payment, navigate, directory). Idle-timeout returns to the Ambient Face.
  - **State machine (extends #82's, adds the presence/identity/dashboard states):** `ambient-idle` → `attentive` (someone present, eyes track) → `greeting` (staff identified → personalized) → `listening`/`thinking`/`speaking` (voice, #80) → `dashboard` (tapped). Auto-return to `ambient-idle` on timeout.
  - **⚠️ CRITICAL architecture — TWO perception pipelines, do NOT cross them:**
    1. **Gaze / presence = ON-DEVICE, local, fast.** Eyes tracking a passerby needs a *position* (bounding-box), in real time, with no network latency. The spine recognizer does NOT provide this — it emits identity (`face_detected{staff_id,name,distance}`), polls ~1s, and has no box. So the chest screen runs a **lightweight local ML Kit face-detect on the robot `/snapshot`** (same source enroll_screen already uses — REUSE it, do NOT open a 2nd camera; CameraStreamPlugin owns camera2) to drive gaze x/y + "someone is here". CSJBot `personDetected` (boolean, Phase 1A) is a coarser presence fallback.
    2. **Identity / greeting = SPINE, authoritative.** Who the person is comes from the existing Milestone-D recognizer over the WS (`face_detected` event). The chest screen listens for it → triggers the `greeting` state with the name. Keep ONE embedding pipeline (spine) — the on-device ML Kit is for *gaze/presence only*, never identity (would be a divergent recognition path — forbidden, same rule as enrollment).
    - Net: **local detection animates the face (responsive); spine recognition supplies the name (authoritative).** Don't try to recognize on-device, don't try to gaze-track from spine.
  - **DPDP:** strangers/passersby are **anonymous presence only** — drive the eyes, store NOTHING (no frames, no embeddings). Greeting-by-name uses staff identity from the consented enrollment pipeline only. Consistent with no-customer-biometrics.
  - **Tech:** Rive for the face (#82 — state-machine inputs: gaze x/y, blink, mouth-open, state). App shell = a simple state-driven `Stack`/`Navigator` (AmbientFace ↔ Dashboard), NOT heavy routing. GPU-light (Android 7.1.2).
  - **Phasing (build mock-first, exactly like #82):**
    - **P1 — App shell + ambient face (mock inputs).** AmbientFace ↔ Dashboard navigation, tap-to-open, idle-timeout-return, the Rive face with a debug toggle cycling idle→attentive→greeting→listening→thinking→speaking. No real perception yet. *Hardware-free, buildable NOW.*
    - **P2 — Wire real perception.** Local ML Kit `/snapshot` detect → gaze + `attentive`; spine `face_detected` WS → `greeting`-by-name. Needs robot.
    - **P3 — Voice commands** (depends #80): wake/STT → `listening`/`thinking`/`speaking`; voice nav of the dashboard.
    - **P4 — Lip-sync** (depends #80 TTS): amplitude-driven mouth, per #82.
  - **Dependencies:** #82 (the face asset/animation), #80 (voice, for P3/P4), recognition pipeline (DONE — emits `face_detected`), `personDetected` sensor (Phase 1A), battery (already on the chest screen via #87). P1 depends on none of these being *finished* — it's the shell + a placeholder face with mock state.
  - **Effort:** large (it's a full app redesign + the parent of #82/#80). But P1 (shell + mock face) is a self-contained, hardware-free, demo-able chunk — start there.
  - **"Designed properly":** ✅ **design doc DONE** → `robot_app/docs/CHEST_UX_REDESIGN.md` (state machine, two screens, the two-pipeline split, Rive input contract, P1–P4 phasing, P1 acceptance criteria). **Decisions locked (2026-06-19):** face = **full stylized character** (eyes+mouth+brows from the start); Dashboard v1 real tiles = **Enroll Staff + Robot Status + Manual Control + Settings** (all wire to EXISTING `main.dart` providers/`EnrollScreen`), rest are disabled placeholders. **Next: build P1** (app shell + mock-state face + 4 tiles, hardware-free) against that doc.

**📱 Mobile admin / remote-control app (#90) — phone-first "drive + monitor + get-alerted on the go." Added 2026-06-19 per user request. NOT built.**

A mobile experience for the admin: a **remote-control + monitoring** client for a phone — drive Timo, watch the camera, see status, get pushed when a visitor arrives. NOT the full admin authoring suite (enrollment management, gallery, patrol-map editing, analytics stay on the larger web/tablet screen). Think **"Timo Remote"**, not "admin console on a small screen."
  - **✅ Architecture decision LOCKED (2026-06-19): Option A — adaptive layouts in the EXISTING `app/`.** NOT a separate app. `app/` already targets iOS+Android+web (pubspec: "Flutter web + iOS + Android"); add responsive breakpoints (`LayoutBuilder`) → phones get a mobile-first remote layout (joystick-first), web/tablet keep the current dashboard. **Shares everything** — `spine_service.dart`, Supabase auth, all Riverpod providers, models, the mobile `MjpegView` path. One codebase, no duplication; push notifications + haptics are the mobile-native layer on top. (Considered + rejected: a separate "Timo Remote" app + extracted `packages/timo_core` — unnecessary maintenance overhead for a solo MVP unless the products genuinely diverge. `viewer_mobile/` stays a camera-only viewer.)
  - **Core features (v1 — the "remote"):**
    1. **Login** (Supabase — reuse; gated by the #auth go-live work).
    2. **Live camera** — full-screen MJPEG (mobile `MjpegView` already exists), portrait + landscape.
    3. **Drive joystick** (chassis fwd/back/left/right) — the headline; on-screen touch joystick (mirror the admin Control joystick → spine `drive` intent).
    4. **Head pan/tilt** — touch pad / mini-joystick → `head` intent.
    5. **Arm + wave** — buttons → `arm`/`wave` intents.
    6. **STOP / RESUME** — big, ALWAYS-visible emergency stop (safety-critical) → `stop`/`resume`.
    7. **Robot status** — battery, connection, SDK status, obstacle/sensor state (reuse `SensorStatusCard` from the sensor-UI branch once merged).
    8. **Quick actions** — wave, reset body, snapshot.
  - **Mobile-native value-adds (the reason it's worth a phone app at all):**
    - **Push notifications** — visitor arrived (#70 already emits `visitor_arrived`), battery low, obstacle blocked, intrusion. This is the killer mobile feature: the host gets the arrival alert on their phone. (Needs FCM/APNs wiring + a spine→push bridge or Supabase Edge Function.)
    - **Haptic feedback** on controls; connection indicator + auto-reconnect (spine WS).
  - **Explicitly DEFERRED off mobile v1 (keep on web/tablet):** staff enrollment/CRUD, gallery, patrol-route map editor, Mission Control analytics. Mobile = control + monitor + alerts, not authoring.
  - **Dependencies / reuse:** `spine_service.dart` (WS + intents — done), mobile `MjpegView` (done), `visitorArrivedProvider`/`faceDetectionProvider` (#70/Milestone D — done), auth (gated on #auth go-live). Push notifications are the one genuinely-new infra piece.
  - **Effort:** medium (responsive layouts + push). Push-notification infra is the long pole.
  - **Build order (user, 2026-06-19):** **AUTH GO-LIVE FIRST** (JWKS/ES256 hardening, mid-flight in VS Code) before #90 or #89-P1 — don't stack more UI on the open auth bypass. #90 also depends on real login (feature 1) which the auth work delivers.

**🟧 LIDAR / obstacle feature activation (#81) — turn on the obstacle awareness that's already built but unfed. Added 2026-06 per user request.**

Phase 1A built the **entire** obstacle/sensor pipeline (types, `createSensorPipeline`, mock emitter, Flutter `SensorStatusCard` + `BlockedOverlay`) — but on the real robot it is **fed by nothing**, so the UI sits at `obstacleState: 'unknown'` forever. "Activation" = connect the real sensor source to the existing pipeline.
  - **Reality (don't expect raw LIDAR):** CSJBot does **not** expose a raw LIDAR point cloud — only high-level nav events (`NAVI_ROBOT_BLOCKED_NTF`, `WAITSHORT`, `LQ_LOW`, etc.). "LIDAR feature" here = consuming those high-level obstacle/health/localization events, not rendering a point cloud.
  - **What's already done:** spine pipeline is wired (`server.ts:241` registers `sdk.onSensorEvent`); Flutter `SensorStatusCard`/`BlockedOverlay` exist.
  - **What's missing (the 3 breaks in the chain):**
    1. **`RealRobotSDK.onSensorEvent` is a no-op** (`spine/src/robot/real.ts:301`) — must invoke the handler with parsed events.
    2. **`real.ts` doesn't parse obstacle messages** — `handleRobotMessage` only handles `face_detected`/`battery_update`; add parsing for the CSJBot nav/obstacle events.
    3. **The native bridge was never built/deployed** — the Kotlin/Dart in `robot_app/docs/SENSOR_BRIDGE.md` (reference only) must be built into `robot_app` to capture CSJBot SDK events and forward them over the chassis WebSocket to spine.
  - **Same as Hardware bring-up #63.** Requires the physical robot. Once fed, the existing `SensorStatusCard`/`BlockedOverlay` light up with no further UI work. Note the old mock emitter was disabled (`49ee0da`) because its synthetic "blocked" events were tripping the STOP interlock — re-enable carefully / behind a flag if used for dev.

**🟦 Mapping & Navigation foundation (#83) — prerequisite for ALL physical autonomy. Added 2026-06 per user request.**

**Honest framing (important):** on CSJBot you do **NOT** implement SLAM yourself. The robot's firmware runs SLAM/localization internally (it reports `OnPositioningQualityListener` quality; waypoints are `{x, y, heading}` in the robot's own map frame). So this feature = **use the CSJBot mapping mode to build the map, then integrate its navigate-to-point API** — not writing a SLAM/particle-filter algorithm. Don't reinvent what the platform already does.

  - **⚠️ "Uses LIDAR" ≠ "gives raw LIDAR access" — settle this so it isn't re-litigated.** Recurring question: *"if we don't have raw LIDAR, how do we map at all?"* Answer: **we ARE mapping with LIDAR — the firmware's LIDAR does it; we just don't get the raw scans/point cloud.** Two different things. The mapping IS LIDAR-based; it's just LIDAR-consumed *inside the firmware*, where you take the finished map as output. (Mental model: like building on Supabase/Postgres without touching the storage engine — the DB does the hard part, you consume the result.) The layering:
    | Layer | Who runs it | Uses LIDAR? | Exposed to us? |
    |---|---|---|---|
    | Raw LIDAR scans / point cloud | firmware only | ✅ consumes | ❌ **NOT exposed** |
    | SLAM + map building | CSJBot firmware | ✅ | ✅ we *trigger* it, get the saved map |
    | Map + waypoints `{x,y,heading}` + localization quality | SDK | — | ✅ |
    | Navigate-to-point (live obstacle avoidance) | firmware | ✅ live | ✅ we issue `goto` |
    - **What "no raw access" actually costs us — and why we need neither:** (1) writing our OWN SLAM (we don't — firmware does it better); (2) custom raw-LIDAR+CV obstacle fusion (we don't — **event-level fusion** covers it: CSJBot's own fused `BLOCKED`/`WAITSHORT`/`LQ_LOW` events + CV semantics on spine + virtual walls on the map). Everything a reception robot needs — knows the floor, localizes, navigates point-to-point avoiding obstacles — comes from the **map + nav API**, which IS exposed. Raw access only matters if you're rebuilding the robot's brain from scratch, which we are not.
    - **Caveats (unchanged):** mapping *initiation* is **operator-guided** — drive the floor ONCE to build the map (CSJBot almost certainly does NOT expose autonomous "explore unknown building"); after that, localization + navigation are fully autonomous. **Glass walls are invisible to LIDAR** (laser passes through) even to the firmware → they don't get mapped → **mark them as virtual no-go walls** (#84). Glass is the one obstacle where BOTH LIDAR and plain RGB/CV are weak; the sensors that catch glass are ultrasonic (CSJBot fuses some internally) + depth-reflection tricks + manual virtual walls. Do NOT plan to "fall back to LIDAR when CV is unsure about glass" — for glass specifically LIDAR is the WORST sensor, not the fallback.
    - **Sensor fusion happens at the EVENT layer, not the raw-data layer.** CV (spine) = *what/who/why* (semantic); CSJBot high-level obstacle events (Phase 1A pipeline) = *am I physically blocked* (safety, already firmware-fused); virtual walls = known invisible hazards. Combine those three at the app layer. Raw-LIDAR-on-demand fusion is NOT buildable on this SDK — don't start down that path.
    - **If glass collisions ever become a real operational problem** after virtual walls: the only way to get raw range data the SDK won't give is to ADD your own sensor (external ultrasonic array or depth/ToF cam on the Android device) and fuse THAT with CV at the app layer. That's a **hardware modification** (Vishal's domain, real cost) — do NOT build speculatively; only if virtual walls prove insufficient in practice.

  - **What it unlocks (everything physical):** #71 navigate-to-desk, autonomous patrol, auto-return-to-charge, escort/guide. Nothing moves intelligently without it.
  - **Pieces to build:**
    1. **Build maps** with the CSJBot vendor mapping tool (drive the floor once); save named maps.
    2. **`navigate`/`goto` intent in spine** (MISSING today — only drive/head/arm/wave/stop) + wire `RealRobotSDK` to CSJBot's point-to-point nav API; surface nav state via the existing sensor pipeline (`running/blocked/wait`).
    3. **Waypoint & zone management** in the admin app — name points ("reception", "sales desk", "charging dock"). Data model partly ready: `patrol_route.waypoints jsonb [{x,y,heading,dwell_s,narration}]`; Flutter `patrol_routes` feature (`MapCanvas`, `patrol_panels`) is UI scaffolding.
    4. **Map + live robot-position visualization** in admin.
  - **Dependencies:** physical robot + CSJBot mapping tools (Hardware bring-up gated).
  - **"Is it THE most important feature?"** It's the *foundation for an entire category* (all physical autonomy), so critically important — but **not the immediate next step.** Recognition + voice + notification deliver reception value *without* navigation. Build the brain first; #83 unlocks the legs (Phase 3).

---

## Candidate feature backlog (exploration — 2026-06)

A menu to prioritize from. Many are already anticipated in the schema (grounding noted in parens). Not scheduled.

**Physical autonomy (all need #83 mapping):**
- **Autonomous night patrol** — `patrol_route` table built (`active_from`/`active_to`, `narration`, `enabled`); `capture_patrol` kind exists.
- **Auto-return-to-charge / docking** — battery-low → navigate to dock (CSJBot dock/charge listeners; Phase 1.5 #43).
- **Escort / guide visitor to a room**; lead-mode (visitor follows).
- **Multi-floor** — elevator/door integration (CSJBot SDK supports; site-specific).

**Security / monitoring:**
- **Intrusion detection** — after-hours person detection → alert + frame capture (schema ready: `capture_intrusion`, 365-day retention).
- Incident/anomaly capture + alerts.

**Reception / visitor experience:**
- Visitor check-in + host notification (#70); appointment/calendar pre-booking.
- **Greet-by-name** (recognition → personalized greeting); multi-language; touchscreen directory/FAQ on chest screen.
- Visitor badge — QR/print or send-to-phone pass.
- **Telepresence** — visitor ↔ remote staff video call through the robot.

**Conversational (with #80 voice / #82 avatar):**
- Voice Q&A; animated avatar; sentiment/engagement read.

**Admin / analytics:**
- **Mission Control dashboard** (in progress — `MISSION_CONTROL_BUILD.md`).
- Footfall / dwell / peak-time analytics; staff attendance via recognition.
- Health & diagnostics (battery, motor overload, self-check — Phase 1.5 #44).

**Platform / robustness:**
- OTA update + lifecycle (#49); SDK auth visibility (#51); **WebRTC camera upgrade** (lower latency than MJPEG).

---

**🟦 Zone mapping & virtual boundaries (#84) — semantic layer on top of #83. Added 2026-06 per user request.**

User idea: "auto-map the office (showroom vs inside office) with boundaries using CV/OpenCV." **Honest correction recorded so this isn't mis-built:** the geometric/boundary map comes from **CSJBot's built-in SLAM** (depth/LIDAR), NOT from OpenCV on the RGB camera — monocular camera mapping is drift-prone and the wrong tool when the platform already does sensor SLAM. CV adds the **semantic** layer on top:
  - **Operator-tagged zones (reliable, recommended):** on the SLAM map, draw/label zones ("Showroom", "Office") + **virtual boundaries / no-go geofences** ("don't cross into office during business hours"). `patrol_route` table + Flutter `MapCanvas` are scaffolding for this.
  - **CV-assisted labeling (hint only):** during a mapping run, use camera scene/object recognition to *suggest* zone labels. Don't treat auto vision-segmentation as source of truth — unreliable.
  - **ArUco/AprilTag markers (robust CV trick):** printed markers around the office → OpenCV reads them cheaply for solid zone/landmark identification, far more reliable than scene classification.
  - **Depends on #83** (the SLAM map must exist first) + physical robot.

**🟩 Computer Vision suite (#86) — capability menu (formalized from the CV table, 2026-06).** The camera + spine face-api pipeline already exists; these layer on. Continuous/autonomous CV → run on **spine** (reuse frame pipeline); interactive → browser. **DPDP:** presence/object/anomaly detection (no identity) is clean; demographics/emotion/age-gender on visitors is biometric-adjacent — OUT unless Vishal signs off (consistent with no-customer-biometrics).
  - **Face recognition** (in progress) — greet staff/known by name (face-api).
  - **Person detection & counting** — footfall, "someone's here → greet", occupancy (YOLO/COCO-SSD).
  - **Object detection** — unattended bags/packages at reception, products, obstacles (YOLO/COCO).
  - **Approach / wave / gesture** — trigger greeting when someone walks up (MediaPipe pose/hands).
  - **OCR / business-card / ID / QR scan** — visitor self check-in, badge scan (Tesseract / vision API).
  - **ArUco/AprilTag markers** — cheap robust zone/landmark ID for navigation (OpenCV).
  - **Anomaly / activity (after-hours)** — security patrol: motion, fallen person, intruder. Schema ready: `capture_intrusion` (365-day retention).
  - **Product recognition** — showroom "what is this?" Q&A (custom classifier / vision API).
  - **Liveness / anti-spoof** — block photo-of-photo enrollment (face-api + inter-frame motion).
  - **Tools:** face-api.js (faces, have it), YOLO/COCO-SSD (objects/people), MediaPipe (pose/hands/face mesh), OpenCV (markers, motion, contours), Tesseract (OCR), or cloud vision (Google Vision / AWS Rekognition) as alternatives.

**🟨 Payment / checkout (#85) — visitors/customers pay via the Timo app. Added 2026-06 per user request.**

Reception robot pivots slightly into commerce/kiosk. Doable and well-trodden in India — but it's a real compliance surface, so build it backend-driven and minimize PCI scope.
  - **Recommended approach: UPI QR / hosted checkout via an Indian PSP (Razorpay or Cashfree).** Robot displays a **UPI QR or hosted checkout page** → customer pays on **their own phone** (PhonePe/GPay/Paytm). Card data NEVER touches the robot or our servers → stays **out of PCI-DSS scope**. UPI is the dominant rail in India and ideal for a kiosk (no card-reader hardware needed — just the chest screen).
  - **Architecture (backend-driven — NEVER trust the client to confirm payment):**
    1. Flutter → spine: create order (amount, item, visitor contact for receipt).
    2. Spine → PSP order API (**secret keys on spine ONLY, in env**) → returns order id / QR / hosted URL.
    3. Flutter shows the QR / checkout.
    4. Customer pays on their phone.
    5. PSP → spine **webhook** (`payment.captured`) → spine **verifies the HMAC signature** → marks order paid → pushes status to the app (WS) → success + receipt (email/SMS).
    - **Mark paid ONLY on the verified webhook** — never because the client said so. Webhooks must be idempotent (PSPs retry).
  - **Data model (NEW — none exists today):** `order` (amount, status, items, visitor ref), `payment` (psp_order_id, psp_payment_id, status, amount), optional `product`/`catalog`. Minimal PII; **store NO card data, ever**.
  - **Security / compliance:**
    * Hosted/QR flow keeps card data off our systems (PCI scope minimized).
    * Secrets only on spine; Flutter gets the public key / order id only.
    * Mandatory webhook **signature (HMAC) verification** — reuse the `xboom-flow` webhook-auth discipline (#14–#17: Exotel/MyOperator/Interakt + secret rotation).
    * Idempotency + reconciliation + refund handling; receipts via email/SMS; DPDP-minimal storage.
  - **Scope first:** define WHAT is being sold (showroom products? services? appointments?) — that drives the catalog/order model.
  - **Effort:** medium–large (distinct commerce domain). Avoid card-terminal hardware unless truly required (adds PCI + hardware).

**🟢 Done this session (cloud, branch `claude/clever-brown-8kLaJ`):**

- **Live camera view in the admin app** — new cross-platform `MjpegView` (`app/lib/features/live_feed/widgets/`): native `<img>`/HtmlElementView on web, pure-Dart JPEG frame parser (`mjpeg_parser.dart`, unit-tested) on mobile/desktop. Wired into the Live Feed screen + Control screen feed cards with a start/stop toggle, reading the robot IP from `settingsProvider` → `http://<ip>:8080/stream`. Closes the gap where those panels were static `videocam` icons. Works against the mock camera today; "just works" when #62 swaps in the real feed.
- **Settings ↔ provider fix** — the Settings "Robot IP" field previously wrote only to local widget state, so it never reached the stream URL. Now seeds from and persists to `settingsProvider`. Added `http: ^1.2.0` dep + `robotStreamUrl()` helper in `constants.dart`.

**🌐 Cross-project (xboom-flow, separate repo):**

- **#14–#17** Webhook auth header migration (Exotel / MyOperator / Interakt + 30-day secret rotation)

> **Note on task tracking:** Claude Code's task list is session-local — it does NOT sync across machines or sessions. The numbered tasks (#14–#54) live in the Windows session's task tool. When you (iMac Claude) need to track work, create your own tasks; use the numbers above as cross-reference IDs only.

---

## Critical gotchas

### 1. The #53 wire-format bug — ✅ RESOLVED (commit `7a19c83`)

**Historical, kept for context.** `spine/src/server.ts` used to do `{ type: 'event', event: event.type, ...event }`; the spread clobbered `type` with `RobotEvent`'s own `type`. The fix destructures it cleanly:
```ts
const { type: eventType, ...rest } = event;
const msg: SpineMessage = { type: 'event', event: eventType, eventPayload: rest };
```
`SpineMessage` was updated to `event?: string` + `eventPayload?: Record<string, any>`. Both consumers now read `eventPayload`:
- `app/lib/services/spine/spine_service.dart` — `event` branch reads `msg['event']` + `msg['eventPayload']` (logs only for now; Phase 1B wires to UI).
- `viewer_web/index.html` — `handleSpineMessage` reads `msg.eventPayload`.

No action needed. Don't re-introduce the spread.

### 2. STOP location

When wiring new sensor or intent code: STOP state lives in `spine/src/commands/interlocks.ts` via `getStoppedState()`, NOT in the SDK. Use the injected predicate pattern from `createSensorPipeline` if you need STOP awareness in new code.

### 3. tsc baseline

```bash
cd spine && npx tsc --noEmit
```

Clean of the old #53 wire-format errors (fixed in `7a19c83`). The only remaining output is an unrelated config deprecation: `tsconfig.json(8,25): TS5107 moduleResolution=node10 is deprecated`. **New code should add zero new errors.** Verify before committing.

### 4. Test baseline

```bash
cd spine && npm install && npm test    # fresh containers need install first
```

**49 tests must pass** (was 47; the #53 fix added 2 event-handling cases). Every behavioral change adds a vitest case.

### 5. Real hardware is unavailable

All Phase 1A code runs against `MockRobotSDK`. **Correction to earlier notes:** `RealRobotSDK` (`spine/src/robot/real.ts`) is *not* a no-op — it implements intent→command translation over WS ports 8081/8082/8083 and HTTP snapshot. What's true: it has **never been run against hardware**, `onSensorEvent` is a no-op, and `getStatus` is static. The Kotlin in `SENSOR_BRIDGE.md` is reference code; it has NOT been built or tested. See the Hardware bring-up epic (#60–#64). Don't deploy `robot_app/` against a real Timo until that epic runs.

### 5b. Camera view needs on-device verification

The new `MjpegView` (this session) was written **without a Flutter SDK in the cloud container — not compiled or `flutter analyze`'d here.** Before relying on it: `cd app && flutter pub get && flutter analyze && flutter test`. The web path uses `dart:html` + `dart:ui_web` (fine for `flutter run -d chrome`; not Wasm builds). The mobile path streams via `package:http`. The `mjpeg_parser.dart` slicer has unit tests (`app/test/mjpeg_parser_test.dart`); the platform rendering needs a real device/browser + a running MJPEG source (mock camera in `robot_app`, or any MJPEG URL). Note: the **Dashboard** mini live-feed card still shows a hardcoded `192.168.1.42` placeholder — not yet wired to `MjpegView` (out of scope this pass).

### 6. Orphan-rewriter (Windows-only)

If you're reading this on Windows, beware: long multi-line `feat:` / `docs:` commit messages get auto-rewritten by the orphan fleet. `chore:` one-liners pass through cleanly. **On iMac you're safe** — no orphan, no rewriter.

### 7. `.claude/settings.json`

Per-machine. Don't commit it. Permission grants will rebuild as you approve commands on the new machine.

---

## Recommended next step

### Next up (2026-06-18) — pick one; Phase 2 recognition + enrollment + #70/#87 are all done

The strongest candidates, roughly in priority order:

1. **🔴 Production auth go-live (security).** Highest-value hardening — see the "Production auth go-live checklist" near the top. Re-enable `router.dart:118` login, set `JWT_SECRET`, leave `DEV_AUTH_BYPASS` unset, mint a kiosk credential for `robot_app`. Until then all biometric/PII endpoints + the WS only work via the dev bypass.
2. **🟡 Recognition robustness.** The nearest-neighbour gap is OVERLAPPING at 6 people (threshold dropped to 0.53 for precision). Re-enroll the loose/short captures (rohit + Amit = 4 poses each) sharper/more-frontal, then re-run `scripts/enroll/calibrate.js` and raise the threshold back toward the gap midpoint.
3. **🟦 #71 navigate-to-desk** — the Phase-3 premium layer on #70. BLOCKED on **#83 mapping & navigation foundation** (no `navigate`/`goto` intent exists; needs a CSJBot-built floor map). Big multi-track effort.
4. **#70 polish:** wire a real SMTP email sender (currently log-only), test the WhatsApp/Interakt path against a live key, and set real `notify_channel` values on hosts (most are NULL).
5. **🟪 Voice (#80) / 🟩 avatar (#82)** — larger conversational tracks; KB/`conversation` schema is half-ready.

**Per-session env reminders (DHCP — re-set each session):** `spine/.env ROBOT_IP` and `robot_app kSpineBaseUrl` point at this session's IPs; the robot's adb/IP changes between sessions.

```bash
# Sync + baselines
git pull origin main
cd spine && npm install && npm test     # 51 pass; 2 MockRobotSDK *timing* tests are pre-existing flaky (mock-sdk/sensors)
npx tsc --noEmit                         # clean
```

### If you're on **Windows** → Path A (recommended)

Resolve **#54** first. Multi-file feature work (Phase 1.5) is unsafe while the orphan can silently rewrite messages. Diagnostic command in the task list above.

After #54 is resolved, Phase 1.5 (#43–#47) is fully runnable.

### Either machine — free wins that don't need #54 or Flutter

- **#48** mic volume monitoring (transient state, no Supabase logging — narrow surface)
- **#49** OTA + shutdown lifecycle (defensive, mock-only changes)
- **#51** SDK auth state (defensive banner)

Each is ~1–2h spine work, single-file diff. Safe to bundle as `chore:` commits.

---

## Cross-machine context

### Memory files (Windows-only, NOT in this repo)

The original Windows session built extended context in personal memory files at `C:\Users\Nishant\.claude\projects\<project-id>\memory\`. Two scopes:

**Git Bash session scope:**
- `timodesk-overview.md` — full architectural snapshot
- `timodesk-lidar-integration.md` — SDK research (raw LIDAR not exposed; high-level events are)
- `timodesk-sdk-roadmap.md` — ~70-listener CSJBot SDK inventory mapped to status
- Plus xboom-flow memos (separate project)

**VS Code Claude Code session scope (also Windows):**
- `timodesk-phase1a-sensors.md` — Phase 1A state + gotchas
- `git-history-orphan-rewriter.md` — #54 hazard fully diagnosed

**iMac doesn't have any of these.** This `HANDOFF.md` + `CLAUDE.md` are designed to be sufficient without them. If you (iMac Claude) need deeper context on a specific topic, ask the user to paste the relevant memory file's contents.

### Sync discipline

1. **Always `git push` before switching machines.** Habit: "switching laptops → push first."
2. **Always `git pull` before starting work on the other machine.**
3. **Update this file at end-of-session.** Replace `Last updated`, refresh "What just shipped" + "Pipeline status" + "Recommended next step". Commit as `chore: update session handoff`.

---

## Quick-reference paths

| What | Where |
|---|---|
| Phase 1A spine code | `spine/src/sensors.ts`, `spine/src/types.ts`, `spine/src/server.ts` |
| Phase 1A tests | `spine/tests/sensors.test.ts` |
| Mock synthetic emitter | `spine/src/robot/mock.ts` |
| Native bridge reference (NOT deployed) | `robot_app/docs/SENSOR_BRIDGE.md` |
| Wire-format fix (#53, DONE `7a19c83`) | `spine/src/server.ts` event handler · `app/lib/services/spine/spine_service.dart` · `viewer_web/index.html` |
| Phase 1B target (#42) | `app/lib/services/spine/spine_state.dart` (model) · `app/lib/features/control/widgets/` (new cards) · `control_screen.dart` (wire-in) |
| STOP state | `spine/src/commands/interlocks.ts` |
| Project context | `CLAUDE.md` |
| Status snapshot (older) | `PROJECT_STATUS.md` |
| Flutter app summary | `FLUTTER_APP_SUMMARY.md` |
| Known blocker | `ISSUE_EMAIL_RATE_LIMIT.md` |

---

## Update protocol

This file is a living doc. At end of every cross-machine session, refresh:

1. `Last updated:` line at top
2. "What just shipped" table — add new commits
3. "Pipeline status" — move completed tasks, add new ones, update blockers
4. "Recommended next step" — what should the next session start with
5. Any new critical gotchas

Commit as `chore: update session handoff` and `git push` before switching machines.
