# Chest-Screen Experience Redesign (#89)

> **Status:** DESIGN — not built. Owner: Nishant. Created 2026-06-19.
> **Read with:** `HANDOFF.md` #89 (pipeline entry), #82 (animated avatar), #80 (voice).
> This doc is the "designed properly" artifact requested before any Flutter code. Build
> against the contracts here so the Rive asset and the code agree.

---

## 1. Goal

Turn `robot_app` from a **utility** (MJPEG streamer + battery server + control receivers +
enrollment) into the robot's **front-of-house personality + interaction shell**. The chest
screen should *behave like a being*: an ambient animated face when idle, that reacts to
people walking by, greets identified staff by name, and on tap opens a feature dashboard
driven by tap + (later) voice.

**#89 is the CONTAINER.** The animated face (#82) and voice (#80) are engines that plug into
it. Face recognition (Milestone D, DONE) already provides the identity signal.

### What does NOT change

The existing background servers keep running untouched — this redesigns only the
**foreground UI**:
- MJPEG camera server (`CameraStreamPlugin`, :8080) — owns camera2.
- Battery HTTP server (`BatteryService`, :8090) — spine polls it.
- Control WS receivers — head :8081, chassis :8082, arm :8083.
- Native plugins + EventChannels (`streamProvider`, `headProvider`, `chassisProvider`,
  `armProvider`, `batteryProvider` in `main.dart`).

The current `_StreamScreen` content is **not deleted** — it is **repurposed** into the
Dashboard's "Robot Status" + "Manual Control" tiles (see §5).

---

## 2. Constraints

- **Android 7.1.2, modest GPU.** Keep animations GPU-light. This drives the Rive choice
  and "one face, simple shell, no heavy routing" decisions below.
- **One camera consumer.** `CameraStreamPlugin` owns camera2. Any on-device vision for the
  face MUST reuse the robot `/snapshot` endpoint (exactly like `enroll_screen.dart` does) —
  NEVER open a second camera.
- **One embedding pipeline.** Identity recognition stays on spine. On-device detection is
  for gaze/presence ONLY, never identity (a second recognition path is forbidden — same
  rule as enrollment).
- **DPDP.** Strangers/passersby are anonymous presence only — drive the eyes, store NOTHING
  (no frames, no embeddings). Greeting-by-name uses staff identity from the consented
  enrollment pipeline only.

---

## 3. ★ The central architecture decision — two perception pipelines, never crossed

The single thing that makes this feel alive vs. janky is **how the eyes know where to look
and who they're looking at.** Two signals, two jobs, two sources:

| Job | Needs | Source | NOT this |
|---|---|---|---|
| **Gaze** — eyes track a passerby | a *position*, real-time, zero latency | **On-device ML Kit** face-detect on robot `/snapshot` (bounding box, local, instant) | spine recognizer — polls ~1s, no box → eyes lag & jerk |
| **Identity** — greet staff by name | *who* it is, authoritatively | **spine** `face_detected` WS event (Milestone D) | on-device — would be a divergent recognition path (forbidden) |

**Net: local detection animates the face (responsive); spine recognition supplies the name
(authoritative).**

- Stranger walks by → on-device box moves the eyes; no identity → robot just watches
  (anonymous, stores nothing).
- Staff walks up → same gaze tracking, **plus** spine fires `face_detected{staff_id, name,
  distance}` → robot greets "Hi Rohit."

```
  robot /snapshot ──┐
   (poll ~300ms)    ├─► on-device ML Kit ──► face box ──► gaze x/y + "present" ──► FACE
                    │
  spine WS ─────────┴─► face_detected ─────► staff name ──► "greeting" state ───► FACE
   (Milestone D)                                                                   (#82)
```

> CSJBot `personDetected` (Phase 1A boolean) is a coarse presence fallback when no face box
> is available (someone present but not face-on).

---

## 4. State machine

Extends #82's avatar states with presence/identity/dashboard. Drives the Rive `state` input.

```
            ┌──────────────────────────────────────────────┐
            │                 ambient-idle                  │  ◄── default, ~99% of the time
            │      blink · subtle look-around · breathe     │
            └───────┬───────────────────────────────▲──────┘
       presence     │                                │  no presence 8s
       (face box)   ▼                                │
            ┌───────────────┐                        │
            │   attentive   │  eyes track gaze x/y ───┘
            └───┬───────▲───┘
   face_detected│       │ greeting done
   (staff)      ▼       │
            ┌───────────────┐
            │   greeting    │  "Hi <name>" + wave (arm SDK) + warm expression
            └───────┬───────┘
                    │ (voice, #80 — P3+)
                    ▼
       ┌────────────────────────────┐
       │ listening → thinking →      │  STT / RAG / TTS+lip-sync (#80/#82)
       │ speaking                    │
       └────────────────────────────┘

   ANY state ──(tap / "Hey Mikee, open dashboard")──► DASHBOARD ──(idle 30s / back)──► ambient-idle
```

Transitions:
- `ambient-idle → attentive`: on-device face box present.
- `attentive → greeting`: spine `face_detected` with a known staff_id (debounced — don't
  re-greet the same person within N minutes).
- `attentive/greeting → ambient-idle`: no presence for 8s.
- `* → dashboard`: tap anywhere on the face, or (P3) voice command.
- `dashboard → ambient-idle`: 30s idle timeout, or explicit back.
- voice states (`listening/thinking/speaking`): P3+, driven by #80 pipeline events.

---

## 5. Screens

### 5a. Ambient Face (new home — replaces `_StreamScreen` as `home:`)

- Full-screen **Rive** stylized face (see §6) on `#0F0F0F`.
- A small, low-contrast battery + connection chip in a corner (reuse `_BatteryIndicator` +
  `streamProvider.sdkStatus`) — present but unobtrusive; it's a robot, a little status is OK.
- Whole screen is one big tap target → Dashboard.
- A hidden long-press (e.g. 2s on a corner) as a discreet operator gesture is optional.

### 5b. Dashboard (on tap)

Full-stylized-face chosen, so the dashboard is the "serious controls" surface behind the
playful face. **2×2 grid of large tiles** + a placeholder row. Dark theme, orange accent
(`#FF6B35`), consistent with the app + admin.

```
   ┌─────────────────────┬─────────────────────┐
   │  👤 ENROLL STAFF     │  📊 ROBOT STATUS     │
   │  (existing           │  MJPEG · battery ·   │
   │   EnrollScreen)      │  SDK · sensor health │
   ├─────────────────────┼─────────────────────┤
   │  🎮 MANUAL CONTROL   │  ⚙️  SETTINGS         │
   │  head · chassis ·    │  spine URL · robot   │
   │  arm · e-stop        │  IP · kiosk config   │
   ├─────────────────────┴─────────────────────┤
   │  PLACEHOLDERS (disabled, "coming soon"):    │
   │  🗣 Voice Q&A · 💳 Pay · 🧭 Navigate ·       │
   │  📇 Directory                               │
   └─────────────────────────────────────────────┘
   [ ← back to face ]
```

**v1 real tiles (per decision) — all four wire to EXISTING code:**

| Tile | Backed by | Notes |
|---|---|---|
| **Enroll Staff** | `EnrollScreen` (`enroll_screen.dart`, #88 Part 2) | Already built — just a tile that pushes it. |
| **Robot Status** | `streamProvider` (MJPEG/FPS/clients/SDK) + `batteryProvider` + (later) sensor health | Repurpose `_StatusCard` + `_BatteryIndicator`. |
| **Manual Control** | `headProvider`/`chassisProvider`/`armProvider` | Repurpose `_HeadControlCard`, `_ChassisControlCard`, `_ArmControlCard`, sliders, e-stop. Move the current `_StreamScreen` control widgets here. |
| **Settings** | spine URL / robot IP / kiosk config | New small screen; persist via SharedPreferences. Surface `kSpineBaseUrl`/`kCameraBaseUrl` from `enroll_screen.dart` here instead of hardcoded consts. |

**Placeholders (disabled tiles, labeled "coming soon"):** Voice Q&A (#80), Pay (#85),
Navigate (#83), Directory. They exist so the dashboard reads as "complete with room to grow"
and the layout doesn't churn when features land.

---

## 6. The face — full stylized character (per decision)

Eyes + mouth + brows from the start (not eyes-only, not an abstract orb). Cozy, friendly,
slightly cartoon — think a warm reception host, not uncanny-realistic.

### Rive input contract (build P1 against this; the asset + code must agree)

| Input | Type | Range | Meaning |
|---|---|---|---|
| `state` | enum/number | 0..6 | 0 idle, 1 attentive, 2 greeting, 3 listening, 4 thinking, 5 speaking, 6 sleepy/dim |
| `gazeX` | number | -1..1 | horizontal eye target (-1 left … 1 right) |
| `gazeY` | number | -1..1 | vertical eye target (-1 up … 1 down) |
| `blink` | trigger | — | one blink (code fires on a randomized 2–6s timer) |
| `mouthOpen` | number | 0..1 | mouth openness — amplitude-driven lip-sync (P4) |
| `expression` | enum/number | 0..n | neutral / happy / curious / surprised (greeting = happy) |
| `talking` | bool | — | speaking animation on/off (P4) |

Rules:
- Code owns timing (blink timer, gaze smoothing, idle micro-movements); Rive owns the art.
- **Smooth gaze:** lerp `gazeX/gazeY` toward the target (don't snap) — this is the
  difference between "alive" and "twitchy."
- Idle micro-motion: small random gaze drift + occasional blink so it never looks frozen.

### Tech

- **Rive** (`rive` Flutter package) — state-machine character, named inputs above,
  GPU-light enough for Android 7.1.2. (Lottie / `CustomPainter` are fallbacks if Rive
  authoring is a blocker, but Rive is the recommendation.)
- The `.riv` asset is a **design task** (Rive editor) — P1 can ship with a **placeholder
  face** (simple `CustomPainter` two-eyes-and-mouth wired to the same input contract) so
  code progresses before the polished asset exists. Swap the painter for the `.riv` later
  without touching the state wiring.

---

## 7. Phasing

| Phase | Scope | Hardware? | Depends on |
|---|---|---|---|
| **P1** | App shell (AmbientFace ↔ Dashboard, tap-to-open, idle-return) + face with **mock state** (debug toggle cycles all states) + the 4 real dashboard tiles wired to existing providers + placeholder tiles | **No** — buildable now | — |
| **P2** | Real perception: local ML Kit `/snapshot` detect → `gazeX/Y` + `attentive`; spine `face_detected` WS → `greeting`-by-name (debounced) | Yes (robot) | recognizer (done), `/snapshot` |
| **P3** | Voice commands: wake/STT → `listening`/`thinking`/`speaking`; voice nav of dashboard | Yes | #80 |
| **P4** | Lip-sync: amplitude-driven `mouthOpen` + `talking` from TTS audio | Yes | #80 TTS, #82 |

**Start with P1.** It's self-contained, hardware-free, demoable, and establishes the shell +
the Rive contract everything else plugs into.

### P1 acceptance criteria

- [ ] App opens to the **Ambient Face** (not the old `_StreamScreen`).
- [ ] Face shows idle life: randomized blink + subtle gaze drift.
- [ ] A **debug control** (hidden gesture or debug-build button) cycles `state` through
      idle → attentive → greeting → listening → thinking → speaking, and nudges `gazeX/Y`.
- [ ] Tapping the face opens the **Dashboard**; 30s idle (or back) returns to the face.
- [ ] Dashboard shows the **4 real tiles** — Enroll Staff (pushes `EnrollScreen`), Robot
      Status (live MJPEG/battery/SDK from existing providers), Manual Control (head/chassis/
      arm/e-stop from existing providers), Settings — plus **disabled placeholder tiles**.
- [ ] Background servers still run (MJPEG :8080, battery :8090, control :8081-3) — verify
      the admin app + spine still reach the robot exactly as before.
- [ ] No second camera opened; `/snapshot` untouched in P1 (perception is P2).
- [ ] Debug APK builds; runs on the robot's Android 7.1.2 without frame-rate collapse.

---

## 8. Open questions (decide before P2+)

- **Greeting debounce window** — how long before re-greeting the same staff member? (default
  suggestion: 10 min.)
- **`/snapshot` poll cadence for gaze** — 300ms is responsive but costs CPU on a modest
  device; tune on hardware (P2).
- **Voice engine** (#80) — STT/TTS/wake-word vendor; out of scope until #80 is scoped.
- **Rive asset ownership** — who authors the `.riv` (designer vs. Nishant in Rive editor).
  P1 ships with the placeholder painter regardless.
- **Operator access to Manual Control** — should it be gated (PIN/long-press) so a curious
  visitor can't drive the robot from the dashboard? Likely yes for production.
