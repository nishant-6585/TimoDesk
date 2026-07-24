import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config.dart';
import 'providers.dart'; // chassisProvider (native getPosition/naviTo/cancelNavi)
import 'services/audio_bridge.dart'; // arrival speech fallback (device TTS)
import 'services/elevenlabs_tts.dart'; // arrival speech (Mikee's real voice)
import 'services/nav_points_api.dart';
import 'services/spine_client.dart';

/// Shared spine WS client for navigation sync. Separate instance from the
/// ambient-face screen's private client (cleanup TODO: unify them here).
final navSpineClientProvider = Provider<SpineClient>((ref) {
  ref.keepAlive();
  final client = SpineClient()..start();
  ref.onDispose(client.dispose);
  return client;
});

/// Whole-screen state for the on-robot Navigation Points feature.
///
/// Holds the loaded list (as an [AsyncValue] so the UI can render
/// loading/empty/error uniformly) plus a transient "navigating to X" flag while
/// a go-to is in flight.
@immutable
class NavPointsState {
  final AsyncValue<List<NavPoint>> points;
  final bool capturing;
  final NavPoint? navigatingTo; // non-null while a go-to is active
  final String? arrivedAt; // name of the point just reached (transient banner)

  const NavPointsState({
    this.points = const AsyncValue.loading(),
    this.capturing = false,
    this.navigatingTo,
    this.arrivedAt,
  });

  NavPointsState copyWith({
    AsyncValue<List<NavPoint>>? points,
    bool? capturing,
    NavPoint? navigatingTo,
    bool clearNavigating = false,
    String? arrivedAt,
    bool clearArrived = false,
  }) =>
      NavPointsState(
        points: points ?? this.points,
        capturing: capturing ?? this.capturing,
        navigatingTo: clearNavigating ? null : (navigatingTo ?? this.navigatingTo),
        arrivedAt: clearArrived ? null : (arrivedAt ?? this.arrivedAt),
      );
}

class NavPointsNotifier extends StateNotifier<NavPointsState> {
  NavPointsNotifier(this._ref) : super(const NavPointsState()) {
    load();
    // Listen for navi lifecycle events from the native SDK → announce arrival.
    _naviSub = _ref
        .read(chassisProvider.notifier)
        .naviEvents
        .listen(_onNaviEvent);
    // Spine navi_state broadcasts: a Go To / Cancel from ANY client (web admin
    // or this robot) syncs the banner + cancel UI here.
    _naviStateSub =
        _ref.read(navSpineClientProvider).naviState.listen(_onSpineNaviState);
  }

  final Ref _ref;
  final NavPointsApi _api = NavPointsApi();
  final AudioBridge _audio = AudioBridge();
  late final ElevenLabsTts _voice = ElevenLabsTts(
    apiKey: RobotConfig.elevenLabsApiKey,
    voiceId: RobotConfig.elevenLabsVoiceId,
    audio: _audio,
  );
  StreamSubscription<NaviEvent>? _naviSub;
  StreamSubscription<Map<String, dynamic>>? _naviStateSub;

  /// Speak an arrival announcement through Mikee's real voice (ElevenLabs →
  /// proven speaker path). The device-TTS fallback exists because ElevenLabs
  /// needs internet + key — but device TTS is NOT guaranteed installed on this
  /// Android build, which is why ElevenLabs is primary.
  Future<void> _speakArrival(String phrase) async {
    debugPrint('navSync: speaking arrival: "$phrase"');
    final ok = await _voice.speak(phrase);
    if (!ok) {
      debugPrint('navSync: ElevenLabs failed — falling back to device TTS');
      await _audio.speak(phrase);
    }
  }

  /// Apply a spine navi_state broadcast (the shared cross-client truth).
  void _onSpineNaviState(Map<String, dynamic> m) {
    if (!mounted) return;
    if (m['active'] != true) {
      if (m['arrived'] == true) {
        // Spine's arrival watcher confirmed the robot reached the point.
        final name =
            (m['name'] as String?) ?? state.navigatingTo?.name ?? 'the destination';
        debugPrint('navSync: arrived at "$name" — speaking announcement');
        _speakArrival(_arrivalPhrase(name, m['arrivalText'] as String?));
        state = state.copyWith(clearNavigating: true, arrivedAt: name);
      } else {
        state = state.copyWith(clearNavigating: true);
      }
      return;
    }
    final name = (m['name'] as String?) ?? 'a saved point';
    if (state.navigatingTo?.name == name) return; // already showing it
    final list = state.points.valueOrNull ?? const <NavPoint>[];
    final target = list.where((p) => p.name == name).firstOrNull ??
        NavPoint(
          id: '_remote',
          name: name,
          x: 0,
          y: 0,
          z: 0,
          rotation: 0,
          kind: 'navigation',
          sortOrder: 0,
        );
    state = state.copyWith(navigatingTo: target, clearArrived: true);
    // Departure announcement — fires exactly once per navigation (the early
    // return above dedupes the cancelling/stalled re-broadcasts) for BOTH
    // admin- and robot-initiated navs.
    _speakArrival('Okay, follow me to $name.');
  }

  /// What the robot says on arrival: the point's custom announcement (stored in
  /// nav_points.description) when set, else a phrase built from the point name.
  String _arrivalPhrase(String name, String? custom) {
    final text = custom?.trim();
    if (text != null && text.isNotEmpty) return text;
    return "We have arrived at $name.";
  }

  /// Handle a navigation lifecycle event from the native chassis plugin.
  /// On arrival: speak the destination name, clear the navigating flag, and
  /// surface a transient "arrived" banner.
  void _onNaviEvent(NaviEvent e) {
    if (!mounted) return;
    if (e.isArrival) {
      final target = state.navigatingTo;
      final name = target?.name ?? 'the destination';
      _speakArrival(_arrivalPhrase(name, target?.description));
      state = state.copyWith(clearNavigating: true, arrivedAt: name);
    } else if (e.kind == 'cancel_result') {
      state = state.copyWith(clearNavigating: true);
    }
  }

  /// Dismiss the "arrived" banner.
  void clearArrived() {
    if (mounted) state = state.copyWith(clearArrived: true);
  }

  @override
  void dispose() {
    _naviSub?.cancel();
    _naviStateSub?.cancel();
    super.dispose();
  }

  /// Ensure chassis control is started before any getPosition/navi call — the
  /// native SDK no-ops otherwise (mirrors how the dashboard d-pad starts it).
  Future<void> _ensureChassis() async {
    final chassis = _ref.read(chassisProvider);
    if (!chassis.isRunning) {
      await _ref.read(chassisProvider.notifier).startChassisControl();
    }
  }

  /// (Re)load all saved points.
  Future<void> load() async {
    state = state.copyWith(points: const AsyncValue.loading());
    try {
      final list = await _api.list();
      if (!mounted) return;
      state = state.copyWith(points: AsyncValue.data(list));
    } catch (e, st) {
      if (!mounted) return;
      state = state.copyWith(points: AsyncValue.error(e, st));
    }
  }

  /// Capture the robot's CURRENT pose (drive it there first) and save under
  /// [name]. Throws on failure (not localized / insert error) so the screen can
  /// surface the reason; reloads on success.
  Future<void> capture(String name, {String? description}) async {
    state = state.copyWith(capturing: true);
    try {
      await _ensureChassis();
      final pose = await _ref.read(chassisProvider.notifier).getPosition();
      if (pose == null) {
        throw Exception(
            'Could not read robot position. Make sure the robot is localized on its map, then try again.');
      }
      await _api.insert(
        name: name,
        description: description,
        x: pose['x'] ?? 0.0,
        y: pose['y'] ?? 0.0,
        z: pose['z'] ?? 0.0,
        rotation: pose['rotation'] ?? 0.0,
      );
      await load();
    } finally {
      if (mounted) state = state.copyWith(capturing: false);
    }
  }

  /// Update a point's name / arrival announcement and reload.
  Future<void> update(String id, {String? name, String? description}) async {
    await _api.update(id, name: name, description: description);
    await load();
  }

  /// Delete a saved point and reload.
  Future<void> delete(String id) async {
    await _api.delete(id);
    await load();
  }

  /// Send the robot to a saved point. Sets [NavPointsState.navigatingTo] while
  /// the SDK is driving there. Returns false if the SDK rejected the request.
  ///
  /// Routed through the spine when connected (single command path + the spine
  /// broadcasts navi_state so the web admin shows the same banner/cancel).
  /// Falls back to the native MethodChannel when the spine is unreachable
  /// (standalone mode — no cross-device sync then).
  Future<bool> goTo(NavPoint point) async {
    state = state.copyWith(navigatingTo: point, clearArrived: true);
    final spine = _ref.read(navSpineClientProvider);
    if (spine.isConnected) {
      // isConnected can be STALE after a silent Wi-Fi drop (half-open socket) —
      // require the spine's navi_state confirmation broadcast; on timeout fall
      // through to the native path so on-robot Go To works offline too.
      final confirmed = spine.naviState
          .firstWhere((m) => m['active'] == true)
          .timeout(const Duration(seconds: 3));
      spine.sendIntent({
        'intent': 'navi',
        'point': point.pose,
        'name': point.name,
        'source': 'robot',
        if (point.description?.trim().isNotEmpty == true)
          'arrivalText': point.description!.trim(),
      });
      try {
        await confirmed;
        return true;
      } catch (_) {
        debugPrint('goTo: spine unconfirmed in 3s — falling back to native');
      }
    }
    try {
      await _ensureChassis();
      final ok = await _ref.read(chassisProvider.notifier).naviTo(point.pose);
      if (!ok && mounted) state = state.copyWith(clearNavigating: true);
      return ok;
    } catch (e) {
      debugPrint('goTo: $e');
      if (mounted) state = state.copyWith(clearNavigating: true);
      return false;
    }
  }

  /// Cancel an in-flight navigation and clear the navigating flag.
  /// Via spine when connected (so all clients see the cancel); falls back to
  /// the native path if the spine doesn't confirm within 3s (stale socket).
  Future<void> cancel() async {
    final spine = _ref.read(navSpineClientProvider);
    if (spine.isConnected) {
      final confirmed = spine.naviState
          .firstWhere((m) => m['active'] != true || m['cancelling'] == true)
          .timeout(const Duration(seconds: 3));
      spine.sendIntent({'intent': 'cancel_navi'});
      try {
        await confirmed;
        return; // banner clears on the robot's cancel_result broadcast
      } catch (_) {
        debugPrint('cancel: spine unconfirmed in 3s — falling back to native');
      }
    }
    await _ref.read(chassisProvider.notifier).cancelNavi();
    if (mounted) state = state.copyWith(clearNavigating: true);
  }

  /// Mark navigation finished (e.g. the operator dismisses the banner).
  void clearNavigating() {
    if (mounted) state = state.copyWith(clearNavigating: true);
  }
}

/// Singleton provider (kept alive so the saved list survives navigating away
/// from the screen), matching the robot_app convention.
final navPointsProvider =
    StateNotifierProvider<NavPointsNotifier, NavPointsState>((ref) {
  ref.keepAlive();
  return NavPointsNotifier(ref);
});
