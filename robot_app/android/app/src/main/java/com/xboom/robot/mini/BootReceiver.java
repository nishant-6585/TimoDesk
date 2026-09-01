package com.xboom.robot.mini;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;

/**
 * Auto-bring-up after a device reboot — replaces the PC-side robot_bringup.sh so
 * the robot returns to a working voice + chassis state on its own.
 *
 * On BOOT_COMPLETED this receiver does exactly ONE thing: deploy the bundled
 * assets/mikee_bringup.sh into this app's files dir and detach-run it as root.
 * Everything else (start robotsdk first, fresh app process AFTER robotsdk, mic
 * reclaim kill-loop, ordered restarts) happens in that root shell, independent of
 * this process — which matters because:
 *   - Android 14 blocks startActivity() from a boot receiver (the old approach
 *     silently never launched the app); a root `am start` is exempt.
 *   - The CSJBot binder inits in MikeeApplication.onCreate, i.e. at PROCESS start.
 *     Receiving this broadcast spawns our process before robotsdk is up, so the
 *     script must be able to kill and relaunch us — impossible from in-process.
 *   - The Option-B `am stopservice` mic-free does NOT release the ALSA fd on this
 *     unit (verified 2026-08-18/20); only the force-stop kill-loop works, and it
 *     must be sequenced with taps + verified holds (the script does this).
 *
 * Needs RECEIVE_BOOT_COMPLETED. Root via this robot's su ("su 0 ...").
 * Script log: /data/local/tmp/mikee_bringup.log (written by the root shell).
 */
public class BootReceiver extends BroadcastReceiver {
    private static final String TAG = "Mikee.Boot";
    private static final String SCRIPT_ASSET = "mikee_bringup.sh";

    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null || !Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())) return;
        Log.d(TAG, "BOOT_COMPLETED → deploy + detach-run bringup script as root");
        final Context app = context.getApplicationContext();
        new Thread(() -> runBringup(app), "mikee-boot-bringup").start();
    }

    static void runBringup(Context context) {
        // The app cannot write /data/local/tmp (shell-owned); its own files dir
        // works, and root has no trouble reading it from there.
        File script = new File(context.getFilesDir(), SCRIPT_ASSET);
        try {
            deployScript(context, script);
        } catch (Throwable t) {
            Log.w(TAG, "script deploy failed: " + t.getMessage() + " — trying existing copy");
        }
        if (!script.exists()) {
            Log.w(TAG, "no bringup script at " + script + " — aborting");
            return;
        }
        try {
            // nohup + & so the script survives this process being killed by its own
            // step 2 (it kills the early app process the broadcast spawned).
            Process p = Runtime.getRuntime().exec(new String[]{
                    "su", "0", "sh", "-c",
                    "nohup sh " + script.getAbsolutePath() + " >/dev/null 2>&1 &"});
            p.waitFor();
            Log.d(TAG, "bringup script launched, su exit=" + p.exitValue());
        } catch (Throwable t) {
            Log.w(TAG, "bringup launch failed: " + t.getMessage());
        }
    }

    private static void deployScript(Context context, File dest) throws Exception {
        try (InputStream in = context.getAssets().open(SCRIPT_ASSET);
             FileOutputStream out = new FileOutputStream(dest)) {
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
        }
        Log.d(TAG, "deployed " + SCRIPT_ASSET + " -> " + dest);
    }
}
