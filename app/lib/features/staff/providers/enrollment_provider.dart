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
      if (imageBytes.isEmpty) {
        return FaceCheckResult(match: false);
      }

      final session = Supabase.instance.client.auth.currentSession;
      final token = session?.accessToken ?? (throw Exception('Not authenticated'));

      String imageBase64;
      try {
        imageBase64 = base64Encode(imageBytes);
      } on FormatException catch (e) {
        throw Exception('Failed to encode image: $e');
      }

      final response = await http
          .post(
            Uri.parse('http://localhost:4000/check-face'),
            headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
            body: jsonEncode({'image_base64': imageBase64}),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('HTTP ${response.statusCode}');
      }

      Map<String, dynamic> data;
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (e) {
        throw Exception('Invalid JSON: $e');
      }

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
    bool setThumbnail = false, // True → use this photo as the gallery thumbnail
    Map<String, dynamic>? deskPose, // Optional {x,y,z,rotation} — the person's desk (#71)
  }) async {
    // Get JWT token from Supabase session
    final session = Supabase.instance.client.auth.currentSession;
    final token = session?.accessToken ?? (throw Exception('Not authenticated'));

    // Validate and encode image
    if (imageBytes.isEmpty) {
      throw Exception('Image bytes cannot be empty');
    }

    String imageBase64;
    try {
      imageBase64 = base64Encode(imageBytes);
    } on FormatException catch (e) {
      throw Exception('Failed to encode image: $e');
    }

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
        'set_thumbnail': setThumbnail,
        if (deskPose != null) 'desk_pose': deskPose,
      }),
    ).timeout(const Duration(seconds: 30));

    // Check HTTP status
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}');
    }

    // Parse response
    Map<String, dynamic> responseData;
    try {
      responseData = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Invalid JSON: $e');
    }

    final result = EnrollmentResponse(
      ok: responseData['ok'] as bool? ?? false,
      staffId: responseData['staff_id'] as String?,
      embeddingId: responseData['embeddingId'] as String?,
      facesFound: responseData['facesFound'] as int?,
      reason: responseData['reason'] as String?,
    );

    return result;
  }
}
