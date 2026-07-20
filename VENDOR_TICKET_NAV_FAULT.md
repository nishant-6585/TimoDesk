# CSJBot / Alpha Robotics support ticket — chassis navigation fault

**Robot:** Mikee reception robot, SN **6008**, chest unit `rk3576_u` (Android 14, build `UQ1A.240205.004.B1 eng.server.20251118-1155`)
**RobotSDK app:** `com.csjbot.robotsdk.ten` **i18n_2.5.3** · **Alpha Map:** `com.csjbot.robotstation` **V1.0.25**
**Date observed:** 2026-07-20 (recurrence of an identical incident on 2026-07-10)

## Summary

After an unclean/spontaneous reboot, the chassis navigation service permanently
stops executing `move_to` goals. Goals are **accepted** but the base never
receives a velocity command. The fault survives Android restarts and is only
(sometimes) cleared by a full power-off of the base. It reproduces in **your own
Alpha Map app**, so it is independent of our software.

## Symptoms (from live logcat on the robot)

- `move_to` accepted; ROS `action_status` either:
  - goes `code 2` (running) for 2–4 s then **`code -1` (aborted)**, or
  - sticks at `SlamMove: move_to N WAITING_FOR_START` indefinitely (task
    created, motion executor never starts), or
  - rotates in place at the start point without ever translating.
- `linear_velocity` / `angular_velocity` remain **0.00** throughout — no
  velocity command is ever issued. No path-planning or motor error is logged.

## Verified healthy at the same time (so NOT the cause)

- Teleop/manual drive works perfectly (base motors fine).
- Map loaded, `nav_ready: true`, localization `get_localization_quality`
  **level 5 / quality 1**, `reStatus 2`, pose tracks manual driving accurately.
- `e_stop: false`, `charge_status: 0` (off dock), battery > 60%.
- Reproduced identically from **Alpha Map → Navigation → tap point** with our
  application force-stopped.

## Trigger pattern

Both incidents (2026-07-10, 2026-07-20) began after an unexpected robot
reboot. Between incidents, navigation worked normally for extended periods.

## Questions for CSJBot

1. Is this a known chassis/base firmware issue, and does a firmware update
   exist that fixes `move_to` execution after unclean reboots?
2. What is the officially supported procedure (and image) to update the chassis
   firmware for SN 6008?
3. Is there a supported way to restart/reset the chassis motion service
   without a full base power-cycle?
4. What do `action_status` result codes (2, 5, -1, 0) and the
   `WAITING_FOR_START` state formally mean, so our integration can react
   correctly?

Full logcat captures from both incidents are available on request.
