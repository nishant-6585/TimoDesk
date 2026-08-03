package com.mikee.robotapp;

import android.app.Activity;
import android.app.admin.DevicePolicyManager;
import android.content.ComponentName;
import android.content.Context;
import android.os.Build;
import android.util.Log;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * Kiosk / Lock Task Mode. Enforceable only when the app is DEVICE-OWNER:
 *   adb shell dpm set-device-owner com.mikee.robotapp/.KioskAdminReceiver
 * All calls no-op gracefully if not device-owner (app still runs, just unlocked).
 *
 * API note: this robot is Android 7.1.2 (API 25). setLockTaskFeatures (granular
 * Home/Recents/status-bar allow) is API 28+, so on 25 it's all-or-nothing:
 *   allowSystemUi=false → startLockTask() (pinned, bars blocked)
 *   allowSystemUi=true  → stopLockTask()  (system UI available for maintenance)
 * On API 28+ we stay locked and use setLockTaskFeatures for the granular toggle.
 */
public class KioskPlugin implements MethodChannel.MethodCallHandler {
    private static final String TAG = "Mikee.Kiosk";

    private final Activity activity;
    private final DevicePolicyManager dpm;
    private final ComponentName admin;

    KioskPlugin(Activity activity) {
        this.activity = activity;
        this.dpm = (DevicePolicyManager) activity.getSystemService(Context.DEVICE_POLICY_SERVICE);
        this.admin = new ComponentName(activity, KioskAdminReceiver.class);
    }

    private boolean isOwner() {
        return dpm != null && dpm.isDeviceOwnerApp(activity.getPackageName());
    }

    @Override
    public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        switch (call.method) {
            case "isDeviceOwner":
                result.success(isOwner());
                break;
            case "startKiosk": {
                boolean allow = Boolean.TRUE.equals(call.argument("allowSystemUi"));
                if (isOwner()) {
                    try {
                        dpm.setLockTaskPackages(admin, new String[]{activity.getPackageName()});
                    } catch (Throwable t) {
                        Log.w(TAG, "setLockTaskPackages: " + t.getMessage());
                    }
                }
                applyMode(allow);
                Log.d(TAG, "startKiosk owner=" + isOwner() + " allowSystemUi=" + allow);
                result.success(null);
                break;
            }
            case "setSystemUi": {
                boolean allow = Boolean.TRUE.equals(call.argument("allow"));
                applyMode(allow);
                result.success(null);
                break;
            }
            default:
                result.notImplemented();
        }
    }

    /** Apply the lock-task state for the current [allowSystemUi] preference. */
    private void applyMode(boolean allowSystemUi) {
        // API 28+ : stay pinned, toggle features granularly.
        if (isOwner() && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            int f = allowSystemUi
                    ? (DevicePolicyManager.LOCK_TASK_FEATURE_HOME
                     | DevicePolicyManager.LOCK_TASK_FEATURE_OVERVIEW
                     | DevicePolicyManager.LOCK_TASK_FEATURE_NOTIFICATIONS
                     | DevicePolicyManager.LOCK_TASK_FEATURE_SYSTEM_INFO
                     | DevicePolicyManager.LOCK_TASK_FEATURE_GLOBAL_ACTIONS)
                    : DevicePolicyManager.LOCK_TASK_FEATURE_NONE;
            try {
                dpm.setLockTaskFeatures(admin, f);
            } catch (Throwable t) {
                Log.w(TAG, "setLockTaskFeatures: " + t.getMessage());
            }
            activity.runOnUiThread(this::safeStartLockTask);
            return;
        }
        // API < 28 (this robot): all-or-nothing.
        activity.runOnUiThread(() -> {
            if (allowSystemUi) {
                try { activity.stopLockTask(); } catch (Throwable t) { Log.w(TAG, "stopLockTask: " + t.getMessage()); }
            } else {
                safeStartLockTask();
            }
        });
    }

    private void safeStartLockTask() {
        try {
            activity.startLockTask();
        } catch (Throwable t) {
            Log.w(TAG, "startLockTask: " + t.getMessage());
        }
    }
}
