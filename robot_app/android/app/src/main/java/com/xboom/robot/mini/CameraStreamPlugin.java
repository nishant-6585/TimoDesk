package com.xboom.robot.mini;

import android.Manifest;
import android.content.Context;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.ImageFormat;
import android.graphics.Paint;
import android.hardware.camera2.CameraAccessException;
import android.hardware.camera2.CameraCaptureSession;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraDevice;
import android.hardware.camera2.CameraManager;
import android.hardware.camera2.CaptureRequest;
import android.hardware.camera2.params.StreamConfigurationMap;
import android.media.Image;
import android.media.ImageReader;
import android.net.wifi.WifiManager;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Looper;
import android.util.Log;
import android.util.Size;

import androidx.core.content.ContextCompat;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.ByteBuffer;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public class CameraStreamPlugin
        implements MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private static final String TAG = "Mikee";

    // Set true to run the color-cycling mock instead of the real camera.
    private static final boolean IS_MOCK = false;

    private static final int    PORT     = 8080;
    private static final String BOUNDARY = "frame";

    private final Context context;
    private ServerSocket  serverSocket;
    private Thread        serverThread;
    private Thread        cameraThread;       // mock only
    private volatile boolean streaming = false;

    // ── Camera2 fields ────────────────────────────────────────────────────────
    private CameraDevice           cameraDevice;
    private CameraCaptureSession   captureSession;
    private ImageReader            imageReader;
    private HandlerThread          cameraHandlerThread;
    private Handler                cameraHandler;

    // ── WebRTC frame consumer ─────────────────────────────────────────────────
    // WebRtcPlugin registers here to receive JPEG frames without opening camera twice.
    public interface WebRtcFrameConsumer {
        void onJpegFrame(byte[] jpeg, int width, int height);
    }
    private volatile WebRtcFrameConsumer webRtcConsumer;
    private int captureWidth  = 640;
    private int captureHeight = 480;

    public void setWebRtcFrameConsumer(WebRtcFrameConsumer consumer) {
        this.webRtcConsumer = consumer;
        if (consumer != null && cameraDevice == null && !IS_MOCK) {
            // Camera not open (MJPEG stopped/not started) — open it for WebRTC
            startCamera2();
        } else if (consumer == null && cameraDevice != null && !streaming) {
            // Neither MJPEG nor WebRTC need the camera any more
            stopCamera2();
        }
    }

    private final CopyOnWriteArrayList<ClientWriter> clients = new CopyOnWriteArrayList<>();
    private volatile byte[] latestJpeg = null;

    // Rolling 30-frame FPS window
    private final long[] frameTimes = new long[30];
    private int  frameHead  = 0;
    private int  frameCount = 0;

    private enum SdkStatus { CONNECTING, CONNECTED, ERROR }
    private volatile SdkStatus sdkStatus =
            IS_MOCK ? SdkStatus.CONNECTED : SdkStatus.CONNECTING;

    private EventChannel.EventSink   eventSink;
    private ScheduledExecutorService statusScheduler;
    private final Handler            mainHandler = new Handler(Looper.getMainLooper());

    // ── Freeze watchdog ───────────────────────────────────────────────────────
    // The USB camera pipeline occasionally freezes (device contention): the
    // capture session stays "open" but onImageAvailable stops firing, so every
    // consumer (/stream, /snapshot, gaze, spine face-rec) serves the LAST frame
    // forever. Detect staleness (no frame for FREEZE_AFTER_MS) and force a full
    // close→reopen of camera2, with linear backoff so a genuinely absent camera
    // isn't hammered.
    private static final long FREEZE_AFTER_MS   = 8_000;
    private static final long WATCHDOG_TICK_MS  = 5_000;
    private volatile long lastFrameAtMs   = 0;
    private volatile long lastReopenAtMs  = 0;
    private volatile int  reopenAttempts  = 0;
    private ScheduledExecutorService freezeWatchdog;

    public CameraStreamPlugin(Context context) {
        this.context = context;
    }

    // ── MethodChannel ──────────────────────────────────────────────────────────

    @Override
    public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        switch (call.method) {
            case "startStream": startStream(result); break;
            case "stopStream":  stopStream(result);  break;
            case "getStatus":   result.success(buildStatus()); break;
            case "getConfig":   result.success(buildConfig()); break;
            default:            result.notImplemented();
        }
    }

    private void startStream(MethodChannel.Result result) {
        if (streaming) { result.success(buildStatus()); return; }
        streaming = true;
        lastFrameAtMs = System.currentTimeMillis(); // baseline until frames flow
        reopenAttempts = 0;
        startCamera();
        startServer();
        startStatusBroadcast();
        startFreezeWatchdog();
        result.success(buildStatus());
    }

    private void startFreezeWatchdog() {
        if (IS_MOCK) return;
        if (freezeWatchdog != null) freezeWatchdog.shutdownNow();
        freezeWatchdog = Executors.newSingleThreadScheduledExecutor();
        freezeWatchdog.scheduleWithFixedDelay(() -> {
            if (!streaming) return;
            final long now = System.currentTimeMillis();
            if (now - lastFrameAtMs < FREEZE_AFTER_MS) return;
            // Linear backoff: 2s, 4s, 6s… capped at 30s between reopen attempts.
            final long backoff = Math.min(2_000L * Math.max(1, reopenAttempts), 30_000L);
            if (now - lastReopenAtMs < backoff) return;
            lastReopenAtMs = now;
            reopenAttempts++;
            Log.w(TAG, "Camera FROZEN (no frame for " + (now - lastFrameAtMs)
                    + "ms) — reopening (attempt " + reopenAttempts + ")");
            mainHandler.post(() -> {
                forceCloseCamera2();
                if (streaming) startCamera2();
            });
        }, WATCHDOG_TICK_MS, WATCHDOG_TICK_MS, TimeUnit.MILLISECONDS);
    }

    private void stopStream(MethodChannel.Result result) {
        streaming = false;
        if (freezeWatchdog != null) { freezeWatchdog.shutdownNow(); freezeWatchdog = null; }
        stopCamera2();
        sdkStatus = IS_MOCK ? SdkStatus.CONNECTED : SdkStatus.CONNECTING;
        if (statusScheduler != null) { statusScheduler.shutdownNow(); statusScheduler = null; }
        for (ClientWriter cw : clients) cw.close();
        clients.clear();
        if (serverSocket != null) {
            try { serverSocket.close(); } catch (IOException ignored) {}
            serverSocket = null;
        }
        if (result != null) result.success(buildStatus());
    }

    // ── Camera dispatch ────────────────────────────────────────────────────────

    private void startCamera() {
        if (IS_MOCK) {
            startMockCamera();
        } else {
            startCamera2();
        }
    }

    // ── Mock Camera ────────────────────────────────────────────────────────────

    private void startMockCamera() {
        cameraThread = new Thread(() -> {
            int   slot      = 0;
            final int[][] palette = {{255, 0, 0}, {0, 255, 0}, {0, 0, 255}};
            long  slotStart = System.currentTimeMillis();

            while (streaming) {
                long now = System.currentTimeMillis();
                if (now - slotStart >= 1000) { slot = (slot + 1) % 3; slotStart = now; }

                int[]  rgb = palette[slot];
                Bitmap bmp = makeMockFrame(rgb[0], rgb[1], rgb[2]);
                byte[] jpeg = bitmapToJpeg(bmp);
                bmp.recycle();
                pushFrame(jpeg);

                try { Thread.sleep(33); } catch (InterruptedException e) { break; }
            }
        });
        cameraThread.setDaemon(true);
        cameraThread.start();
    }

    private Bitmap makeMockFrame(int r, int g, int b) {
        Bitmap bmp    = Bitmap.createBitmap(640, 480, Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(bmp);
        canvas.drawColor(Color.rgb(r, g, b));

        Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
        p.setColor(Color.WHITE);
        p.setTextSize(38f);
        String ts = new SimpleDateFormat("HH:mm:ss.SSS", Locale.US).format(new Date());
        canvas.drawText("MOCK CAMERA", 20, 60, p);
        canvas.drawText(ts, 20, 112, p);

        p.setTextSize(26f);
        p.setColor(Color.argb(180, 255, 255, 255));
        canvas.drawText("Mikee  •  640×480  •  ~30 fps", 20, 156, p);
        return bmp;
    }

    // ── Camera2 ───────────────────────────────────────────────────────────────

    private void startCamera2() {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA)
                != PackageManager.PERMISSION_GRANTED) {
            Log.e(TAG, "CAMERA permission not granted");
            sdkStatus = SdkStatus.ERROR;
            notifyStatusNow();
            return;
        }

        // Dedicated background thread for camera callbacks
        cameraHandlerThread = new HandlerThread("CameraBackground");
        cameraHandlerThread.start();
        cameraHandler = new Handler(cameraHandlerThread.getLooper());

        CameraManager manager =
                (CameraManager) context.getSystemService(Context.CAMERA_SERVICE);

        try {
            String cameraId = pickCamera(manager);
            if (cameraId == null) {
                Log.e(TAG, "No suitable camera found");
                sdkStatus = SdkStatus.ERROR;
                notifyStatusNow();
                return;
            }

            Size jpegSize = pickJpegSize(manager, cameraId);
            captureWidth  = jpegSize.getWidth();
            captureHeight = jpegSize.getHeight();
            Log.d(TAG, "Opening camera " + cameraId + " at " + jpegSize);

            // JPEG ImageReader — direct JPEG bytes, no YUV conversion needed
            imageReader = ImageReader.newInstance(
                    jpegSize.getWidth(), jpegSize.getHeight(), ImageFormat.JPEG, 2);

            imageReader.setOnImageAvailableListener(reader -> {
                Image image = reader.acquireLatestImage();
                if (image == null) return;
                try {
                    ByteBuffer buf  = image.getPlanes()[0].getBuffer();
                    byte[]     jpeg = new byte[buf.remaining()];
                    buf.get(jpeg);
                    if (streaming) {
                        if (sdkStatus != SdkStatus.CONNECTED) {
                            sdkStatus = SdkStatus.CONNECTED;
                            Log.d(TAG, "First camera frame — CONNECTED");
                        }
                        pushFrame(jpeg);
                    }
                } finally {
                    image.close();
                }
            }, cameraHandler);

            manager.openCamera(cameraId, new CameraDevice.StateCallback() {
                @Override
                public void onOpened(CameraDevice camera) {
                    cameraDevice = camera;
                    createCaptureSession(camera);
                }
                @Override
                public void onDisconnected(CameraDevice camera) {
                    Log.w(TAG, "Camera disconnected — scheduling reopen");
                    camera.close();
                    cameraDevice = null;
                    // USB contention drop: reopen after a beat instead of going
                    // dark until an app restart (the watchdog would also catch
                    // this, but the explicit path recovers faster).
                    if (streaming) {
                        mainHandler.postDelayed(() -> {
                            if (streaming && cameraDevice == null) {
                                forceCloseCamera2();
                                startCamera2();
                            }
                        }, 2_000);
                    }
                }
                @Override
                public void onError(CameraDevice camera, int error) {
                    Log.e(TAG, "Camera error: " + error);
                    camera.close();
                    cameraDevice = null;
                    sdkStatus = SdkStatus.ERROR;
                    notifyStatusNow();
                }
            }, cameraHandler);

        } catch (CameraAccessException | SecurityException e) {
            Log.e(TAG, "Camera open failed: " + e.getMessage());
            sdkStatus = SdkStatus.ERROR;
            notifyStatusNow();
        }
    }

    private void createCaptureSession(CameraDevice camera) {
        try {
            CaptureRequest.Builder builder =
                    camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW);
            builder.addTarget(imageReader.getSurface());
            builder.set(CaptureRequest.JPEG_QUALITY, (byte) 60);
            // Continuous auto-focus and auto-exposure
            builder.set(CaptureRequest.CONTROL_AF_MODE,
                    CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE);
            builder.set(CaptureRequest.CONTROL_AE_MODE,
                    CaptureRequest.CONTROL_AE_MODE_ON);

            camera.createCaptureSession(
                    Collections.singletonList(imageReader.getSurface()),
                    new CameraCaptureSession.StateCallback() {
                        @Override
                        public void onConfigured(CameraCaptureSession session) {
                            captureSession = session;
                            try {
                                session.setRepeatingRequest(
                                        builder.build(), null, cameraHandler);
                                Log.d(TAG, "Camera capture session started");
                            } catch (CameraAccessException e) {
                                Log.e(TAG, "setRepeatingRequest failed: " + e.getMessage());
                                sdkStatus = SdkStatus.ERROR;
                                notifyStatusNow();
                            }
                        }
                        @Override
                        public void onConfigureFailed(CameraCaptureSession session) {
                            Log.e(TAG, "Capture session configuration failed");
                            sdkStatus = SdkStatus.ERROR;
                            notifyStatusNow();
                        }
                    }, cameraHandler);

        } catch (CameraAccessException e) {
            Log.e(TAG, "createCaptureSession failed: " + e.getMessage());
            sdkStatus = SdkStatus.ERROR;
            notifyStatusNow();
        }
    }

    private void stopCamera2() {
        if (!IS_MOCK && webRtcConsumer != null) {
            // WebRTC still needs the camera — keep it open, MJPEG server is just stopping
            return;
        }
        forceCloseCamera2();
    }

    /// Unconditional camera teardown — used by the freeze watchdog before a
    /// reopen (must run even while a WebRTC consumer is registered: a frozen
    /// camera serves WebRTC nothing either).
    private void forceCloseCamera2() {
        if (IS_MOCK) return;
        try { if (captureSession != null) captureSession.close(); } catch (Exception ignored) {}
        try { if (cameraDevice  != null)  cameraDevice.close();   } catch (Exception ignored) {}
        try { if (imageReader   != null)  imageReader.close();    } catch (Exception ignored) {}
        captureSession = null;
        cameraDevice   = null;
        imageReader    = null;
        if (cameraHandlerThread != null) {
            cameraHandlerThread.quitSafely();
            cameraHandlerThread = null;
        }
    }

    // Pick the front camera, fall back to first available
    private String pickCamera(CameraManager manager) throws CameraAccessException {
        String first = null;
        for (String id : manager.getCameraIdList()) {
            CameraCharacteristics c = manager.getCameraCharacteristics(id);
            Integer facing = c.get(CameraCharacteristics.LENS_FACING);
            if (first == null) first = id;
            if (facing != null && facing == CameraCharacteristics.LENS_FACING_FRONT) return id;
        }
        return first;
    }

    // Pick closest JPEG output size to 640x480
    private Size pickJpegSize(CameraManager manager, String cameraId)
            throws CameraAccessException {
        CameraCharacteristics chars  = manager.getCameraCharacteristics(cameraId);
        StreamConfigurationMap map   =
                chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP);
        if (map == null) return new Size(640, 480);

        Size[] sizes = map.getOutputSizes(ImageFormat.JPEG);
        if (sizes == null || sizes.length == 0) return new Size(640, 480);

        Size best = sizes[0];
        long target = 640L * 480;
        long bestDiff = Math.abs(best.getWidth() * (long) best.getHeight() - target);
        for (Size s : sizes) {
            long diff = Math.abs(s.getWidth() * (long) s.getHeight() - target);
            if (diff < bestDiff) { bestDiff = diff; best = s; }
        }
        return best;
    }

    // ── Frame pipeline ────────────────────────────────────────────────────────

    private byte[] bitmapToJpeg(Bitmap bmp) {
        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        bmp.compress(Bitmap.CompressFormat.JPEG, 60, baos);
        return baos.toByteArray();
    }

    private void pushFrame(byte[] jpeg) {
        latestJpeg = jpeg;
        lastFrameAtMs = System.currentTimeMillis(); // feeds the freeze watchdog
        reopenAttempts = 0; // frames flowing again → reset the backoff
        recordFrame();

        // Forward to WebRTC consumer if registered (no second camera open needed)
        WebRtcFrameConsumer consumer = webRtcConsumer;
        if (consumer != null) consumer.onJpegFrame(jpeg, captureWidth, captureHeight);

        if (clients.isEmpty()) return;

        byte[] hdr  = ("--" + BOUNDARY + "\r\n"
                + "Content-Type: image/jpeg\r\n"
                + "Content-Length: " + jpeg.length + "\r\n"
                + "\r\n").getBytes();
        byte[] tail = "\r\n".getBytes();

        List<ClientWriter> dead = new ArrayList<>();
        for (ClientWriter cw : clients) {
            try {
                cw.out.write(hdr);
                cw.out.write(jpeg);
                cw.out.write(tail);
                cw.out.flush();
            } catch (IOException e) {
                cw.alive = false;
                dead.add(cw);
            }
        }
        clients.removeAll(dead);
    }

    // ── MJPEG Server ───────────────────────────────────────────────────────────

    private void startServer() {
        serverThread = new Thread(() -> {
            try {
                serverSocket = new ServerSocket(PORT);
                while (streaming && !serverSocket.isClosed()) {
                    try {
                        Socket sock = serverSocket.accept();
                        handleIncomingConnection(sock);
                    } catch (IOException ignored) {}
                }
            } catch (IOException e) {
                Log.e(TAG, "Server socket error: " + e.getMessage());
            }
        });
        serverThread.setDaemon(true);
        serverThread.start();
    }

    private void handleIncomingConnection(Socket sock) {
        Thread t = new Thread(() -> {
            try {
                InputStream  in  = sock.getInputStream();
                OutputStream out = sock.getOutputStream();

                byte[] buf = new byte[4096];
                int    n   = in.read(buf);
                String req = n > 0 ? new String(buf, 0, n, "UTF-8") : "";

                // Handle CORS preflight OPTIONS request
                if (req.startsWith("OPTIONS")) {
                    String cors = "HTTP/1.1 204 No Content\r\n"
                            + "Access-Control-Allow-Origin: *\r\n"
                            + "Access-Control-Allow-Methods: GET, OPTIONS\r\n"
                            + "Access-Control-Allow-Headers: content-type\r\n"
                            + "Access-Control-Max-Age: 86400\r\n"
                            + "\r\n";
                    out.write(cors.getBytes("UTF-8"));
                    out.flush();
                    sock.close();
                } else if (req.startsWith("GET /stream")) {
                    serveMjpegStream(sock, out);
                } else if (req.startsWith("GET /snapshot")) {
                    serveSnapshot(out);
                    sock.close();
                } else {
                    serveIndexPage(out);
                    sock.close();
                }
            } catch (IOException ignored) {
            } finally {
                try { if (!sock.isClosed()) sock.close(); } catch (IOException ignored) {}
            }
        });
        t.setDaemon(true);
        t.start();
    }

    private void serveMjpegStream(Socket sock, OutputStream out) throws IOException {
        String hdr = "HTTP/1.1 200 OK\r\n"
                + "Content-Type: multipart/x-mixed-replace; boundary=" + BOUNDARY + "\r\n"
                + "Cache-Control: no-cache\r\n"
                + "Connection: keep-alive\r\n"
                + "Access-Control-Allow-Origin: *\r\n"
                + "\r\n";
        out.write(hdr.getBytes("UTF-8"));
        out.flush();

        ClientWriter cw = new ClientWriter(sock, out);
        clients.add(cw);
        while (streaming && cw.alive) {
            try { Thread.sleep(200); } catch (InterruptedException e) { break; }
        }
        clients.remove(cw);
    }

    private void serveSnapshot(OutputStream out) throws IOException {
        byte[] jpeg = latestJpeg;
        if (jpeg == null) {
            out.write("HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\n\r\n"
                    .getBytes("UTF-8"));
            out.flush();
            return;
        }
        String resp = "HTTP/1.1 200 OK\r\nContent-Type: image/jpeg\r\n"
                + "Content-Length: " + jpeg.length + "\r\nAccess-Control-Allow-Origin: *\r\n\r\n";
        out.write(resp.getBytes("UTF-8"));
        out.write(jpeg);
        out.flush();
    }

    private void serveIndexPage(OutputStream out) throws IOException {
        String ip   = wifiIp();
        String body = "<!DOCTYPE html><html><head>"
                + "<meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>"
                + "<title>Mikee Camera</title>"
                + "<style>body{background:#0f0f0f;color:#fff;font-family:sans-serif;"
                + "display:flex;flex-direction:column;align-items:center;justify-content:center;"
                + "min-height:100vh;margin:0;padding:16px;box-sizing:border-box}"
                + "h2{color:#FF6B35}img{max-width:100%;border-radius:8px}a{color:#FF6B35}"
                + "</style></head><body>"
                + "<h2>Mikee Camera</h2>"
                + "<img src='/stream' alt='MJPEG stream'/>"
                + "<p>Stream: <a href='http://" + ip + ":" + PORT + "/stream'>"
                + "http://" + ip + ":" + PORT + "/stream</a></p>"
                + "<p>Snapshot: <a href='/snapshot'>/snapshot</a></p>"
                + "</body></html>";
        byte[] bodyBytes = body.getBytes("UTF-8");
        String resp = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n"
                + "Content-Length: " + bodyBytes.length + "\r\n\r\n";
        out.write(resp.getBytes("UTF-8"));
        out.write(bodyBytes);
        out.flush();
    }

    // ── FPS ────────────────────────────────────────────────────────────────────

    private void recordFrame() {
        frameTimes[frameHead % 30] = System.currentTimeMillis();
        frameHead++;
        if (frameCount < 30) frameCount++;
    }

    private double fps() {
        if (frameCount < 2) return 0.0;
        int  n       = Math.min(frameCount, 30);
        long oldest  = frameTimes[(frameHead - n + 60) % 30];
        long newest  = frameTimes[(frameHead - 1 + 60) % 30];
        long elapsed = newest - oldest;
        return elapsed > 0 ? (n - 1) * 1000.0 / elapsed : 0.0;
    }

    // ── Status / Config ────────────────────────────────────────────────────────

    private Map<String, Object> buildStatus() {
        Map<String, Object> m = new HashMap<>();
        m.put("isStreaming",      streaming);
        m.put("port",             PORT);
        m.put("fps",              fps());
        m.put("connectedClients", clients.size());
        m.put("ipAddress",        wifiIp());
        m.put("sdkStatus",        sdkStatusString());
        return m;
    }

    private Map<String, Object> buildConfig() {
        Map<String, Object> m = new HashMap<>();
        m.put("flavor", BuildConfig.FLAVOR);
        m.put("sdkIp",  BuildConfig.SDK_IP);
        return m;
    }

    private String sdkStatusString() {
        switch (sdkStatus) {
            case CONNECTED: return "connected";
            case ERROR:     return "error";
            default:        return "connecting";
        }
    }

    private void notifyStatusNow() {
        if (eventSink == null) return;
        Map<String, Object> s = buildStatus();
        mainHandler.post(() -> { if (eventSink != null) eventSink.success(s); });
    }

    private String wifiIp() {
        try {
            WifiManager wm = (WifiManager) context.getApplicationContext()
                    .getSystemService(Context.WIFI_SERVICE);
            if (wm != null) {
                int ip = wm.getConnectionInfo().getIpAddress();
                if (ip != 0) return String.format(Locale.US, "%d.%d.%d.%d",
                        ip & 0xff, (ip >> 8) & 0xff, (ip >> 16) & 0xff, (ip >> 24) & 0xff);
            }
            String fallback = null;
            for (NetworkInterface ni : Collections.list(NetworkInterface.getNetworkInterfaces())) {
                for (InetAddress addr : Collections.list(ni.getInetAddresses())) {
                    String host = addr.getHostAddress();
                    if (addr.isLoopbackAddress() || host.contains(":")) continue;
                    if (host.startsWith("192.168.43.") || host.startsWith("192.168.99.")) continue;
                    if (host.startsWith("192.168.")) return host;
                    if (fallback == null) fallback = host;
                }
            }
            if (fallback != null) return fallback;
        } catch (Exception ignored) {}
        return "0.0.0.0";
    }

    private void startStatusBroadcast() {
        statusScheduler = Executors.newSingleThreadScheduledExecutor();
        statusScheduler.scheduleAtFixedRate(() -> {
            if (eventSink == null) return;
            Map<String, Object> s = buildStatus();
            mainHandler.post(() -> { if (eventSink != null) eventSink.success(s); });
        }, 0, 1, TimeUnit.SECONDS);
    }

    // ── EventChannel ───────────────────────────────────────────────────────────

    @Override public void onListen(Object args, EventChannel.EventSink sink) { eventSink = sink; }
    @Override public void onCancel(Object args)                              { eventSink = null; }

    // ── Inner class ────────────────────────────────────────────────────────────

    private static final class ClientWriter {
        final Socket       socket;
        final OutputStream out;
        volatile boolean   alive = true;

        ClientWriter(Socket socket, OutputStream out) {
            this.socket = socket;
            this.out    = out;
        }

        void close() {
            alive = false;
            try { socket.close(); } catch (IOException ignored) {}
        }
    }
}
