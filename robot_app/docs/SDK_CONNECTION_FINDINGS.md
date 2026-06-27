# CSJBot SDK ↔ robot-core connection — root-cause findings (2026-06-27)

## Symptom
robot_app's CSJBot SDK receives **no robot-state callbacks**: battery falls back to
the Android head/tablet value (~50%), person detection is silent/inconsistent, and
the chassis never reports nav-ready (drive blocked). All three are the *same* failure.

## Root cause (confirmed)
The bundled SDK (`android/libs/newSceneSDK-release.aar`) reaches robot-core over
**MQTT**: `CsjRobot.init()` → `connectToMqtt()` → `Extra.connectMqttServer()`.

On-robot diagnostics added to `MikeeApplication` (`SDK-DIAG` logs) show:
```
SDK auth success
SDK target: defaultIp=127.0.0.1 defaultPort=60002 (flavor ip=127.0.0.1:60002)
SDK initialized — flavor=robot ip=127.0.0.1
```
…and then **none** of the connection callbacks ever fire — no `mqttConnect=true`,
no `serverConnect`, no `slam`. The SDK dials an MQTT broker at **127.0.0.1:60002**.

A full port scan of the robot (with Alpha Map logged in and robot-core healthy)
shows **nothing listening on 60002** — on localhost, on the internal chassis net
(`eth1 192.168.99.x`), or anywhere — and **no mqtt/mosquitto/cos broker process**.
Listening ports are only: 8080/8081/8082/8083/8090 (robot_app's own servers),
53 (dns), and a couple of dynamic localhost ports.

Meanwhile **Alpha Map (com.csjbot.robotstation) talks to robot-core successfully**
— but over a **different transport: Netty/ROS** (`CosConnectorNetty`,
`CsjSlamCore` `robot_info`/`get_localization_quality`), NOT MQTT. robot-core
reports `nav_ready=true`, `e_stop=false`, localization quality 5 — it is alive and
healthy; mikee's SDK simply can't reach it because it speaks the wrong protocol to
a port that has no listener.

## Conclusion: SDK ↔ firmware version mismatch
This robot's robot-core exposes **Netty/ROS** (what Alpha Map uses). The bundled
`newSceneSDK` AAR is an **MQTT-based** build that expects a broker at
`127.0.0.1:60002` which this firmware does not run. A reboot does NOT help — it's
not a service that failed to start; the robot simply has no MQTT broker.

## The fix (needs the vendor — CSJBot, via Vishal)
Obtain the **CSJBot SDK AAR + sample/demo app that matches this robot's firmware**
— the version Alpha Map is built against (Netty/ROS transport), not MQTT/60002.
Then:
1. Replace `android/libs/newSceneSDK-release.aar` with the matching version.
2. Align `MikeeApplication.initSdk()` with the demo's init sequence.
3. Verify `SDK-DIAG` shows the connection succeeding; battery/person/nav callbacks
   then fire and the bridge (`spine/battery-bridge.mjs`) can be retired.

### Exact question for CSJBot
> "Our app embeds `newSceneSDK` which connects to robot-core via MQTT at
> 127.0.0.1:60002, but our Timo has no MQTT broker there — robot-core is reachable
> via Netty/ROS (what Alpha Map / robotstation uses). Please provide the SDK
> version + demo that matches this robot's firmware so a third-party app can
> receive robot-state (battery, person detection) and drive the chassis."

## What works without this (interim)
`spine/battery-bridge.mjs` tails Alpha Map's robot-core logs over adb and feeds the
real battery + charging to the admin. Dev stopgap only; not a production feed.
