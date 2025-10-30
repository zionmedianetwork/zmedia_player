/// Certificate pinning for secure connections
///
/// Prevents man-in-the-middle attacks by validating server certificates
/// against known good certificates (pins). Used for DRM license servers
/// and media CDNs.
library;

import 'dart:convert';

/// Configuration for certificate pinning
class CertificatePinningConfig {
  /// Map of domains to their certificate pins (SHA256 hashes)
  final Map<String, List<String>> pins;

  /// Whether to enforce pinning (fail if pin doesn't match)
  final bool enforceExpiration;

  /// Whether to allow backup pins
  final bool allowBackupPins;

  /// Number of pins required for a domain
  final int minimumPins;

  const CertificatePinningConfig({
    required this.pins,
    this.enforceExpiration = true,
    this.allowBackupPins = true,
    this.minimumPins = 2,
  });

  /// Creates an empty config (no pinning)
  factory CertificatePinningConfig.disabled() {
    return const CertificatePinningConfig(pins: {});
  }

  /// Creates config from domain and certificate hashes
  factory CertificatePinningConfig.fromPins(
    Map<String, List<String>> pins, {
    bool enforceExpiration = true,
  }) {
    return CertificatePinningConfig(
      pins: pins,
      enforceExpiration: enforceExpiration,
    );
  }

  /// Validates the configuration
  bool isValid() {
    if (pins.isEmpty) return true; // No pinning is valid

    // Check that each domain has minimum required pins
    for (final entry in pins.entries) {
      if (entry.value.length < minimumPins) {
        return false;
      }

      // Validate pin format (should be SHA256 hashes)
      for (final pin in entry.value) {
        if (!_isValidSha256(pin)) {
          return false;
        }
      }
    }

    return true;
  }

  /// Gets pins for a specific domain
  List<String>? getPinsForDomain(String domain) {
    // Exact match
    if (pins.containsKey(domain)) {
      return pins[domain];
    }

    // Wildcard match (*.example.com)
    final parts = domain.split('.');
    if (parts.length >= 2) {
      final wildcard = '*.${parts.sublist(1).join('.')}';
      if (pins.containsKey(wildcard)) {
        return pins[wildcard];
      }
    }

    return null;
  }

  /// Checks if a domain has pinning configured
  bool hasPinsForDomain(String domain) {
    return getPinsForDomain(domain) != null;
  }

  /// Converts to map for platform communication
  Map<String, dynamic> toMap() {
    return {
      'pins': pins,
      'enforceExpiration': enforceExpiration,
      'allowBackupPins': allowBackupPins,
      'minimumPins': minimumPins,
    };
  }

  /// Creates from map
  factory CertificatePinningConfig.fromMap(Map<String, dynamic> map) {
    final pinsMap = (map['pins'] as Map<dynamic, dynamic>).map(
      (key, value) => MapEntry(
        key.toString(),
        (value as List<dynamic>).map((e) => e.toString()).toList(),
      ),
    );

    return CertificatePinningConfig(
      pins: pinsMap,
      enforceExpiration: map['enforceExpiration'] as bool? ?? true,
      allowBackupPins: map['allowBackupPins'] as bool? ?? true,
      minimumPins: map['minimumPins'] as int? ?? 2,
    );
  }

  bool _isValidSha256(String hash) {
    // SHA256 hash should be 64 hex characters
    final regex = RegExp(r'^[a-fA-F0-9]{64}$');
    return regex.hasMatch(hash);
  }

  @override
  String toString() {
    return 'CertificatePinningConfig(domains: ${pins.length}, '
        'enforceExpiration: $enforceExpiration)';
  }
}

/// Helper class for certificate pinning operations
class CertificatePinningHelper {
  /// Calculates SHA256 fingerprint of a certificate
  /// Note: This is a placeholder. Real SHA256 calculation should be done
  /// on the native side (Android/iOS) where crypto libraries are available.
  static String calculateFingerprint(List<int> certificateBytes) {
    // This will be implemented natively on Android/iOS
    // For now, return a hex representation
    return certificateBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join('');
  }

  /// Validates certificate against pins
  static bool validateCertificate(
    List<int> certificateBytes,
    List<String> pins,
  ) {
    final fingerprint = calculateFingerprint(certificateBytes);

    // Check if fingerprint matches any of the pins
    return pins.any((pin) => pin.toLowerCase() == fingerprint.toLowerCase());
  }

  /// Extracts domain from URL
  static String extractDomain(String url) {
    final uri = Uri.parse(url);
    return uri.host;
  }

  /// Creates a pin from a PEM certificate
  static String pinFromPem(String pemCertificate) {
    // Remove PEM headers and whitespace
    final lines = pemCertificate
        .replaceAll('-----BEGIN CERTIFICATE-----', '')
        .replaceAll('-----END CERTIFICATE-----', '')
        .replaceAll(RegExp(r'\s'), '');

    // Decode base64
    final bytes = base64.decode(lines);

    // Calculate SHA256
    return calculateFingerprint(bytes);
  }

  /// Creates pins from multiple PEM certificates
  static List<String> pinsFromPems(List<String> pemCertificates) {
    return pemCertificates.map(pinFromPem).toList();
  }

  /// Formats a fingerprint for display (adds colons)
  static String formatFingerprint(String fingerprint) {
    final buffer = StringBuffer();
    for (var i = 0; i < fingerprint.length; i += 2) {
      if (i > 0) buffer.write(':');
      buffer.write(fingerprint.substring(i, i + 2));
    }
    return buffer.toString().toUpperCase();
  }
}

/// Example usage:
/// ```dart
/// // Create pinning config
/// final config = CertificatePinningConfig.fromPins({
///   'cdn.example.com': [
///     'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
///     'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB',
///   ],
///   '*.drm-server.com': [
///     'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC',
///     'DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD',
///   ],
/// });
///
/// // Calculate pin from PEM certificate
/// final pem = '''
/// -----BEGIN CERTIFICATE-----
/// MIIDXTCCAkWgAwIBAgIJAKL0UG+mRqOjMA0GCSqGSIb3...
/// -----END CERTIFICATE-----
/// ''';
/// final pin = CertificatePinningHelper.pinFromPem(pem);
/// ```
