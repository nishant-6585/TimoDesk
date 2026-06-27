# Milestone — Reception-app feature parity

Goal: bring the Timo reception experience into our own stack (admin app + spine +
robot_app), matching the vendor "Reception" app (`com.csjbot.csjbotscence`) feature by
feature. The vendor app is **not obfuscated** and uses the **same SDK singleton**
(`CsjRobot.getInstance().getAction()`) our `ChassisControlPlugin` already drives — so
nearly everything is replicable by calling `getAction()` ourselves, with **no vendor
cloud** for navigation (points/routes are local JSON). Full analysis:
[`RECEPTION_APP_FEATURES.md`](./RECEPTION_APP_FEATURES.md).

Prereqs (DONE this session): RobotSDK installed + AIDL transport + `move(direction)`
teleop → robot drives from admin & robot_app. `navi()` needs a loaded+localized SLAM
map and the robot off the dock.

---

## P0 — Navigation points (capture + go-to)  ★ start here
The core reception capability. From `SettingPointActivity`:
- **Capture a point:** drive robot to a spot → `getAction().getPosition(listener)` →
  `{x,y,z,rotation}` → name it → persist (Gson JSON).
- **Go to a point:** `getAction().navi("{x,y,z,rotation}")`; cancel via `cancelNavi()`.
- **Build:** native `getPosition` bridge + `navi(point)`/`cancel_navi` spine intents;
  store points in Supabase; admin UI to capture/name/list/edit/delete points and a
  one-tap "send robot to <point>". Robot_app shows arrival + speaks on arrival.
- Parity: ✅ pure SDK. Risk: requires a saved map + localization (operator step).

## P1 — Welcome point + auto-return
`WelcomePointActivity`: one designated point the robot idles at / returns to after a
task. `getAction().navi(welcome)` + `goHome()`. Wire into our idle state machine.
Parity ✅.

## P2 — Lead-the-way (one-key guidance)
`LeadingWayChooseTargetActivity` / `…OnTheWay`: pick a destination, robot leads a guest
there, talks en route, returns to welcome point. Ordered `navi()` calls + arrival
speech + return. Parity ✅.

## P3 — Guided tour ("expound" multi-point)
`ExpoundMultiPointsInRunningActivity`: visit an ordered list of points, play a
description/media at each, support pause/continue/skip. Sequence of `navi()` +
per-point content (store content in Supabase/KB). Parity ✅ (state machine in spine).

## P4 — Patrol routes
`Patrol*Activity`: scheduled loops over a saved route (security/rounds). Ordered
`navi()` on a schedule + obstacle/health events. Parity ✅.

## P5 — Interactive entertainment
`DanceActivity`/`MusicActivity`/`StoryActivity`: `getAction().startDance()/stopDance()`
+ Android media for songs/stories. Parity ✅ (media content is ours).

## P6 — Member / face registration & greet-by-name
NOT in the vendor app (it offloads to cloud). Our Phase-2 face stack (Supabase
pgvector + enrollment) already covers this — keep building ours. Parity = build-our-own.

## P7 — Manual customer service / human handoff
`CustomerHelpService`: remote teleop + live chat via vendor MQTT/cloud. Replace with
**our** Supabase realtime + WebRTC (admin already has live feed + teleop). Parity =
our-own (don't use vendor cloud).

---

## Cross-cutting follow-ups (not vendor features, but needed)
- **Battery telemetry via SDK:** robot-core has the real charge (`ROBOT_GET_BATTERY_RSP`,
  ~44%), but our SDK isn't subscribed — `ROBOT_SDK_AGENT_ENABLE` only enabled
  asr/slam/face. Add a periodic `getBattery` poll (or enable battery push) so robot_app
  + admin show the real % without the `battery-bridge.mjs` stopgap.
- **Person detection:** face module is enabled; confirm `OnDetectPersonListener` fires
  with a person in view (untested — no one in front during checks).
- **Map/localization UX:** `navi()` needs a localized map. Add an admin check/indicator
  for "map loaded + localized" and surface relocation state.

## Suggested order
P0 → (battery poll + person-detect confirm) → P1 → P2 → P3 → P5 → P4 → P7. P6 continues
on its own track.
