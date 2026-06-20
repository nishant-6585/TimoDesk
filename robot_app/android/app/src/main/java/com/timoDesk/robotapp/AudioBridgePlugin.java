package com.timoDesk.robotapp;

import android.Manifest;
import android.content.Context;
import android.content.pm.PackageManager;
import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioRecord;
import android.media.AudioTrack;
import android.media.MediaRecorder;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import androidx.core.content.ContextCompat;

import java.util.Arrays;
import java.util.concurrent.LinkedBlockingQueue;

import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * #80 Phase B — audio bridge.
 *
 * Mic IN:  AudioRecord (16 kHz / mono / 16-bit PCM) → EventChannel
 *          "com.timoDesk/audio_mic". Each chunk is forwarded to Dart, which pipes
 *          it to the ElevenLabs session (voiceAgent.sendAudioChunk).
 * Speaker OUT: MethodChannel "com.timoDesk/audio_control" → AudioTrack
 *          (MODE_STREAM) writes the PCM chunks ElevenLabs sends back.
 *
 * Uses VOICE_COMMUNICATION as the capture source so the platform AEC suppresses
 * the robot hearing its own TTS through the speaker. RECORD_AUDIO is a runtime
 * permission (Android 6+) — checked here; REQUESTING it is the Dart/host job.
 */
public class AudioBridgePlugin
        implements MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private static final String TAG = "TimoDesk.Audio";

    private static final int SAMPLE_RATE = 16000;
    private static final int CHANNEL_IN = AudioFormat.CHANNEL_IN_MONO;
    private static final int CHANNEL_OUT = AudioFormat.CHANNEL_OUT_MONO;
    private static final int FORMAT = AudioFormat.ENCODING_PCM_16BIT;

    private final Context context;
    private final Handler main = new Handler(Looper.getMainLooper());

    private EventChannel.EventSink micSink;

    // Mic
    private AudioRecord audioRecord;
    private Thread micThread;
    private volatile boolean micRunning = false;

    // Speaker
    private AudioTrack audioTrack;
    private Thread playThread;
    private volatile boolean playRunning = false;
    private final LinkedBlockingQueue<byte[]> playQueue = new LinkedBlockingQueue<>();

    AudioBridgePlugin(Context context) {
        this.context = context;
    }

    // ── MethodChannel ───────────────────────────────────────────────────────────

    @Override
    public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        switch (call.method) {
            case "startMic":
                startMic(result);
                break;
            case "stopMic":
                stopMic();
                result.success(null);
                break;
            case "playAudio":
                playAudio((byte[]) call.arguments);
                result.success(null);
                break;
            case "stopAudio":
                stopAudio();
                result.success(null);
                break;
            default:
                result.notImplemented();
        }
    }

    private void startMic(MethodChannel.Result result) {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO)
                != PackageManager.PERMISSION_GRANTED) {
            result.error("MIC_PERMISSION", "RECORD_AUDIO not granted", null);
            return;
        }
        if (micRunning) {
            result.success(null);
            return;
        }
        try {
            int minBuf = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_IN, FORMAT);
            final int bufferSize = Math.max(minBuf * 4, 8000);

            int source = MediaRecorder.AudioSource.VOICE_COMMUNICATION; // AEC
            audioRecord = new AudioRecord(source, SAMPLE_RATE, CHANNEL_IN, FORMAT, bufferSize);
            if (audioRecord.getState() != AudioRecord.STATE_INITIALIZED) {
                // Fall back to the plain mic source if VOICE_COMMUNICATION is unavailable.
                audioRecord.release();
                audioRecord = new AudioRecord(
                        MediaRecorder.AudioSource.MIC, SAMPLE_RATE, CHANNEL_IN, FORMAT, bufferSize);
            }
            if (audioRecord.getState() != AudioRecord.STATE_INITIALIZED) {
                audioRecord.release();
                audioRecord = null;
                result.error("MIC_ERROR", "AudioRecord failed to initialize", null);
                return;
            }

            audioRecord.startRecording();
            micRunning = true;
            micThread = new Thread(() -> {
                byte[] buf = new byte[bufferSize / 2];
                while (micRunning) {
                    int n = audioRecord.read(buf, 0, buf.length);
                    if (n > 0) {
                        final byte[] chunk = Arrays.copyOf(buf, n);
                        main.post(() -> {
                            if (micSink != null) micSink.success(chunk);
                        });
                    }
                }
            }, "timo-mic");
            micThread.start();
            result.success(null);
        } catch (Throwable e) {
            Log.e(TAG, "startMic failed: " + e.getMessage());
            result.error("MIC_ERROR", e.getMessage(), null);
        }
    }

    private void stopMic() {
        micRunning = false;
        try {
            if (audioRecord != null) {
                audioRecord.stop();
                audioRecord.release();
                audioRecord = null;
            }
        } catch (Throwable e) {
            Log.w(TAG, "stopMic: " + e.getMessage());
        }
        micThread = null;
    }

    private void playAudio(byte[] bytes) {
        if (bytes == null || bytes.length == 0) return;
        ensurePlayback();
        playQueue.offer(bytes);
    }

    private void ensurePlayback() {
        try {
            if (audioTrack == null) {
                int minBuf = AudioTrack.getMinBufferSize(SAMPLE_RATE, CHANNEL_OUT, FORMAT);
                int bufferSize = minBuf * 4;
                audioTrack = new AudioTrack(
                        AudioManager.STREAM_MUSIC, SAMPLE_RATE, CHANNEL_OUT, FORMAT,
                        bufferSize, AudioTrack.MODE_STREAM);
            }
            if (audioTrack.getPlayState() != AudioTrack.PLAYSTATE_PLAYING) {
                audioTrack.play();
            }
            if (playThread == null || !playRunning) {
                playRunning = true;
                playThread = new Thread(() -> {
                    while (playRunning) {
                        try {
                            byte[] chunk = playQueue.take();
                            if (chunk.length > 0 && audioTrack != null) {
                                audioTrack.write(chunk, 0, chunk.length);
                            }
                        } catch (InterruptedException e) {
                            break;
                        } catch (Throwable e) {
                            Log.w(TAG, "playback write: " + e.getMessage());
                        }
                    }
                }, "timo-speaker");
                playThread.start();
            }
        } catch (Throwable e) {
            Log.e(TAG, "ensurePlayback failed: " + e.getMessage());
        }
    }

    private void stopAudio() {
        playQueue.clear();
        try {
            if (audioTrack != null
                    && audioTrack.getPlayState() == AudioTrack.PLAYSTATE_PLAYING) {
                audioTrack.stop();
                audioTrack.flush();
            }
        } catch (Throwable e) {
            Log.w(TAG, "stopAudio: " + e.getMessage());
        }
        // Keep the AudioTrack object — ensurePlayback() re-arms play() on the next chunk.
    }

    // ── EventChannel (mic) ───────────────────────────────────────────────────────

    @Override
    public void onListen(Object args, EventChannel.EventSink sink) {
        micSink = sink;
    }

    @Override
    public void onCancel(Object args) {
        micSink = null;
    }
}
