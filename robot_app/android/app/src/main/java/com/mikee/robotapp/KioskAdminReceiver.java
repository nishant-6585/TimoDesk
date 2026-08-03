package com.mikee.robotapp;

import android.app.admin.DeviceAdminReceiver;

/**
 * Device-admin component required to make Mikee the DEVICE-OWNER (kiosk).
 * Activate once via: adb shell dpm set-device-owner com.mikee.robotapp/.KioskAdminReceiver
 * (needs 0 accounts on the device — verified). Remove: dpm remove-active-admin.
 */
public class KioskAdminReceiver extends DeviceAdminReceiver {
}
