# TimoDesk — Camera Live Stream

Live-stream the Timo / CSJBot robot camera over local WiFi to a browser
or Flutter mobile app.

```
timoDesk/
├── robot_app/      Flutter app that runs ON the robot (Android 7.1.2 / API 25)
├── viewer_web/     Single-file browser viewer (no server required)
└── viewer_mobile/  Flutter mobile viewer (Android + iOS)
```

---

## robot_app — runs on the Timo chest screen

### Prerequisites
- Flutter SDK installed on your dev machine
- Robot connected via USB or wirelessly reachable for `adb`
- (Optional) Android SDK / adb in PATH

### Build & deploy debug APK

```bash
cd robot_app
flutter pub get
flutter build apk --debug
# output: build/app/outputs/flutter-apk/app-debug.apk
adb install build/app/outputs/flutter-apk/app-debug.apk
```

Or run directly while the robot is connected via USB:

```bash
flutter run
```

### What it does
- Opens an MJPEG HTTP server on port **8080**
- Tap **START STREAM** — the app shows the stream URL + QR code
- Scan the QR code with a phone (or open the URL in a browser) to view live

### Endpoints
| Path        | Description                              |
|-------------|------------------------------------------|
| `/stream`   | MJPEG stream (multipart/x-mixed-replace) |
| `/snapshot` | Single JPEG frame (for quick testing)    |
| `/`         | Embedded HTML player                     |

---

## viewer_web — browser viewer

No build step needed — just open the HTML file.

```bash
open timoDesk/viewer_web/index.html
# or drag the file into any browser
```

1. Type the robot's IP address in the input field
2. Click **Connect**
3. The MJPEG stream appears; click **Fullscreen** for full-screen view

Works in Chrome, Firefox, Safari, and mobile browsers on the same WiFi.

---

## viewer_mobile — Flutter mobile app

### Run on a connected phone

```bash
cd viewer_mobile
flutter pub get
flutter run
```

### Build APK (Android) or IPA (iOS)

```bash
flutter build apk --release
flutter build ipa --release   # requires Xcode / macOS
```

### How to use
1. **Connect screen** — enter the robot's IP and port (default 8080)  
   Recently used IPs are saved locally for quick reconnect.
2. **Live Feed screen** — full-screen MJPEG stream with status overlay  
   Supports landscape rotation; auto-retries on disconnect.

---

## Swapping the mock camera for the real CsjRobot SDK

The mock camera (cycling red/green/blue frames) lives in one place:

**`robot_app/android/app/src/main/java/com/timoDesk/robotapp/CameraStreamPlugin.java`**

Look for the `startCamera()` method and the comment block:

```java
// ===== REAL SDK INTEGRATION POINT =====
// Replace this mock with:
// CsjRobot.getInstance().registerCameraListener(new OnCameraListener() {
//     @Override
//     public void response(Bitmap bitmap) {
//         pushFrame(bitmap);
//     }
// });
// ===== END SDK INTEGRATION POINT =====
```

**Steps:**

1. Drop the CsjRobot SDK `.aar` into `robot_app/android/app/libs/`

2. Add to `robot_app/android/app/build.gradle`:
   ```gradle
   dependencies {
       implementation fileTree(dir: 'libs', include: ['*.aar'])
   }
   ```

3. In `startCamera()`, **delete** the mock `cameraThread` block and
   **replace** it with:
   ```java
   CsjRobot.getInstance().registerCameraListener(new OnCameraListener() {
       @Override
       public void response(Bitmap bitmap) {
           pushFrame(bitmap);   // pushFrame(Bitmap) overload handles conversion
       }
   });
   ```

4. Add any required SDK initialization in `MainActivity.java`
   (refer to the CsjRobot SDK docs for `init()` calls).

5. Rebuild and deploy.

No other files need to change — the MJPEG server, Flutter UI, web viewer,
and mobile viewer all remain exactly the same.
