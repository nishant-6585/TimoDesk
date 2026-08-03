/// checkin_api.dart — spine HTTP calls for voice visitor check-in.
///
/// GET /staff to resolve the spoken host name, POST /visit to record the
/// visit + notify the host (spine #70 path: Slack/WhatsApp/email + admin
/// broadcast). Same auth as the other kiosk calls (RobotConfig.authToken).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'checkin_voice.dart' show StaffMember;

class CheckinApi {
  /// Active staff, for host matching. Throws on transport/HTTP errors so the
  /// caller can speak an honest "can't reach reception system" line.
  Future<List<StaffMember>> fetchStaff() async {
    final res = await http.get(
      Uri.parse('${RobotConfig.spineBaseUrl}/staff'),
      headers: {'Authorization': 'Bearer ${RobotConfig.authToken}'},
    ).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) {
      throw Exception('GET /staff → ${res.statusCode}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final rows = (body['staff'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .where((r) => r['active'] != false)
        .map(StaffMember.fromJson)
        .toList();
    return rows;
  }

  /// Check the visitor in. Returns true when the visit was recorded (the
  /// notification itself may still fail server-side; spine logs the visit
  /// first either way).
  Future<bool> postVisit({
    required String visitorName,
    required String hostStaffId,
    String? company,
    String? purpose,
  }) async {
    final res = await http
        .post(
          Uri.parse('${RobotConfig.spineBaseUrl}/visit'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${RobotConfig.authToken}',
          },
          body: jsonEncode({
            'visitor_name': visitorName,
            'host_staff_id': hostStaffId,
            // Omitted entirely when the visitor skipped them — the spine treats
            // absent and empty alike, but sending nothing keeps the log clean.
            if (company != null && company.isNotEmpty) 'company': company,
            if (purpose != null && purpose.isNotEmpty) 'purpose': purpose,
          }),
        )
        .timeout(const Duration(seconds: 10));
    return res.statusCode == 200;
  }
}
