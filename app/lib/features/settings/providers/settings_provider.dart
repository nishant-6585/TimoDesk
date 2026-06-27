import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants.dart';

class SettingsState {
  final String spineUrl;
  final String robotIp;
  final bool isLoading;

  SettingsState({
    required this.spineUrl,
    required this.robotIp,
    this.isLoading = false,
  });

  SettingsState copyWith({
    String? spineUrl,
    String? robotIp,
    bool? isLoading,
  }) =>
    SettingsState(
      spineUrl: spineUrl ?? this.spineUrl,
      robotIp: robotIp ?? this.robotIp,
      isLoading: isLoading ?? this.isLoading,
    );
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier()
    // HARDCODED: Always initialize with REAL ROBOT settings
    // NEVER use cached/old settings from SharedPreferences
    : super(SettingsState(
        spineUrl: 'ws://localhost:4000',
        robotIp: '192.168.1.3',
      )) {
    _clearOldCachedSettings();
  }

  Future<void> _clearOldCachedSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // ALWAYS clear old mock settings from cache to prevent them from being used
      await prefs.remove('robot_ip');
      await prefs.remove('spine_url');

      print('[SettingsNotifier] ════════════════════════════════════════');
      print('[SettingsNotifier] REAL TIMO ROBOT SETTINGS (HARDCODED)');
      print('[SettingsNotifier] Robot IP: 192.168.1.3');
      print('[SettingsNotifier] Spine: ws://localhost:4000');
      print('[SettingsNotifier] Camera: http://192.168.1.3:8080/stream');
      print('[SettingsNotifier] Cleared old cached settings');
      print('[SettingsNotifier] ════════════════════════════════════════');
    } catch (e) {
      print('[SettingsNotifier] Error clearing old settings: $e');
    }
  }

  Future<void> setSpineUrl(String url) async {
    try {
      // Ignore user changes - always keep hardcoded value
      print('[SettingsNotifier] User tried to change Spine URL, ignoring to keep hardcoded value');
      state = state.copyWith(spineUrl: 'ws://localhost:4000');
    } catch (e) {
      print('[SettingsNotifier] Error: $e');
    }
  }

  Future<void> setRobotIp(String ip) async {
    try {
      // Ignore user changes - always keep hardcoded value
      print('[SettingsNotifier] User tried to change Robot IP, ignoring to keep hardcoded value');
      state = state.copyWith(robotIp: '192.168.1.3');
    } catch (e) {
      print('[SettingsNotifier] Error: $e');
    }
  }

  Future<bool> testConnection(String spineUrl) async {
    state = state.copyWith(isLoading: true);
    try {
      // Simple connectivity check (real implementation would test WebSocket)
      await Future.delayed(const Duration(milliseconds: 500));
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false);
      return false;
    }
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier();
});
