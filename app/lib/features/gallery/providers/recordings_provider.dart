import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../../core/spine_base.dart';

/// A recorded video clip listed by spine (ffmpeg over the MJPEG stream, saved
/// to spine/recordings/). Playback streams from spine with HTTP Range support.
class Recording {
  final String file;
  final int size;
  final double mtime; // epoch ms

  Recording({required this.file, required this.size, required this.mtime});

  /// Direct stream/play URL on the spine (the browser plays it natively).
  String get url => '$spineHttpBase/recordings/$file';

  String get sizeLabel {
    if (size >= 1 << 20) return '${(size / (1 << 20)).toStringAsFixed(1)} MB';
    if (size >= 1 << 10) return '${(size / (1 << 10)).toStringAsFixed(0)} KB';
    return '$size B';
  }

  factory Recording.fromJson(Map<String, dynamic> j) => Recording(
        file: j['file'] as String,
        size: (j['size'] as num?)?.toInt() ?? 0,
        mtime: (j['mtime'] as num?)?.toDouble() ?? 0,
      );
}

final recordingsProvider =
    FutureProvider.autoDispose<List<Recording>>((ref) async {
  final res = await http
      .get(Uri.parse('$spineHttpBase/recordings'))
      .timeout(const Duration(seconds: 12));
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  if (data['ok'] != true) throw Exception(data['reason'] ?? 'failed to list');
  return (data['recordings'] as List)
      .map((e) => Recording.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Delete a recorded clip file on spine.
Future<void> deleteRecording(String file) async {
  final res = await http
      .delete(Uri.parse('$spineHttpBase/recordings/$file'))
      .timeout(const Duration(seconds: 12));
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  if (data['ok'] != true) throw Exception(data['reason'] ?? 'delete failed');
}
