/// xboom_lead_api.dart — spine HTTP call for showroom order / enquiry capture.
///
/// The face screen's Order and Enquiry FABs collect a visitor's details and
/// POST them to the spine (`/xboom/lead`), which forwards into XBoom Workflow
/// OS's sales pipeline (enquiries table → AI scoring → sales follow-up task).
/// Same auth as the other kiosk calls (RobotConfig.authToken); the robot never
/// holds XBoom credentials.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';

/// What the visitor is asking for. `order` = wants to buy now (hot lead);
/// `enquiry` = wants information / a quote. Both land in XBoom's enquiries
/// pipeline — the kind sets the priority tagging on the spine side.
enum LeadKind { order, enquiry }

class LeadSubmitResult {
  const LeadSubmitResult({required this.ok, this.reference, this.reason});

  final bool ok;

  /// Human-readable reference from XBoom (e.g. an enquiry id) when available.
  final String? reference;
  final String? reason;
}

class XboomLeadApi {
  /// Submit a showroom lead. Never throws — the kiosk form needs a clean
  /// ok/failed answer to show the visitor, not a stack trace.
  Future<LeadSubmitResult> submit({
    required LeadKind kind,
    required String name,
    required String phone,
    required String product,
    String? email,
    int? quantity,
    String? notes,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('${RobotConfig.spineBaseUrl}/xboom/lead'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${RobotConfig.authToken}',
            },
            body: jsonEncode({
              'kind': kind.name,
              'name': name,
              'phone': phone,
              'product': product,
              if (email != null && email.isNotEmpty) 'email': email,
              if (quantity != null) 'quantity': quantity,
              if (notes != null && notes.isNotEmpty) 'notes': notes,
            }),
          )
          .timeout(const Duration(seconds: 12));
      final body = res.body.isEmpty
          ? const <String, dynamic>{}
          : jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && body['ok'] == true) {
        return LeadSubmitResult(
          ok: true,
          reference: body['reference'] as String?,
        );
      }
      return LeadSubmitResult(
        ok: false,
        reason: (body['reason'] as String?) ?? 'HTTP ${res.statusCode}',
      );
    } catch (e) {
      return LeadSubmitResult(ok: false, reason: e.toString());
    }
  }
}
