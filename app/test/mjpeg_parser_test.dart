import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikee_admin/features/live_feed/widgets/mjpeg_parser.dart';

void main() {
  group('takeJpegFrames', () {
    test('extracts a single complete JPEG frame and empties the buffer', () {
      final buffer = <int>[0xFF, 0xD8, 1, 2, 3, 0xFF, 0xD9];
      final frames = takeJpegFrames(buffer);

      expect(frames.length, 1);
      expect(frames.first, Uint8List.fromList([0xFF, 0xD8, 1, 2, 3, 0xFF, 0xD9]));
      expect(buffer, isEmpty);
    });

    test('leaves an incomplete trailing frame in the buffer (failure mode)', () {
      final buffer = <int>[0xFF, 0xD8, 9, 9]; // SOI but no EOI yet
      final frames = takeJpegFrames(buffer);

      expect(frames, isEmpty);
      expect(buffer, [0xFF, 0xD8, 9, 9]); // preserved for the next chunk
    });

    test('discards leading junk before the SOI marker', () {
      final buffer = <int>[0x00, 0x11, 0xFF, 0xD8, 5, 0xFF, 0xD9, 0xFF, 0xD8, 7];
      final frames = takeJpegFrames(buffer);

      expect(frames.length, 1);
      expect(frames.first, Uint8List.fromList([0xFF, 0xD8, 5, 0xFF, 0xD9]));
      // Only the start of the next (incomplete) frame remains.
      expect(buffer, [0xFF, 0xD8, 7]);
    });

    test('extracts multiple frames delivered in one chunk', () {
      final buffer = <int>[
        0xFF, 0xD8, 1, 0xFF, 0xD9, //
        0xFF, 0xD8, 2, 0xFF, 0xD9,
      ];
      final frames = takeJpegFrames(buffer);

      expect(frames.length, 2);
      expect(frames[0], Uint8List.fromList([0xFF, 0xD8, 1, 0xFF, 0xD9]));
      expect(frames[1], Uint8List.fromList([0xFF, 0xD8, 2, 0xFF, 0xD9]));
      expect(buffer, isEmpty);
    });
  });
}
