package com.mikee.robotapp;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

/**
 * Auto-bring-up after a device reboot — replaces the Mac-side robot_bringup.sh so
 * the robot returns to a working voice state on its own.
 *
 * On BOOT_COMPLETED:
 *   1. Wait for robotsdk to come up, then FREE THE MIC (Option B): stop robotsdk's
 *      own AIUI service (root) so our app can own the mic. Chassis/SLAM untouched.
 *   2. Launch Mikee (this app doesn't run its own AIUI until a Talk session, and
 *      startSpeechEngine also frees the mic then — this is belt-and-suspenders).
 *
 * Needs RECEIVE_BOOT_COMPLETED. Root via this robot's eng-build su ("su 0 <cmd>").
 */
public class BootReceiver extends BroadcastReceiver {
    private static final String TAG = "Mikee.Boot";
    private static final String ROBOTSDK_AIUI_SERVICE =
            "com.csjbot.robotsdk.ten/com.csjbot.asragent.aiui_soft.AiuiMixedService";

    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null || !Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())) return;
        Log.d(TAG, "BOOT_COMPLETED → free mic (Option B) + launch Mikee");

        // Free the mic off the main thread, after a grace period for robotsdk to boot
        // and start its AIUI (so there's something to stop). startSpeechEngine frees it
        // again per session, so exact timing here is not critical.
        new Thread(() -> {
            try { Thread.sleep(10000); } catch (InterruptedException ignore) {}
            try {
                Process p = Runtime.getRuntime().exec(new String[]{
                        "su", "0", "sh", "-c", "am stopservice " + ROBOTSDK_AIUI_SERVICE});
                p.waitFor();
                Log.d(TAG, "boot mic-free exit=" + p.exitValue());
            } catch (Throwable t) {
                Log.w(TAG, "boot mic-free failed: " + t.getMessage());
            }
        }, "mikee-boot-mic").start();

        try {
            Intent launch = new Intent(context, MainActivity.class);
            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            context.startActivity(launch);
            Log.d(TAG, "Mikee launch requested");
        } catch (Throwable t) {
            Log.w(TAG, "boot launch failed: " + t.getMessage());
        }
    }
}
