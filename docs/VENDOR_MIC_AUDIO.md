# Vendor request — microphone audio for our client app (Mikee)

**To:** Alpha Robotics / CSJBot support (via Vishal)
**Robot:** Mikee (CSJBot platform, Android 7.1.2 chest screen)
**Our app:** `com.mikee.robotapp` (secondary/foreground reception app; uses the CSJBot SDK)
**Contact:** Nishant (xboom Utilities Pvt. Ltd.)

## One-line ask
On this robot, the system speech service recognises speech but **forwards empty
results (`result:""`) and no mic PCM to client apps** registered via the SDK
`OnSpeechListener`. We need the supported way to receive the microphone audio in
our app **without exclusive-opening the ALSA device**, because the vendor SDK
process (`com.csjbot.robotsdk.ten`) holds the mic exclusively and also drives the
chassis, so we cannot take the device from it without breaking navigation.

## What we observe (evidence)
1. **The USB 4-mic array `/dev/snd/pcmC1D0c` is exclusive-open.** Only one process
   can hold it. `com.csjbot.robotsdk.ten`'s CAE grabs it at boot and **re-grabs it
   within ~2 s** whenever it is freed. Any `AudioRecord`/`startRecord()` in our
   process then fails with `open pcm device failed`.
2. **The SDK `OnSpeechListener` path returns nothing useful.** We register
   `CsjRobot.getInstance().registerSpeechListener(...)` and implement both
   `speechInfo(json, type)` and `onAudio(byte[])`. With the system engine running,
   `speechInfo` arrives but the `"text"` field is **empty (`result:""`)** and no
   usable `onAudio` PCM is delivered to our (client) process.
3. **The stock CSJBot demo/reception app behaves the same** on this robot — it
   recognises speech but receives empty results — which tells us this is a
   **robot/server-side speech-forwarding configuration issue**, not our code.
4. As a workaround we start an **in-process AIUI/CAE** (`getSpeech().startIsr()` +
   `AIUIMixedManager.getInstance().startAudioRecognize()`). This *does* stream mic
   PCM to our `onAudio`, but it (a) **exclusive-grabs `pcmC1D0c`**, conflicting with
   `robotsdk.ten` (whoever loses the race is deaf until reboot), (b) floods
   `IAlsaRawDataSender.sendAlsaData → DeadObjectException` when
   `com.csjbot.asragent` (the `AlsaDataReceiverService`) is not alive, and (c)
   **pegs the CPU at ~130%** (com.android.phone ANRs). Not viable in production.

## What we need (either path is fine)

### Option A — forward mic audio/ASR to client apps (preferred; our code is ready)
Enable the system speech service to forward recognised text **and/or** raw mic PCM
to client apps registered via `registerSpeechListener` (`OnSpeechListener.speechInfo`
with a non-empty `text`, and/or `onAudio(byte[])`), **while `robotsdk.ten` keeps
owning the mic device**. Our listener is already registered passively — the moment
forwarding works we consume it with **no code change**.
- Q1: Why does `speechInfo` return `result:""` to client apps on this unit? Is
  there a robot/OS setting or a CSJBot config that enables speech-result forwarding?
- Q2: Can the system deliver raw beamformed mic PCM to `OnSpeechListener.onAudio`
  for a client app without that app starting its own CAE/`startIsr()`?
- Q3: What keeps `com.csjbot.asragent` (`AlsaDataReceiverService`) alive and its
  `sendAlsaData` binder valid while OUR app is the foreground app? It dies when we
  foreground, breaking the forwarding chain (DeadObjectException flood).

### Option B — let our app own the mic cleanly
If forwarding to clients isn't supported, give us a supported way to **stop
`robotsdk.ten`'s own wake-word / voice-assistant mic capture** (or run its AIUI
in-process in our app via `enableFace(true)`), so the mic is free for our app to
hold **permanently**, while chassis + SLAM keep running in `robotsdk.ten`.
- Q4: Is there an SDK call / system setting to disable the vendor voice assistant's
  microphone capture without stopping chassis/SLAM?
- Q5: Is `enableFace(true)`-style in-process AIUI the supported way for a client app
  to own the mic 24/7? If so, how do we make it durable (no CPU peg, no re-grab war)?

## Reference (our code)
- `robot_app/android/app/src/main/java/com/mikee/robotapp/AudioBridgePlugin.java`
  - `startSdkMic()` — the passive `registerSpeechListener` consumer (Option A, ready).
  - `startSpeechEngine()` — the in-process AIUI workaround (the mic-grab we want to retire).
  - Comments at lines 224–235 and 308–353 document the exclusive-mic conflict and the
    empty-`result` forwarding problem in detail.
