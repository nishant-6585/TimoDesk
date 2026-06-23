package com.mikee.robotapp;

import android.util.Log;

import androidx.multidex.MultiDexApplication;

import com.csjbot.coshandler.core.CsjRobot;
import com.csjbot.coshandler.listener.OnAuthenticationListener;

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

                // Remote flavor: point SDK at the robot over WiFi instead of localhost
                if (!BuildConfig.SDK_IP.equals("127.0.0.1")) {
                    CsjRobot.setIpAndrPort(BuildConfig.SDK_IP, BuildConfig.SDK_PORT);
                }

                // Person-detection sensors (laser + RGBD + ultrasonic), pre-init like
                // the demo. PersonDetectPlugin only registers the listener now.
                CsjRobot.getInstance().setPersonCheckType(true, true, true);

                // Step 7: Init
                CsjRobot.getInstance().init(MikeeApplication.this);

                // Register the person-detection listener AFTER init so it binds to
                // a live perception engine (registering at Activity start raced this
                // async init → the listener never attached and detection never fired).
                PersonDetectPlugin.registerWithSdk();

                Log.d(TAG, "SDK initialized — flavor=" + BuildConfig.FLAVOR
                        + "  ip=" + BuildConfig.SDK_IP);

            } catch (Exception e) {
                Log.e(TAG, "SDK init failed: " + e.getMessage());
            }
        }).start();
    }
}
