/// Input validation for security hardening
///
/// Validates and sanitizes all external inputs to prevent injection attacks,
/// invalid configurations, and other security issues.
library;

import '../models/drm_config.dart';
import '../core/exceptions.dart';

/// Input validator for media player inputs
class InputValidator {
  /// Validates a URL
  static void validateUrl(String url, {bool requireHttps = false}) {
    // Check if URL is empty
    if (url.trim().isEmpty) {
      throw ConfigurationException(
        'URL cannot be empty',
        parameter: 'url',
        value: url,
      );
    }

    // Try to parse URL
    final Uri? uri;
    try {
      uri = Uri.parse(url);
    } catch (e) {
      throw ConfigurationException(
        'Invalid URL format: $e',
        parameter: 'url',
        value: url,
      );
    }

    // Check if has scheme
    if (!uri.hasScheme) {
      throw ConfigurationException(
        'URL must include a scheme (http:// or https://)',
        parameter: 'url',
        value: url,
      );
    }

    // Validate scheme
    final validSchemes =
        requireHttps ? ['https'] : ['http', 'https', 'rtmp', 'rtsp'];
    if (!validSchemes.contains(uri.scheme.toLowerCase())) {
      throw ConfigurationException(
        requireHttps
            ? 'URL must use HTTPS protocol'
            : 'URL must use HTTP, HTTPS, RTMP, or RTSP protocol',
        parameter: 'url',
        value: url,
      );
    }

    // Check if has host
    if (uri.host.isEmpty) {
      throw ConfigurationException(
        'URL must include a valid host',
        parameter: 'url',
        value: url,
      );
    }

    // Validate host format (basic check)
    if (!_isValidHost(uri.host)) {
      throw ConfigurationException(
        'Invalid host format',
        parameter: 'url',
        value: url,
      );
    }
  }

  /// Validates a DRM configuration
  static void validateDrmConfig(DrmConfig config) {
    // Validate license URL
    if (config.licenseUrl.isEmpty) {
      throw ConfigurationException(
        'DRM license URL cannot be empty',
        parameter: 'licenseUrl',
      );
    }

    validateUrl(config.licenseUrl, requireHttps: true);

    // Validate certificate URL for FairPlay
    if (config.scheme == DrmScheme.fairplay) {
      if (config.certificateUrl == null || config.certificateUrl!.isEmpty) {
        throw ConfigurationException(
          'FairPlay DRM requires a certificate URL',
          parameter: 'certificateUrl',
        );
      }

      validateUrl(config.certificateUrl!, requireHttps: true);
    }

    // Validate token format if present
    if (config.token != null && config.token!.isNotEmpty) {
      validateToken(config.token!);
    }

    // Validate custom headers
    if (config.headers != null) {
      validateHeaders(config.headers!);
    }
  }

  /// Validates an authentication token
  static void validateToken(String token) {
    // Check length
    if (token.length < 10) {
      throw ConfigurationException(
        'Token is too short (minimum 10 characters)',
        parameter: 'token',
      );
    }

    if (token.length > 10000) {
      throw ConfigurationException(
        'Token is too long (maximum 10000 characters)',
        parameter: 'token',
      );
    }

    // Check for suspicious characters (basic SQL injection prevention)
    final suspiciousPatterns = [
      '; DROP',
      'SELECT *',
      '<script',
      'javascript:',
      'onerror=',
      '../',
      '..\\',
    ];

    final upperToken = token.toUpperCase();
    for (final pattern in suspiciousPatterns) {
      if (upperToken.contains(pattern.toUpperCase())) {
        throw ConfigurationException(
          'Token contains suspicious patterns',
          parameter: 'token',
        );
      }
    }

    // Basic JWT format check if it looks like a JWT
    if (token.contains('.')) {
      final parts = token.split('.');
      if (parts.length != 3) {
        // Might be JWT, validate format
        if (token.startsWith('ey')) {
          // Looks like JWT but wrong format
          throw ConfigurationException(
            'Invalid JWT format',
            parameter: 'token',
          );
        }
      }
    }
  }

  /// Validates HTTP headers
  static void validateHeaders(Map<String, String> headers) {
    for (final entry in headers.entries) {
      // Validate header name
      if (entry.key.isEmpty) {
        throw ConfigurationException(
          'Header name cannot be empty',
          parameter: 'headers',
        );
      }

      // Check for invalid characters in header name
      if (!_isValidHeaderName(entry.key)) {
        throw ConfigurationException(
          'Invalid header name: ${entry.key}',
          parameter: 'headers',
        );
      }

      // Validate header value
      if (entry.value.contains('\n') || entry.value.contains('\r')) {
        throw ConfigurationException(
          'Header value cannot contain newlines',
          parameter: 'headers',
        );
      }

      // Check for header injection attempts
      if (_containsHeaderInjection(entry.value)) {
        throw ConfigurationException(
          'Header value contains suspicious patterns',
          parameter: 'headers',
        );
      }
    }
  }

  /// Validates a player ID
  static void validatePlayerId(String playerId) {
    if (playerId.isEmpty) {
      throw ConfigurationException(
        'Player ID cannot be empty',
        parameter: 'playerId',
      );
    }

    if (playerId.length > 100) {
      throw ConfigurationException(
        'Player ID is too long (maximum 100 characters)',
        parameter: 'playerId',
      );
    }

    // Only allow alphanumeric, hyphens, and underscores
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(playerId)) {
      throw ConfigurationException(
        'Player ID can only contain letters, numbers, hyphens, and underscores',
        parameter: 'playerId',
      );
    }
  }

  /// Validates a duration
  static void validateDuration(Duration duration,
      {Duration? min, Duration? max}) {
    if (min != null && duration < min) {
      throw ConfigurationException(
        'Duration is below minimum: ${duration.inMilliseconds}ms < ${min.inMilliseconds}ms',
        parameter: 'duration',
      );
    }

    if (max != null && duration > max) {
      throw ConfigurationException(
        'Duration exceeds maximum: ${duration.inMilliseconds}ms > ${max.inMilliseconds}ms',
        parameter: 'duration',
      );
    }
  }

  /// Validates a bitrate
  static void validateBitrate(int bitrate) {
    if (bitrate < 0) {
      throw ConfigurationException(
        'Bitrate cannot be negative',
        parameter: 'bitrate',
        value: bitrate,
      );
    }

    // Sanity check: max 1 Gbps
    if (bitrate > 1000000000) {
      throw ConfigurationException(
        'Bitrate exceeds reasonable maximum (1 Gbps)',
        parameter: 'bitrate',
        value: bitrate,
      );
    }
  }

  /// Sanitizes a URL by removing potentially dangerous elements
  static String sanitizeUrl(String url) {
    final uri = Uri.parse(url);

    // Remove javascript: protocol
    if (uri.scheme.toLowerCase() == 'javascript') {
      throw ConfigurationException(
        'javascript: URLs are not allowed',
        parameter: 'url',
        value: url,
      );
    }

    // Remove data: URLs with scripts
    if (uri.scheme.toLowerCase() == 'data' && url.contains('script')) {
      throw ConfigurationException(
        'data: URLs with scripts are not allowed',
        parameter: 'url',
        value: url,
      );
    }

    return url;
  }

  /// Sanitizes a string by removing control characters
  static String sanitizeString(String input) {
    // Remove control characters except newline, carriage return, and tab
    return input.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
  }

  // Private helper methods

  static bool _isValidHost(String host) {
    // Basic hostname validation
    // Allow: letters, numbers, hyphens, dots
    // Must not start or end with hyphen or dot
    final hostRegex = RegExp(
      r'^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*$',
    );

    return hostRegex.hasMatch(host) || _isValidIpAddress(host);
  }

  static bool _isValidIpAddress(String ip) {
    // IPv4
    final ipv4Regex = RegExp(
      r'^((25[0-5]|(2[0-4]|1\d|[1-9]|)\d)\.?\b){4}$',
    );

    if (ipv4Regex.hasMatch(ip)) return true;

    // IPv6 (basic check)
    if (ip.contains(':')) {
      final parts = ip.split(':');
      return parts.length >= 3 && parts.length <= 8;
    }

    return false;
  }

  static bool _isValidHeaderName(String name) {
    // HTTP header names: letters, numbers, and hyphens
    return RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(name);
  }

  static bool _containsHeaderInjection(String value) {
    // Check for CRLF injection
    if (value.contains('\r\n') || value.contains('\n\r')) {
      return true;
    }

    // Check for null bytes
    if (value.contains('\x00')) {
      return true;
    }

    return false;
  }
}

/// Example usage:
/// ```dart
/// // Validate URL
/// try {
///   InputValidator.validateUrl('https://example.com/video.m3u8');
/// } catch (e) {
///   print('Invalid URL: $e');
/// }
///
/// // Validate DRM config
/// final drmConfig = DrmConfig.fairPlay(
///   licenseUrl: 'https://drm.example.com/license',
///   certificateUrl: 'https://drm.example.com/cert',
/// );
/// InputValidator.validateDrmConfig(drmConfig);
/// ```
