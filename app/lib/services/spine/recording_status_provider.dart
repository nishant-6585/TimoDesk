import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../core/spine_base.dart';

/// Global recording state — the ffmpeg recorder lives on spine, so a recording
/// keeps running across UI navigation. Every screen reads THIS (kept in sync by
/// the `recording_state` WS broadcast + an initial /record/status fetch), so
/// returning to Dashboard/Control shows the live status and a Stop control.
class RecordingState {
  final bool active;
  final String? file;
  final int? startedAt; // epoch ms
  final int? maxMs; // auto-stop cap

  const RecordingState({
    this.active = false,
    this.file,
    this.startedAt,
    this.maxMs,
  });

  /// Seconds elapsed since the recording started (0 when idle).
  int get elapsedSeconds => (active && startedAt != null)
      ? ((DateTime.now().millisecondsSinceEpoch - startedAt!) / 1000).round()
      : 0;
}

class RecordingNotifier extends StateNotifier<RecordingState> {
  RecordingNotifier() : super(const RecordingState()) {
    _fetchInitial();
  }

  Future<void> _fetchInitial() async {
    try {
      final res = await http
          .get(Uri.parse('$spineHttpBase/record/status'))
          .timeout(const Duration(seconds: 6));
      final m = jsonDecode(res.body) as Map<String, dynamic>;
      if (m['ok'] == true) {
        sync(
          m['recording'] == true,
          file: m['file'] as String?,
          startedAt: (m['startedAt'] as num?)?.toInt(),
          maxMs: (m['maxMs'] as num?)?.toInt(),
        );
      }
    } catch (_) {
      // spine unreachable — leave idle; the WS broadcast will correct it.
    }
  }

  /// Apply a spine recording_state broadcast (or the initial fetch).
  void sync(bool active, {String? file, int? startedAt, int? maxMs}) {
    state = RecordingState(
      active: active,
      file: active ? file : null,
      startedAt: active ? startedAt : null,
      maxMs: maxMs ?? state.maxMs,
    );
  }

  /// Fire-and-forget start/stop via spine HTTP. The WS broadcast flips [state].
  Future<void> start() async {
    try {
      await http
          .post(Uri.parse('$spineHttpBase/record/start'))
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await http
          .post(Uri.parse('$spineHttpBase/record/stop'))
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
  }
}

final recordingProvider =
    StateNotifierProvider<RecordingNotifier, RecordingState>(
        (ref) => RecordingNotifier());
