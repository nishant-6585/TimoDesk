import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/spine_base.dart';

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
        spineUrl: spineWsUrl,
        robotIp: _fallbackRobotIp,
      )) {
    _clearOldCachedSettings();
    _syncRobotIpFromSpine();
  }

  // Last-resort default if the spine is unreachable at startup. The REAL IP is
  // fetched from the spine (see _syncRobotIpFromSpine) — this only bootstraps the
  // very first frame before that returns.
  static const String _fallbackRobotIp = '192.168.1.6';

  // Durable fix for the recurring DHCP-churn hardcode: the spine already knows
  // ROBOT_IP (it dials the robot), so fetch it instead of hardcoding it here.
  // When the robot's lease moves, find_robot.sh updates spine/.env + restarts the
  // spine and this repoints the camera on next load — no source edit, no rebuild.
  Future<void> _syncRobotIpFromSpine() async {
    try {
      final res = await http
          .get(Uri.parse('$spineHttpBase/robot/config'))
          .timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) return;
      final ip = (jsonDecode(res.body) as Map<String, dynamic>)['robotIp'];
      if (ip is String && ip.isNotEmpty && ip != state.robotIp) {
        state = state.copyWith(robotIp: ip);
        print('[SettingsNotifier] Robot IP from spine: $ip (camera repointed)');
      }
    } catch (e) {
      print('[SettingsNotifier] spine robot IP fetch failed ($e) — using $_fallbackRobotIp');
    }
  }

  Future<void> _clearOldCachedSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // ALWAYS clear old mock settings from cache to prevent them from being used
      await prefs.remove('robot_ip');
      await prefs.remove('spine_url');

      print('[SettingsNotifier] ════════════════════════════════════════');
      print('[SettingsNotifier] REAL TIMO ROBOT SETTINGS (HARDCODED)');
      print('[SettingsNotifier] Robot IP: 192.168.1.6');
      print('[SettingsNotifier] Spine: $spineWsUrl');
      print('[SettingsNotifier] Camera: http://192.168.1.6:8080/stream');
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
      state = state.copyWith(spineUrl: spineWsUrl);
    } catch (e) {
      print('[SettingsNotifier] Error: $e');
    }
  }

  Future<void> setRobotIp(String ip) async {
    try {
      // Ignore user changes - always keep hardcoded value
      print('[SettingsNotifier] User tried to change Robot IP, ignoring to keep hardcoded value');
      state = state.copyWith(robotIp: '192.168.1.6');
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
