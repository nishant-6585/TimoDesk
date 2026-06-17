import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/staff_enroll_model.dart';

final enrollmentProvider = StateNotifierProvider<EnrollmentNotifier, AsyncValue<EnrollmentResponse?>>((ref) {
  return EnrollmentNotifier();
});

/// Result of the pre-enrollment duplicate check.
class FaceCheckResult {
  final bool match;
  final String? name;
  final double? distance;
  FaceCheckResult({required this.match, this.name, this.distance});
}

class EnrollmentNotifier extends StateNotifier<AsyncValue<EnrollmentResponse?>> {
  EnrollmentNotifier() : super(const AsyncValue.data(null));

  /// Ask spine whether this face already belongs to an enrolled person.
  /// Fails OPEN (returns no-match) on any error so a flaky check never blocks
  /// a legitimate enrollment.
  Future<FaceCheckResult> checkFace(List<int> imageBytes) async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      final token = session?.accessToken ?? 'test-token';
      final response = await http
          .post(
            Uri.parse('http://localhost:4000/check-face'),
            headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
            body: jsonEncode({'image_base64': base64Encode(imageBytes)}),
          )
          .timeout(const Duration(seconds: 20));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['ok'] != true) return FaceCheckResult(match: false);
      return FaceCheckResult(
        match: data['match'] == true,
        name: data['name'] as String?,
        distance: (data['distance'] as num?)?.toDouble(),
      );
    } catch (_) {
      return FaceCheckResult(match: false);
    }
  }

  Future<EnrollmentResponse> enrollOnePhoto({
    required String fullName,
    required String role,
    required String notifyChannel,
    required String consentRef,
    required List<int> imageBytes, // Raw JPEG/PNG bytes
    String? phone,
    String? personType,
  }) async {
    // Get JWT token from Supabase session (or use empty for testing)
    final session = Supabase.instance.client.auth.currentSession;
    final token = session?.accessToken ?? 'test-token'; // Use test token if no session

    // Base64 encode image
    final imageBase64 = base64Encode(imageBytes);

    // POST to Spine /enroll endpoint (one photo at a time)
    final spineUrl = 'http://localhost:4000/enroll';
    final response = await http.post(
      Uri.parse(spineUrl),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'full_name': fullName,
        'role': role,
        'notify_channel': notifyChannel,
        'consent': true, // Always true
        'consent_ref': consentRef,
        'image_base64': imageBase64,
        'phone': phone,
        'person_type': personType ?? 'Employee',
      }),
    ).timeout(const Duration(seconds: 30));

    // Parse response
    final responseData = jsonDecode(response.body);

    final result = EnrollmentResponse(
      ok: responseData['ok'] ?? false,
      staffId: responseData['staff_id'],
      embeddingId: responseData['embeddingId'],
      facesFound: responseData['facesFound'],
      reason: responseData['reason'],
    );

    return result;
  }
}
