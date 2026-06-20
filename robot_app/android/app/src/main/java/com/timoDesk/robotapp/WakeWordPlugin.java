package com.timoDesk.robotapp;

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
 * Dart over the "com.timoDesk/wake_events" EventChannel; the face screen starts a
 * voice session on wakeup.
 *
 * The CSJBot SDK only functions on the real Timo chest hardware — on an emulator
 * the wake engine never fires (and the SDK may be unavailable), so every SDK touch
 * is wrapped in try/catch(Throwable) and degrades to a silent no-op.
 *
 * NOTE: the default wake word is Chinese ("小蜜蜂"). Configure an English wake word
 * via the CSJBot dashboard, or rely on the face tap (already wired in
 * ambient_face_screen) as the primary trigger.
 */
public class WakeWordPlugin implements EventChannel.StreamHandler {

    private static final String TAG = "TimoDesk.Wake";

    private final Handler main = new Handler(Looper.getMainLooper());
    private EventChannel.EventSink sink;

    public void register(Context ctx) {
        try {
            CsjRobot.getInstance().registerWakeupListener(new OnWakeupListener() {
                @Override
                public void response(int angle) {
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
