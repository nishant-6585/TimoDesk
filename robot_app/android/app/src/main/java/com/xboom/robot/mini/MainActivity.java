package com.xboom.robot.mini;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {

    private static final String METHOD_CHANNEL = "com.mikee/camera_stream";
    private static final String EVENT_CHANNEL  = "com.mikee/camera_events";
    private static final String HEAD_METHOD_CH = "com.mikee/head_control";
    private static final String HEAD_EVENT_CH  = "com.mikee/head_events";
    private static final String CHASSIS_METHOD_CH = "com.mikee/chassis_control";
    private static final String CHASSIS_EVENT_CH  = "com.mikee/chassis_events";
    private static final String ARM_METHOD_CH = "com.mikee/arm_control";
    private static final String ARM_EVENT_CH  = "com.mikee/arm_events";
    private static final String BATTERY_METHOD_CH = "com.mikee/battery";
    private static final String BATTERY_EVENT_CH  = "com.mikee/battery_events";
    private static final String AUDIO_METHOD_CH    = "com.mikee/audio_control";
    private static final String AUDIO_MIC_EVENT_CH = "com.mikee/audio_mic";
    private static final String AUDIO_PLAY_EVENT_CH = "com.mikee/audio_playback";
    private static final String WAKE_EVENT_CH      = "com.mikee/wake_events";
    private static final String PERSON_EVENT_CH    = "com.mikee/person_events";
    private static final String FACE_EVENT_CH      = "com.mikee/face_events";
    private static final String FACE_SAVE_METHOD_CH = "com.mikee/face_save";

    // Held so onResume can re-assert lockdown if the kiosk fell out of lock task.
    private KioskPlugin kioskPlugin;

    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        // Kiosk / Lock Task Mode control (device-owner). Registered first so the
        // Dart side can lock down as early as possible.
        kioskPlugin = new KioskPlugin(this);
        new MethodChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                "com.mikee/kiosk"
        ).setMethodCallHandler(kioskPlugin);

        CameraStreamPlugin cameraPlugin = new CameraStreamPlugin(this);

        new MethodChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                METHOD_CHANNEL
        ).setMethodCallHandler(cameraPlugin);

        new EventChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                EVENT_CHANNEL
        ).setStreamHandler(cameraPlugin);

        HeadControlPlugin headPlugin = new HeadControlPlugin();

        new MethodChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                HEAD_METHOD_CH
        ).setMethodCallHandler(headPlugin);

        new EventChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                HEAD_EVENT_CH
        ).setStreamHandler(headPlugin);

        ChassisControlPlugin chassisPlugin = new ChassisControlPlugin();

        new MethodChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                CHASSIS_METHOD_CH
        ).setMethodCallHandler(chassisPlugin);

        new EventChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                CHASSIS_EVENT_CH
        ).setStreamHandler(chassisPlugin);

        ArmControlPlugin armPlugin = new ArmControlPlugin();
        armPlugin.setup(flutterEngine);

        // Real battery telemetry (CSJBot SDK, Android BatteryManager fallback).
        BatteryPlugin batteryPlugin = new BatteryPlugin(this);
        new MethodChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                BATTERY_METHOD_CH
        ).setMethodCallHandler(batteryPlugin);
        new EventChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                BATTERY_EVENT_CH
        ).setStreamHandler(batteryPlugin);
        batteryPlugin.register();

        // Audio bridge (#80 Phase B): mic capture (EventChannel) + speaker playback
        // (MethodChannel).
        AudioBridgePlugin audioPlugin = new AudioBridgePlugin(this);
        new MethodChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                AUDIO_METHOD_CH
        ).setMethodCallHandler(audioPlugin);
        new EventChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                AUDIO_MIC_EVENT_CH
        ).setStreamHandler(audioPlugin);
        new EventChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                AUDIO_PLAY_EVENT_CH
        ).setStreamHandler(audioPlugin.playbackStreamHandler);
        new EventChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                "com.mikee/asr_events"
        ).setStreamHandler(audioPlugin.asrStreamHandler);

        // CSJBot wake word (silent no-op on emulator — SDK absent).
        WakeWordPlugin wakePlugin = new WakeWordPlugin();
        wakePlugin.register(this);
        new EventChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                WAKE_EVENT_CH
        ).setStreamHandler(wakePlugin);

        // On-device person detection (laser/RGBD/ultrasonic) — idle→active trigger.
        // Works without cloud or mic; silent no-op on emulator. The SDK listener
        // is registered post-init in MikeeApplication (see registerWithSdk); here we
        // only wire the EventChannel so the Dart sink is captured.
        PersonDetectPlugin personPlugin = new PersonDetectPlugin();
        new EventChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                PERSON_EVENT_CH
        ).setStreamHandler(personPlugin);

        // Staff face recognition → greet-by-name. The SDK listener is registered
        // post-init in MikeeApplication (see registerWithSdk); here we only wire the
        // EventChannel so the Dart sink is captured. Silent no-op on emulator.
        FaceRecognitionPlugin facePlugin = new FaceRecognitionPlugin();
        new EventChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                FACE_EVENT_CH
        ).setStreamHandler(facePlugin);

        // On-robot face enrollment (live-camera capture). MethodChannel only —
        // saveFace registers the person currently in front of the camera.
        FaceSavePlugin faceSavePlugin = new FaceSavePlugin();
        new MethodChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                FACE_SAVE_METHOD_CH
        ).setMethodCallHandler(faceSavePlugin);
    }

    @Override
    protected void onResume() {
        super.onResume();
        // Re-pin if we're supposed to be locked but fell out of lock task (a stray
        // system intent, dialog, or maintenance-app return). No-op in maintenance
        // mode or when not device-owner.
        if (kioskPlugin != null) {
            kioskPlugin.reassertLock();
        }
    }
}
