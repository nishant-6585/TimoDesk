# Mikee Sensor Bridge — Native → Spine wiring (Phase 1B, hardware-gated)

> **Status: NOT DEPLOYED.** This is the reference implementation for the native
> Android bridge that forwards the Mikee robot's high-level sensor/obstacle
> events to `spine`. It runs only on real hardware. Until the physical robot is
> available, spine's `MockRobotSDK` synthesises these events (see
> `spine/src/robot/mock.ts`) and `RealRobotSDK.onSensorEvent()` is a no-op.

> ⚠️ **Verify against the real SDK before deploying.** The code below is written
> against the listener names documented in CSJBot SDK research
> (`mikee-lidar-integration.md`), **not** copied from a compiled, tested
> sample. Exact method/parameter signatures (`OnRobotMoveStatusListener`,
> `setPersonCheckType`, `getSensorHealth`, …) must be confirmed against the
> actual `English Sdk Document Translation.pdf` / `SdkDemoCsj` sample when
> hardware arrives. Treat every signature as a TODO until it compiles on-device.

---

## Why this exists

The CSJBot SDK does **not** expose a raw LIDAR point cloud. It surfaces
**high-level** navigation/obstacle/sensor events via listeners. Those are
sufficient for a reception robot. This bridge:

1. Initialises the CsjBot SDK on the robot's Android 7.1.2 chest screen.
2. Registers the four relevant listeners + enables multi-sensor person check.
3. Forwards each event up to Flutter via a `MethodChannel`.
4. Flutter relays it as JSON over the **existing chassis WebSocket** to `spine`.
5. `spine` parses it into a `SensorEvent`, updates `RobotStatus`, broadcasts to
   admin clients, and logs to Supabase.

```
CsjBot SDK ─listeners─► MikeeSensorBridge.kt ─MethodChannel─► sensor_bridge.dart
   ─WebSocket(JSON)─► spine RealRobotSDK.onSensorEvent ─► createSensorPipeline
   ─► broadcast RobotStatus + logEvent(robot_event)
```

---

## Wire format (Kotlin → Flutter → spine)

The JSON sent to spine must match the `SensorEvent` discriminated union in
[`spine/src/types.ts`](../../spine/src/types.ts) **exactly** — spine maps these
1:1 with no translation:

```jsonc
// obstacle — from OnRobotMoveStatusListener
{ "type": "obstacle_event", "state": "running|blocked|wait_short|wait_long", "timestamp": 1700000000000 }

// sensor health — from OnSensorHealthListener
{ "type": "sensor_health", "sensors": { "lidar": "ok|warn|error", "rgbd": "...", "sonar": "..." }, "timestamp": 1700000000000 }

// localization quality — from OnPositioningQualityListener
{ "type": "localization_lq", "quality": "low|normal", "lq": 42, "timestamp": 1700000000000 }

// person detection — from OnDetectPersonListener
{ "type": "person_detected", "detected": true, "timestamp": 1700000000000 }
```

> spine logs `obstacle.<state>`, `sensor.health`, `localization.lq_low|lq_normal`,
> and `person.detected_on|off` (person logged only on **transition**). See
> `spine/src/sensors.ts`.

---

## `MikeeSensorBridge.kt`

`robot_app/android/app/src/main/kotlin/com/csjbot/mikee/MikeeSensorBridge.kt`

> Adjust the package to match the robot_app `applicationId`. Import paths for the
> CsjBot SDK classes (`CsjBotApi`, `OnRobotMoveStatusListener`, …) come from the
> vendor `.aar` — confirm against `SdkDemoCsj`.

```kotlin
package com.csjbot.mikee

import android.content.Context
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
// import com.csjbot.sdk.*  // ← actual CsjBot SDK imports — confirm against SdkDemoCsj

/**
 * Bridges CsjBot high-level sensor/obstacle events to Flutter over a MethodChannel.
 *
 * VERIFY every SDK call below against the real SDK before deploying. Listener
 * names follow mikee-lidar-integration.md research notes.
 */
class MikeeSensorBridge(
    private val context: Context,
    private val channel: MethodChannel,
) {
    // private val sdk = CsjBotApi.getInstance(context)  // exact accessor TBD

    fun start() {
        // Enable LIDAR + RGB-D + ultrasonic fusion for person detection.
        // sdk.setPersonCheckType(/* laser = */ true, /* rgbd = */ true, /* ult = */ true)

        registerMoveStatus()
        registerPositioningQuality()
        registerSensorHealth()
        registerPersonDetect()
    }

    // OnRobotMoveStatusListener → obstacle_event ------------------------------
    private fun registerMoveStatus() {
        // sdk.setOnRobotMoveStatusListener { status ->
        //     val state = when (status) {
        //         NAVI_ROBOT_RUNNING_NTF   -> "running"
        //         NAVI_ROBOT_BLOCKED_NTF   -> "blocked"
        //         NAVI_ROBOT_WAITSHORT_NTF -> "wait_short"
        //         NAVI_ROBOT_WAITLONG_NTF  -> "wait_long"
        //         else -> return@setOnRobotMoveStatusListener
        //     }
        //     send("obstacle_event", JSONObject().put("state", state))
        // }
    }

    // OnPositioningQualityListener → localization_lq --------------------------
    private fun registerPositioningQuality() {
        // sdk.setOnPositioningQualityListener { isLow, lqValue ->
        //     send("localization_lq", JSONObject()
        //         .put("quality", if (isLow) "low" else "normal")
        //         .put("lq", lqValue))
        // }
    }

    // OnSensorHealthListener → sensor_health ---------------------------------
    private fun registerSensorHealth() {
        // sdk.setOnSensorHealthListener { json ->          // json = vendor health blob
        //     val health = parseHealth(json)               // → {lidar,rgbd,sonar}: ok|warn|error
        //     send("sensor_health", JSONObject().put("sensors", health))
        // }
    }

    // OnDetectPersonListener → person_detected -------------------------------
    private fun registerPersonDetect() {
        // sdk.setOnDetectPersonListener { detected ->
        //     send("person_detected", JSONObject().put("detected", detected))
        // }
    }

    /** Map the vendor health blob to {lidar,rgbd,sonar}: "ok"|"warn"|"error". */
    private fun parseHealth(@Suppress("UNUSED_PARAMETER") vendorJson: String): JSONObject {
        // TODO: parse the real OnSensorHealthListener `data` field.
        return JSONObject()
            .put("lidar", "ok")
            .put("rgbd", "ok")
            .put("sonar", "ok")
    }

    /** Forward an event to Flutter. Adds a timestamp so spine needs no clock. */
    private fun send(type: String, payload: JSONObject) {
        payload.put("type", type)
        payload.put("timestamp", System.currentTimeMillis())
        channel.invokeMethod("sensorEvent", payload.toString())
    }
}
```

---

## `MainActivity.kt` integration

`robot_app/android/app/src/main/kotlin/com/csjbot/mikee/MainActivity.kt`

```kotlin
package com.csjbot.mikee

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "mikee/sensors"
    private var bridge: MikeeSensorBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        bridge = MikeeSensorBridge(applicationContext, channel).also { it.start() }
    }
}
```

---

## `sensor_bridge.dart` (Flutter receiver)

`robot_app/lib/sensor_bridge.dart`

> Reuses the existing chassis WebSocket that already streams to spine for camera
> control. If that socket lives elsewhere, inject it instead of opening a new one.

```dart
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Receives native sensor events over the MethodChannel and relays them as JSON
/// to spine over the chassis WebSocket. The native payload already matches
/// spine's SensorEvent shape, so this is a passthrough.
class SensorBridge {
  static const _channel = MethodChannel('mikee/sensors');
  final WebSocketChannel _spine;

  SensorBridge(this._spine) {
    _channel.setMethodCallHandler(_onNative);
  }

  Future<void> _onNative(MethodCall call) async {
    if (call.method != 'sensorEvent') return;
    // call.arguments is the JSON string built in MikeeSensorBridge.send().
    final String json = call.arguments as String;
    // Validate before forwarding; spine trusts this shape.
    final Map<String, dynamic> event = jsonDecode(json) as Map<String, dynamic>;
    _spine.sink.add(jsonEncode(event));
  }
}
```

---

## Deploy-when-hardware-arrives checklist

- [ ] Drop the vendor CsjBot `.aar` into `robot_app/android/app/libs/` and wire
      `build.gradle` (`implementation files('libs/<sdk>.aar')`).
- [ ] Replace every commented `sdk.*` call with the real SDK signatures from
      `SdkDemoCsj` + `English Sdk Document Translation.pdf`.
- [ ] Confirm the `NAVI_ROBOT_*_NTF` constant names and `OnSensorHealthListener`
      payload shape; finish `parseHealth()`.
- [ ] Match the Kotlin package to the robot_app `applicationId`.
- [ ] Inject the **existing** chassis WebSocket into `SensorBridge` (don't open a
      second connection).
- [ ] In `spine/src/robot/real.ts`, implement `onSensorEvent()` + parse the
      incoming JSON in `handleRobotMessage()` into `SensorEvent` (the mock and
      the pipeline in `spine/src/sensors.ts` already prove the downstream path).
- [ ] Build + install: `cd robot_app && flutter build apk --debug && adb install build/app/outputs/flutter-apk/app-debug.apk`.
- [ ] Verify on-device: trigger an obstacle, confirm an admin client receives a
      `robot_status` broadcast with the new `obstacleState`, and a `robot_event`
      row lands in Supabase.
```
