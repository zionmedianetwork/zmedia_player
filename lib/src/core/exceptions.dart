/// Exception handling for ZMedia Player
///
/// This file defines a typed exception hierarchy for consistent error handling
/// across the plugin. Each exception type provides specific context to help
/// developers understand and handle errors appropriately.
library;

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
    Map<String, dynamic>? details,
  }) : super(message, details: details);

  /// Platform-specific error code
  final String? errorCode;

  @override
  String toString() => 'PlaybackException: $message (Code: $errorCode)';
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
