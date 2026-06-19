# Firebase Setup — Push Notifications (FCM)

> Setup guide for the TimoDesk **mobile admin push notifications** (#90 Part B).
> Project: **`timodesk`** · project number **`362219956591`**.
> Push: visitor-arrived → host, battery-low → admins, obstacle-blocked → admins.

**Architecture:** the Flutter admin app registers an FCM device token (stored in Supabase
`device_token`); **spine** sends pushes via the **FCM HTTP v1 API** using a service-account
key. Client = `app/lib/.../push_service.dart`; sender = `spine/src/services/push.ts`.

---

## Status (2026-06-19)

| Step | State |
|---|---|
| Firebase project `timodesk` created | ✅ |
| Apps registered (Android `com.example.timo_admin`, iOS `com.example.timoAdmin`, web) via `flutterfire configure` | ✅ |
| `firebase_options.dart` generated + committed; `main.dart` inits with `DefaultFirebaseOptions.currentPlatform` | ✅ |
| Android `google-services` Gradle plugin wired (Kotlin DSL, v4.3.10); APK build proven | ✅ |
| `google-services.json` + `GoogleService-Info.plist` committed (client config, not secrets) | ✅ |
| **Spine service-account key** (`FCM_SERVICE_ACCOUNT`) | ⬜ **TODO — you** |
| **On-device test** (Android) | ⬜ TODO |
| **iOS APNs key** (needs Apple Developer account) | ⬜ TODO |

---

## What's already done (no action needed)

`flutterfire configure` registered the apps and generated/placed:
- `app/lib/firebase_options.dart` (committed — client config, needed to build everywhere)
- `app/android/app/google-services.json` (committed)
- `app/ios/Runner/GoogleService-Info.plist` (committed)

`main.dart` initializes Firebase with the generated options behind a try/catch guard, and the
Android `com.google.gms.google-services` plugin is applied (`settings.gradle.kts` +
`app/build.gradle.kts`). The debug APK builds clean — which proves the Android config is wired
correctly (the plugin hard-fails if `google-services.json` is missing or its package name
mismatches `applicationId`).

> **Cross-machine note:** these three config files are committed precisely so the app builds
> on every machine (cloud session, CI, second laptop) — they contain no real secret (a Firebase
> API key is a project identifier, not a credential; security is enforced server-side).

---

## TODO 1 — Spine service-account key (lets spine SEND) ← do this to activate push

1. Firebase Console → ⚙ **Project settings** → **Service accounts** → **Generate new private key**
   → downloads e.g. `timodesk-firebase-adminsdk-xxxxx.json`.
2. Put it where spine can read it, **OUTSIDE git** — e.g. `spine/secrets/firebase-service-account.json`.
   Confirm it's gitignored. **NEVER commit this file** (it has `private_key` + `client_email`).
3. In `spine/.env`:
   ```
   FCM_SERVICE_ACCOUNT=/absolute/path/to/spine/secrets/firebase-service-account.json
   FCM_PROJECT_ID=timodesk        # optional — spine also reads project_id from the JSON
   ```
   (`FCM_SERVICE_ACCOUNT` accepts a file path **or** inline JSON.)
4. Restart spine. On boot it should NOT log `[push] FCM not configured`.

## TODO 2 — Confirm FCM HTTP v1 is enabled
Firebase Console → Project settings → **Cloud Messaging** tab → **Firebase Cloud Messaging API
(V1)** = **Enabled** (on by default for new projects). Spine uses v1, not the deprecated legacy
server key.

## TODO 3 — On-device test (Android)
1. Install the debug APK on a **real Android phone** (or an emulator **with Google Play**).
2. **Log in** → a row should appear in the Supabase **`device_token`** table. ✅ client registration works.
3. **Quick test:** Firebase Console → **Cloud Messaging** → *Send test message* → paste the
   device's FCM token → confirm it arrives.
4. **Real trigger:** `POST /visit` (visitor check-in for a host with a registered device) →
   the host's phone should get *"👋 X is here."* Spine logs show the push sent.

## TODO 4 — iOS push (APNs) — when the Apple Developer account is ready
1. **Apple Developer** → Certificates, Identifiers & Profiles → **Keys** → **+** → enable
   **Apple Push Notifications service (APNs)** → Register → **download the `.p8`** (one-time
   download). Note the **Key ID** + your **Team ID**.
2. Firebase Console → Project settings → **Cloud Messaging** → **Apple app configuration** →
   **APNs Authentication Key** → upload the `.p8`, enter Key ID + Team ID.
3. Xcode (`app/ios/Runner.xcworkspace`) → Runner target → **Signing & Capabilities**:
   + **Push Notifications**, + **Background Modes → Remote notifications**; set a real signing
   Team + Bundle Identifier.
4. iOS push works on a **real device only** (not the simulator).

---

## Gotchas

- **`com.example.timo_admin` is a placeholder package.** Fine for testing; for a real Play/App
  Store release switch to a real reverse-domain id (e.g. `in.xboom.timo`) — but that means
  re-registering the apps in Firebase, so decide before going to stores.
- **Host-specific targeting is TODO** in `push.ts` — pushes currently go to all admins with the
  host named in the body, because there's no `staff ↔ auth.users` link yet.
- **Never commit:** the service-account JSON, the `.p8` APNs key, or `spine/.env`.

---

## File map

| Piece | Where |
|---|---|
| Client FCM registration | `app/lib/services/.../push_service.dart` |
| Firebase init | `app/lib/main.dart` + `app/lib/firebase_options.dart` |
| Android plugin | `app/android/settings.gradle.kts` + `app/android/app/build.gradle.kts` |
| Spine sender (HTTP v1) | `spine/src/services/push.ts` |
| Device token table + RLS | `supabase/migrations/008_device_token.sql` |
| Spine env | `spine/.env` (`FCM_SERVICE_ACCOUNT`, `FCM_PROJECT_ID`) · `spine/.env.example` |
