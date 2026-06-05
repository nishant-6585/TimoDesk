package com.timoDesk.robotapp;

import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import com.csjbot.coshandler.core.CsjRobot;

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

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;

public class ArmControlPlugin {
    private static final String TAG = "TimoDesk.ArmControl";
    private static final int PORT = 8083;
    private static final int MAX_CLIENTS = 3;
    private static final long RATE_LIMIT_MS = 50;

    private volatile boolean running = false;
    private volatile int currentLeftArm = 50;
    private volatile int currentRightArm = 50;
    private volatile boolean isWaving = false;
    private ServerSocket serverSocket;
    private ExecutorService executor;
    private Set<ClientHandler> clients = new HashSet<>();
    private long lastCommandTime = 0;
    private EventChannel.EventSink eventSink;
    private Handler mainHandler = new Handler(Looper.getMainLooper());

    public void setup(FlutterEngine flutterEngine) {
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), "com.timoDesk/arm_control")
                .setMethodCallHandler((call, result) -> {
                    switch (call.method) {
                        case "startArmControl":
                            startServer();
                            result.success(null);
                            break;
                        case "stopArmControl":
                            stopServer();
                            result.success(null);
                            break;
                        case "resetArms":
                            resetArms();
                            result.success(null);
                            break;
                        case "wave":
                            wave();
                            result.success(null);
                            break;
                        case "stopWave":
                            stopWave();
                            result.success(null);
                            break;
                        case "getArmStatus":
                            result.success(buildStatus());
                            break;
                        default:
                            result.notImplemented();
                    }
                });

        new EventChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), "com.timoDesk/arm_events")
                .setStreamHandler(new EventChannel.StreamHandler() {
                    @Override
                    public void onListen(Object args, EventChannel.EventSink sink) {
                        eventSink = sink;
                    }

                    @Override
                    public void onCancel(Object args) {
                        eventSink = null;
                    }
                });
    }

    private void startServer() {
        if (running) return;
        running = true;
        executor = Executors.newCachedThreadPool();

        new Thread(() -> {
            try {
                serverSocket = new ServerSocket(PORT);
                Log.d(TAG, "WebSocket server started on port " + PORT);
                emitEvent(buildStatus());

                while (running) {
                    Socket clientSocket = serverSocket.accept();
                    if (clients.size() >= MAX_CLIENTS) {
                        clientSocket.close();
                        continue;
                    }
                    ClientHandler handler = new ClientHandler(clientSocket);
                    clients.add(handler);
                    executor.execute(handler);
                }
            } catch (IOException e) {
                if (running) {
                    Log.e(TAG, "Server error: " + e.getMessage());
                }
            }
        }).start();
    }

    private void stopServer() {
        running = false;
        resetArms();
        if (serverSocket != null) {
            try {
                serverSocket.close();
            } catch (IOException e) {
                Log.e(TAG, "Error closing server: " + e.getMessage());
            }
        }
        synchronized (clients) {
            for (ClientHandler client : clients) {
                client.close();
            }
            clients.clear();
        }
        if (executor != null) {
            executor.shutdownNow();
        }
        emitEvent(buildStatus());
    }

    private void resetArms() {
        try {
            CsjRobot.getInstance().getAction().TimoActionReset();
            currentLeftArm = 50;
            currentRightArm = 50;
            isWaving = false;
            Log.d(TAG, "Arms reset");
            emitEvent(buildStatus());
        } catch (Exception e) {
            Log.e(TAG, "Reset error: " + e.getMessage());
        }
    }

    private void wave() {
        try {
            CsjRobot.getInstance().getAction().startWaveHands(1500);
            isWaving = true;
            Log.d(TAG, "Wave started");
            emitEvent(buildStatus());
        } catch (Exception e) {
            Log.e(TAG, "Wave error: " + e.getMessage());
        }
    }

    private void stopWave() {
        try {
            CsjRobot.getInstance().getAction().stopWaveHands();
            isWaving = false;
            Log.d(TAG, "Wave stopped");
            emitEvent(buildStatus());
        } catch (Exception e) {
            Log.e(TAG, "Stop wave error: " + e.getMessage());
        }
    }

    private void setLeftArm(int angle) {
        angle = Math.max(0, Math.min(100, angle));
        try {
            CsjRobot.getInstance().getAction().TimoActionLeftHandCtrl(angle);
            currentLeftArm = angle;
            Log.d(TAG, "Left arm: " + angle);
            emitEvent(buildStatus());
        } catch (Exception e) {
            Log.e(TAG, "Left arm error: " + e.getMessage());
        }
    }

    private void setRightArm(int angle) {
        angle = Math.max(0, Math.min(100, angle));
        try {
            CsjRobot.getInstance().getAction().TimoActionRightHandCtrl(angle);
            currentRightArm = angle;
            Log.d(TAG, "Right arm: " + angle);
            emitEvent(buildStatus());
        } catch (Exception e) {
            Log.e(TAG, "Right arm error: " + e.getMessage());
        }
    }

    private Map<String, Object> buildStatus() {
        Map<String, Object> m = new HashMap<>();
        m.put("isRunning", running);
        m.put("port", PORT);
        m.put("clientCount", clients.size());
        m.put("leftArm", currentLeftArm);
        m.put("rightArm", currentRightArm);
        m.put("isWaving", isWaving);
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

                String line = textReader.readLine();
                if (line != null && line.startsWith("GET")) {
                    performHandshake();
                    connected = true;
                    emitEvent(buildStatus());

                    while (connected) {
                        byte[] frameData = readWebSocketFrame();
                        if (frameData == null) break;
                        handleMessage(new String(frameData, StandardCharsets.UTF_8));
                    }
                }
            } catch (IOException e) {
                Log.d(TAG, "Client disconnected");
            } finally {
                close();
            }
        }

        private void performHandshake() throws IOException {
            String line;
            String key = null;
            while ((line = textReader.readLine()) != null && !line.isEmpty()) {
                if (line.startsWith("Sec-WebSocket-Key:")) {
                    key = line.substring(19).trim();
                }
            }
            if (key != null) {
                String magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
                try {
                    MessageDigest md = MessageDigest.getInstance("SHA-1");
                    byte[] hash = md.digest((key + magic).getBytes(StandardCharsets.UTF_8));
                    String accept = Base64.getEncoder().encodeToString(hash);
                    textWriter.write("HTTP/1.1 101 Switching Protocols\r\n");
                    textWriter.write("Upgrade: websocket\r\n");
                    textWriter.write("Connection: Upgrade\r\n");
                    textWriter.write("Sec-WebSocket-Accept: " + accept + "\r\n\r\n");
                    textWriter.flush();
                } catch (Exception e) {
                    Log.e(TAG, "Handshake error: " + e.getMessage());
                }
            }
        }

        private byte[] readWebSocketFrame() throws IOException {
            int b = inputStream.read();
            if (b == -1) return null;

            boolean fin = (b & 0x80) != 0;
            int opcode = b & 0x0F;
            if (opcode == 0x08) return null;

            b = inputStream.read();
            boolean masked = (b & 0x80) != 0;
            long payloadLen = b & 0x7F;
            if (payloadLen == 126) {
                payloadLen = ((inputStream.read() & 0xFF) << 8) | (inputStream.read() & 0xFF);
            } else if (payloadLen == 127) {
                payloadLen = 0;
                for (int i = 0; i < 8; i++) {
                    payloadLen = (payloadLen << 8) | (inputStream.read() & 0xFF);
                }
            }

            byte[] mask = new byte[4];
            if (masked) {
                inputStream.read(mask);
            }

            byte[] payload = new byte[(int) payloadLen];
            inputStream.read(payload);

            if (masked) {
                for (int i = 0; i < payload.length; i++) {
                    payload[i] ^= mask[i % 4];
                }
            }

            return payload;
        }

        private void handleMessage(String message) {
            try {
                JSONObject json = new JSONObject(message);
                String cmd = json.getString("cmd");

                switch (cmd) {
                    case "left_arm":
                        setLeftArm(json.getInt("value"));
                        break;
                    case "right_arm":
                        setRightArm(json.getInt("value"));
                        break;
                    case "both_arms":
                        setLeftArm(json.getInt("left"));
                        setRightArm(json.getInt("right"));
                        break;
                    case "wave":
                        wave();
                        break;
                    case "stop_wave":
                        stopWave();
                        break;
                    case "reset":
                        resetArms();
                        break;
                    case "ping":
                        sendFrame("{\"type\":\"pong\"}");
                        break;
                    case "get_status":
                        sendFrame(new JSONObject(buildStatus()).toString());
                        break;
                }
            } catch (JSONException e) {
                Log.e(TAG, "Parse error: " + e.getMessage());
            }
        }

        private void sendFrame(String text) {
            try {
                byte[] payload = text.getBytes(StandardCharsets.UTF_8);
                outputStream.write(0x81);
                if (payload.length < 126) {
                    outputStream.write(payload.length);
                } else if (payload.length < 65536) {
                    outputStream.write(126);
                    outputStream.write((payload.length >> 8) & 0xFF);
                    outputStream.write(payload.length & 0xFF);
                }
                outputStream.write(payload);
                outputStream.flush();
            } catch (IOException e) {
                Log.e(TAG, "Send error: " + e.getMessage());
            }
        }

        void close() {
            connected = false;
            try {
                socket.close();
            } catch (IOException e) {
                Log.e(TAG, "Close error: " + e.getMessage());
            }
            synchronized (clients) {
                clients.remove(this);
                if (clients.isEmpty() && running) {
                    resetArms();
                }
            }
            emitEvent(buildStatus());
        }
    }
}
