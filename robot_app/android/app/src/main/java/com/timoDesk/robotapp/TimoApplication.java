package com.timoDesk.robotapp;

import android.util.Log;

import androidx.multidex.MultiDexApplication;

import com.csjbot.coshandler.core.CsjRobot;
import com.csjbot.coshandler.listener.OnAuthenticationListener;

public class TimoApplication extends MultiDexApplication {

    private static final String TAG = "TimoDesk";

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
                CsjRobot.enableFace(false);
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
                CsjRobot.getInstance().init(TimoApplication.this);

                Log.d(TAG, "SDK initialized — flavor=" + BuildConfig.FLAVOR
                        + "  ip=" + BuildConfig.SDK_IP);

            } catch (Exception e) {
                Log.e(TAG, "SDK init failed: " + e.getMessage());
            }
        }).start();
    }
}
