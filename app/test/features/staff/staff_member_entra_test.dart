import 'package:flutter_test/flutter_test.dart';
import 'package:mikee_admin/features/staff/providers/staff_list_provider.dart';

/// The Entra chips on the staff list are driven entirely by these two fields,
/// which arrive from the spine's `GET /staff` select (migrations 016 + 019).
void main() {
  Map<String, dynamic> row(Map<String, dynamic> extra) => {
        'id': 'aaaaaaaa-0000-0000-0000-000000000001',
        'full_name': 'Test Person',
        'person_type': 'Employee',
        'active': true,
        ...extra,
      };

  test('manually enrolled staff (no entra columns set) is not from Entra', () {
    final m = StaffMember.fromJson(row({}));
    expect(m.entraId, isNull);
    expect(m.entraPhotoStatus, isNull);
    expect(m.fromEntra, isFalse);
  });

  test('an empty entra_id does not count as directory-sourced', () {
    final m = StaffMember.fromJson(row({'entra_id': ''}));
    expect(m.fromEntra, isFalse);
  });

  test('parses entra_id and entra_photo_status from a synced row', () {
    final m = StaffMember.fromJson(row({
      'entra_id': '8f4b1c22-1111-2222-3333-444455556666',
      'entra_photo_status': 'collision',
      'entra_synced_at': '2026-08-13T12:00:00.000Z',
    }));
    expect(m.fromEntra, isTrue);
    expect(m.entraPhotoStatus, 'collision');
  });

  test('every status the spine writes survives the round trip', () {
    // Mirrors the enum documented in migration 019 and written by
    // spine/src/services/entra-photos.ts.
    const statuses = [
      'ok',
      'none',
      'no_consent',
      'rejected_quality',
      'rejected_multi_face',
      'collision',
      'error',
      'purged',
    ];
    for (final s in statuses) {
      final m = StaffMember.fromJson(row({'entra_id': 'x', 'entra_photo_status': s}));
      expect(m.entraPhotoStatus, s, reason: 'status $s must parse');
      expect(m.fromEntra, isTrue);
    }
  });
}
