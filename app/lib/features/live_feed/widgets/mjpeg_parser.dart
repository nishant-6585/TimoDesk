import 'dart:typed_data';

/// Pulls every complete JPEG frame out of [buffer] and removes the consumed
/// bytes. A frame runs from its SOI marker (FF D8) to its EOI marker (FF D9) —
/// slicing on these is the most robust way to decode an MJPEG / CSJBot stream,
/// since it needs no multipart-boundary parsing. Mutates [buffer] in place.
List<Uint8List> takeJpegFrames(List<int> buffer) {
  final frames = <Uint8List>[];
  while (true) {
    final start = _marker(buffer, 0xD8, 0);
    if (start < 0) {
      // No frame start yet — cap the buffer so junk can't grow unbounded.
      if (buffer.length > 1 << 20) buffer.clear();
      break;
    }
    final end = _marker(buffer, 0xD9, start + 2);
    if (end < 0) {
      // Frame not finished; drop anything before its start.
      if (start > 0) buffer.removeRange(0, start);
      break;
    }
    frames.add(Uint8List.fromList(buffer.sublist(start, end + 2)));
    buffer.removeRange(0, end + 2);
  }
  return frames;
}

/// Index of an `FF <marker>` byte pair at/after [from], else -1.
int _marker(List<int> b, int marker, int from) {
  for (int i = from; i < b.length - 1; i++) {
    if (b[i] == 0xFF && b[i + 1] == marker) return i;
  }
  return -1;
}
