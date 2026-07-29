import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config.dart';
import 'providers.dart'; // chassisProvider (native getPosition/naviTo/cancelNavi)
import 'services/audio_bridge.dart'; // arrival speech fallback (device TTS)
import 'services/elevenlabs_tts.dart'; // arrival speech (Mikee's real voice)
import 'services/interaction_log.dart';
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
  final String? navSource; // 'robot' | 'admin' | 'patrol' | 'escort' — who started the nav.
  //                          Survives arrival (the escort arrival check needs it);
  //                          overwritten by the next departure.
  final Map<String, dynamic>? escort; // spine Follow-Me progress
  //                          {active,index,total,checking} — non-null while the
  //                          spine escort sequencer is running (from navi_state).

  const NavPointsState({
    this.points = const AsyncValue.loading(),
    this.capturing = false,
    this.navigatingTo,
    this.arrivedAt,
    this.navSource,
    this.escort,
  });

  NavPointsState copyWith({
    AsyncValue<List<NavPoint>>? points,
    bool? capturing,
    NavPoint? navigatingTo,
    bool clearNavigating = false,
    String? arrivedAt,
    bool clearArrived = false,
    String? navSource,
    Map<String, dynamic>? escort,
    bool clearEscort = false,
  }) =>
      NavPointsState(
        points: points ?? this.points,
        capturing: capturing ?? this.capturing,
        navigatingTo: clearNavigating ? null : (navigatingTo ?? this.navigatingTo),
        arrivedAt: clearArrived ? null : (arrivedAt ?? this.arrivedAt),
        navSource: navSource ?? this.navSource,
        escort: clearEscort ? null : (escort ?? this.escort),
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
    // Escort lifecycle events → spoken lines, so a checkpoint pause is never
    // silent (the visitor being escorted must know why the robot stopped).
    _escortEventSub =
        _ref.read(navSpineClientProvider).escortEvents.listen(_onEscortEvent);
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
  StreamSubscription<Map<String, dynamic>>? _escortEventSub;
  Timer? _navStaleTimer; // safety net for a navigation that never reports back

  /// A navigation this old with no update from the spine or the SDK is treated
  /// as dead state. Deliberately longer than every spine-side watchdog (navi
  /// watch 4 min, dock watch 6 min) so a real, slow navigation is never cut
  /// short — this only fires when nobody ever told us the nav ended.
  ///
  /// Why it matters beyond a stuck banner: `navigatingTo` gates the face
  /// greeting (navigation owns the speaker), so a stale value silenced every
  /// greeting until the app was restarted.
  static const Duration _navStaleAfter = Duration(minutes: 7);

  void _armNavStaleWatch() {
    _navStaleTimer?.cancel();
    _navStaleTimer = Timer(_navStaleAfter, () {
      if (!mounted || state.navigatingTo == null) return;
      debugPrint('navSync: no nav update in ${_navStaleAfter.inMinutes}m — '
          'clearing stale navigation state');
      InteractionLog.log('nav_state_stale_cleared', state.navigatingTo!.name);
      state = state.copyWith(clearNavigating: true, clearEscort: true);
    });
  }

  void _cancelNavStaleWatch() {
    _navStaleTimer?.cancel();
    _navStaleTimer = null;
  }
  Timer? _escortTimer; // periodic "please stay with me" while escorting
  // Departure announced for this nav target — guards the double-speak between
  // the INSTANT announcement in goTo() (robot-initiated: speak BEFORE the
  // spine round-trip so the visitor hears a response immediately) and the
  // navi_state broadcast (admin-initiated navs, or our own echoed back).
  String? _announcedDeparture;

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

  /// Escort reassurance: while leading a visitor ("follow me"), speak a short
  /// configurable phrase every N seconds so they know to keep following. The
  /// chest camera faces the direction of travel, so we CANNOT see whether the
  /// follower is still behind us mid-route — time-based reassurance is the
  /// honest tool here; the camera check happens after arrival (ambient screen).
  /// Patrol legs never reassure (nobody is being escorted).
  void _startEscortTimer() {
    _stopEscortTimer();
    final secs = RobotConfig.escortReassureSeconds;
    final text = RobotConfig.escortReassureText;
    if (secs <= 0 || text.isEmpty) return;
    // FAILSAFE CAP: if arrival detection misses for ANY reason (chassis parks
    // outside the arrival radius, position path hiccup, missed broadcast), the
    // robot must not chant the reassurance forever at the destination — stop
    // after a handful of repeats; the nav state itself is untouched.
    var repeats = 0;
    _escortTimer = Timer.periodic(Duration(seconds: secs), (_) {
      if (!mounted || state.navigatingTo == null) {
        _stopEscortTimer();
        return;
      }
      if (++repeats > 6) {
        debugPrint('escort: reassurance capped after $repeats repeats');
        InteractionLog.log('escort_reassure_capped', state.navigatingTo!.name);
        _stopEscortTimer();
        return;
      }
      _speakArrival(text);
    });
  }

  void _stopEscortTimer() {
    _escortTimer?.cancel();
    _escortTimer = null;
  }

  /// Speak "Okay, follow me to X" — exactly once per navigation, whichever
  /// path gets there first (goTo's instant call or the spine broadcast).
  /// The escort reassurance loop runs ONLY for robot-initiated navs (a
  /// visitor said "take me to…" and is walking behind) — an admin Go-To has
  /// nobody to reassure and was chanting at an empty room.
  void _announceDeparture(String name, String source) {
    if (_announcedDeparture == name) return;
    _announcedDeparture = name;
    InteractionLog.log('departure', '$name (source: $source)');
    _speakArrival('Okay, follow me to $name.');
    if (source == 'robot') _startEscortTimer();
  }

  // Spoken escort-check lines. The pause phrase is the critical one: the spine
  // cancels the goal mid-leg for a person check and the robot would otherwise
  // just stop dead in silence — the visitor has to know it's deliberate.
  // (Candidates for RobotConfig settings later; the lost line reuses the
  // ambient screen's configurable phrasing style but is mid-route specific.)
  static const _checkPhrase =
      'One moment — just making sure you are still with me.';
  static const _resumePhrase = 'Great, there you are. This way.';
  static const _lostPhrase =
      'It seems we got separated. I will wait right here — '
      'please find me if you still need me.';

  /// Speak the escort lifecycle so the visitor understands each pause.
  void _onEscortEvent(Map<String, dynamic> e) {
    if (!mounted) return;
    final event = e['event'] as String?;
    switch (event) {
      case 'checkpoint':
      case 'arrival_check':
        _speakArrival(_checkPhrase);
      case 'person_confirmed':
        // Only checkpoint confirmations get a spoken resume — an arrival
        // confirmation flows straight into the next leg's departure
        // announcement ("Okay, follow me to …"), which already covers it.
        if (e['at'] == 'checkpoint') _speakArrival(_resumePhrase);
      case 'finished':
        if (e['reason'] == 'visitor_lost') {
          InteractionLog.log('escort_lost_midroute',
              state.navigatingTo?.name ?? 'unknown leg');
          _speakArrival(_lostPhrase);
        }
    }
  }

  /// Apply a spine navi_state broadcast (the shared cross-client truth).
  void _onSpineNaviState(Map<String, dynamic> m) {
    if (!mounted) return;
    // Follow-Me escort progress rides on navi_state; the spine only includes
    // the field while its escort sequencer runs → absent means not escorting.
    final escort = m['escort'] as Map<String, dynamic>?;
    if (escort?['active'] == true) {
      state = state.copyWith(escort: escort);
    } else if (state.escort != null) {
      state = state.copyWith(clearEscort: true);
    }
    if (m['active'] != true) {
      _stopEscortTimer();
      _cancelNavStaleWatch();
      _announcedDeparture = null; // nav over → next one announces again
      if (m['arrived'] == true) {
        // Spine's arrival watcher confirmed the robot reached the point.
        final name =
            (m['name'] as String?) ?? state.navigatingTo?.name ?? 'the destination';
        debugPrint('navSync: arrived at "$name" — speaking announcement');
        InteractionLog.log('arrival', name);
        _speakArrival(_arrivalPhrase(name, m['arrivalText'] as String?));
        state = state.copyWith(clearNavigating: true, arrivedAt: name);
      } else {
        state = state.copyWith(clearNavigating: true);
      }
      return;
    }
    final name = (m['name'] as String?) ?? 'a saved point';
    // Departure announcement — once per navigation via _announceDeparture's
    // guard. IMPORTANT: this must run even when navigatingTo is already set:
    // robot-initiated goTo() sets state BEFORE this broadcast echoes back, and
    // the old early-return silently ate the phrase for every voice-commanded
    // nav. Patrol legs are EXCLUDED (per product decision): a looping patrol
    // announcing every departure is noise — the per-waypoint arrival
    // announcements carry the patrol narration.
    if (m['source'] != 'patrol') {
      _announceDeparture(name, (m['source'] as String?) ?? 'admin');
    }
    if (state.navigatingTo?.name == name) return; // state already up to date
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
    state = state.copyWith(
      navigatingTo: target,
      clearArrived: true,
      navSource: (m['source'] as String?) ?? 'admin',
    );
    _armNavStaleWatch();
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
    if (e.isArrival || e.kind == 'cancel_result') {
      _stopEscortTimer();
      _cancelNavStaleWatch();
    }
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
    _escortEventSub?.cancel();
    _stopEscortTimer();
    _cancelNavStaleWatch();
    super.dispose();
  }

  /// Return to the charging dock (the "Go to Charge" action). Speaks a
  /// departure line, then drives home via the SDK goHome path (dock IR aligns
  /// the final approach). No saved point needed — home is the dock the robot
  /// booted from. Arrival is announced by the same naviEvents path as goTo.
  Future<bool> goHome() async {
    InteractionLog.log('go_home', 'returning to charging dock');
    _speakArrival('Okay, I am returning to my charging station.');
    try {
      await _ensureChassis();
      final ok = await _ref.read(chassisProvider.notifier).goHome();
      if (!ok) {
        _speakArrival("Sorry, I couldn't start heading to the dock right now.");
      }
      return ok;
    } catch (e) {
      debugPrint('goHome: $e');
      return false;
    }
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

  /// Background refresh: re-fetch WITHOUT dropping to loading, so the last
  /// list stays usable for concurrent voice matching / UI while we fetch. On
  /// failure the old list is kept (a stale list beats an empty one mid-escort).
  /// This is what makes points captured from the admin app voice-actionable
  /// without restarting the robot app.
  Future<void> refresh() async {
    try {
      final list = await _api.list();
      if (!mounted) return;
      state = state.copyWith(points: AsyncValue.data(list));
    } catch (_) {
      // keep the previous list
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
    state = state.copyWith(
        navigatingTo: point, clearArrived: true, navSource: 'robot');
    _armNavStaleWatch();
    // Speak BEFORE dispatching: the visitor must hear an acknowledgement the
    // moment their command is accepted, not after the spine round-trip. The
    // navi_state broadcast that follows is deduped by _announceDeparture.
    _announceDeparture(point.name, 'robot');
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
    _cancelNavStaleWatch();
    if (mounted) state = state.copyWith(clearNavigating: true);
  }

  /// Start a Follow-Me escort over [route] (in order; last point is the
  /// destination). The sequencer + camera person-checks run IN THE SPINE, so
  /// this requires a live spine connection — no native fallback. Returns false
  /// when the spine is unreachable so the screen can say why.
  bool escortStart(List<NavPoint> route) {
    final spine = _ref.read(navSpineClientProvider);
    if (!spine.isConnected || route.isEmpty) return false;
    InteractionLog.log('escort_start', route.map((p) => p.name).join(' → '));
    spine.sendIntent({
      'intent': 'escort_start',
      'points': [
        for (final p in route)
          {
            ...p.pose,
            'name': p.name,
            if (p.description?.trim().isNotEmpty == true)
              'arrivalText': p.description!.trim(),
          }
      ],
    });
    return true;
  }

  /// Stop the running escort (also cancels the active leg).
  void escortStop() {
    final spine = _ref.read(navSpineClientProvider);
    if (spine.isConnected) spine.sendIntent({'intent': 'escort_stop'});
    if (mounted) state = state.copyWith(clearEscort: true);
  }
}

/// Singleton provider (kept alive so the saved list survives navigating away
/// from the screen), matching the robot_app convention.
final navPointsProvider =
    StateNotifierProvider<NavPointsNotifier, NavPointsState>((ref) {
  ref.keepAlive();
  return NavPointsNotifier(ref);
});
