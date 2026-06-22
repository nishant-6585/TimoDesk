package com.timoDesk.robotapp;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {

    private static final String METHOD_CHANNEL = "com.timoDesk/camera_stream";
    private static final String EVENT_CHANNEL  = "com.timoDesk/camera_events";
    private static final String HEAD_METHOD_CH = "com.timoDesk/head_control";
    private static final String HEAD_EVENT_CH  = "com.timoDesk/head_events";
    private static final String CHASSIS_METHOD_CH = "com.timoDesk/chassis_control";
    private static final String CHASSIS_EVENT_CH  = "com.timoDesk/chassis_events";
    private static final String ARM_METHOD_CH = "com.timoDesk/arm_control";
    private static final String ARM_EVENT_CH  = "com.timoDesk/arm_events";
    private static final String BATTERY_METHOD_CH = "com.timoDesk/battery";
    private static final String BATTERY_EVENT_CH  = "com.timoDesk/battery_events";
    private static final String AUDIO_METHOD_CH    = "com.timoDesk/audio_control";
    private static final String AUDIO_MIC_EVENT_CH = "com.timoDesk/audio_mic";
    private static final String AUDIO_PLAY_EVENT_CH = "com.timoDesk/audio_playback";
    private static final String WAKE_EVENT_CH      = "com.timoDesk/wake_events";
    private static final String PERSON_EVENT_CH    = "com.timoDesk/person_events";

    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

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
                "com.timoDesk/asr_events"
        ).setStreamHandler(audioPlugin.asrStreamHandler);

        // CSJBot wake word (silent no-op on emulator — SDK absent).
        WakeWordPlugin wakePlugin = new WakeWordPlugin();
        wakePlugin.register(this);
        new EventChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                WAKE_EVENT_CH
        ).setStreamHandler(wakePlugin);

        // On-device person detection (laser/RGBD/ultrasonic) — idle→active trigger.
        // Works without cloud or mic; silent no-op on emulator.
        PersonDetectPlugin personPlugin = new PersonDetectPlugin();
        personPlugin.register();
        new EventChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                PERSON_EVENT_CH
        ).setStreamHandler(personPlugin);
    }
}
