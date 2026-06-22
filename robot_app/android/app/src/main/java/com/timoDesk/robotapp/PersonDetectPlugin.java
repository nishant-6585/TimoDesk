package com.timoDesk.robotapp;

import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import com.csjbot.coshandler.core.CsjRobot;
import com.csjbot.coshandler.listener.OnDetectPersonListener;

import io.flutter.plugin.common.EventChannel;

/**
 * On-device person detection (CSJBot laser / RGBD / ultrasonic sensors).
 *
 * Registers the SDK's {@link OnDetectPersonListener} and forwards the presence
 * state to Dart over the "com.timoDesk/person_events" EventChannel. Used as an
 * idle→active trigger: someone approaches the robot → it wakes / greets. This is
 * camera/sensor based, so it works WITHOUT the network/cloud and WITHOUT the
 * microphone (independent of the mic-routing issue).
 *
 * Like the other CSJBot bridges, every SDK touch is wrapped in try/catch and
 * degrades to a silent no-op off the real Timo hardware (emulator).
 */
public class PersonDetectPlugin implements EventChannel.StreamHandler {

    private static final String TAG = "TimoDesk.Person";

    private final Handler main = new Handler(Looper.getMainLooper());
    private EventChannel.EventSink sink;

    public void register() {
        try {
            // Enable all three presence sensors (laser + RGBD + ultrasonic), as the
            // vendor demo's MyApplication does.
            CsjRobot.getInstance().setPersonCheckType(true, true, true);
            CsjRobot.getInstance().registerDetectPersonListener(new OnDetectPersonListener() {
                @Override
                public void response(int state) {
                    // `state` is the sensor person-detection state. Exact codes need
                    // on-device verification; Dart treats non-zero as "present".
                    Log.d(TAG, "person-detect state=" + state);
                    final int s = state;
                    main.post(() -> { if (sink != null) sink.success(s); });
                }
            });
            Log.d(TAG, "person-detect listener registered");
        } catch (Throwable e) {
            // SDK absent (emulator) — silent: detection just won't fire.
            Log.w(TAG, "CSJBot SDK not available: " + e.getMessage());
        }
    }

    @Override
    public void onListen(Object args, EventChannel.EventSink s) {
        this.sink = s;
    }

    @Override
    public void onCancel(Object args) {
        this.sink = null;
    }
}
