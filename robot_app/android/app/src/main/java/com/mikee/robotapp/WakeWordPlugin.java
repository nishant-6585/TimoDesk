package com.mikee.robotapp;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import com.csjbot.coshandler.core.CsjRobot;
import com.csjbot.coshandler.listener.OnWakeupListener;

import io.flutter.plugin.common.EventChannel;

/**
 * #80 Phase B — CSJBot wake word.
 *
 * Registers the SDK's {@link OnWakeupListener} and forwards a "wakeup" string to
 * Dart over the "com.mikee/wake_events" EventChannel; the face screen starts a
 * voice session on wakeup.
 *
 * The CSJBot SDK only functions on the real Mikee chest hardware — on an emulator
 * the wake engine never fires (and the SDK may be unavailable), so every SDK touch
 * is wrapped in try/catch(Throwable) and degrades to a silent no-op.
 *
 * NOTE: the default wake word is Chinese ("小蜜蜂"). Configure an English wake word
 * via the CSJBot dashboard, or rely on the face tap (already wired in
 * ambient_face_screen) as the primary trigger.
 */
public class WakeWordPlugin implements EventChannel.StreamHandler {

    private static final String TAG = "Mikee.Wake";

    /** On wake word, rotate the robot to face the speaker (sound-source direction),
     *  matching the vendor demo (AsrNlpActivity). Set false if chassis rotation is
     *  unwanted at a fixed reception desk. */
    private static final boolean TURN_TOWARD_SPEAKER = true;

    private final Handler main = new Handler(Looper.getMainLooper());
    private EventChannel.EventSink sink;

    public void register(Context ctx) {
        try {
            CsjRobot.getInstance().registerWakeupListener(new OnWakeupListener() {
                @Override
                public void response(int angle) {
                    Log.d(TAG, "wakeup, sound-source angle=" + angle);
                    // Turn toward whoever spoke (the demo's signature behavior). The
                    // angle is 0–360°; take the shortest rotation. Best-effort.
                    if (TURN_TOWARD_SPEAKER) {
                        try {
                            int a = angle > 180 ? -(360 - angle) : angle;
                            CsjRobot.getInstance().getAction().moveAngle(a, null);
                        } catch (Throwable t) {
                            Log.w(TAG, "turn-toward-speaker failed: " + t.getMessage());
                        }
                    }
                    // SDK thread → marshal to main for the EventChannel sink.
                    main.post(() -> {
                        if (sink != null) sink.success("wakeup");
                    });
                }
            });
            Log.d(TAG, "CSJBot wakeup listener registered");
        } catch (Throwable e) {
            // SDK absent (emulator) — silent: wake word just won't fire.
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
