# Drive-to-Point — On-Site Verification Checklist

> **Purpose:** Prove `navi()` actually moves the chassis to a saved point on the physical Mikee, and confirm Phase 1's arrival detection + map-ready signals fire correctly. This is the supervised hardware gate that Phase 2 (guided experiences) is blocked on.
>
> **Run this with the robot in front of you, off the dock, in an open area.** Nobody should build lead-the-way / patrol until this passes.

---

## What Phase 1 gives you to watch

During this test, the admin nav screen and the robot's own nav screen expose three new signals — use them, they're the whole point:

| Signal | Where | Means |
|---|---|---|
| **Map-Ready pill** — "Map Ready" vs "No Map · Localizing" | Top bar, next to chassis pill | `isNaviReady` from the SDK. Go-to is only possible when this is green. |
| **Spoken "I've arrived at X"** | Robot speaker (CSJBot TTS) | Arrival detected from `moveResult`. **This is the heuristic under test.** |
| **Green arrival banner** | Admin nav screen | Same arrival event, visual confirm. |

---

## Pre-flight (do these IN ORDER — most failures are here, not in code)

- [ ] **RobotSDK app running** on the chest screen (cos server on `:60002`). If not up, nothing connects. See `sdk-connection-debug-checklist`.
- [ ] **Robot OFF the charger.** It will not drive while charging. (Battery % in admin is head/tablet, not drive battery — ignore it; confirm real charge on the robot core.)
- [ ] **E-stop released** (physical button not engaged).
- [ ] **SLAM map loaded** for this location.
- [ ] **Localization done** — robot knows where it is on the map. Watch the Map-Ready pill flip to **green**.

> ⚠️ If the Map-Ready pill never goes green: the CSJBot nav/chassis service is down (SLAM never becomes ready, nav queries never call back). This is the known `chassis-nav-service-not-responding` failure — it's **operational** (re-dock / power-cycle / reload map), not a code bug. Do not proceed until the pill is green.

---

## Test A — Admin "Go" (the WS/spine path)

1. [ ] Confirm at least one saved point exists (capture one at the robot's current spot if needed).
2. [ ] Stand clear. Tap **Go** on a point ~2–3 m away.
3. [ ] **Observe:** chassis pill shows nav in-progress; robot physically drives toward the point.
4. [ ] **On arrival:** robot speaks "I've arrived at X" **and** green banner appears in admin.
5. [ ] **Tap Cancel mid-drive** on a second run → robot stops, no false arrival speech.

**Record for each run:**
- Did it physically reach the point? (Y / N)
- Did arrival speech fire? Too early / on time / never?
- Did the banner match the speech?

---

## Test B — On-Robot "Go" button (the MethodChannel path, the Phase 1 bug fix)

This path previously called `navi()` with **no callback** → silent, no arrival feedback. Phase 1 wired the callback. Confirm it now behaves like Test A.

1. [ ] On the robot's own nav screen, tap **Go** on a point.
2. [ ] **Observe:** same lifecycle feedback as admin — drives, then speaks + shows arrival.
3. [ ] Cancel mid-drive → clean stop, no false arrival.

---

## The one thing that needs your eyes: arrival-detection tuning

Phase 1 detects arrival with a **permissive heuristic** on the SDK's `moveResult` JSON, because the exact arrival payload isn't documented. This test is where we learn the truth.

- [ ] **Capture the raw `moveResult`** the SDK emits at the moment of arrival (log it / screenshot it). Note whether the speech fired **early, exactly on arrival, or not at all**.
- [ ] If early/late/missing → send me the raw payload and I'll tighten the heuristic to the real field. **One good capture is all I need.**

---

## Pass criteria (all must hold)

- [ ] Map-Ready pill correctly reflects localized / not-localized state.
- [ ] Robot physically reaches the target point via **both** Admin and On-Robot Go.
- [ ] Arrival speech fires **on** arrival (not early, not never) and matches the banner.
- [ ] Cancel produces a clean stop with **no** false arrival.
- [ ] Raw arrival `moveResult` captured (so the heuristic can be locked).

**When all boxes are checked → the drive-to-point foundation is verified and Phase 2 is unblocked.**

---

## If something fails

| Symptom | Likely cause | Reference |
|---|---|---|
| Map-Ready never green | SLAM/nav service down | `chassis-nav-service-not-responding` (operational) |
| Nothing connects at all | RobotSDK app / socket | `sdk-connection-debug-checklist` |
| Won't move despite green pill | On charger / e-stop / localization | Pre-flight steps above |
| Arrival speech wrong timing | Heuristic needs real payload | Capture `moveResult`, send to me |
