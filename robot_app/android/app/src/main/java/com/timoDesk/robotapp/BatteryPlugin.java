package com.timoDesk.robotapp;

import android.content.Context;
import android.os.BatteryManager;
import android.content.IntentFilter;
import android.content.Intent;
import android.content.BroadcastReceiver;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel.Result;
import java.util.HashMap;
import java.util.Map;

public class BatteryPlugin implements MethodChannel.MethodCallHandler {
    private static final String BATTERY_CHANNEL = "com.timoDesk/battery";
    private final Context context;
    private MethodChannel methodChannel;

    public BatteryPlugin(Context context) {
        this.context = context;
    }

    public void setup(FlutterEngine flutterEngine) {
        methodChannel = new MethodChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                BATTERY_CHANNEL
        );
        methodChannel.setMethodCallHandler(this);
    }

    @Override
    public void onMethodCall(MethodCall call, Result result) {
        switch (call.method) {
            case "getBatteryLevel":
                getBatteryLevel(result);
                break;
            case "broadcastBatteryUpdate":
                broadcastBatteryUpdate(call, result);
                break;
            default:
                result.notImplemented();
                break;
        }
    }

    private void getBatteryLevel(MethodChannel.Result result) {
        try {
            BatteryManager batteryManager = (BatteryManager) context.getSystemService(Context.BATTERY_SERVICE);
            IntentFilter ifilter = new IntentFilter(Intent.ACTION_BATTERY_CHANGED);
            Intent batteryStatus = context.registerReceiver(null, ifilter);

            if (batteryStatus != null) {
                int level = batteryStatus.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
                int scale = batteryStatus.getIntExtra(BatteryManager.EXTRA_SCALE, -1);
                int status = batteryStatus.getIntExtra(BatteryManager.EXTRA_STATUS, -1);

                // Calculate percentage
                int batteryPercentage = Math.round(level * 100.0f / scale);

                // Check if charging
                boolean isCharging = (status == BatteryManager.BATTERY_STATUS_CHARGING ||
                        status == BatteryManager.BATTERY_STATUS_FULL);

                // Return battery info
                Map<String, Object> response = new HashMap<>();
                response.put("level", batteryPercentage);
                response.put("isCharging", isCharging);
                response.put("status", status);

                System.out.println("[BatteryPlugin] Battery Level: " + batteryPercentage + "% (Charging: " + isCharging + ")");
                result.success(response);
            } else {
                result.error("BATTERY_ERROR", "Could not get battery status", null);
            }
        } catch (Exception e) {
            System.err.println("[BatteryPlugin] Error: " + e.getMessage());
            result.error("BATTERY_ERROR", e.getMessage(), null);
        }
    }

    private void broadcastBatteryUpdate(MethodCall call, Result result) {
        try {
            // Extract battery data from arguments
            @SuppressWarnings("unchecked")
            Map<String, Object> args = (Map<String, Object>) call.arguments;

            if (args != null) {
                String type = (String) args.get("type");
                @SuppressWarnings("unchecked")
                Map<String, Object> payload = (Map<String, Object>) args.get("payload");

                if ("battery_update".equals(type) && payload != null) {
                    int level = ((Number) payload.get("level")).intValue();

                    // Log the broadcast
                    System.out.println("[BatteryPlugin] Broadcasting battery_update: " + level + "%");

                    // Send to all WebSocket clients via WebSocketBroadcaster
                    WebSocketBroadcaster.getInstance().broadcastBatteryUpdate(level);

                    result.success(null);
                } else {
                    result.error("INVALID_ARGS", "Invalid broadcast arguments", null);
                }
            } else {
                result.error("NULL_ARGS", "Arguments cannot be null", null);
            }
        } catch (Exception e) {
            System.err.println("[BatteryPlugin] Broadcast error: " + e.getMessage());
            result.error("BROADCAST_ERROR", e.getMessage(), null);
        }
    }
}
