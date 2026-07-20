# Demo runbook — running Mikee on any network (hotspot / client site)

The stack is network-agnostic. It needs exactly three things anywhere:
1. Robot + Mac on the **same** network (spine ↔ robot is direct LAN traffic).
2. IPs repointed for that network (automated by `scripts/find_robot.sh`).
3. Internet on that network for Supabase features (points/staff/events lists).
   Robot control, camera, joystick, and navigation work **without** internet.

## Recommended network: your phone's hotspot

Client/guest Wi-Fi frequently has **AP isolation** (devices can't reach each
other) — that kills robot↔Mac traffic and you can't fix it. Your hotspot has
no isolation, gives internet for Supabase, and behaves the same at every venue.

## Setup sequence (~5 minutes)

1. **Start the hotspot** on your phone.
2. **Join the Mac** to the hotspot.
3. **Join the robot** to the hotspot: chest screen → Android Settings → Wi-Fi.
   (Forget other saved networks nearby to prevent mid-demo network hopping.)
4. On the Mac:
   ```bash
   cd ~/development/Xboom/Project/TimoDesk
   ./scripts/find_robot.sh          # finds robot, repoints spine/.env, app IPs,
                                    # and the robot's spine address (via adb)
   ```
   If adb isn't connected it prints the spine URL to enter manually in the
   Mikee app's settings screen on the robot (http://<mac-ip>:4000).
5. **Restart the spine**: `cd spine && npm run dev` (or `touch spine/src/index.ts`
   if tsx watch is already running).
6. **Run the admin**: `cd app && flutter run -d chrome` (recompiles with the
   new robot IP automatically). For a shareable LAN URL also run
   `flutter build web --release` and serve `build/web` on :8090.
7. **Robot app**: relaunch the Mikee app on the chest screen (it reconnects to
   the new spine address).
8. **Alpha Map check** (after any robot power-up): map loaded + robot's dot
   matches its physical position/heading; re-localize if not.

## Pre-demo smoke test (2 minutes)

- Dashboard shows ONLINE + live camera.
- Joystick drive responds.
- Go To a saved point → drives, arrives, speaks its announcement, green
  "Arrived" banner on both UIs.
- Cancel navigation from the web admin mid-drive → robot stops.

## Known gotchas

- **iPhone hotspot**: keep the Personal Hotspot screen open while devices join;
  disable "Maximize Compatibility" only if devices struggle to see each other.
- **Both devices must re-run step 4 whenever the network changes** — IPs are
  per-network.
- **Battery**: charge the robot fully; drive battery reads optimistically
  (the admin % is the head/tablet battery). Low charge → brownout reboots →
  the chassis nav wedge (see VENDOR_TICKET_NAV_FAULT.md). Bring the charger.
- **After any robot reboot**: re-localize in Alpha Map before navigating.
- If saved points / staff spin forever → that network has no internet
  (Supabase unreachable); control + navigation still work.
