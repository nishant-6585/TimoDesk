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

                // Steps 3–6: Configure before init
                CsjRobot.enableAsr(false);
                CsjRobot.enableFace(false);
                CsjRobot.enableSlam(false);
                CsjRobot.setRobotType(CsjRobot.RobotType.TIMO);

                // Remote flavor: point SDK at the robot over WiFi instead of localhost
                if (!BuildConfig.SDK_IP.equals("127.0.0.1")) {
                    CsjRobot.setIpAndrPort(BuildConfig.SDK_IP, BuildConfig.SDK_PORT);
                }

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
