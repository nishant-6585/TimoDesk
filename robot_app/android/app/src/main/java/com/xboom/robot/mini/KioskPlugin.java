package com.xboom.robot.mini;

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
 *   adb shell dpm set-device-owner com.xboom.robot.mini/.KioskAdminReceiver
 * All calls no-op gracefully if not device-owner (app still runs, just unlocked).
 *
 * PLATFORM NOTE: this robot runs Android 14 (API 34) — verified via
 * `getprop ro.build.version.sdk` = 34 (older comments/docs that said 7.1.2/API 25
 * were wrong). So the granular setLockTaskFeatures path (API 28+) is what runs.
 *
 * TWO MODES (Settings → "Allow Home / Recents" switch, itself behind the admin PIN):
 *   LOCKDOWN    (allowSystemUi=false): allowlist = {this app}, features = NONE,
 *               startLockTask() → only Mikee runs; Home/Recents/status-bar blocked.
 *   MAINTENANCE (allowSystemUi=true):  stopLockTask() → lock task fully released so
 *               an operator can open Settings / any other app.
 *
 * PREVIOUS BUG (fixed here): the API-28+ branch ALWAYS re-called startLockTask(),
 * even in maintenance, and the lock-task allowlist only ever contained this app.
 * Result: with Home/Recents enabled the launcher appeared but tapping any other
 * app icon did nothing — the system blocks launching a package that isn't on the
 * lock-task allowlist while lock task is active. Fully releasing the lock in
 * maintenance is the correct fix (and matches how kiosk exit is normally done).
 */
public class KioskPlugin implements MethodChannel.MethodCallHandler {
    private static final String TAG = "Mikee.Kiosk";

    private final Activity activity;
    private final DevicePolicyManager dpm;
    private final ComponentName admin;

    // Desired lockdown state, tracked so MainActivity.onResume can re-pin a kiosk
    // that somehow dropped out of lock task (stray system intent, dialog, etc.).
    // Starts true = locked; corrected on the first startKiosk() call from Dart.
    private volatile boolean lockdownDesired = true;

    // Guards the onResume re-pin against a startup race: Dart reads the persisted
    // allowSystemUi pref and calls startKiosk() only after the first frame, which
    // is AFTER the initial onResume. Without this flag, that early onResume would
    // re-pin with the default lockdownDesired=true and clobber a maintenance boot.
    // reassertLock() stays a no-op until Dart has set the mode at least once.
    private volatile boolean modeApplied = false;

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
                applyMode(allow);
                Log.d(TAG, "startKiosk owner=" + isOwner() + " allowSystemUi=" + allow);
                result.success(null);
                break;
            }
            case "setSystemUi": {
                boolean allow = Boolean.TRUE.equals(call.argument("allow"));
                applyMode(allow);
                Log.d(TAG, "setSystemUi owner=" + isOwner() + " allowSystemUi=" + allow);
                result.success(null);
                break;
            }
            default:
                result.notImplemented();
        }
    }

    /**
     * Apply the lock-task state.
     *   allowSystemUi=true  → MAINTENANCE: release lock task (any app reachable).
     *   allowSystemUi=false → LOCKDOWN:    pin to this app only.
     */
    private void applyMode(boolean allowSystemUi) {
        lockdownDesired = !allowSystemUi;
        modeApplied = true;

        if (!isOwner()) {
            // Not device-owner: best-effort screen pinning (all-or-nothing, needs
            // an on-screen confirm). Lets a dev exercise the flow without ownership.
            activity.runOnUiThread(() -> {
                if (allowSystemUi) safeStopLockTask();
                else safeStartLockTask();
            });
            return;
        }

        if (allowSystemUi) {
            // MAINTENANCE: fully exit lock task so the operator can open any app.
            activity.runOnUiThread(this::safeStopLockTask);
            return;
        }

        // LOCKDOWN: restrict the allowlist to this app, strip all system-UI
        // features, then pin. Order matters — set the allowlist before pinning.
        try {
            dpm.setLockTaskPackages(admin, new String[]{ activity.getPackageName() });
        } catch (Throwable t) {
            Log.w(TAG, "setLockTaskPackages: " + t.getMessage());
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                dpm.setLockTaskFeatures(admin, DevicePolicyManager.LOCK_TASK_FEATURE_NONE);
            } catch (Throwable t) {
                Log.w(TAG, "setLockTaskFeatures: " + t.getMessage());
            }
        }
        activity.runOnUiThread(this::safeStartLockTask);
    }

    /**
     * Re-assert lockdown if that's the desired state. Called from
     * MainActivity.onResume so a kiosk that fell out of lock task re-pins itself.
     * No-op in maintenance mode or when not device-owner.
     */
    void reassertLock() {
        if (modeApplied && isOwner() && lockdownDesired) {
            applyMode(false);
        }
    }

    private void safeStartLockTask() {
        try {
            activity.startLockTask();
        } catch (Throwable t) {
            Log.w(TAG, "startLockTask: " + t.getMessage());
        }
    }

    private void safeStopLockTask() {
        try {
            activity.stopLockTask();
        } catch (Throwable t) {
            Log.w(TAG, "stopLockTask: " + t.getMessage());
        }
    }
}
