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
    }
}
