package com.mikee.robotapp;

import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import com.csjbot.coshandler.core.CsjRobot;
import com.csjbot.coshandler.listener.OnDetectPersonListener;
import com.csjbot.coshandler.listener.OnFaceListener;

import io.flutter.plugin.common.EventChannel;

/**
 * On-device person detection (CSJBot laser / RGBD / ultrasonic sensors).
 *
 * Forwards the SDK's {@link OnDetectPersonListener} presence state to Dart over
 * the "com.mikee/person_events" EventChannel — an idle→active trigger (someone
 * approaches → Mikee wakes / greets). Sensor based, so it works WITHOUT the
 * network/cloud and WITHOUT the microphone.
 *
 * IMPORTANT: the SDK listener is registered from {@link MikeeApplication} AFTER
 * {@code CsjRobot.init()} completes (see {@link #registerWithSdk()}). Registering
 * it at Activity start (the old behaviour) raced the async SDK init — the SDK
 * wasn't up yet, so the listener never attached and detection never fired. The
 * Dart-facing sink is static so the post-init listener can reach it regardless of
 * when the Activity/engine is (re)created.
 */
public class PersonDetectPlugin implements EventChannel.StreamHandler {

    private static final String TAG = "Mikee.Person";
    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    // Static so the SDK listener (registered from MikeeApplication, no plugin
    // instance in hand) can forward to whatever Dart is currently subscribed.
    private static volatile EventChannel.EventSink sSink;

    @Override
    public void onListen(Object args, EventChannel.EventSink s) {
        sSink = s;
    }

    @Override
    public void onCancel(Object args) {
        sSink = null;
    }

    /**
     * Register the SDK person-detection listener. MUST be called AFTER
     * {@code CsjRobot.getInstance().init()} so it binds to a live perception
     * engine. Safe to call off-device — the SDK touch throws and we no-op.
     */
    public static void registerWithSdk() {
        try {
            CsjRobot robot = CsjRobot.getInstance();

            // (1) Device-sensor person-near (laser / ultrasonic / RGBD). Kept like
            // the demo, but on this unit it stays silent (no DEVICE_DETECT_PERSON_
            // NEAR_NTF), so it's not what actually drives presence.
            robot.registerDetectPersonListener(new OnDetectPersonListener() {
                @Override
                public void response(int state) {
                    Log.d(TAG, "person-detect (device) state=" + state);
                    emit(state);
                }
            });

            // (2) Face-module person-near — THIS is what the vendor demo uses for
            // the "person present" state: FACE_DETECT_PERSON_NEAR_NTF → pushFace →
            // OnFaceListener.personNear(boolean). Runs off enableFace(true) (set in
            // MikeeApplication); no camera preview required (the demo only opens the
            // preview for face registration, not for presence).
            robot.registerFaceListener(new OnFaceListener() {
                @Override
                public void personNear(boolean person) {
                    Log.d(TAG, "person-detect (face) personNear=" + person);
                    emit(person ? 1 : 0);
                }

                @Override
                public void personInfo(String json) {
                    // Face-recognition payload (name/confidence) — not needed for
                    // presence; logged for future greet-by-name work.
                    Log.d(TAG, "face personInfo=" + json);
                }
            });

            // NOTE: we do NOT start the CSJBot face video here. On this unit it
            // emits no FACE_DETECT_PERSON_NEAR_NTF, and openVideo() can hold the
            // camera that our MJPEG stream + ML Kit gaze pipeline needs. Presence
            // is driven by the on-device ML Kit face detector over /snapshot
            // instead (see GazeTracker). These listeners stay registered as a
            // best-effort fallback if the vendor enables the NTF later.
            Log.d(TAG, "person-detect listeners registered (post-init): device + face");
        } catch (Throwable e) {
            // SDK absent (emulator) or not ready — silent: detection won't fire.
            Log.w(TAG, "registerWithSdk failed: " + e.getMessage());
        }
    }

    private static void emit(int state) {
        MAIN.post(() -> {
            EventChannel.EventSink sink = sSink;
            if (sink != null) sink.success(state);
        });
    }
}
