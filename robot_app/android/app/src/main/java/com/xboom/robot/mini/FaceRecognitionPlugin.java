package com.xboom.robot.mini;

import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import com.csjbot.coshandler.core.CsjRobot;
import com.csjbot.coshandler.listener.OnFaceListener;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.HashMap;
import java.util.Map;

import io.flutter.plugin.common.EventChannel;

/**
 * Staff face RECOGNITION bridge (greet-by-name).
 *
 * Registers a second {@link OnFaceListener} with the SDK and forwards two kinds
 * of event to Dart over the "com.mikee/face_events" EventChannel:
 *   • personInfo(json)   → {type:"recognized", name, confidence, age, gender}
 *   • personNear(bool)   → {type:"near", present:true|false}
 *
 * This coexists with {@link PersonDetectPlugin}'s listener: the SDK keeps face
 * listeners in a CopyOnWriteArrayList and APPENDS (it skips duplicates but never
 * replaces), so registering here does NOT clobber person-presence detection —
 * both listeners receive every callback.
 *
 * Like PersonDetectPlugin, the SDK listener is registered post-init from
 * {@link MikeeApplication} (see {@link #registerWithSdk()}) so it binds to a live
 * perception engine, and the Dart sink is static so that listener can reach
 * whatever engine/Activity is currently subscribed. All SDK touches are wrapped
 * in try/catch(Throwable) so the app is a silent no-op off the robot.
 */
public class FaceRecognitionPlugin implements EventChannel.StreamHandler {

    private static final String TAG = "Mikee.FaceRecg";
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
     * Register the SDK face-recognition listener. MUST be called AFTER
     * {@code CsjRobot.getInstance().init()} (mirrors PersonDetectPlugin). Safe to
     * call off-device — the SDK touch throws and we no-op.
     */
    public static void registerWithSdk() {
        try {
            CsjRobot.getInstance().registerFaceListener(new OnFaceListener() {
                @Override
                public void personInfo(String json) {
                    emitRecognized(json);
                }

                @Override
                public void personNear(boolean person) {
                    Map<String, Object> m = new HashMap<>();
                    m.put("type", "near");
                    m.put("present", person);
                    emit(m);
                }
            });
            Log.d(TAG, "face-recognition listener registered (post-init)");
        } catch (Throwable e) {
            // SDK absent (emulator) or not ready — silent: recognition won't fire.
            Log.w(TAG, "registerWithSdk failed: " + e.getMessage());
        }
    }

    /**
     * Parse the SDK personInfo payload and forward the first recognised face.
     * Shape (from the vendor demo / PersonDetectBean):
     * {"face_list":[{"face_detect":{"age":18,"gender":0},
     *                "face_recg":{"confidence":18,"name":"tt","person_id":"…"}}]}
     */
    private static void emitRecognized(String json) {
        try {
            if (json == null || json.isEmpty()) return;
            JSONArray faceList = new JSONObject(json).optJSONArray("face_list");
            if (faceList == null || faceList.length() == 0) return;
            JSONObject face0 = faceList.getJSONObject(0);
            JSONObject recg = face0.optJSONObject("face_recg");
            JSONObject detect = face0.optJSONObject("face_detect");

            String name = recg != null ? recg.optString("name", "") : "";
            int confidence = recg != null ? recg.optInt("confidence", 0) : 0;
            int age = detect != null ? detect.optInt("age", 0) : 0;
            // SDK gender is an int code; mapping is best-effort (0/1), unused by the
            // greeting logic — surfaced for completeness only.
            int g = detect != null ? detect.optInt("gender", -1) : -1;
            String gender = g == 1 ? "male" : g == 0 ? "female" : "unknown";

            Map<String, Object> m = new HashMap<>();
            m.put("type", "recognized");
            m.put("name", name);
            m.put("confidence", confidence);
            m.put("age", age);
            m.put("gender", gender);
            emit(m);
        } catch (Throwable e) {
            Log.w(TAG, "personInfo parse failed: " + e.getMessage());
        }
    }

    private static void emit(Map<String, Object> event) {
        MAIN.post(() -> {
            EventChannel.EventSink sink = sSink;
            if (sink != null) sink.success(event);
        });
    }
}
