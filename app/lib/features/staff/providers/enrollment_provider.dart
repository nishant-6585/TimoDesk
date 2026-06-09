import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/staff_enroll_model.dart';

final enrollmentProvider = StateNotifierProvider<EnrollmentNotifier, AsyncValue<EnrollmentResponse?>>((ref) {
  return EnrollmentNotifier();
});

class EnrollmentNotifier extends StateNotifier<AsyncValue<EnrollmentResponse?>> {
  EnrollmentNotifier() : super(const AsyncValue.data(null));

  Future<EnrollmentResponse> enrollStaff({
    required String fullName,
    required String role,
    required String notifyChannel,
    required String consentRef,
    required List<int> imageBytes, // Raw JPEG/PNG bytes
  }) async {
    try {
      state = const AsyncValue.loading();

      // Get JWT token from Supabase session
      final session = Supabase.instance.client.auth.currentSession;
      final token = session?.accessToken;

      if (token == null) {
        throw Exception('Not authenticated');
      }

      // Base64 encode image
      final imageBase64 = base64Encode(imageBytes);

      // Build request
      final request = StaffEnrollmentRequest(
        fullName: fullName,
        role: role,
        notifyChannel: notifyChannel,
        consent: true, // Always true when calling this
        consentRef: consentRef,
        imageBase64: imageBase64,
      );

      // POST to Spine /enroll endpoint
      final spineUrl = 'http://localhost:4000/enroll';
      final response = await http.post(
        Uri.parse(spineUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'full_name': request.fullName,
          'role': request.role,
          'notify_channel': request.notifyChannel,
          'consent': request.consent,
          'consent_ref': request.consentRef,
          'image_base64': request.imageBase64,
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

      state = AsyncValue.data(result);
      return result;
    } catch (err) {
      final error = err is Exception ? err : Exception(err.toString());
      state = AsyncValue.error(error, StackTrace.current);
      rethrow;
    }
  }
}
