import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config.dart';
import 'providers.dart'; // chassisProvider (native getPosition/naviTo/cancelNavi)
import 'services/audio_bridge.dart'; // arrival speech fallback (device TTS)
import 'services/robot_tts.dart'; // arrival speech (selected engine's voice)
import 'services/voice_arbiter.dart'; // single-speaker gate (agent vs announcements)
import 'services/interaction_log.dart';
import 'services/nav_points_api.dart';
import 'services/nav_points_cache.dart';
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
  final bool offline; // the list on screen came from the on-device cache, not
  //                     the spine. Driving still works (native chassis path);
  //                     capture/rename/delete do not.
  final DateTime? cachedAt; // when that cached list was last refreshed

  const NavPointsState({
    this.points = const AsyncValue.loading(),
    this.capturing = false,
    this.navigatingTo,
    this.arrivedAt,
    this.navSource,
    this.escort,
    this.offline = false,
    this.cachedAt,
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
    bool? offline,
    DateTime? cachedAt,
    bool clearCachedAt = false,
  }) =>
      NavPointsState(
        points: points ?? this.points,
        capturing: capturing ?? this.capturing,
        navigatingTo: clearNavigating ? null : (navigatingTo ?? this.navigatingTo),
        arrivedAt: clearArrived ? null : (arrivedAt ?? this.arrivedAt),
        navSource: navSource ?? this.navSource,
        escort: clearEscort ? null : (escort ?? this.escort),
        offline: offline ?? this.offline,
        cachedAt: clearCachedAt ? null : (cachedAt ?? this.cachedAt),
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
    // Spine (re)connected → resync. This is what turns the offline cache back
    // into live data without anyone touching the screen: boot offline on the
    // cache, spine comes up minutes later, list refreshes + offline flag drops.
    _connSub = _ref
        .read(navSpineClientProvider)
        .connected
        .listen((up) => up ? refresh() : null);
  }

  final Ref _ref;
  final NavPointsApi _api = NavPointsApi();
  final AudioBridge _audio = AudioBridge();
  late final RobotTts _voice = RobotTts(audio: _audio);
  StreamSubscription<NaviEvent>? _naviSub;
  StreamSubscription<Map<String, dynamic>>? _naviStateSub;
  StreamSubscription<Map<String, dynamic>>? _escortEventSub;
  StreamSubscription<bool>? _connSub;
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
  bool _stallAnnounced = false; // spoke the "trouble moving" line once per nav

  /// Speak an arrival announcement through Mini's real voice (ElevenLabs →
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
      // One voice at a time: if a conversation agent is holding the speaker, skip
      // this reassurance tick (don't talk over the live conversation, and don't
      // burn a repeat — resume reassuring once the conversation frees the speaker).
      if (VoiceArbiter.agentActive) {
        debugPrint('escort: agent owns speaker — skipping reassurance tick');
        return;
      }
      if (++repeats > 3) {
        // Arrival was never confirmed after a few reassurances. On this unit the
        // base can fail to translate (hardware) so the robot is stationary while
        // it chants "please stay with me" — stop and hand off HONESTLY instead of
        // repeating for a minute-plus.
        debugPrint('escort: reassurance capped after $repeats repeats');
        InteractionLog.log('escort_reassure_capped', state.navigatingTo!.name);
        _speakArrival('You can head over — I will be right here.');
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
    _speakArrival('Follow me to $name.');
    if (source == 'robot') _startEscortTimer();
  }

  // Spoken escort-check lines. The pause phrase is the critical one: the spine
  // cancels the goal mid-leg for a person check and the robot would otherwise
  // just stop dead in silence — the visitor has to know it's deliberate.
  // (Candidates for RobotConfig settings later; the lost line reuses the
  // ambient screen's configurable phrasing style but is mid-route specific.)
  static const _checkPhrase = 'One moment — checking you are with me.';
  static const _resumePhrase = 'Great — this way.';
  static const _lostPhrase = 'We got separated. I will wait right here.';

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
    // STALL: the spine says the goal is active but the robot isn't translating
    // (e.g. the base motor fault). Stop chanting "follow me" at a robot that
    // isn't moving — say it ONCE, honestly, and let the spine's watchdog clear
    // the goal. (Without this the escort reassurance loops for minutes.)
    if (m['stalled'] == true && m['active'] == true) {
      _stopEscortTimer();
      if (!_stallAnnounced) {
        _stallAnnounced = true;
        _speakArrival("Sorry — I'm having trouble moving right now. Please bear with me.");
      }
      return;
    }
    if (m['active'] != true) {
      _stopEscortTimer();
      _cancelNavStaleWatch();
      _announcedDeparture = null; // nav over → next one announces again
      _stallAnnounced = false; // reset for the next navigation
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
    return "We're at $name.";
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
    _connSub?.cancel();
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
    _speakArrival('Returning to my dock.');
    try {
      await _ensureChassis();
      final ok = await _ref.read(chassisProvider.notifier).goHome();
      if (!ok) {
        _speakArrival("Sorry, I can't head to the dock now.");
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

  /// (Re)load all saved points — offline-first.
  ///
  /// The on-device cache is shown IMMEDIATELY (if present) while the spine
  /// fetch runs, so the screen has tappable tiles and NavVoice has names to
  /// match even when the spine is slow or gone — driving is native and needs
  /// no server. A successful fetch then replaces the list and rewrites the
  /// cache; a failed fetch keeps the cached list and flags [offline]. The
  /// error state is now reserved for the truly-cold case: no spine AND no
  /// cache (first boot before any sync).
  Future<void> load() async {
    // Only drop to a spinner when there's nothing to show yet — a reload with
    // a list on screen (or a cache to replay) should never blank the screen.
    final cached = await NavPointsCache.read();
    if (!mounted) return;
    if (cached != null) {
      state = state.copyWith(
        points: AsyncValue.data(cached.points),
        offline: true,
        cachedAt: cached.savedAt,
      );
    } else if (state.points.valueOrNull == null) {
      state = state.copyWith(points: const AsyncValue.loading());
    }
    try {
      final list = await _api.list();
      if (!mounted) return;
      state = state.copyWith(
          points: AsyncValue.data(list), offline: false, clearCachedAt: true);
      await NavPointsCache.save(list);
    } catch (e, st) {
      if (!mounted) return;
      if (state.points.valueOrNull == null) {
        // Cold start with no cache — surface the real error.
        state = state.copyWith(points: AsyncValue.error(e, st));
      }
      // else: keep the cached/previous list, offline flag already set above.
      debugPrint('nav load: spine unreachable, serving cache — $e');
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
      state = state.copyWith(
          points: AsyncValue.data(list), offline: false, clearCachedAt: true);
      await NavPointsCache.save(list);
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
      await _withSpineWriteError(() => _api.insert(
            name: name,
            description: description,
            x: pose['x'] ?? 0.0,
            y: pose['y'] ?? 0.0,
            z: pose['z'] ?? 0.0,
            rotation: pose['rotation'] ?? 0.0,
          ));
      await load();
    } finally {
      if (mounted) state = state.copyWith(capturing: false);
    }
  }

  /// Update a point's name / arrival announcement and reload.
  Future<void> update(String id, {String? name, String? description}) async {
    await _withSpineWriteError(
        () => _api.update(id, name: name, description: description));
    await load();
  }

  /// Delete a saved point and reload.
  Future<void> delete(String id) async {
    await _withSpineWriteError(() => _api.delete(id));
    await load();
  }

  /// Point WRITES (capture/rename/delete) go to Supabase through the spine —
  /// deliberately, since migration 017 (the write credential must not live in
  /// this APK). Offline they fail; translate the raw network error into words
  /// an operator standing at the robot can act on, and make clear that reading
  /// + driving still work.
  Future<T> _withSpineWriteError<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on SocketException {
      throw Exception(
          'Spine server unreachable — saving point changes needs it. '
          'Existing points still work for navigation.');
    } on TimeoutException {
      throw Exception(
          'Spine server not responding — saving point changes needs it. '
          'Existing points still work for navigation.');
    }
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
    // isLive (recent traffic on the socket), not isConnected: a half-open
    // socket after a silent Wi-Fi drop keeps isConnected true, and the old 3s
    // confirmation wait made every offline Go To stall — feeling broken while
    // the native path underneath was fine. With a dead spine we now go native
    // immediately; the short timeout below only covers a live-but-slow spine.
    if (spine.isLive) {
      final confirmed = spine.naviState
          .firstWhere((m) => m['active'] == true)
          .timeout(const Duration(milliseconds: 1500));
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
        debugPrint('goTo: spine unconfirmed in 1.5s — falling back to native');
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
  /// Via spine when live (so all clients see the cancel); native immediately
  /// when the spine is dead — a Cancel must never wait on a broken socket.
  Future<void> cancel() async {
    final spine = _ref.read(navSpineClientProvider);
    if (spine.isLive) {
      final confirmed = spine.naviState
          .firstWhere((m) => m['active'] != true || m['cancelling'] == true)
          .timeout(const Duration(milliseconds: 1500));
      spine.sendIntent({'intent': 'cancel_navi'});
      try {
        await confirmed;
        return; // banner clears on the robot's cancel_result broadcast
      } catch (_) {
        debugPrint('cancel: spine unconfirmed in 1.5s — falling back to native');
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
    // isLive, not isConnected: the escort sequencer runs IN the spine, so a
    // half-open socket would accept the intent into the void and the screen
    // would show a running escort that never moves.
    if (!spine.isLive || route.isEmpty) return false;
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
