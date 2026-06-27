package com.mikee.robotapp;

import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import com.csjbot.coshandler.core.CsjRobot;
import com.csjbot.coshandler.core.Face;
import com.csjbot.coshandler.listener.OnFaceSaveListener;

import java.util.concurrent.atomic.AtomicBoolean;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * On-robot face ENROLLMENT bridge (MethodChannel "com.mikee/face_save").
 *
 * IMPORTANT — why this does NOT take image bytes: the CSJBot SDK can only
 * register a face from the robot's OWN live camera. Its API is
 * {@code getFace().saveFace(String name, OnFaceSaveListener)} — there is no
 * overload that accepts a Bitmap / JPEG, so staff photos stored in Supabase
 * cannot be pushed into the SDK's on-device face DB. Enrollment therefore
 * happens here, on the robot, with the person standing in front of the camera:
 *
 *   startFaceService() → prepareReg() → saveFace(name, listener) → faceRegEnd()
 *
 * Method: "saveface", args { "name": String }. Replies true/false once the SDK
 * reports the result (or false on timeout / SDK-absent). The recognition side
 * ({@link FaceRecognitionPlugin}) then fires personInfo with this name when the
 * same face is seen again.
 */
public class FaceSavePlugin implements MethodChannel.MethodCallHandler {

    private static final String TAG = "Mikee.FaceSave";
    private static final Handler MAIN = new Handler(Looper.getMainLooper());
    // Give the operator a few seconds to get the staff member's face in frame
    // before we give up and report failure (so Dart's await never hangs).
    private static final long CAPTURE_TIMEOUT_MS = 8000;

    @Override
    public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        if (!"saveface".equals(call.method)) {
            result.notImplemented();
            return;
        }
        final String name = call.argument("name");
        if (name == null || name.trim().isEmpty()) {
            result.error("bad_args", "name is required", null);
            return;
        }

        // saveFace replies asynchronously via the listener; a timeout backstops the
        // case where no face is ever captured. Guard so we reply to Flutter exactly once.
        final AtomicBoolean replied = new AtomicBoolean(false);
        try {
            final Face face = CsjRobot.getInstance().getFace();
            face.startFaceService();
            face.prepareReg();
            face.saveFace(name.trim(), new OnFaceSaveListener() {
                @Override
                public void response(String response) {
                    Log.d(TAG, "saveFace('" + name + "') response: " + response);
                    endReg(face);
                    // Best-effort success heuristic on the SDK's result string —
                    // confirm the exact shape on-device and tighten if needed.
                    boolean ok = response != null
                            && !response.toLowerCase().contains("fail")
                            && !response.toLowerCase().contains("error");
                    if (replied.compareAndSet(false, true)) reply(result, ok);
                }
            });

            MAIN.postDelayed(() -> {
                if (replied.compareAndSet(false, true)) {
                    Log.w(TAG, "saveFace('" + name + "') timed out — no face captured");
                    endReg(face);
                    reply(result, false);
                }
            }, CAPTURE_TIMEOUT_MS);
        } catch (Throwable e) {
            // SDK absent (emulator) or not ready.
            Log.w(TAG, "saveFace failed: " + e.getMessage());
            if (replied.compareAndSet(false, true)) reply(result, false);
        }
    }

    private static void endReg(Face face) {
        try {
            face.faceRegEnd();
        } catch (Throwable ignored) {
        }
    }

    private static void reply(MethodChannel.Result result, boolean ok) {
        MAIN.post(() -> {
            try {
                result.success(ok);
            } catch (Throwable ignored) {
            }
        });
    }
}
