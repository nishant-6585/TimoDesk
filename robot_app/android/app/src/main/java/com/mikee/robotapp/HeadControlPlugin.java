package com.mikee.robotapp;

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

import com.csjbot.coshandler.core.CsjRobot;

public class HeadControlPlugin implements MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private static final String TAG = "Mikee.HeadControl";
    private static final int PORT = 8081;
    private static final int RATE_LIMIT_MS = 50;

    private ServerSocket serverSocket;
    private ExecutorService executor;
    private volatile boolean running = false;
    private volatile int currentHeadLR = 50;
    private volatile int currentHeadUD = 50;
    private Set<ClientHandler> clients = new HashSet<>();
    private long lastCommandTime = 0;
    private EventChannel.EventSink eventSink;
    private Handler mainHandler = new Handler(Looper.getMainLooper());

    @Override
    public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        switch (call.method) {
            case "startHeadControl":
                startServer();
                result.success(buildStatus());
                break;
            case "stopHeadControl":
                stopServer();
                result.success(buildStatus());
                break;
            case "resetHead":
                resetHead();
                result.success(buildStatus());
                break;
            case "nudgeHead": {
                // Discrete head nudge from the on-robot dashboard d-pad: step the
                // current pan/tilt and re-issue TimoActionCustomerCtrl. headLR/headUD
                // are 0–100 (50 = center); higher UD = up, higher LR = right.
                String dir = (String) call.argument("dir");
                final int step = 12;
                int lr = currentHeadLR, ud = currentHeadUD;
                if ("left".equals(dir)) lr -= step;
                else if ("right".equals(dir)) lr += step;
                else if ("up".equals(dir)) ud += step;
                else if ("down".equals(dir)) ud -= step;
                executeHeadCommand(lr, ud);
                result.success(buildStatus());
                break;
            }
            case "setHead": {
                // Absolute head pose for conversational gestures (nod/tilt/sway/
                // center). lr/ud are 0–100 (50 = center; higher UD = up, higher
                // LR = right). Missing arg keeps the current value.
                Integer lr = call.argument("lr");
                Integer ud = call.argument("ud");
                executeHeadCommand(lr == null ? currentHeadLR : lr,
                                   ud == null ? currentHeadUD : ud);
                result.success(buildStatus());
                break;
            }
            case "getHeadStatus":
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

        new Thread(() -> {
            try {
                serverSocket = new ServerSocket(PORT);
                Log.d(TAG, "WebSocket server started on port " + PORT);
                emitEvent(buildStatus());

                while (running) {
                    try {
                        Socket clientSocket = serverSocket.accept();
                        executor.execute(new ClientHandler(clientSocket));
                    } catch (IOException e) {
                        if (running) Log.e(TAG, "Accept error: " + e.getMessage());
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
        resetHead();
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
        emitEvent(buildStatus());
    }

    private void resetHead() {
        try {
            CsjRobot.getInstance().getAction().TimoActionReset();
            currentHeadLR = 50;
            currentHeadUD = 50;
            emitEvent(buildStatus());
        } catch (Exception e) {
            Log.e(TAG, "Reset error: " + e.getMessage());
        }
    }

    private void executeHeadCommand(int headLR, int headUD) {
        long now = System.currentTimeMillis();
        if (now - lastCommandTime < RATE_LIMIT_MS) return;
        lastCommandTime = now;

        headLR = Math.max(0, Math.min(100, headLR));
        headUD = Math.max(0, Math.min(100, headUD));

        try {
            currentHeadLR = headLR;
            currentHeadUD = headUD;
            CsjRobot.getInstance().getAction().TimoActionCustomerCtrl(headLR, headUD, 50, 50);
            emitEvent(buildStatus());
        } catch (Exception e) {
            Log.e(TAG, "Command error: " + e.getMessage());
        }
    }

    private Map<String, Object> buildStatus() {
        Map<String, Object> m = new HashMap<>();
        m.put("isRunning", running);
        m.put("port", PORT);
        m.put("clientCount", clients.size());
        m.put("headLR", currentHeadLR);
        m.put("headUD", currentHeadUD);
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

                // WebSocket handshake
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

                // Send current status
                sendJson(buildStatusMessage());

                // Read messages
                while (connected) {
                    String message = readWebSocketFrame();
                    if (message == null) break;
                    handleMessage(message);
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

            // Read HTTP request
            while ((line = textReader.readLine()) != null && !line.isEmpty()) {
                if (line.startsWith("Sec-WebSocket-Key:")) {
                    key = line.substring(19).trim();
                }
            }

            if (key == null) return false;

            // Compute accept key
            String magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
            String combined = key + magic;
            MessageDigest md = MessageDigest.getInstance("SHA-1");
            byte[] hash = md.digest(combined.getBytes(StandardCharsets.UTF_8));
            String accept = Base64.getEncoder().encodeToString(hash);

            // Send response
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
                JSONObject json = new JSONObject(message);
                String cmd = json.optString("cmd");

                if ("head_both".equals(cmd)) {
                    int lr = json.optInt("lr", currentHeadLR);
                    int ud = json.optInt("ud", currentHeadUD);
                    executeHeadCommand(lr, ud);
                } else if ("head_lr".equals(cmd)) {
                    int value = json.optInt("value", currentHeadLR);
                    executeHeadCommand(value, currentHeadUD);
                } else if ("head_ud".equals(cmd)) {
                    int value = json.optInt("value", currentHeadUD);
                    executeHeadCommand(currentHeadLR, value);
                } else if ("reset".equals(cmd)) {
                    resetHead();
                } else if ("ping".equals(cmd)) {
                    sendJson("{\"type\":\"pong\"}");
                } else if ("get_status".equals(cmd)) {
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
                obj.put("headLR", currentHeadLR);
                obj.put("headUD", currentHeadUD);
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
                    resetHead();
                }
            }
            emitEvent(buildStatus());
        }
    }
}
