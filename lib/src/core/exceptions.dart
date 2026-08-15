/// Exception handling for ZMedia Player
///
/// This file defines a typed exception hierarchy for consistent error handling
/// across the plugin. Each exception type provides specific context to help
/// developers understand and handle errors appropriately.
library;

/// Canonical wire-format vocabulary for *why* a native playback error
/// occurred, shared by both native platforms and the Dart exception mapper.
///
/// This is the H-01 fix: previously [MediaPlayer]'s error mapping tested
/// [PlatformException.code] for values (`'NETWORK_ERROR'`, `'DRM_...'`,
/// `'HTTP_ERROR'`) that neither native implementation ever actually sent —
/// every real error fell through to a generic fallback, making the typed
/// exception hierarchy effectively unreachable. [MediaErrorCategory] is the
/// one, documented set of reasons both platforms now emit:
///
/// - Android: `MediaPlayerInstance.categorizeExoPlayerError` in
///   `android/.../MediaPlayerManager.kt` maps ExoPlayer's
///   `PlaybackException.errorCode` onto these values and sends them as the
///   `"category"` field of the `onError` native event (plus, best-effort,
///   from the synchronous `LOAD_ERROR` result error in `ZMediaPlayerPlugin.kt`
///   via a `"category"` details entry — see `categorizeSynchronousLoadError`).
/// - iOS: `MediaPlayerInstance.categorize(_:)` in
///   `ios/.../MediaPlayerManager.swift` maps `AVError`/`NSError` onto the
///   same values for the `onError` event.
///
/// Both native call sites carry a comment pointing back here, and
/// `test/exceptions/error_category_vocabulary_test.dart` parses the native
/// source files as text and asserts every category string literal they use
/// is a member of this enum's [wireValue]s — that is what actually catches
/// native/Dart drift, since the native code is not part of this package's
/// automated test/build pipeline.
///
/// `docs/` should document this table for consumers (see the
/// production-gate-assessment H-01 report for the exact wording); this file
/// is the source of truth for the enum values and the native mapping.
enum MediaErrorCategory {
  /// Could not reach or read from the source at all: DNS failure, timeout,
  /// connection refused/lost, offline, TLS/cleartext rejected, etc.
  network('NETWORK'),

  /// The server responded, but with a failure/unusable HTTP status (404,
  /// 403, 5xx, invalid content-type for a manifest, etc.).
  http('HTTP'),

  /// DRM/license/content-protection failure (license acquisition,
  /// certificate/provisioning, unsupported scheme, disallowed operation).
  drm('DRM'),

  /// The device's decoder/hardware cannot play this content (codec
  /// unsupported, decoder init failed, decoding failed).
  decoder('DECODER'),

  /// The source itself is invalid/malformed/unsupported at the
  /// container/manifest level (corrupt file, unparseable manifest,
  /// unsupported container).
  source('SOURCE'),

  /// Native reported an error that doesn't fit (or couldn't be classified
  /// into) one of the categories above.
  unknown('UNKNOWN');

  const MediaErrorCategory(this.wireValue);

  /// The exact string native sends over the MethodChannel for this
  /// category. Keep in sync with the Kotlin/Swift mappers referenced above.
  final String wireValue;

  /// Parses a native `"category"` string, defaulting to [unknown] for a
  /// missing/unrecognized value (e.g. an older cached native build that
  /// predates this vocabulary and never sends `"category"` at all).
  static MediaErrorCategory fromWireValue(String? value) {
    for (final category in MediaErrorCategory.values) {
      if (category.wireValue == value) return category;
    }
    return MediaErrorCategory.unknown;
  }
}

/// Maps a native error report onto a concrete [MediaPlayerException]
/// subtype using the shared [MediaErrorCategory] vocabulary.
///
/// This is the single place both the asynchronous `onError` native event
/// (routed through [MediaPlayer.errorStream]) and the synchronous
/// method-call failure paths (e.g. `MediaPlayer.load()`'s `on
/// PlatformException` handler) go through, so a native/Dart wire-format
/// drift only has to be fixed in one place.
MediaPlayerException mapNativeMediaError({
  required String message,
  String? categoryWireValue,
  String? nativeErrorCode,
  Map<String, dynamic>? details,
}) {
  final category = MediaErrorCategory.fromWireValue(categoryWireValue);
  switch (category) {
    case MediaErrorCategory.network:
      return NetworkException(
        message,
        isOffline: details?['isOffline'] as bool? ?? false,
        isTimeout: details?['isTimeout'] as bool? ?? false,
        details: details,
      );
    case MediaErrorCategory.http:
      return MediaLoadException(
        message,
        statusCode: details?['httpStatusCode'] as int?,
        details: details,
      );
    case MediaErrorCategory.drm:
      return DrmException(
        message,
        errorCode: nativeErrorCode,
        isLicenseError: details?['isLicenseError'] as bool? ?? false,
        isCertificateError: details?['isCertificateError'] as bool? ?? false,
        details: details,
      );
    case MediaErrorCategory.decoder:
    case MediaErrorCategory.source:
    case MediaErrorCategory.unknown:
      return PlaybackException(
        message,
        errorCode: nativeErrorCode,
        category: category,
        details: details,
      );
  }
}

/// Base exception for all media player errors
///
/// This is a sealed class, meaning all subclasses must be defined in this file.
/// This allows for exhaustive pattern matching in error handling.
sealed class MediaPlayerException implements Exception {
  const MediaPlayerException(this.message, {this.details});

  /// Human-readable error message
  final String message;

  /// Additional context about the error
  final Map<String, dynamic>? details;

  @override
  String toString() {
    if (details != null && details!.isNotEmpty) {
      return 'MediaPlayerException: $message\nDetails: $details';
    }
    return 'MediaPlayerException: $message';
  }
}

/// Media could not be loaded
///
/// Thrown when attempting to load a media item fails, typically due to:
/// - Invalid URL
/// - Unsupported format
/// - Server errors
/// - Permission issues
class MediaLoadException extends MediaPlayerException {
  const MediaLoadException(
    String message, {
    this.url,
    this.statusCode,
    Map<String, dynamic>? details,
  }) : super(message, details: details);

  /// The URL that failed to load
  final String? url;

  /// HTTP status code (if applicable)
  final int? statusCode;

  @override
  String toString() =>
      'MediaLoadException: $message (URL: $url, Status: $statusCode)';
}

/// Network-related errors
///
/// Thrown when network connectivity issues prevent operations from completing.
class NetworkException extends MediaPlayerException {
  const NetworkException(
    String message, {
    this.isOffline = false,
    this.isTimeout = false,
    Map<String, dynamic>? details,
  }) : super(message, details: details);

  /// Whether the device appears to be offline
  final bool isOffline;

  /// Whether the error was due to a timeout
  final bool isTimeout;

  @override
  String toString() {
    if (isOffline) return 'NetworkException: No internet connection';
    if (isTimeout) return 'NetworkException: Request timed out - $message';
    return 'NetworkException: $message';
  }
}

/// DRM-related errors
///
/// Thrown when content protection (DRM) operations fail, including:
/// - License acquisition failures
/// - Certificate errors
/// - Key system issues
/// - Rights violations
class DrmException extends MediaPlayerException {
  const DrmException(
    String message, {
    this.drmType,
    this.errorCode,
    this.isLicenseError = false,
    this.isCertificateError = false,
    Map<String, dynamic>? details,
  }) : super(message, details: details);

  /// Type of DRM (e.g., 'Widevine', 'FairPlay', 'PlayReady')
  final String? drmType;

  /// Platform-specific error code
  final String? errorCode;

  /// Whether this is a license acquisition error
  final bool isLicenseError;

  /// Whether this is a certificate/provisioning error
  final bool isCertificateError;

  @override
  String toString() {
    final type = drmType ?? 'Unknown';
    if (isLicenseError) {
      return 'DrmException ($type): License error - $message (Code: $errorCode)';
    }
    if (isCertificateError) {
      return 'DrmException ($type): Certificate error - $message';
    }
    return 'DrmException ($type): $message (Code: $errorCode)';
  }
}

/// Playback errors (decoding, rendering, etc.)
///
/// Thrown when media playback fails after successful loading, typically due to:
/// - Codec issues
/// - Corrupted media
/// - Resource exhaustion
/// - Hardware limitations
class PlaybackException extends MediaPlayerException {
  const PlaybackException(
    String message, {
    this.errorCode,
    this.category = MediaErrorCategory.unknown,
    Map<String, dynamic>? details,
  }) : super(message, details: details);

  /// Platform-specific error code
  final String? errorCode;

  /// Which part of the shared [MediaErrorCategory] vocabulary this failure
  /// falls into. [PlaybackException] is the catch-all for categories that
  /// don't have a dedicated subtype (currently
  /// [MediaErrorCategory.decoder], [MediaErrorCategory.source], and
  /// [MediaErrorCategory.unknown] — network/HTTP/DRM failures are instead
  /// represented by [NetworkException]/[MediaLoadException]/[DrmException]).
  final MediaErrorCategory category;

  @override
  String toString() =>
      'PlaybackException: $message (Code: $errorCode, Category: ${category.wireValue})';
}

/// Player is in invalid state for requested operation
///
/// Thrown when attempting an operation that is not valid for the current
/// player state (e.g., seeking when no media is loaded, playing when disposed).
class InvalidStateException extends MediaPlayerException {
  const InvalidStateException(
    String message, {
    this.currentState,
    this.requiredState,
    Map<String, dynamic>? details,
  }) : super(message, details: details);

  /// The current state of the player
  final String? currentState;

  /// The state required for the operation
  final String? requiredState;

  @override
  String toString() =>
      'InvalidStateException: $message (Current: $currentState, Required: $requiredState)';
}

/// Player has been disposed
///
/// Thrown when attempting to use a player that has been disposed.
/// This helps catch use-after-dispose bugs early.
class PlayerDisposedException extends MediaPlayerException {
  const PlayerDisposedException([
    String message = 'Player has been disposed',
  ]) : super(message);

  @override
  String toString() => 'PlayerDisposedException: $message';
}

/// Configuration error
///
/// Thrown when player configuration is invalid, including:
/// - Invalid parameters
/// - Conflicting settings
/// - Missing required configuration
class ConfigurationException extends MediaPlayerException {
  const ConfigurationException(
    String message, {
    this.parameter,
    this.value,
    Map<String, dynamic>? details,
  }) : super(message, details: details);

  /// The parameter that caused the error
  final String? parameter;

  /// The invalid value
  final dynamic value;

  @override
  String toString() =>
      'ConfigurationException: $message (Parameter: $parameter, Value: $value)';
}

/// Platform-specific error
///
/// Thrown when a platform-specific operation fails and doesn't fit
/// into other exception categories.
class PlatformOperationException extends MediaPlayerException {
  const PlatformOperationException(
    String message, {
    this.platform,
    this.code,
    Map<String, dynamic>? details,
  }) : super(message, details: details);

  /// The platform where the error occurred ('android' or 'ios')
  final String? platform;

  /// Platform-specific error code
  final String? code;

  @override
  String toString() =>
      'PlatformOperationException ($platform): $message (Code: $code)';
}

/// Native/Dart protocol skew detected (M-16)
///
/// Thrown when the Dart package and the compiled native (Android/iOS)
/// plugin implementation disagree about the MethodChannel wire protocol.
/// Because this package is distributed by git ref rather than pub.dev, a
/// host app can easily end up running a newer Dart package against a
/// stale, previously-built native binary. Two situations throw this:
///
/// - [MediaPlayer.initialize] explicitly negotiates a `protocolVersion`
///   with native; either side declaring the other's version unsupported
///   throws this with [dartProtocolVersion] and [nativeProtocolVersion]
///   set.
/// - Any MethodChannel call raises a raw `MissingPluginException` (native
///   doesn't implement a method this Dart package expects at all) — that
///   otherwise would escape this package's sealed exception hierarchy
///   entirely; it's wrapped here instead, with [missingMethod] set.
class ProtocolMismatchException extends MediaPlayerException {
  const ProtocolMismatchException(
    String message, {
    this.dartProtocolVersion,
    this.nativeProtocolVersion,
    this.missingMethod,
    Map<String, dynamic>? details,
  }) : super(message, details: details);

  /// This Dart package's declared protocol version, when known.
  final int? dartProtocolVersion;

  /// The native plugin's declared protocol version, when known (native
  /// reports this in `initialize`'s error `details` or success payload).
  final int? nativeProtocolVersion;

  /// The MethodChannel method name that triggered a `MissingPluginException`,
  /// when this exception was raised reactively rather than during the
  /// `initialize` handshake.
  final String? missingMethod;

  @override
  String toString() =>
      'ProtocolMismatchException: $message (dart: $dartProtocolVersion, '
      'native: $nativeProtocolVersion, missingMethod: $missingMethod)';
}

/// Operation skipped due to another operation in progress
///
/// Thrown when a non-critical operation cannot be executed because
/// another operation is currently in progress. This allows callers
/// to decide whether to retry, ignore, or handle differently.
class OperationBusyException extends MediaPlayerException {
  const OperationBusyException([
    super.message = 'Operation skipped - another operation in progress',
  ]);

  @override
  String toString() => 'OperationBusyException: $message';
}
