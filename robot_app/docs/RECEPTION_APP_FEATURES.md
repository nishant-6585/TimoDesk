# Reception App (`com.csjbot.csjbotscence`) — Feature-Parity Report

> Source of truth: decompiled vendor "AlphaApp / Reception" app at
> `/tmp/reception/src/sources/com/csjbot/csjbotscence/` (728 Java files, **not obfuscated** — only
> lambda helper classes are mangled; all real class/method names are readable).
> Cross-referenced against the CSJBot SDK source at
> `…/Timo/SdkDemoCsj/newSceneSDK/src/main/java/com/csjbot/coshandler/`.

## How the vendor app talks to the robot

The app **never calls the SDK directly from Activities**. It layers two wrappers over the SDK
singleton `CsjRobot.getInstance()`:

```
Activity
  → ReceptionRobot.getInstance()        (com.csjbot.baseagent.ui_robot.ReceptionRobot)
      → StateMachineHandler.getInstance()  (state machine: welcome/expound/patrol/lead states)
      → CsjRobotPrivate                     (thin pass-through)
          → CsjRobot.getInstance().getAction()   ← the real SDK (com.csjbot.coshandler.core.Action)
```

Key fact for us: **`Action` (the SDK) is the same object our `ChassisControlPlugin` already uses**
(`CsjRobot.getInstance().getAction().move()/setNaviMode()/setSpeed()`). The vendor's
`ReceptionRobot` + `StateMachineHandler` are just orchestration/UX glue on top of the *same* SDK
methods — `navi()`, `getPosition()`, `goHome()`, `loadMap()`, `getMapList()`, `setNaviMode()`. We
can replicate every robot-motion behavior by calling `getAction()` directly; we do **not** need the
vendor's state machine, and there is **no cloud ("Little Bee") dependency** for navigation — all
point/route data is stored locally in **SharedPreferences as Gson JSON**.

### The SDK navigation surface (from `IChassisReq.java` / `Action.java`)

| SDK method | Purpose | Direction/arg semantics |
|---|---|---|
| `getPosition(OnPositionListener)` | **read current pose** | callback returns JSON `{x,y,z,rotation}` |
| `move(int dir)` | continuous hold-to-drive | 0=fwd 1=back 2=left 3=right (`NAVI_ROBOT_MOVE_REQ`) |
| `moveAngle(int deg, listener)` | rotate by relative angle | >0 left, <0 right |
| `goAngle(int deg)` | turn to absolute angle | — |
| `setSpeed(float)` | nav speed | 0.3–1.2 |
| `navi(String json [,OnNaviListener])` | **navigate to a pose** | json = `{x,y,z,rotation}` floats |
| `cancelNavi(OnNaviListener)` | abort current navi | — |
| `goHome(OnNaviListener)` | return to charging dock | — |
| `loadMap(name[,x,y,r])` | load SLAM map / relocalize at pose | — |
| `saveMap(name)` / `getMapList(listener)` | save / enumerate maps | — |
| `setNaviMode(int)` | 1 = manual/track mode (direct move) | — |
| `getDockerState` / `getMapState` | dock & map-recovery status | — |

---

## Navigation & Points  ★ (highest priority)

### What it does
A point is a named SLAM pose (X/Y/rotation in map coordinates) plus a large bag of reception
metadata (greeting text, arrival speech, photo/video, background music, wait time). Points are the
atomic unit reused by **every** higher feature: lead-the-way, expound/tour, patrol, welcome.

### Data model
- **`bean/Position.java`** — the pose. Fields: `x`, `y`, `z`, `rotation` (all **`String`**),
  plus `name`, `sn`. `toJson()` emits `{"x":<float>,"y":<float>,"z":0,"rotation":<float>}` — this
  is exactly the string passed to `navi()`.
- **`bean/NaviBean.java`** — a point = `Position pos` + UX metadata: `name`, `nickName`,
  `startTip`/`arriveTip` (speech), `description`/`descContent`, `pointImgPath`,
  `runningVideoUrl`, `backgroundMusicUrl`, `waitTime`, `isOnTheMap`, a random `id` (UUID).
- **`entity/RosPosition.java`** — float `{x,y,z,rotation}` used by the SDK-facing `navi()` call
  (`SlamCtrlImpl.navi()` does `getAction().navi(new Gson().toJson(rosPosition))`).
- **Persistence:** SharedPreferences, file `scj_sp_file`, key
  **`NAVI_NAME`/`NAVI_KEY`** (`SharedKey.java`) holding `Gson().toJson(List<NaviBean>)`. No DB, no
  cloud. (`bean/Position.java` references `DBManager` only for default-value constants, not storage.)

### ★ HOW A NAVIGATION POINT IS SET PER LOCATION — full traced flow

Screen: **`SettingPointActivity.java`** (title `set_point_position`). Step by step:

1. **Drive the robot to the physical location.** (Manual teleop / chassis d-pad → `getAction().move()`.)
2. **Capture the current pose.** User taps "Acquire point" (`R.id.bt_acquire_point`).
   `SettingPointActivity.onViewClicked()` (line ~769) calls
   **`ReceptionRobot.getInstance().UiDoGetPoseInfo()`**
   (guarded by `isConnectedToSDK()` + `HomeService.isConnectNav`).
3. That routes `StateMachineHandler.UiDoGetPoseInfo()` (line 205) →
   `SlamCtrlImpl.getPoseInfo()` (line 63) →
   **`CsjRobot.getInstance().getAction().getPosition(OnPositionListener)`** (line 67).
4. The SDK answers via `OnPositionListener.positionInfo(json)` (`SlamCtrlImpl$2`) →
   `StateMachineHandler.getPoseCallUI(json)` (line 420) → fires the registered
   `OnReceptionRobotPoseListener.getPose(json)` (ReceptionRobot line 655).
5. `SettingPointActivity.lambda$new$2` (line 1085) parses the JSON:
   `x`, `y`, `z`, `rotation` → builds a `Position`, calls
   `naviBeanTemp.setPos(position)`, and posts `handler` msg `12` to fill the
   `etPointX/Y/R` text fields. (In non-real-robot mode it stubs `0.1/0.2/0.3`.)
6. **Name & describe it.** User types the point name (`etPointName`), nickname, start/arrival
   speech, optional image/video/music. Default speech is auto-generated from the name
   ("到达 <name> 了！" / "请跟我到 <name> 吧").
7. **Save.** `savePoint()` (line 866): validates name + that `pos != null`, dedupes against
   existing names, then **persists the whole list**:
   `SharedPreUtil.putStringCommit(NAVI_NAME, NAVI_KEY, Gson().toJson(navis))` (line 968).
   If editing, it also rewrites any route that references the point id (`changeNaviLineData`).

### ★ HOW THE POINT IS LATER USED FOR NAVIGATION
- Load points: `DataBuilder.buildNaviPoints()` reads `NAVI_NAME/NAVI_KEY` back into `List<NaviBean>`.
- Navigate to a point: take its `pos`, serialize, and call **`navi(json)`**:
  - `ReceptionRobot.naviToPoint(json)` (line 1562) → `CsjRobotPrivate.naviToPoint` (line 615) →
    **`CsjRobot.getInstance().getAction().navi(json)`**.
  - Higher flows (`SlamCtrlImpl.navi(name, id, RosPosition)`, line 104) call the same
    `getAction().navi(...)` after copying `Position` → `RosPosition`.
- The robot reports progress through `OnNaviListener` and `slamTargetGoing/slamTargetArrived`
  (`SlamCtrlImpl` lines 36–43), which the state machine turns into "arrived → speak → wait" UX.

**Parity:** ✅ **Fully replicable via SDK.** Capture = `getAction().getPosition(listener)`;
navigate = `getAction().navi("{\"x\":..,\"y\":..,\"z\":0,\"rotation\":..}")`. Persist points
yourself (SharedPreferences / our spine+Supabase). No vendor-only path, no cloud.
Map prerequisite: a SLAM map must be loaded and localized (`loadMap`, `getMapState`) and
`setNaviMode` appropriate for navigation — note the vendor uses `navi()` for autonomous
goto, distinct from the manual `setNaviMode(1)` + `move()` teleop our `ChassisControlPlugin` uses.

---

## Welcome / Reception greeting (迎宾)

### What it does
A single saved "welcome point" the robot returns to and stands at to greet visitors (greeting
video loop `back_1.mp4`/`back_cicle.mp4` + speech). Triggered on idle/auto-return/full-battery.

### Data model & persistence
- Welcome point saved as an `ExpoundPosition` array under SharedKey **`YINGBIN_NAME`/`YINGBIN_KEY`**
  (`NaviSettingActivity` line ~373: `SharedPreUtil.putString(YINGBIN_*, GsonUtils.objectToJson(arrayList))`;
  cleared via `removeString`). `entity/ExpoundPosition.java` wraps a `RosPosition` + name + `busynessId`.
- Capture uses the **same `UiDoGetPoseInfo()` → `getPosition()`** flow as points
  (`NaviSettingActivity` lines ~305–377).

### Key SDK calls
- Go to welcome point: `ReceptionRobot.UiDoGoWelcome(RobotAction)` (e.g. `ScoringPageActivity` line 333),
  internally a `navi()` to the welcome pose.
- Greeting: `ReceptionRobot.startSpeak(...)` / `stopSpeaking()`, body/arm waves
  (`WelcomePointActivity` lines ~243, 309); pause on touch via `UIDoPauseWelcome()` (line 178).
- Listener `OnReceptionRobotGoWelcomeListener` for arrived/paused states.

**Parity:** ✅ Replicable. Welcome point = one saved pose + `navi()` to it + TTS + wave.
We already have wave/TTS; just persist one pose and `navi()` to it. No cloud.

---

## Lead-the-way / Guidance (带领/引导)

### What it does
Robot leads a visitor to a chosen destination point, with start/arrival speech, pause/continue,
and "take me back" to the welcome point.

### Data model & persistence
- Guide destinations stored under SharedKey **`LEADING_WAY_KEY`/`LEADING_WAY_POINT`**
  as `Gson().toJson(List<NaviBean>)` (`SettingLeadActivity` line ~79 read,
  `SettingLeadAddPointActivity` line ~499 write).
- Point capture in `SettingLeadAddPointActivity`: same `UiDoGetPoseInfo()` → pose-listener →
  `naviBeanTemp.setPos()` → save (lines ~412, 507–531).
- Runtime task objects: `LeadingWayTask`, `entity/LeadingWayPosition` (target pose + welcome pose).

### Key SDK calls (all via `ReceptionRobot`, all ultimately `getAction().navi()`/`cancelNavi()`)
- Start: `UIDoStartLeadingWay(RobotAction)` (`LeadingWayChooseTargetActivity` line ~230), after
  `currentAction.setWelComePoint(...)` + `setLeadingWayTask(...)`.
- Pause/continue/cancel: `UIDoPauseLeadingWay()` / `UIDoContinueLeadingWay()` / `UiDoCancel()`
  (`LeadingWayOnTheWayActivity` lines ~147, 164, 308).
- Finish / go back: `UIDoLeadingWayFinished()` (line 282) / `UIDoLeadingWayGoBackWelcome(RobotAction)` (line 311).

**Parity:** ✅ Replicable via SDK. Lead-the-way ≈ `navi(destination)` then on-arrival `navi(welcome)`,
with cancel = `cancelNavi()`. The vendor's pause/continue is state-machine UX we can re-implement
in the spine. No cloud.

---

## Expound / Guided multi-point tour (讲解)

### What it does
An **ordered route** of points the robot visits in sequence, narrating at each ("讲解"). Supports
per-point media (image/video), background music, in-transit speech, and a wait/dwell time.

### Data model & persistence
- A route = **`bean/RouteBean.java`** = `routeName` + `CopyOnWriteArrayList<NaviBean> naviList`.
- Persisted under SharedKey **`ROUTE_NAME`/`ROUTE_KEY`** as `Gson().toJson(List<RouteBean>)`
  (`NewRouteActivity` builds/saves; `RouteSelectActivity` + `DataBuilder.buildRouteList()` load).
- Points themselves are the same `NaviBean`s saved under `NAVI_KEY`; a route just references them.

### Key SDK calls (via `ReceptionRobot`, → `navi()` per leg)
- Start tour: `UiDoStartExpound(RobotAction)` (`RouteSelectActivity` line ~991,
  `ExpoundMultiPointsInRunningActivity` line ~640) — `currentAction` carries the ordered
  `ExpoundPosition` list (`setExpoundList`).
- Advance: `UiDoExpoundOneFinished()` (arrived & done narrating; lines ~856/876/918),
  `UiDoNextPoint()` (`DescInRunningActivity` line ~898), `UIDoExpoundBeforeGoFinished()` (line ~950).
- Pause: `UiDoPause()`. End → `UiDoGoWelcome()`.

**Parity:** ✅ Replicable. A tour is just an ordered list → loop `navi(point[i])`, wait for
arrival callback, narrate, advance. State machine = our spine. No cloud.

---

## Patrol routes (巡逻)

### What it does
Autonomous, optionally **scheduled** (day-of-week + start/end time) loop over waypoints; can take a
photo on arrival; on completion returns to charging dock or welcome point.

### Data model & persistence
- **`bean/PatrolBean.java`** = `lineName` + `List<Position>` + timing (start/end H:M) +
  `DayEntity` days + start/transit/end tips + audio paths + `backType` (dock vs welcome).
- Routes under SharedKey **`PATROL_ROUTE_NAME`/`PATROL_ROUTE_KEY`**; patrol points under
  **`PATROL_POSITION_NAME`/`PATROL_POSITION_KEY`** (both `Gson().toJson(...)`).
  (`PatrolSettingActivity` ~140/109 read/write routes; `PointConfigurationActivity` ~229/472
  read/write points.)
- Point capture in `PointConfigurationActivity`: same `UiDoGetPoseInfo()` → pose-listener →
  `positionBean` → save (lines ~292, 482–503, 472).
- Runtime: `PatrolTask`, `entity/PatrolPosition`, scheduling driven by **`PatrolService.java`**
  (a foreground Service polling the schedule).

### Key SDK calls (via `ReceptionRobot`, → `navi()` per waypoint)
- `UIDoStartPatrol(RobotAction)` / `UIDoAddNewPatrolTask` (`PatrolService` ~329/327),
  `currentAction.setExpoundList(...)`, `setPatrolTaskOverType(GO_WELCOME|GO_CHARGE)`,
  `setWelComePoint(DataBuilder.buildWelcome())`.
- Control: `UIDoPatrolContinue()` / `UIDoPatrolCancel()` (`PatrolActivity` ~132/264),
  `UIDoPatralTaskFinished()`.
- Listener `OnReceptionRobotPatrolListener`: `patrolGoingToTarget`, `patrolArrived` (photo capture),
  `allpatrolFinished(PatrolTaskOverType)` → `goHome()` or welcome.

**Parity:** ✅ Replicable. Patrol = scheduled expound loop. Scheduling + photo-on-arrival live in
our spine/robot_app; motion = `navi()` per waypoint; finish = `goHome()`. No cloud.

---

## Manual customer service / Teleop

### What it does
A remote/manual operator can drive the robot, pose it, send it to a named point, and hand off to a
human agent. Implemented in **`customer/CustomerHelpService.java`** (NOT `ManualPositionActivity`).

### Key SDK calls (`CustomerHelpService.java`)
- Drive: `ReceptionRobot.moveForward()/moveBack()` (lines ~211/213),
  `moveAngle(7)/moveAngle(-7)` rotate (~215/217) → SDK `move()` / `moveAngle()`.
- Pose: `setBodyAction(part, action)` (~238), `setExpression(id,once,time)` (~231).
- Go to point: `naviToPoint(naviBean.getPos().toJson())` (~255) → `getAction().navi()`.
- Human handoff: `interventionCustomer()` (~268) / `unInterventionCustomer()` (~283) →
  `CsjRobot.getInstance().getmCustomer().humanInterventi(SN)` etc. (ReceptionRobot ~1570–1586).
  Sets `BaseConstans.sIsCustomerIntervened`, sends MQTT-style `ROBOT_HUMAN_INTERVENTI_NTF`.

> **Correction:** `settings/ManualPositionActivity.java` is **not** robot teleop/relocation — it is a
> **Baidu Map** geographic address picker (sets the robot's *physical street address* for
> weather/location services). Its `manual_position_relocation_success` toast is about saving that
> address, not SLAM relocalization.

**Parity:** ✅ Teleop already done in our `ChassisControlPlugin` (`move()` + `moveAngle()` +
`setNaviMode(1)`). "Go to point" = `navi()`. ⚠️ **Human-agent handoff** (`getmCustomer()…humanInterventi`)
is a **vendor cloud/MQTT customer-service backend** — replace with our own Supabase/WebRTC handoff,
do not depend on the CSJBot customer cloud.

---

## Interactive entertainment

| Screen | What | Key calls |
|---|---|---|
| `entertainment/DanceActivity.java` | canned dance + music + animation video | `getAction().startDance()` (line ~104) / `stopDance()` (~173); `audioUtil.play(url)`; `videoMusic.start()` |
| `entertainment/MusicActivity.java` | jukebox; announces song then plays | `speak(songName, listener)` (~141); `audioUtil.play(volume,url,…)` (~158) |
| `entertainment/StoryActivity.java` | story audio + waveform animation | `mediaPlayer.setDataSource(url)` (~194) / `start()` (~214); `mVoiceWave.start()` |

**Parity:** ✅ `startDance()/stopDance()` are plain SDK body actions; everything else is Android
media playback we fully control. No cloud (media is local/asset URLs). Lowest robotics value.

---

## Other / Hospital / Scoring (lower priority)

- `hospital/PreConsultationActivity.java` — symptom/body-part intake form (vertical-screen
  "pre-consultation" use case); not face registration, not navigation. Vertical-market UX only.
- `visit_route/ScoringPageActivity.java` — 1–5 star satisfaction rating after a tour; different TTS
  per score; logs `sendRobotStatesMSG(Contants.NAVI_APPRAISE,"")`; then `UiDoGoWelcome()`.

### Face / member registration — **NOT present in this app**
A full-tree grep found **no** face/member registration UI in `com.csjbot.csjbotscence`. The SDK
exposes `CsjRobot.getInstance().getFace()` (used here only for `startVideo()/stopVideo()` camera
preview and `getFaceVersion()` for version reporting). Face *recognition* enrollment is not part of
the Reception app — it would be a separate module / the vendor cloud. (Matches our Phase-2 plan to
build face recognition ourselves.)

---

## Recommended implementation plan for our app

Priority order, with exact SDK calls. All motion goes through the spine intent layer (keep the
single-broker safety model); the native bridge just exposes these `getAction()` methods.

### P0 — Navigation point capture + go-to-point (unlocks everything)
This is the user's explicit ask and the foundation of lead/tour/patrol/welcome.
1. **New native methods in `ChassisControlPlugin` (or a sibling `NavPlugin`):**
   - `getPose()` → `CsjRobot.getInstance().getAction().getPosition(listener)`; return the
     `{x,y,z,rotation}` JSON up to Flutter.
   - `naviToPose(x,y,rotation)` → `getAction().navi("{\"x\":x,\"y\":y,\"z\":0,\"rotation\":r}")`
     with an `OnNaviListener` to stream going/arrived/failed.
   - `cancelNavi()` → `getAction().cancelNavi(listener)`; `goHome()` → `getAction().goHome(listener)`.
   - Map readiness: `getMapList()`, `getMapState()`, and `loadMap(name)` (we already log these).
2. **New spine intents:** `{intent:'get_pose'}`, `{intent:'save_point', name, pose, meta}`,
   `{intent:'navi', pointId|pose}`, `{intent:'cancel_navi'}`, `{intent:'go_home'}`.
3. **Point store:** keep the vendor's `Position`/`NaviBean` *shape* (x/y/rotation + name + speech +
   media) but persist in **Supabase**, not SharedPreferences — gives us the admin UI + multi-robot.
   Our spine sends the pose JSON to the SDK; SharedPreferences only if we want on-robot offline cache.

**Risk/gaps:** `navi()` requires a **loaded, localized SLAM map**. Before any goto we must:
load the map (`loadMap(name[,x,y,r])`), confirm `getMapState`/`naviReady`, and ensure the robot is
**off the dock** (dock locks motors — we already surface `getDockerState`). Map *creation* (SLAM
mapping/`saveMap`) is a vendor/operator step done once; we should not try to remap from our app.
Distinguish nav-mode: autonomous `navi()` vs manual `setNaviMode(1)+move()` (our current teleop).

### P1 — Welcome point + auto-return-to-greet
One saved pose + `navi()` to it + wave + TTS (we have wave+TTS). Trigger on idle/auto-return.
Replaces the vendor `YINGBIN_*` flow. Pure SDK.

### P2 — Lead-the-way
`navi(destination)` → on arrival speak → `navi(welcome)`; cancel = `cancelNavi()`. Pause/continue is
spine-side state, since the firmware itself only exposes navi + cancel. Pure SDK.

### P3 — Guided tour (expound) + Patrol
Ordered list loop: `navi(point[i])` → await arrival → narrate/photo/wait → advance; finish =
`goHome()` or welcome. Patrol adds a scheduler (day/time) in the spine + foreground service.
Both are pure SDK once P0 exists. Photo-on-arrival reuses our MJPEG/camera path.

### P4 — Entertainment (dance/music/story)
`getAction().startDance()/stopDance()` + Android media. Low robotics risk, low business value;
build only if reception demo wants it.

### Explicitly do NOT depend on vendor cloud
- **Human-agent handoff** (`getmCustomer().humanInterventi/callHumanService`) — vendor MQTT/cloud
  customer-service. Build our own (Supabase + our WebRTC/viewer) instead.
- **Face/member registration** — not in this app; our Phase-2 face module is the right path.
- `ManualPositionActivity`'s Baidu-map address picker — irrelevant to robot control; skip.

### What we already have (no work needed)
Manual teleop (`move()` hold-to-drive + `moveAngle()` rotate), `setSpeed()`, `setNaviMode(1)`,
wave, head/arm body actions, MJPEG camera, battery, dock/map diagnostics — all in
`ChassisControlPlugin` and the existing spine pipeline.
