import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'spine_service.dart';
import 'spine_state.dart';

// Singleton provider for SpineService
// This is created once and reused for the entire app lifetime
final spineProvider = StateNotifierProvider<SpineService, SpineState>((ref) {
  return SpineService(ref);
});
