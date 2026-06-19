import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Background isolate handler. Must be a top-level / static function. The OS
/// shows the tray notification itself; we keep this minimal.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  // Intentionally minimal — heavy work isn't safe in the background isolate.
}

/// FCM device registration + message handling for the mobile admin (#90 Part B).
///
/// Dormant-by-default: callers wrap [init] so that without Firebase config
/// (google-services.json) the app still runs. Web is skipped in v1 (web push
/// needs a VAPID key + service worker — out of scope; Android first, iOS
/// fast-follow).
class PushService {
  /// Set by main() so foreground messages can show an in-app banner.
  static GlobalKey<ScaffoldMessengerState>? messengerKey;

  /// Set by main() so a tapped notification can deep-link.
  static void Function(RemoteMessage message)? onOpen;

  static Future<void> init() async {
    if (kIsWeb) return; // v1 = mobile only

    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
    final messaging = FirebaseMessaging.instance;

    await messaging.requestPermission();

    // Register now (if already logged in) + on every future login.
    await _registerToken();
    Supabase.instance.client.auth.onAuthStateChange.listen((_) => _registerToken());
    messaging.onTokenRefresh.listen(_upsert);

    // Foreground → in-app banner. Tap (background) → deep-link.
    FirebaseMessaging.onMessage.listen(_onForeground);
    FirebaseMessaging.onMessageOpenedApp.listen((m) => onOpen?.call(m));
  }

  static Future<void> _registerToken() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return; // only register for a real, logged-in user
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await _upsert(token);
  }

  /// UPSERT the token to Supabase `device_token` (unique on token → idempotent).
  static Future<void> _upsert(String token) async {
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return;
      final platform = Platform.isIOS ? 'ios' : 'android';
      await client.from('device_token').upsert(
        {
          'user_id': user.id,
          'token': token,
          'platform': platform,
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'token',
      );
    } catch (e) {
      debugPrint('[push] token upsert failed: $e');
    }
  }

  static void _onForeground(RemoteMessage message) {
    final n = message.notification;
    final messenger = messengerKey?.currentState;
    if (n == null || messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1A1A1A),
        content: Text('${n.title ?? ''}\n${n.body ?? ''}'.trim()),
        action: onOpen == null
            ? null
            : SnackBarAction(label: 'OPEN', onPressed: () => onOpen!(message)),
      ),
    );
  }
}
