# Mikee

> Smart reception app for the **Mikee robot** (Alpha Robotics / CSJBot platform). Built for **xboom Utilities Pvt. Ltd.** to staff their office reception autonomously — greet visitors, recognize staff, notify hosts, and be driven/monitored remotely.

Mikee turns a CSJBot service robot into a reception host: a live camera + drive controls, staff face enrollment & recognition, visitor check-in with host notifications, and an animated personality face on the robot's chest screen.

---

## Architecture

Three layers, with a single safety broker in the middle. **Clients never talk to the robot SDK directly** — every command flows through `spine` so safety interlocks live in one place.

| Layer | What | Where |
|---|---|---|
| **Edge** | CSJBot/Alpha Robotics SDK on the robot's Android 7.1.2 chest screen — camera, motors, sensors, chest-screen UI | `robot_app/` |
| **Cloud** | Node.js + TypeScript broker (port 4000) + Supabase (Postgres · RLS · pgvector) | `spine/` · `supabase/` |
| **Client** | Flutter admin app (web + iOS + Android, with an adaptive phone remote) + browser/mobile camera viewers | `app/` · `viewer_web/` · `viewer_mobile/` |

```
robot_app/          Flutter on the Mikee chest screen — MJPEG camera (:8080), battery (:8090),
                    motor-control WS receivers (:8081 head / :8082 chassis / :8083 arm),
                    staff enrollment, and the ambient "personality face" shell.
spine/              ★ TypeScript broker (:4000) — the central safety + routing layer.
                    MockRobotSDK (default) ↔ RealRobotSDK. Face recognition, host
                    notifications, FCM push, JWKS auth. Vitest-covered.
supabase/           8 migrations · RLS on every table · pgvector for face/KB embeddings ·
                    DPDP-compliant nightly purge.
app/                ★ Flutter admin — auth, dashboard, live feed, control, gallery, events,
                    settings, staff enrollment. Adaptive: phones get a remote-control layout.
viewer_web/         Single-file browser camera viewer (no server needed).
viewer_mobile/      Flutter mobile camera viewer (Android + iOS).
signaling_server/   WebRTC signaling (:3000) + serves viewer_web.
```

### Key design decisions

1. **Spine is the single broker.** All intents (`drive`, `head`, `arm`, `wave`, `stop`, `resume`, `snapshot`, `get_status`) flow through spine on :4000. Safety interlocks (STOP/RESUME) live in one place.
2. **Mock-first.** The whole stack is built against `MockRobotSDK`; swap to real hardware via `ROBOT_MODE=real`. New features must work against the mock before hardware integration.
3. **Stateless client.** The app sends intents and receives status; spine + Supabase own state. Closing the app mid-session is safe.
4. **DPDP compliance baked in.** Only **staff/employee** face data is stored, **opt-in with a consent timestamp**. The `visitor` table has **zero biometric fields**. Nightly auto-purge enforces retention.

---

## Current status

**Working (against the real robot + MockRobotSDK):**
- ✅ Live MJPEG camera, joystick drive, head/arm control, battery telemetry — on real hardware.
- ✅ **Staff face recognition** — enrollment (laptop webcam *or* robot chest screen) → spine `@vladmandic/face-api` 128-d embeddings → autonomous recognizer emits `face_detected` → live admin dashboard card. Margin-guard + temporal voting for precision.
- ✅ **Duplicate-face guard** during enrollment; staff view/edit/delete (DPDP erasure).
- ✅ **Visitor check-in → host notification** (`/visit` endpoint + notifier).
- ✅ **Production auth** — Supabase JWKS/ES256 verification via `jose`, real login gate, fail-closed by default.
- ✅ **Mobile remote** — adaptive phone layout (drive/head/arm, STOP/RESUME, live camera, status); FCM push code-complete (dormant until Firebase config).
- ✅ **Chest-screen ambient face shell** (P1) — animated face + tap-through feature dashboard (mock state; real perception is next).

**In progress / not yet built:**
- 🟡 Chest-screen face P2 (real perception: on-device gaze + spine greeting-by-name).
- 🟡 On-device mobile build (a pre-existing web-only-import break in `live_feed/` is being fixed).
- ⬜ Voice Q&A (STT + KB RAG + TTS), animated lip-sync, mapping/navigation, payment, advanced CV.

See **`HANDOFF.md`** for the live, detailed state and the task pipeline.

---

## Quick start

| Component | Commands |
|---|---|
| **Spine** (broker) | `cd spine && npm install && npm run dev` — MockRobotSDK by default |
| **Spine tests** | `cd spine && npm test` |
| **Admin app** (web) | `cd app && flutter pub get && flutter run -d chrome` |
| **Admin app** (mobile) | `cd app && flutter run -d android` (or `-d ios`) |
| **Robot app** (chest screen) | `cd robot_app && flutter build apk --debug && adb install build/app/outputs/flutter-apk/app-debug.apk` |
| **Viewer (web)** | open `viewer_web/index.html` in any browser |
| **Viewer (mobile)** | `cd viewer_mobile && flutter pub get && flutter run` |

**Spine env** (`spine/.env`): `SPINE_PORT` (4000), `ROBOT_MODE` (`mock`|`real`), `ROBOT_IP`, `SUPABASE_URL` + keys, `DEV_AUTH_BYPASS` (dev only — leave unset in prod with `NODE_ENV=production`). See `spine/.env.example`.

---

## Camera streaming

The robot app exposes the camera as an MJPEG server so any browser/phone on the same WiFi can view it.

### Run on the robot
```bash
cd robot_app
flutter pub get
flutter build apk --debug
adb install build/app/outputs/flutter-apk/app-debug.apk
# or, with the robot connected over USB:  flutter run
```
Open the chest-screen dashboard → camera tile → **START STREAM**; a stream URL + QR appear.

### Endpoints (robot, :8080)
| Path | Description |
|---|---|
| `/stream` | MJPEG stream (`multipart/x-mixed-replace`) |
| `/snapshot` | Single JPEG frame (used by the spine recognizer + quick testing) |
| `/` | Embedded HTML player |

### View it
- **Browser:** open `viewer_web/index.html`, enter the robot IP, **Connect**.
- **Phone:** `viewer_mobile` app, or scan the QR, or open `http://<robot-ip>:8080/stream`.
- **Admin app:** the Live Feed / Control / phone-remote screens embed the stream via the robot IP in Settings.

---

## Swapping the mock camera for the real CSJBot SDK

The mock camera (cycling RGB frames) lives in one place:

**`robot_app/android/app/src/main/java/com/mikee/robotapp/CameraStreamPlugin.java`**

Find `startCamera()` and the integration comment block:

```java
// ===== REAL SDK INTEGRATION POINT =====
// CsjRobot.getInstance().registerCameraListener(new OnCameraListener() {
//     @Override public void response(Bitmap bitmap) { pushFrame(bitmap); }
// });
// ===== END SDK INTEGRATION POINT =====
```

**Steps:**
1. Drop the CsjRobot SDK `.aar` into `robot_app/android/app/libs/`.
2. In `robot_app/android/app/build.gradle`:
   ```gradle
   dependencies { implementation fileTree(dir: 'libs', include: ['*.aar']) }
   ```
3. In `startCamera()`, replace the mock `cameraThread` block with the `registerCameraListener` call above (`pushFrame(Bitmap)` handles conversion).
4. Add SDK `init()` in `MainActivity.java` per the CsjRobot docs.
5. Rebuild and deploy.

The MJPEG server, Flutter UI, and viewers stay unchanged. (Sensor/motor bridges follow the same pattern — see `robot_app/docs/SENSOR_BRIDGE.md`.)

---

## Documentation map

| Doc | What |
|---|---|
| **`HANDOFF.md`** | ⚡ **Read first.** Live session state — what shipped, what's pending, the task pipeline. |
| `CLAUDE.md` | Durable architectural reference + conventions. |
| `PROJECT_STATUS.md` | Older long-form status snapshot. |
| `FLUTTER_APP_SUMMARY.md` | Admin app build details. |
| `MISSION_CONTROL_BUILD.md` | Mission Control dashboard build. |
| `robot_app/docs/CHEST_UX_REDESIGN.md` | Chest-screen ambient-face + dashboard design (#89). |
| `robot_app/docs/SENSOR_BRIDGE.md` | Native sensor-bridge reference (not yet deployed). |
| `docs/FIREBASE_SETUP.md` | Push-notification (FCM) setup — project `mikee`, remaining console steps. |
| `ISSUE_EMAIL_RATE_LIMIT.md` | Known dev blocker (Supabase email rate limit). |
| `supabase/migrations/` | Schema (8 migrations) — RLS, pgvector, retention. |

---

## Privacy & compliance (DPDP)

- **Only staff/employee biometrics** are stored, and **only with explicit consent** (`consent_at` timestamp). The recognition embedding lives in `staff_face_embedding` (the **only** biometric table).
- **No visitor biometrics, photos, or embeddings — ever.** Visitors are counted/checked-in anonymously (name + timestamps only).
- **RLS on every table**; nightly retention purge enforces DPDP limits.

---

*Mikee is xboom's first product — a reception-robot MVP. xboom builds land, air, and water robots for enterprise.*
