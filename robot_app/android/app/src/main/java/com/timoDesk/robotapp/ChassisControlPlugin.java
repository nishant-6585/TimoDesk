package com.timoDesk.robotapp;

import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.io.OutputStreamWriter;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Base64;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.ScheduledFuture;

import com.csjbot.coshandler.core.CsjRobot;
import com.csjbot.coshandler.listener.OnMapStateListener;

public class ChassisControlPlugin implements MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private static final String TAG = "TimoDesk.ChassisControl";
    private static final int PORT = 8082;
    private static final int RATE_LIMIT_MS = 80;
    private static final int STOP_DELAY_MS = 300;
    private static final float SPEED_MIN = 0.3f;
    private static final float SPEED_MAX = 0.8f;
    private static final int MAX_CLIENTS = 3;

    private ServerSocket serverSocket;
    private ExecutorService executor;
    private ScheduledExecutorService scheduler;
    private volatile boolean running = false;
    private volatile float currentSpeed = 0.5f;
    private volatile String currentDirection = "none";
    private volatile boolean isMoving = false;
    private volatile boolean isChassisReady = false;
    private volatile int currentLinear = 0;
    private volatile int currentAngular = 0;
    private Set<ClientHandler> clients = new HashSet<>();
    private long lastCommandTime = 0;
    private EventChannel.EventSink eventSink;
    private Handler mainHandler = new Handler(Looper.getMainLooper());
    private ScheduledExecutorService heartbeatExecutor;
    private ScheduledFuture<?> heartbeatTask;
    private ScheduledFuture<?> stopTimer;

    @Override
    public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        switch (call.method) {
            case "startChassisControl":
                startServer();
                result.success(buildStatus());
                break;
            case "stopChassisControl":
                stopServer();
                result.success(buildStatus());
                break;
            case "emergencyStop":
                emergencyStop();
                result.success(buildStatus());
                break;
            case "setSpeed":
                float speed = ((Number) call.argument("speed")).floatValue();
                setSpeed(speed);
                result.success(buildStatus());
                break;
            case "getChassisStatus":
                result.success(buildStatus());
                break;
            default:
                result.notImplemented();
        }
    }

    private void startServer() {
        if (running) return;
        running = true;
        executor = Executors.newCachedThreadPool();
        scheduler = Executors.newScheduledThreadPool(1);
        heartbeatExecutor = Executors.newSingleThreadScheduledExecutor();

        initChassisMovement();

        new Thread(() -> {
            try {
                serverSocket = new ServerSocket(PORT);
                Log.d(TAG, "WebSocket server started on port " + PORT);
                emitEvent(buildStatus());

                while (running) {
                    try {
                        if (clients.size() >= MAX_CLIENTS) {
                            Thread.sleep(100);
                            continue;
                        }
                        Socket clientSocket = serverSocket.accept();
                        executor.execute(new ClientHandler(clientSocket));
                    } catch (IOException e) {
                        if (running) Log.e(TAG, "Accept error: " + e.getMessage());
                    } catch (InterruptedException e) {
                        Thread.currentThread().interrupt();
                    }
                }
            } catch (IOException e) {
                Log.e(TAG, "Server error: " + e.getMessage());
                running = false;
            } finally {
                try {
                    if (serverSocket != null) serverSocket.close();
                } catch (IOException e) {
                    Log.e(TAG, "Close error: " + e.getMessage());
                }
            }
        }).start();
    }

    private void stopServer() {
        running = false;
        cancelMove();
        try {
            if (serverSocket != null) serverSocket.close();
        } catch (IOException e) {
            Log.e(TAG, "Error closing server: " + e.getMessage());
        }
        synchronized (clients) {
            for (ClientHandler client : clients) {
                client.close();
            }
            clients.clear();
        }
        if (scheduler != null && !scheduler.isShutdown()) {
            scheduler.shutdown();
        }
        if (executor != null && !executor.isShutdown()) {
            executor.shutdown();
        }
        if (heartbeatExecutor != null && !heartbeatExecutor.isShutdown()) {
            heartbeatExecutor.shutdown();
        }
        emitEvent(buildStatus());
    }

    private void emergencyStop() {
        cancelMove();
    }

    private void cancelMove() {
        stopMoving();
    }

    private void setSpeed(float speed) {
        speed = Math.max(SPEED_MIN, Math.min(SPEED_MAX, speed));
        currentSpeed = speed;
        try {
            CsjRobot.getInstance().getAction().setSpeed(speed);
            emitEvent(buildStatus());
        } catch (Exception e) {
            Log.e(TAG, "Speed error: " + e.getMessage());
        }
    }

    private void executeMove(String direction) {
        long now = System.currentTimeMillis();
        if (now - lastCommandTime < RATE_LIMIT_MS) return;
        lastCommandTime = now;

        if (stopTimer != null) {
            stopTimer.cancel(false);
        }

        try {
            currentDirection = direction;
            isMoving = true;
            Log.d(TAG, "About to call SDK method for: " + direction + " (SLAM ready: " + isChassisReady + ")");

            if (isChassisReady) {
                // SLAM path (preferred)
                switch (direction) {
                    case "forward":
                        Log.d(TAG, "Calling moveForward()");
                        CsjRobot.getInstance().getAction().moveForward();
                        Log.d(TAG, "moveForward() returned");
                        break;
                    case "back":
                        Log.d(TAG, "Calling moveBack()");
                        CsjRobot.getInstance().getAction().moveBack();
                        Log.d(TAG, "moveBack() returned");
                        break;
                    case "left":
                        Log.d(TAG, "Calling moveLeft()");
                        CsjRobot.getInstance().getAction().moveLeft();
                        Log.d(TAG, "moveLeft() returned");
                        break;
                    case "right":
                        Log.d(TAG, "Calling moveRight()");
                        CsjRobot.getInstance().getAction().moveRight();
                        Log.d(TAG, "moveRight() returned");
                        break;
                }
            } else {
                // Direct serial path (bypasses SLAM — works without map)
                Log.d(TAG, "Using moveBySerial (SLAM not ready)");
                // moveBySerial takes a single int parameter (move code)
                switch (direction) {
                    case "forward":
                        Log.d(TAG, "moveBySerial forward (0x01)");
                        CsjRobot.getInstance().getAction().moveBySerial(0x01);
                        break;
                    case "back":
                        Log.d(TAG, "moveBySerial back (0x02)");
                        CsjRobot.getInstance().getAction().moveBySerial(0x02);
                        break;
                    case "left":
                        Log.d(TAG, "moveBySerial left (0x03)");
                        CsjRobot.getInstance().getAction().moveBySerial(0x03);
                        break;
                    case "right":
                        Log.d(TAG, "moveBySerial right (0x04)");
                        CsjRobot.getInstance().getAction().moveBySerial(0x04);
                        break;
                }
            }

            // Use new heartbeat approach for moveSerial
            startMoving(directionToLinearAngular(direction)[0], directionToLinearAngular(direction)[1]);
        } catch (Exception e) {
            Log.e(TAG, "Move error: " + e.getMessage(), e);
            e.printStackTrace();
        }
    }

    private int[] directionToLinearAngular(String direction) {
        switch (direction) {
            case "forward": return new int[]{200, 0};
            case "back": return new int[]{-200, 0};
            case "left": return new int[]{0, 500};
            case "right": return new int[]{0, -500};
            default: return new int[]{0, 0};
        }
    }

    private void startMoving(int linear, int angular) {
        currentLinear = linear;
        currentAngular = angular;

        if (heartbeatTask != null) {
            heartbeatTask.cancel(false);
        }

        if (heartbeatExecutor == null || heartbeatExecutor.isShutdown()) {
            Log.e(TAG, "ERROR: heartbeatExecutor is null or shutdown! Creating new one");
            heartbeatExecutor = Executors.newSingleThreadScheduledExecutor();
        }

        Log.d(TAG, "Scheduling 30ms heartbeat for moveSerial (executor=" + (heartbeatExecutor != null ? "OK" : "NULL") + ")");
        final int[] count = {0};
        try {
            heartbeatTask = heartbeatExecutor.scheduleAtFixedRate(() -> {
                try {
                    count[0]++;
                    if (count[0] % 10 == 0) {
                        Log.d(TAG, "Heartbeat #" + count[0] + ": moveSerial(" + currentLinear + ", " + currentAngular + ")");
                    }
                    CsjRobot.getInstance().getAction().moveSerial(currentLinear, currentAngular);
                } catch (Exception e) {
                    Log.e(TAG, "moveSerial error: " + e.getMessage());
                }
            }, 0, 30, TimeUnit.MILLISECONDS);
            Log.d(TAG, "Heartbeat task scheduled successfully");
        } catch (Exception e) {
            Log.e(TAG, "Failed to schedule heartbeat: " + e.getMessage());
        }

        isMoving = true;
        currentDirection = linearAngularToDirection(linear, angular);
        Log.d(TAG, "Started moving: " + currentDirection + " (linear=" + linear + ", angular=" + angular + ")");
        emitEvent(buildStatus());
    }

    private void stopMoving() {
        if (heartbeatTask != null) {
            heartbeatTask.cancel(false);
            heartbeatTask = null;
        }

        try {
            CsjRobot.getInstance().getAction().moveSerial(0, 0);
        } catch (Exception e) {
            Log.e(TAG, "moveSerial stop error: " + e.getMessage());
        }

        currentLinear = 0;
        currentAngular = 0;
        isMoving = false;
        currentDirection = "none";
        Log.d(TAG, "Stopped moving");
        emitEvent(buildStatus());
    }

    private String linearAngularToDirection(int l, int a) {
        if (l > 0) return "forward";
        if (l < 0) return "back";
        if (a > 0) return "left";
        if (a < 0) return "right";
        return "none";
    }

    private void executeRotate(float degrees) {
        long now = System.currentTimeMillis();
        if (now - lastCommandTime < RATE_LIMIT_MS) return;
        lastCommandTime = now;

        if (stopTimer != null) {
            stopTimer.cancel(false);
        }

        try {
            currentDirection = "rotate";
            isMoving = true;
            CsjRobot.getInstance().getAction().moveAngle((int)degrees, null);

            stopTimer = scheduler.schedule(this::cancelMove, STOP_DELAY_MS, TimeUnit.MILLISECONDS);
            emitEvent(buildStatus());
        } catch (Exception e) {
            Log.e(TAG, "Rotate error: " + e.getMessage());
        }
    }

    private Map<String, Object> buildStatus() {
        Map<String, Object> m = new HashMap<>();
        m.put("isRunning", running);
        m.put("port", PORT);
        m.put("clientCount", clients.size());
        m.put("isMoving", isMoving);
        m.put("speed", currentSpeed);
        m.put("direction", currentDirection);
        return m;
    }

    private void emitEvent(Map<String, Object> data) {
        if (eventSink != null) {
            mainHandler.post(() -> {
                try {
                    eventSink.success(data);
                } catch (Exception e) {
                    Log.e(TAG, "Event error: " + e.getMessage());
                }
            });
        }
    }

    @Override
    public void onListen(Object args, EventChannel.EventSink sink) {
        eventSink = sink;
    }

    @Override
    public void onCancel(Object args) {
        eventSink = null;
    }

    private void initChassisMovement() {
        Log.d(TAG, "initChassisMovement called");
        try {
            // Listen for navi state changes (naviReady + motion_mode)
            CsjRobot.getInstance().setonRobotNaviStatesListener((naviReady, motionMode) -> {
                Log.d(TAG, "NaviStates: naviReady=" + naviReady + " motionMode=" + motionMode);
                if (naviReady) {
                    // Switch to manual/track mode (mode=1) for direct movement commands
                    CsjRobot.getInstance().getAction().setNaviMode(1);
                    Log.d(TAG, "SLAM ready → setNaviMode(1) sent");
                    isChassisReady = true;
                } else {
                    isChassisReady = false;
                }
                emitEvent(buildStatus());
            });

            // Call search() — triggers NAVI_ROBOT_STATES_NTF response
            CsjRobot.getInstance().getAction().search(result -> {
                Log.d(TAG, "search() result: " + result);
            });
        } catch (Exception e) {
            Log.e(TAG, "initChassisMovement error: " + e.getMessage());
        }
    }

    private class ClientHandler implements Runnable {
        private Socket socket;
        private InputStream inputStream;
        private OutputStream outputStream;
        private BufferedReader textReader;
        private BufferedWriter textWriter;
        private volatile boolean connected = false;

        ClientHandler(Socket socket) {
            this.socket = socket;
        }

        @Override
        public void run() {
            try {
                inputStream = socket.getInputStream();
                outputStream = socket.getOutputStream();
                textReader = new BufferedReader(new InputStreamReader(inputStream, StandardCharsets.UTF_8));
                textWriter = new BufferedWriter(new OutputStreamWriter(outputStream, StandardCharsets.UTF_8));

                try {
                    if (!performHandshake()) {
                        close();
                        return;
                    }
                } catch (java.security.NoSuchAlgorithmException e) {
                    Log.e(TAG, "Handshake error: " + e.getMessage());
                    close();
                    return;
                }

                connected = true;
                synchronized (clients) {
                    clients.add(this);
                }
                emitEvent(buildStatus());

                sendJson(buildStatusMessage());

                while (connected) {
                    String message = readWebSocketFrame();
                    if (message != null) {
                        Log.d(TAG, "Frame received: " + message.substring(0, Math.min(100, message.length())));
                        handleMessage(message);
                    } else {
                        break;
                    }
                }
            } catch (IOException e) {
                Log.e(TAG, "Client error: " + e.getMessage());
            } finally {
                close();
            }
        }

        private boolean performHandshake() throws IOException, java.security.NoSuchAlgorithmException {
            String line;
            String key = null;

            while ((line = textReader.readLine()) != null && !line.isEmpty()) {
                if (line.startsWith("Sec-WebSocket-Key:")) {
                    key = line.substring(19).trim();
                }
            }

            if (key == null) return false;

            String magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
            String combined = key + magic;
            MessageDigest md = MessageDigest.getInstance("SHA-1");
            byte[] hash = md.digest(combined.getBytes(StandardCharsets.UTF_8));
            String accept = Base64.getEncoder().encodeToString(hash);

            textWriter.write("HTTP/1.1 101 Switching Protocols\r\n");
            textWriter.write("Upgrade: websocket\r\n");
            textWriter.write("Connection: Upgrade\r\n");
            textWriter.write("Sec-WebSocket-Accept: " + accept + "\r\n\r\n");
            textWriter.flush();

            return true;
        }

        private String readWebSocketFrame() throws IOException {
            byte b = (byte) inputStream.read();
            if (b == -1) return null;

            int opcode = b & 0x0f;

            b = (byte) inputStream.read();
            boolean masked = (b & 0x80) != 0;
            int payloadLen = b & 0x7f;

            if (payloadLen == 126) {
                payloadLen = ((inputStream.read() & 0xff) << 8) | (inputStream.read() & 0xff);
            } else if (payloadLen == 127) {
                for (int i = 0; i < 8; i++) inputStream.read();
                return null;
            }

            byte[] mask = null;
            if (masked) {
                mask = new byte[4];
                inputStream.read(mask);
            }

            byte[] payload = new byte[payloadLen];
            int read = 0;
            while (read < payloadLen) {
                int n = inputStream.read(payload, read, payloadLen - read);
                if (n == -1) return null;
                read += n;
            }

            if (masked && mask != null) {
                for (int i = 0; i < payload.length; i++) {
                    payload[i] ^= mask[i % 4];
                }
            }

            return new String(payload, StandardCharsets.UTF_8);
        }

        private void sendJson(String json) {
            try {
                byte[] data = json.getBytes(StandardCharsets.UTF_8);
                byte[] frame = new byte[2 + data.length];
                frame[0] = (byte) 0x81;
                frame[1] = (byte) data.length;
                System.arraycopy(data, 0, frame, 2, data.length);
                outputStream.write(frame);
                outputStream.flush();
            } catch (IOException e) {
                Log.e(TAG, "Send error: " + e.getMessage());
                connected = false;
            }
        }

        private void handleMessage(String message) {
            try {
                Log.d(TAG, "Received message: " + message);
                JSONObject json = new JSONObject(message);
                String cmd = json.optString("cmd");
                Log.d(TAG, "Command: " + cmd);

                if ("move".equals(cmd)) {
                    String dir = json.optString("dir");
                    Log.d(TAG, "Executing move: " + dir);
                    executeMove(dir);
                } else if ("stop".equals(cmd)) {
                    Log.d(TAG, "Executing stop");
                    cancelMove();
                } else if ("rotate".equals(cmd)) {
                    float degrees = (float) json.optDouble("degrees", 0);
                    Log.d(TAG, "Executing rotate: " + degrees);
                    executeRotate(degrees);
                } else if ("speed".equals(cmd)) {
                    float value = (float) json.optDouble("value", currentSpeed);
                    Log.d(TAG, "Setting speed: " + value);
                    setSpeed(value);
                } else if ("ping".equals(cmd)) {
                    Log.d(TAG, "Ping received");
                    sendJson("{\"type\":\"pong\"}");
                } else if ("get_status".equals(cmd)) {
                    Log.d(TAG, "Status requested");
                    sendJson(buildStatusMessage());
                }
            } catch (JSONException e) {
                Log.e(TAG, "Parse error: " + e.getMessage());
            }
        }

        private String buildStatusMessage() {
            try {
                JSONObject obj = new JSONObject();
                obj.put("type", "status");
                obj.put("isMoving", isMoving);
                obj.put("speed", currentSpeed);
                obj.put("direction", currentDirection);
                obj.put("clientCount", clients.size());
                return obj.toString();
            } catch (JSONException e) {
                return "{}";
            }
        }

        void close() {
            connected = false;
            try {
                if (textReader != null) textReader.close();
                if (textWriter != null) textWriter.close();
                if (inputStream != null) inputStream.close();
                if (outputStream != null) outputStream.close();
                if (socket != null) socket.close();
            } catch (IOException e) {
                Log.e(TAG, "Close error: " + e.getMessage());
            }
            synchronized (clients) {
                clients.remove(this);
                if (clients.isEmpty() && running) {
                    cancelMove();
                }
            }
            emitEvent(buildStatus());
        }
    }
}
