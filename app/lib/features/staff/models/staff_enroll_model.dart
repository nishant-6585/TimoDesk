import 'package:freezed_annotation/freezed_annotation.dart';

part 'staff_enroll_model.freezed.dart';

@freezed
class StaffEnrollmentRequest with _$StaffEnrollmentRequest {
  const factory StaffEnrollmentRequest({
    required String fullName,
    required String role,
    required String notifyChannel,
    required bool consent,
    required String consentRef,
    required String imageBase64, // JPEG/PNG base64
  }) = _StaffEnrollmentRequest;
}

@freezed
class EnrollmentResponse with _$EnrollmentResponse {
  const factory EnrollmentResponse({
    required bool ok,
    String? staffId,
    String? embeddingId,
    int? facesFound,
    String? reason,
  }) = _EnrollmentResponse;
}

@freezed
class PhotoEnrollmentProgress with _$PhotoEnrollmentProgress {
  const factory PhotoEnrollmentProgress({
    required int photoIndex, // 0-based
    required int totalPhotos,
    required bool enrolled,
    String? error,
    String? embeddingId,
  }) = _PhotoEnrollmentProgress;
}
