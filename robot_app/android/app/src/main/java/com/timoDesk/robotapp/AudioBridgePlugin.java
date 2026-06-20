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

import com.csjbot.coshandler.core.CsjRobot;
import com.csjbot.coshandler.listener.OnSpeechListener;

import java.util.Arrays;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;

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

    // Mic — two possible sources: the CSJBot CAE stream (real robot) or AudioRecord.
    private AudioRecord audioRecord;
    private Thread micThread;
    private volatile boolean micRunning = false;
    private boolean usingSdkMic = false; // mic sourced from the CSJBot CAE stream
    private volatile int sdkChunkCount = 0; // CSJBot audio chunks this session
    private int sdkLogN = 0; // throttle the chunk-size debug log

    // Speaker
    private AudioTrack audioTrack;
    private Thread playThread;
    private volatile boolean playRunning = false;
    private final LinkedBlockingQueue<byte[]> playQueue = new LinkedBlockingQueue<>();

    // Playback level stream — amplitude of each chunk AS IT PLAYS (drives lip-sync
    // in sync with the speaker), + a -1 sentinel when the queue drains (speech end).
    private EventChannel.EventSink playbackSink;
    private volatile boolean playbackIdleEmitted = true;
    final EventChannel.StreamHandler playbackStreamHandler = new EventChannel.StreamHandler() {
        @Override public void onListen(Object args, EventChannel.EventSink sink) { playbackSink = sink; }
        @Override public void onCancel(Object args) { playbackSink = null; }
    };

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
        if (usingSdkMic || micRunning) {
            if (result != null) result.success(null);
            return;
        }
        // Prefer the CSJBot CAE stream: on the robot the SDK owns the mic array, so
        // a direct AudioRecord captures only silence. If no SDK audio arrives
        // (emulator / non-CSJBot), fall back to AudioRecord after a short beat.
        if (startSdkMic()) {
            if (result != null) result.success(null);
            return;
        }
        startAudioRecordMic(result);
    }

    /** Source mic audio from the CSJBot CAE pipeline (registerSpeechListener →
     *  onAudio delivers the beamformed PCM the robot already captures). */
    private boolean startSdkMic() {
        try {
            sdkChunkCount = 0;
            sdkLogN = 0;
            CsjRobot.getInstance().registerSpeechListener(new OnSpeechListener() {
                @Override
                public void speechInfo(String json, int type) { }

                @Override
                public void onAudio(byte[] audioData) {
                    if (!usingSdkMic || audioData == null || audioData.length == 0) return;
                    sdkChunkCount++;
                    if (sdkLogN < 3) {
                        Log.d(TAG, "CSJBot mic chunk = " + audioData.length + " bytes");
                        sdkLogN++;
                    }
                    final byte[] chunk = audioData.clone();
                    main.post(() -> {
                        if (micSink != null) micSink.success(chunk);
                    });
                }
            });
            // CRITICAL: actually START the speech/audio pipeline so the vendor
            // service begins pushing mic audio to us (the demo app does this; just
            // registering the listener is not enough).
            try {
                CsjRobot.getInstance().getSpeech().startSpeechService();
                // ACQUIRE the mic resource — the missing step. Per the UBTech/Alpha
                // SDK spec a third-party app must claim the mic after voice init
                // (speech_SetMIC(true)); CsjRobot's equivalent is openMicro()
                // (SPEECH_ISR_MICRO_REQ = "manually wake the robot's microphone").
                // Without this the vendor never routes mic audio to our listener.
                CsjRobot.getInstance().getSpeech().openMicro();
                Log.d(TAG, "startSpeechService() + openMicro() called");
            } catch (Throwable t) {
                Log.w(TAG, "startSpeechService/openMicro failed: " + t.getMessage());
            }
            usingSdkMic = true;
            Log.d(TAG, "mic source = CSJBot CAE (registerSpeechListener)");
            // Emulator/no-SDK safety: if no CAE audio arrives, fall back to AudioRecord.
            main.postDelayed(() -> {
                if (usingSdkMic && sdkChunkCount == 0) {
                    Log.w(TAG, "no CSJBot mic audio in 2s → falling back to AudioRecord");
                    usingSdkMic = false;
                    startAudioRecordMic(null);
                }
            }, 2000);
            return true;
        } catch (Throwable e) {
            Log.w(TAG, "CSJBot SDK mic unavailable: " + e.getMessage());
            return false;
        }
    }

    /** Direct AudioRecord capture — emulator / non-CSJBot fallback. [result] may be
     *  null when invoked as the SDK-mic fallback. */
    private void startAudioRecordMic(MethodChannel.Result result) {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO)
                != PackageManager.PERMISSION_GRANTED) {
            Log.w(TAG, "AudioRecord path: RECORD_AUDIO NOT granted");
            if (result != null) result.error("MIC_PERMISSION", "RECORD_AUDIO not granted", null);
            return;
        }
        Log.d(TAG, "AudioRecord path: opening device mic…");
        if (micRunning) {
            if (result != null) result.success(null);
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
                Log.w(TAG, "AudioRecord FAILED to initialize — device mic busy/owned (CSJBot CAE)");
                audioRecord.release();
                audioRecord = null;
                if (result != null) result.error("MIC_ERROR", "AudioRecord failed to initialize", null);
                return;
            }

            audioRecord.startRecording();
            Log.d(TAG, "AudioRecord started (source ok) — capturing");
            micRunning = true;
            micThread = new Thread(() -> {
                byte[] buf = new byte[bufferSize / 2];
                int logged = 0;
                while (micRunning) {
                    int n = audioRecord.read(buf, 0, buf.length);
                    if (n > 0) {
                        final byte[] chunk = Arrays.copyOf(buf, n);
                        // Diagnostic: is the Android mic actually capturing audio, or
                        // is it silence (CSJBot CAE owns the hardware)? Log RMS of the
                        // first ~12 chunks — >0 while speaking ⇒ AudioRecord works.
                        if (logged < 12) {
                            Log.d(TAG, "AudioRecord RMS = " + String.format("%.4f", rms16(chunk)));
                            logged++;
                        }
                        main.post(() -> {
                            if (micSink != null) micSink.success(chunk);
                        });
                    }
                }
            }, "timo-mic");
            micThread.start();
            if (result != null) result.success(null);
        } catch (Throwable e) {
            Log.e(TAG, "startAudioRecordMic failed: " + e.getMessage());
            if (result != null) result.error("MIC_ERROR", e.getMessage(), null);
        }
    }

    private void stopMic() {
        if (usingSdkMic) {
            try {
                CsjRobot.getInstance().getSpeech().closeSpeechService();
            } catch (Throwable t) {
                Log.w(TAG, "closeSpeechService failed: " + t.getMessage());
            }
        }
        usingSdkMic = false; // stop forwarding CSJBot CAE audio
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
                            // Poll (not take) so we can detect the queue draining.
                            byte[] chunk = playQueue.poll(120, TimeUnit.MILLISECONDS);
                            if (chunk == null) {
                                // Nothing queued for 120ms → playback has drained.
                                if (!playbackIdleEmitted) {
                                    playbackIdleEmitted = true;
                                    emitPlayback(-1.0); // speech-end sentinel
                                }
                                continue;
                            }
                            if (chunk.length > 0 && audioTrack != null) {
                                playbackIdleEmitted = false;
                                // write() blocks ~ at playback rate once the buffer
                                // is full → the emit cadence tracks the speaker.
                                audioTrack.write(chunk, 0, chunk.length);
                                emitPlayback(rms16(chunk));
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
        if (!playbackIdleEmitted) {
            playbackIdleEmitted = true;
            emitPlayback(-1.0); // speech interrupted → face returns to listening
        }
        // Keep the AudioTrack object — ensurePlayback() re-arms play() on the next chunk.
    }

    /** Emit a playback amplitude (0..1), or -1 when playback drains. Main thread. */
    private void emitPlayback(double level) {
        main.post(() -> {
            if (playbackSink != null) playbackSink.success(level);
        });
    }

    /** RMS of a 16-bit little-endian PCM chunk, normalized 0..1. */
    private double rms16(byte[] b) {
        if (b.length < 2) return 0;
        double sum = 0;
        int n = 0;
        for (int i = 0; i + 1 < b.length; i += 2) {
            int s = (short) ((b[i] & 0xff) | (b[i + 1] << 8));
            sum += (double) s * s;
            n++;
        }
        if (n == 0) return 0;
        double r = Math.sqrt(sum / n) / 32768.0;
        return r > 1 ? 1 : r;
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
