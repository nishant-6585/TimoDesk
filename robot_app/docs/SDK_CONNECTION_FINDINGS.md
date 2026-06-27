# CSJBot SDK ↔ robot-core connection — findings & fix (2026-06-27)

## Symptom
robot_app's CSJBot SDK receives **no robot-state callbacks**: battery shows the
Android head/tablet value (~50%), person detection is silent/inconsistent, and the
chassis never reports nav-ready (drive blocked). All three are the *same* failure:
the SDK never connects to robot-core.

## Root cause — APP-SIDE REGRESSION (fixed)
The SDK reaches robot-core through a **Netty "cos" client**
(`HandlerMsgSocketService` → `CosClientAgent` → `CosConnectorNetty.connect(defaultIp,
defaultPort)`), enabled by `useSocket=true` which `setIpAndrPort()` sets.

Two things were broken, both lost when the SDK was switched from a project module to
a **bundled AAR** (commit `ccff2d4`):
1. **The Netty dependency was dropped.** The vendor demo
   (`Timo/SdkDemoCsj/app/build.gradle`) declares `io.netty:netty-all:4.1.23.Final`;
   our `app/build.gradle` never did (though `proguard-rules.pro` still `-keep`s
   `io.netty.**`). Without it, socket mode crashed with
   `ClassNotFoundException: io.netty.channel.nio.NioEventLoopGroup`.
2. **Socket mode was disabled.** `MikeeApplication` skipped `setIpAndrPort()` for the
   `127.0.0.1` (robot) flavor, leaving the SDK on the MQTT path (`HandlerMsgService`)
   which this robot has no broker for.

### Fix applied (this branch)
- `app/build.gradle`: add `io.netty:netty-all:4.1.23.Final`.
- `MikeeApplication`: always call `setIpAndrPort(SDK_IP, SDK_PORT)` (→ `useSocket=true`).

**Verified on-robot:** the app is now stable (no crash) and the SDK correctly
instantiates `com.csjbot.cosclient.core.CosConnectorNetty` and runs a clean 5s
connect-retry loop — the **same Netty cos client Alpha Map uses**. The app-side is
fixed.

## Remaining blocker — robot-side: cos server on :60002 not listening
The SDK dials `defaultIp:defaultPort = 127.0.0.1:60002` and the connect **fails**
(`CosLogger: operationComplete not isSuccess`) because **nothing listens on 60002**
anywhere on the robot — confirmed even with Alpha Map logged in and robot-core
healthy (`nav_ready=true`, battery 63%).

Note Alpha Map does NOT use this port: its data arrives via a **separate ROS/SLAM
backend** (`CsjSlamCore` / `RosClientAgentCallback`), so Alpha Map being up does not
start the SDK's cos server. The cos "message server" on 60002 (robot-state/commands)
is a robot-side service that is simply not running on this unit right now.

### Next steps to close it
1. With the app now fixed, do a **clean reboot of the well-charged robot** — the cos
   server may auto-start on a healthy boot (we have never had one: every prior boot
   was at critically low battery). Then watch for `CosLogger … isSuccess` /
   robot-state callbacks; battery should flip from `(android)` to `(sdk)`.
2. If 60002 still never comes up, ask CSJBot/Vishal: *"what starts the cos message
   server on 127.0.0.1:60002 that the SDK connects to? It isn't running on our Timo,
   though the ROS/SLAM backend (Alpha Map) is."* Possibly the cos server runs on a
   different port — if so, set it via `setIpAndrPort`.

## Interim
`spine/battery-bridge.mjs` scrapes the real battery from Alpha Map's adb logs → admin
only. Retire once the SDK connects.
