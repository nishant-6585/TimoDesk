package com.mikee.robotapp;

import android.content.Context;
import android.os.BatteryManager;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import com.csjbot.coshandler.core.CsjRobot;
import com.csjbot.coshandler.listener.OnRobotStateListener;

import java.util.HashMap;
import java.util.Map;

import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * Real battery telemetry.
 *
 * Primary source: the CSJBot SDK. CsjRobot's internal loop polls the robot's main
 * battery every ~5s and invokes the OnRobotStateListener we register here
 * (getBattery / getCharge). This is the robot's actual charge.
 *
 * Fallback: Android BatteryManager (the chest device's battery) — used only if the
 * SDK never reports (e.g. SDK not authenticated). Still a REAL value, never 85.
 *
 * Forwards to Flutter over an EventChannel; Dart calls BatteryService.setBattery().
 */
public class BatteryPlugin implements EventChannel.StreamHandler, MethodChannel.MethodCallHandler {
    private static final String TAG = "Mikee.Battery";

    private final Context context;
    private final Handler main = new Handler(Looper.getMainLooper());
    private EventChannel.EventSink sink;

    private volatile int sdkBattery = -1; // -1 = SDK hasn't reported yet
    private volatile int charge = -1;
    private boolean registered = false;

    BatteryPlugin(Context context) {
        this.context = context;
    }

    // Handles both the push registration AND the active poll responses. The robot's
    // real charge comes back here as getBattery(int)/getCharge(int).
    private final OnRobotStateListener stateListener = new OnRobotStateListener() {
        @Override
        public void getBattery(int battery) {
            if (battery >= 0 && battery <= 100) {
                sdkBattery = battery;
                emit(battery, "sdk");
            }
        }

        @Override
        public void getCharge(int c) {
            // c = charge_status from the SDK (robot_info: 1 = on charger/charging,
            // 0 = not). Emit on CHANGE so the admin's ⚡ indicator flips promptly
            // on dock/undock without waiting for the next battery poll.
            final boolean changed = (c != charge);
            charge = c;
            Log.d(TAG, "charge_status=" + c + (changed ? " (changed)" : ""));
            if (changed && sdkBattery >= 0) emit(sdkBattery, "sdk");
        }
    };

    /** Register the SDK battery listener + start the SDK poll + Android fallback. Idempotent. */
    void register() {
        if (registered) return;
        registered = true;
        try {
            CsjRobot.getInstance().setOnRobotStateBatteryListener(stateListener);
            Log.d(TAG, "SDK battery listener registered");
        } catch (Throwable t) {
            Log.e(TAG, "SDK battery listener failed, will rely on Android fallback: " + t);
        }
        startSdkPoll();
        startFallbackPoll();
    }

    // The robot does NOT auto-push battery to SDK clients (ROBOT_SDK_AGENT_ENABLE only
    // enables asr/slam/face), so we actively poll robot-core every 20s. getState()
    // .getBattery/getCharge issue ROBOT_GET_BATTERY/CHARGE_REQ; the response fires
    // stateListener with the REAL chassis charge — making the head/tablet fallback
    // and the spine/battery-bridge stopgap unnecessary.
    private void startSdkPoll() {
        final Handler h = new Handler(Looper.getMainLooper());
        h.postDelayed(new Runnable() {
            @Override
            public void run() {
                try {
                    CsjRobot.getInstance().getState().getBattery(stateListener);
                    CsjRobot.getInstance().getState().getCharge(stateListener);
                } catch (Throwable t) {
                    Log.e(TAG, "SDK battery poll failed: " + t);
                }
                h.postDelayed(this, 20_000);
            }
        }, 8_000); // let the SDK finish init/connect first
    }

    // If the SDK hasn't reported, emit the chest device's real battery every 30s.
    private void startFallbackPoll() {
        final Handler h = new Handler(Looper.getMainLooper());
        h.postDelayed(new Runnable() {
            @Override
            public void run() {
                if (sdkBattery < 0) {
                    int b = readAndroidBattery();
                    if (b >= 0) emit(b, "android");
                }
                h.postDelayed(this, 30_000);
            }
        }, 5_000); // give the SDK a few seconds first
    }

    private int readAndroidBattery() {
        try {
            BatteryManager bm = (BatteryManager) context.getSystemService(Context.BATTERY_SERVICE);
            int b = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY);
            return (b >= 0 && b <= 100) ? b : -1;
        } catch (Throwable t) {
            return -1;
        }
    }

    private void emit(int battery, String source) {
        final Map<String, Object> m = new HashMap<>();
        m.put("battery", battery);
        m.put("charge", charge);
        m.put("source", source);
        Log.d(TAG, "battery=" + battery + "% (" + source + ")");
        if (sink != null) {
            main.post(() -> {
                try {
                    if (sink != null) sink.success(m);
                } catch (Exception e) {
                    Log.e(TAG, "emit error: " + e.getMessage());
                }
            });
        }
    }

    @Override
    public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        if ("getBattery".equals(call.method)) {
            int b = sdkBattery >= 0 ? sdkBattery : readAndroidBattery();
            Map<String, Object> m = new HashMap<>();
            m.put("battery", b);
            m.put("charge", charge);
            m.put("source", sdkBattery >= 0 ? "sdk" : "android");
            result.success(m);
        } else {
            result.notImplemented();
        }
    }

    @Override
    public void onListen(Object args, EventChannel.EventSink s) {
        sink = s;
        // Re-emit the last known value so a fresh listener isn't blank.
        if (sdkBattery >= 0) {
            emit(sdkBattery, "sdk");
        } else {
            int b = readAndroidBattery();
            if (b >= 0) emit(b, "android");
        }
    }

    @Override
    public void onCancel(Object args) {
        sink = null;
    }
}
