package com.mikee.robotapp;

import android.util.Log;

import androidx.multidex.MultiDexApplication;

import com.csjbot.coshandler.core.CsjRobot;
import com.csjbot.coshandler.listener.OnAuthenticationListener;
import com.csjbot.coshandler.listener.OnRobotInitListener;
import com.csjbot.coshandler.listener.OnMqttConnectStateListener;
import com.csjbot.coshandler.listener.OnRobotConnectionStateListener;

public class MikeeApplication extends MultiDexApplication {

    private static final String TAG = "Mikee";

    @Override
    public void onCreate() {
        super.onCreate();
        initSdk();
    }

    private void initSdk() {
        new Thread(() -> {
            try {
                // Step 1: Authenticate
                CsjRobot.authentication(this, "csjbot_default", "",
                    new OnAuthenticationListener() {
                        @Override public void success() { Log.d(TAG, "SDK auth success"); }
                        @Override public void error()   { Log.e(TAG, "SDK auth failed");  }
                    });

                // Step 2: Mandatory delay before configuration
                Thread.sleep(1500);

                // Configure BEFORE init — mirrors the vendor demo's MyApplication
                // exactly (enableAsr(false) + enableSlam + setRobotType +
                // setPersonCheckType all before init). Calling setPersonCheckType
                // AFTER init (as our PersonDetectPlugin did) reconfigured the
                // perception engine at runtime and raced the iFlytek AIUI teardown
                // (libaiui destroyAgent → "pthread_mutex_lock on a destroyed mutex"),
                // crashing the app on launch. Doing it here, pre-init, matches the demo.
                CsjRobot.enableAsr(false);
                // Face module ON — required for person detection: the SDK fires
                // OnDetectPersonListener from FACE_DETECT_PERSON_NEAR_NTF, which the
                // RGBD/face module produces. (Demo uses enableFace(true) too.)
                CsjRobot.enableFace(true);
                CsjRobot.enableSlam(true);  // Enable SLAM for chassis movement
                CsjRobot.setRobotType(CsjRobot.RobotType.TIMO);

                // ALWAYS call setIpAndrPort — it does two things: sets the robot-core
                // address AND flips the SDK to SOCKET transport (useSocket=true).
                // Skipping it for 127.0.0.1 (the old guard) left the robot flavor on
                // MQTT (HandlerMsgService → broker at 127.0.0.1:60002), which this
                // robot has no broker for, so the SDK never connected and no
                // robot-state callbacks fired (battery/person/nav all dead). The
                // remote flavor already did this and worked → socket is the path.
                CsjRobot.setIpAndrPort(BuildConfig.SDK_IP, BuildConfig.SDK_PORT);

                // Person-detection sensors (laser + RGBD + ultrasonic), pre-init like
                // the demo. PersonDetectPlugin only registers the listener now.
                CsjRobot.getInstance().setPersonCheckType(true, true, true);

                // ── SDK ↔ robot-core CONNECTION DIAGNOSTICS ─────────────────────
                // The SDK reaches robot-core over MQTT (init → connectToMqtt). When
                // that link is down, NO robot-state callbacks fire — so battery
                // falls back to the head/tablet value, person detection is silent,
                // and chassis nav never becomes ready. These listeners make the
                // connection state visible instead of inferring it from logcat.
                Log.d(TAG, "SDK target: defaultIp=" + CsjRobot.getDefaultIpAddr()
                        + " defaultPort=" + CsjRobot.getDefaultPort()
                        + " (flavor ip=" + BuildConfig.SDK_IP + ":" + BuildConfig.SDK_PORT + ")");

                CsjRobot.getInstance().setOnMqttConnectStateListener(connected ->
                        Log.d(TAG, "SDK-DIAG mqttConnect=" + connected));

                CsjRobot.getInstance().setRobotConnectionStateListener(connected ->
                        Log.d(TAG, "SDK-DIAG robotConnectState=" + connected));

                CsjRobot.getInstance().setOnInitListener(new OnRobotInitListener() {
                    @Override public void onBasicInfoState(int s, String m)     { Log.d(TAG, "SDK-DIAG init.basicInfo=" + s + " " + m); }
                    @Override public void onServerConnectState(int s, String m) { Log.d(TAG, "SDK-DIAG init.serverConnect=" + s + " " + m); }
                    @Override public void onHardWareHealthState(int s, String m){ Log.d(TAG, "SDK-DIAG init.hardware=" + s + " " + m); }
                    @Override public void onSlamState(int s, String m)          { Log.d(TAG, "SDK-DIAG init.slam=" + s + " " + m); }
                    @Override public void onSoftWareState(int s, String m)      { Log.d(TAG, "SDK-DIAG init.software=" + s + " " + m); }
                });

                // Step 7: Init
                CsjRobot.getInstance().init(MikeeApplication.this);

                // Register the person-detection listener AFTER init so it binds to
                // a live perception engine (registering at Activity start raced this
                // async init → the listener never attached and detection never fired).
                PersonDetectPlugin.registerWithSdk();

                // Staff face-recognition listener (greet-by-name). Appends to the
                // SDK's face-listener list — coexists with PersonDetectPlugin above.
                FaceRecognitionPlugin.registerWithSdk();

                Log.d(TAG, "SDK initialized — flavor=" + BuildConfig.FLAVOR
                        + "  ip=" + BuildConfig.SDK_IP);

            } catch (Exception e) {
                Log.e(TAG, "SDK init failed: " + e.getMessage());
            }
        }).start();
    }
}
