// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'staff_enroll_model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$StaffEnrollmentRequest {
  String get fullName => throw _privateConstructorUsedError;
  String get role => throw _privateConstructorUsedError;
  String get notifyChannel => throw _privateConstructorUsedError;
  bool get consent => throw _privateConstructorUsedError;
  String get consentRef => throw _privateConstructorUsedError;
  String get imageBase64 => throw _privateConstructorUsedError;

  /// Create a copy of StaffEnrollmentRequest
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $StaffEnrollmentRequestCopyWith<StaffEnrollmentRequest> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $StaffEnrollmentRequestCopyWith<$Res> {
  factory $StaffEnrollmentRequestCopyWith(StaffEnrollmentRequest value,
          $Res Function(StaffEnrollmentRequest) then) =
      _$StaffEnrollmentRequestCopyWithImpl<$Res, StaffEnrollmentRequest>;
  @useResult
  $Res call(
      {String fullName,
      String role,
      String notifyChannel,
      bool consent,
      String consentRef,
      String imageBase64});
}

/// @nodoc
class _$StaffEnrollmentRequestCopyWithImpl<$Res,
        $Val extends StaffEnrollmentRequest>
    implements $StaffEnrollmentRequestCopyWith<$Res> {
  _$StaffEnrollmentRequestCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of StaffEnrollmentRequest
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? fullName = null,
    Object? role = null,
    Object? notifyChannel = null,
    Object? consent = null,
    Object? consentRef = null,
    Object? imageBase64 = null,
  }) {
    return _then(_value.copyWith(
      fullName: null == fullName
          ? _value.fullName
          : fullName // ignore: cast_nullable_to_non_nullable
              as String,
      role: null == role
          ? _value.role
          : role // ignore: cast_nullable_to_non_nullable
              as String,
      notifyChannel: null == notifyChannel
          ? _value.notifyChannel
          : notifyChannel // ignore: cast_nullable_to_non_nullable
              as String,
      consent: null == consent
          ? _value.consent
          : consent // ignore: cast_nullable_to_non_nullable
              as bool,
      consentRef: null == consentRef
          ? _value.consentRef
          : consentRef // ignore: cast_nullable_to_non_nullable
              as String,
      imageBase64: null == imageBase64
          ? _value.imageBase64
          : imageBase64 // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$StaffEnrollmentRequestImplCopyWith<$Res>
    implements $StaffEnrollmentRequestCopyWith<$Res> {
  factory _$$StaffEnrollmentRequestImplCopyWith(
          _$StaffEnrollmentRequestImpl value,
          $Res Function(_$StaffEnrollmentRequestImpl) then) =
      __$$StaffEnrollmentRequestImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String fullName,
      String role,
      String notifyChannel,
      bool consent,
      String consentRef,
      String imageBase64});
}

/// @nodoc
class __$$StaffEnrollmentRequestImplCopyWithImpl<$Res>
    extends _$StaffEnrollmentRequestCopyWithImpl<$Res,
        _$StaffEnrollmentRequestImpl>
    implements _$$StaffEnrollmentRequestImplCopyWith<$Res> {
  __$$StaffEnrollmentRequestImplCopyWithImpl(
      _$StaffEnrollmentRequestImpl _value,
      $Res Function(_$StaffEnrollmentRequestImpl) _then)
      : super(_value, _then);

  /// Create a copy of StaffEnrollmentRequest
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? fullName = null,
    Object? role = null,
    Object? notifyChannel = null,
    Object? consent = null,
    Object? consentRef = null,
    Object? imageBase64 = null,
  }) {
    return _then(_$StaffEnrollmentRequestImpl(
      fullName: null == fullName
          ? _value.fullName
          : fullName // ignore: cast_nullable_to_non_nullable
              as String,
      role: null == role
          ? _value.role
          : role // ignore: cast_nullable_to_non_nullable
              as String,
      notifyChannel: null == notifyChannel
          ? _value.notifyChannel
          : notifyChannel // ignore: cast_nullable_to_non_nullable
              as String,
      consent: null == consent
          ? _value.consent
          : consent // ignore: cast_nullable_to_non_nullable
              as bool,
      consentRef: null == consentRef
          ? _value.consentRef
          : consentRef // ignore: cast_nullable_to_non_nullable
              as String,
      imageBase64: null == imageBase64
          ? _value.imageBase64
          : imageBase64 // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class _$StaffEnrollmentRequestImpl implements _StaffEnrollmentRequest {
  const _$StaffEnrollmentRequestImpl(
      {required this.fullName,
      required this.role,
      required this.notifyChannel,
      required this.consent,
      required this.consentRef,
      required this.imageBase64});

  @override
  final String fullName;
  @override
  final String role;
  @override
  final String notifyChannel;
  @override
  final bool consent;
  @override
  final String consentRef;
  @override
  final String imageBase64;

  @override
  String toString() {
    return 'StaffEnrollmentRequest(fullName: $fullName, role: $role, notifyChannel: $notifyChannel, consent: $consent, consentRef: $consentRef, imageBase64: $imageBase64)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$StaffEnrollmentRequestImpl &&
            (identical(other.fullName, fullName) ||
                other.fullName == fullName) &&
            (identical(other.role, role) || other.role == role) &&
            (identical(other.notifyChannel, notifyChannel) ||
                other.notifyChannel == notifyChannel) &&
            (identical(other.consent, consent) || other.consent == consent) &&
            (identical(other.consentRef, consentRef) ||
                other.consentRef == consentRef) &&
            (identical(other.imageBase64, imageBase64) ||
                other.imageBase64 == imageBase64));
  }

  @override
  int get hashCode => Object.hash(runtimeType, fullName, role, notifyChannel,
      consent, consentRef, imageBase64);

  /// Create a copy of StaffEnrollmentRequest
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$StaffEnrollmentRequestImplCopyWith<_$StaffEnrollmentRequestImpl>
      get copyWith => __$$StaffEnrollmentRequestImplCopyWithImpl<
          _$StaffEnrollmentRequestImpl>(this, _$identity);
}

abstract class _StaffEnrollmentRequest implements StaffEnrollmentRequest {
  const factory _StaffEnrollmentRequest(
      {required final String fullName,
      required final String role,
      required final String notifyChannel,
      required final bool consent,
      required final String consentRef,
      required final String imageBase64}) = _$StaffEnrollmentRequestImpl;

  @override
  String get fullName;
  @override
  String get role;
  @override
  String get notifyChannel;
  @override
  bool get consent;
  @override
  String get consentRef;
  @override
  String get imageBase64;

  /// Create a copy of StaffEnrollmentRequest
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$StaffEnrollmentRequestImplCopyWith<_$StaffEnrollmentRequestImpl>
      get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$EnrollmentResponse {
  bool get ok => throw _privateConstructorUsedError;
  String? get staffId => throw _privateConstructorUsedError;
  String? get embeddingId => throw _privateConstructorUsedError;
  int? get facesFound => throw _privateConstructorUsedError;
  String? get reason => throw _privateConstructorUsedError;

  /// Create a copy of EnrollmentResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $EnrollmentResponseCopyWith<EnrollmentResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $EnrollmentResponseCopyWith<$Res> {
  factory $EnrollmentResponseCopyWith(
          EnrollmentResponse value, $Res Function(EnrollmentResponse) then) =
      _$EnrollmentResponseCopyWithImpl<$Res, EnrollmentResponse>;
  @useResult
  $Res call(
      {bool ok,
      String? staffId,
      String? embeddingId,
      int? facesFound,
      String? reason});
}

/// @nodoc
class _$EnrollmentResponseCopyWithImpl<$Res, $Val extends EnrollmentResponse>
    implements $EnrollmentResponseCopyWith<$Res> {
  _$EnrollmentResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of EnrollmentResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? ok = null,
    Object? staffId = freezed,
    Object? embeddingId = freezed,
    Object? facesFound = freezed,
    Object? reason = freezed,
  }) {
    return _then(_value.copyWith(
      ok: null == ok
          ? _value.ok
          : ok // ignore: cast_nullable_to_non_nullable
              as bool,
      staffId: freezed == staffId
          ? _value.staffId
          : staffId // ignore: cast_nullable_to_non_nullable
              as String?,
      embeddingId: freezed == embeddingId
          ? _value.embeddingId
          : embeddingId // ignore: cast_nullable_to_non_nullable
              as String?,
      facesFound: freezed == facesFound
          ? _value.facesFound
          : facesFound // ignore: cast_nullable_to_non_nullable
              as int?,
      reason: freezed == reason
          ? _value.reason
          : reason // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$EnrollmentResponseImplCopyWith<$Res>
    implements $EnrollmentResponseCopyWith<$Res> {
  factory _$$EnrollmentResponseImplCopyWith(_$EnrollmentResponseImpl value,
          $Res Function(_$EnrollmentResponseImpl) then) =
      __$$EnrollmentResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {bool ok,
      String? staffId,
      String? embeddingId,
      int? facesFound,
      String? reason});
}

/// @nodoc
class __$$EnrollmentResponseImplCopyWithImpl<$Res>
    extends _$EnrollmentResponseCopyWithImpl<$Res, _$EnrollmentResponseImpl>
    implements _$$EnrollmentResponseImplCopyWith<$Res> {
  __$$EnrollmentResponseImplCopyWithImpl(_$EnrollmentResponseImpl _value,
      $Res Function(_$EnrollmentResponseImpl) _then)
      : super(_value, _then);

  /// Create a copy of EnrollmentResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? ok = null,
    Object? staffId = freezed,
    Object? embeddingId = freezed,
    Object? facesFound = freezed,
    Object? reason = freezed,
  }) {
    return _then(_$EnrollmentResponseImpl(
      ok: null == ok
          ? _value.ok
          : ok // ignore: cast_nullable_to_non_nullable
              as bool,
      staffId: freezed == staffId
          ? _value.staffId
          : staffId // ignore: cast_nullable_to_non_nullable
              as String?,
      embeddingId: freezed == embeddingId
          ? _value.embeddingId
          : embeddingId // ignore: cast_nullable_to_non_nullable
              as String?,
      facesFound: freezed == facesFound
          ? _value.facesFound
          : facesFound // ignore: cast_nullable_to_non_nullable
              as int?,
      reason: freezed == reason
          ? _value.reason
          : reason // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc

class _$EnrollmentResponseImpl implements _EnrollmentResponse {
  const _$EnrollmentResponseImpl(
      {required this.ok,
      this.staffId,
      this.embeddingId,
      this.facesFound,
      this.reason});

  @override
  final bool ok;
  @override
  final String? staffId;
  @override
  final String? embeddingId;
  @override
  final int? facesFound;
  @override
  final String? reason;

  @override
  String toString() {
    return 'EnrollmentResponse(ok: $ok, staffId: $staffId, embeddingId: $embeddingId, facesFound: $facesFound, reason: $reason)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$EnrollmentResponseImpl &&
            (identical(other.ok, ok) || other.ok == ok) &&
            (identical(other.staffId, staffId) || other.staffId == staffId) &&
            (identical(other.embeddingId, embeddingId) ||
                other.embeddingId == embeddingId) &&
            (identical(other.facesFound, facesFound) ||
                other.facesFound == facesFound) &&
            (identical(other.reason, reason) || other.reason == reason));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, ok, staffId, embeddingId, facesFound, reason);

  /// Create a copy of EnrollmentResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$EnrollmentResponseImplCopyWith<_$EnrollmentResponseImpl> get copyWith =>
      __$$EnrollmentResponseImplCopyWithImpl<_$EnrollmentResponseImpl>(
          this, _$identity);
}

abstract class _EnrollmentResponse implements EnrollmentResponse {
  const factory _EnrollmentResponse(
      {required final bool ok,
      final String? staffId,
      final String? embeddingId,
      final int? facesFound,
      final String? reason}) = _$EnrollmentResponseImpl;

  @override
  bool get ok;
  @override
  String? get staffId;
  @override
  String? get embeddingId;
  @override
  int? get facesFound;
  @override
  String? get reason;

  /// Create a copy of EnrollmentResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$EnrollmentResponseImplCopyWith<_$EnrollmentResponseImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$PhotoEnrollmentProgress {
  int get photoIndex => throw _privateConstructorUsedError; // 0-based
  int get totalPhotos => throw _privateConstructorUsedError;
  bool get enrolled => throw _privateConstructorUsedError;
  String? get error => throw _privateConstructorUsedError;
  String? get embeddingId => throw _privateConstructorUsedError;

  /// Create a copy of PhotoEnrollmentProgress
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PhotoEnrollmentProgressCopyWith<PhotoEnrollmentProgress> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PhotoEnrollmentProgressCopyWith<$Res> {
  factory $PhotoEnrollmentProgressCopyWith(PhotoEnrollmentProgress value,
          $Res Function(PhotoEnrollmentProgress) then) =
      _$PhotoEnrollmentProgressCopyWithImpl<$Res, PhotoEnrollmentProgress>;
  @useResult
  $Res call(
      {int photoIndex,
      int totalPhotos,
      bool enrolled,
      String? error,
      String? embeddingId});
}

/// @nodoc
class _$PhotoEnrollmentProgressCopyWithImpl<$Res,
        $Val extends PhotoEnrollmentProgress>
    implements $PhotoEnrollmentProgressCopyWith<$Res> {
  _$PhotoEnrollmentProgressCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of PhotoEnrollmentProgress
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? photoIndex = null,
    Object? totalPhotos = null,
    Object? enrolled = null,
    Object? error = freezed,
    Object? embeddingId = freezed,
  }) {
    return _then(_value.copyWith(
      photoIndex: null == photoIndex
          ? _value.photoIndex
          : photoIndex // ignore: cast_nullable_to_non_nullable
              as int,
      totalPhotos: null == totalPhotos
          ? _value.totalPhotos
          : totalPhotos // ignore: cast_nullable_to_non_nullable
              as int,
      enrolled: null == enrolled
          ? _value.enrolled
          : enrolled // ignore: cast_nullable_to_non_nullable
              as bool,
      error: freezed == error
          ? _value.error
          : error // ignore: cast_nullable_to_non_nullable
              as String?,
      embeddingId: freezed == embeddingId
          ? _value.embeddingId
          : embeddingId // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$PhotoEnrollmentProgressImplCopyWith<$Res>
    implements $PhotoEnrollmentProgressCopyWith<$Res> {
  factory _$$PhotoEnrollmentProgressImplCopyWith(
          _$PhotoEnrollmentProgressImpl value,
          $Res Function(_$PhotoEnrollmentProgressImpl) then) =
      __$$PhotoEnrollmentProgressImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {int photoIndex,
      int totalPhotos,
      bool enrolled,
      String? error,
      String? embeddingId});
}

/// @nodoc
class __$$PhotoEnrollmentProgressImplCopyWithImpl<$Res>
    extends _$PhotoEnrollmentProgressCopyWithImpl<$Res,
        _$PhotoEnrollmentProgressImpl>
    implements _$$PhotoEnrollmentProgressImplCopyWith<$Res> {
  __$$PhotoEnrollmentProgressImplCopyWithImpl(
      _$PhotoEnrollmentProgressImpl _value,
      $Res Function(_$PhotoEnrollmentProgressImpl) _then)
      : super(_value, _then);

  /// Create a copy of PhotoEnrollmentProgress
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? photoIndex = null,
    Object? totalPhotos = null,
    Object? enrolled = null,
    Object? error = freezed,
    Object? embeddingId = freezed,
  }) {
    return _then(_$PhotoEnrollmentProgressImpl(
      photoIndex: null == photoIndex
          ? _value.photoIndex
          : photoIndex // ignore: cast_nullable_to_non_nullable
              as int,
      totalPhotos: null == totalPhotos
          ? _value.totalPhotos
          : totalPhotos // ignore: cast_nullable_to_non_nullable
              as int,
      enrolled: null == enrolled
          ? _value.enrolled
          : enrolled // ignore: cast_nullable_to_non_nullable
              as bool,
      error: freezed == error
          ? _value.error
          : error // ignore: cast_nullable_to_non_nullable
              as String?,
      embeddingId: freezed == embeddingId
          ? _value.embeddingId
          : embeddingId // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc

class _$PhotoEnrollmentProgressImpl implements _PhotoEnrollmentProgress {
  const _$PhotoEnrollmentProgressImpl(
      {required this.photoIndex,
      required this.totalPhotos,
      required this.enrolled,
      this.error,
      this.embeddingId});

  @override
  final int photoIndex;
// 0-based
  @override
  final int totalPhotos;
  @override
  final bool enrolled;
  @override
  final String? error;
  @override
  final String? embeddingId;

  @override
  String toString() {
    return 'PhotoEnrollmentProgress(photoIndex: $photoIndex, totalPhotos: $totalPhotos, enrolled: $enrolled, error: $error, embeddingId: $embeddingId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PhotoEnrollmentProgressImpl &&
            (identical(other.photoIndex, photoIndex) ||
                other.photoIndex == photoIndex) &&
            (identical(other.totalPhotos, totalPhotos) ||
                other.totalPhotos == totalPhotos) &&
            (identical(other.enrolled, enrolled) ||
                other.enrolled == enrolled) &&
            (identical(other.error, error) || other.error == error) &&
            (identical(other.embeddingId, embeddingId) ||
                other.embeddingId == embeddingId));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType, photoIndex, totalPhotos, enrolled, error, embeddingId);

  /// Create a copy of PhotoEnrollmentProgress
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PhotoEnrollmentProgressImplCopyWith<_$PhotoEnrollmentProgressImpl>
      get copyWith => __$$PhotoEnrollmentProgressImplCopyWithImpl<
          _$PhotoEnrollmentProgressImpl>(this, _$identity);
}

abstract class _PhotoEnrollmentProgress implements PhotoEnrollmentProgress {
  const factory _PhotoEnrollmentProgress(
      {required final int photoIndex,
      required final int totalPhotos,
      required final bool enrolled,
      final String? error,
      final String? embeddingId}) = _$PhotoEnrollmentProgressImpl;

  @override
  int get photoIndex; // 0-based
  @override
  int get totalPhotos;
  @override
  bool get enrolled;
  @override
  String? get error;
  @override
  String? get embeddingId;

  /// Create a copy of PhotoEnrollmentProgress
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PhotoEnrollmentProgressImplCopyWith<_$PhotoEnrollmentProgressImpl>
      get copyWith => throw _privateConstructorUsedError;
}
