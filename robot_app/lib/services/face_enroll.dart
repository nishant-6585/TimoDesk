import 'package:flutter/services.dart';

/// On-robot face enrollment, bridged by [FaceSavePlugin] over the
/// "com.mikee/face_save" MethodChannel.
///
/// WHY there's no Supabase sync here: the CSJBot SDK can only register a face
/// from the robot's OWN live camera (`saveFace(name, listener)` — no Bitmap/JPEG
/// overload exists), so staff photos held in Supabase cannot seed the SDK's
/// on-device face DB. Enrollment is therefore a deliberate on-robot action: stand
/// the staff member in front of the camera and call [saveFace] with their name.
/// Once enrolled, [FaceRecognition] fires `recognized` with that name on sight.
///
/// Off the real robot the native side replies `false` (SDK absent).
class FaceEnroll {
  FaceEnroll._();

  static const MethodChannel _ch = MethodChannel('com.mikee/face_save');

  /// Capture the face currently in front of the robot camera and register it
  /// under [name]. Returns true if the SDK reported a successful save. May take a
  /// few seconds (the SDK waits for a face to be framed) and times out to false.
  static Future<bool> saveFace(String name) async {
    try {
      final ok = await _ch.invokeMethod<bool>('saveface', {'name': name});
      return ok ?? false;
    } catch (_) {
      return false; // SDK absent / channel not wired (e.g. emulator)
    }
  }
}
