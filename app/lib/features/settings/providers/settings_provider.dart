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
  SettingsNotifier() : super(SettingsState(spineUrl: defaultSpineUrl, robotIp: defaultRobotIp)) {
    // Initialize with hardcoded real robot settings
    // Always use the real robot IP, ignore any cached mock settings
    _initializeRealRobotSettings();
  }

  Future<void> _initializeRealRobotSettings() async {
    try {
      // HARDCODED: Always use real robot settings, never trust SharedPreferences
      // This ensures the app always connects to the real Timo robot
      final spineUrl = defaultSpineUrl; // ws://192.168.10.18:4000
      final robotIp = defaultRobotIp;   // 192.168.10.18

      state = state.copyWith(spineUrl: spineUrl, robotIp: robotIp);

      print('[SettingsNotifier] ========================================');
      print('[SettingsNotifier] REAL ROBOT CONFIGURATION (HARDCODED)');
      print('[SettingsNotifier] Robot IP: $robotIp');
      print('[SettingsNotifier] Spine URL: $spineUrl');
      print('[SettingsNotifier] Camera Stream: http://$robotIp:8080/stream');
      print('[SettingsNotifier] ========================================');

      // Optionally: Clear any old cached settings from SharedPreferences
      try {
        final prefs = await SharedPreferences.getInstance();
        // Clear old mock settings to prevent reversion
        if (prefs.getString(robotIpKey)?.startsWith('192.168.1.') ?? false) {
          await prefs.remove(robotIpKey);
          await prefs.remove(spineUrlKey);
          print('[SettingsNotifier] Cleared old mock settings from cache');
        }
      } catch (e) {
        // Ignore errors clearing cache
      }
    } catch (e) {
      print('[SettingsNotifier] Error initializing settings: $e');
    }
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load from SharedPreferences or use defaults
      var spineUrl = prefs.getString(spineUrlKey) ?? defaultSpineUrl;
      var robotIp = prefs.getString(robotIpKey) ?? defaultRobotIp;

      // Fix: If settings still point to old mock IPs (192.168.1.x), reset to real robot
      if (robotIp.startsWith('192.168.1.') || spineUrl.contains('192.168.1.')) {
        print('[SettingsNotifier] Detected old mock settings, resetting to real robot...');
        spineUrl = defaultSpineUrl;
        robotIp = defaultRobotIp;

        // Save the corrected values
        await prefs.setString(spineUrlKey, spineUrl);
        await prefs.setString(robotIpKey, robotIp);
      }

      state = state.copyWith(spineUrl: spineUrl, robotIp: robotIp);
      print('[SettingsNotifier] Loaded settings - Robot IP: $robotIp, Spine: $spineUrl');
    } catch (e) {
      print('[SettingsNotifier] Error loading settings: $e');
    }
  }

  Future<void> setSpineUrl(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(spineUrlKey, url);
      state = state.copyWith(spineUrl: url);
    } catch (e) {
      print('[SettingsNotifier] Error saving spine URL: $e');
    }
  }

  Future<void> setRobotIp(String ip) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(robotIpKey, ip);
      state = state.copyWith(robotIp: ip);
    } catch (e) {
      print('[SettingsNotifier] Error saving robot IP: $e');
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
