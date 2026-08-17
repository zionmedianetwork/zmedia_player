/// Input validation for security hardening
///
/// Validates and sanitizes all external inputs to prevent injection attacks,
/// invalid configurations, and other security issues.
library;

import '../models/drm_config.dart';
import '../models/media_item.dart';
import '../core/exceptions.dart';

/// Input validator for media player inputs
class InputValidator {
  /// Remote (network) schemes accepted for a media/license/certificate URL
  /// when HTTPS is not specifically required.
  static const List<String> _remoteSchemes = ['http', 'https', 'rtmp', 'rtsp'];

  /// Local schemes accepted for a *media* URL (never for DRM license/
  /// certificate URLs — see [validateUrl]'s `requireHttps` handling).
  ///
  /// C-02 Stage 1: only `file` is supported. Callers must pass a proper
  /// `file://` URI (e.g. via `Uri.file(path).toString()`, or
  /// [LocalMediaUtils.fileUri]) rather than a bare filesystem path. This is
  /// deliberate, not an oversight:
  ///   - A bare path (`/data/.../movie.mp4`) has no `scheme`, and every other
  ///     input this validator accepts is scheme-qualified; special-casing
  ///     scheme-less strings as "must be a local path" would make the
  ///     validator's error messages ambiguous (is a malformed `http://` typo
  ///     supposed to be treated as a path?) and would silently accept
  ///     accidentally-relative strings.
  ///   - Forcing `file://` pushes callers through `Uri.file()`/
  ///     `Uri.parse()`, which correctly percent-encode spaces and other
  ///     reserved characters. A bare path handed straight to native code has
  ///     already caused subtle bugs elsewhere in this codebase for URLs with
  ///     unencoded special characters.
  ///
  /// `content://` (Android SAF) and `asset://` (Android APK assets) are
  /// intentionally NOT accepted yet even though the native `ExoPlayer`
  /// `DataSource` already understands them — they carry different
  /// permission/lifetime semantics per platform (SAF grants, package
  /// resources) that are out of scope for this stage and deserve their own
  /// validation pass.
  static const List<String> _localSchemes = ['file'];

  /// Validates a URL.
  ///
  /// By default this accepts remote schemes (`http`, `https`, `rtmp`,
  /// `rtsp`) plus the local `file` scheme (C-02 Stage 1 — local file
  /// playback). Pass `requireHttps: true` for anything security-sensitive
  /// (DRM license/certificate URLs) to restrict to `https` only — `file` is
  /// never permitted when `requireHttps` is set, by design: a local media
  /// *file* is safe to play, but a local *license server* is not something
  /// this validator can reason about, so DRM endpoints always stay
  /// network+HTTPS only regardless of this method's default behavior.
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
        'URL must include a scheme (http://, https://, or file://)',
        parameter: 'url',
        value: url,
      );
    }

    // Validate scheme
    final scheme = uri.scheme.toLowerCase();
    final validSchemes =
        requireHttps ? ['https'] : [..._remoteSchemes, ..._localSchemes];
    if (!validSchemes.contains(scheme)) {
      throw ConfigurationException(
        requireHttps
            ? 'URL must use HTTPS protocol'
            : 'URL must use HTTP, HTTPS, RTMP, RTSP, or file protocol',
        parameter: 'url',
        value: url,
      );
    }

    if (scheme == 'file') {
      _validateFileUrl(uri, url);
      return;
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

  /// Validates a `file://` URL (C-02 Stage 1 — local file playback).
  ///
  /// Deliberately does NOT constrain *where* the file may live (e.g. does
  /// not require it to be under the app's documents/sandbox directory).
  /// That boundary is already enforced by the OS: a Flutter app process can
  /// only ever open paths it already has OS-level permission to read
  /// (app sandbox on iOS, app-private storage / granted permissions on
  /// Android) no matter what string is passed here, so hard-coding a single
  /// allowed directory would not add real protection — it would only break
  /// legitimate host-app use cases (playing a file the user picked from
  /// external storage/Files/Photos, a file downloaded to a custom cache
  /// directory, etc.) for no security benefit. The host app remains
  /// responsible for only ever constructing a `file://` URL from a path it
  /// trusts.
  ///
  /// What IS validated defensively, in case a `file://` URL is built by
  /// string-concatenating partially-trusted input (e.g. a server-driven
  /// playlist entry naming a previously-downloaded local file by name): the
  /// decoded path must not contain `.` or `..` segments, and no decoded
  /// segment may itself contain an (encoded) path separator — both are
  /// classic traversal tricks for escaping an intended base directory even
  /// when the final resolved path is still inside the OS sandbox.
  static void _validateFileUrl(Uri uri, String original) {
    // A file:// URL with a non-empty host (`file://host/path`, i.e. a
    // UNC-style remote share reference) is not "local" in any sense this
    // validator can reason about — reject it rather than silently treating
    // it as a local path.
    if (uri.host.isNotEmpty) {
      throw ConfigurationException(
        'file:// URLs must not include a host (use file:///path, not '
        'file://host/path)',
        parameter: 'url',
        value: original,
      );
    }

    if (uri.path.isEmpty || uri.path == '/') {
      throw ConfigurationException(
        'file:// URL must include a file path',
        parameter: 'url',
        value: original,
      );
    }

    // `Uri.parse` silently applies RFC 3986 §5.2.4 dot-segment removal to
    // `uri.path`/`uri.pathSegments` *while parsing* — by the time this code
    // ever looks at them, `file:///base/../../etc/passwd` has already been
    // resolved to `file:///etc/passwd`, so checking the normalized path
    // cannot catch the traversal attempt. Walk the RAW, pre-normalization
    // path text (still percent-encoded) instead, decoding one segment at a
    // time so an encoded segment such as `%2e%2e` is still caught.
    for (final rawSegment in _rawFilePath(original).split('/')) {
      if (rawSegment.isEmpty) continue;
      String decoded;
      try {
        decoded = Uri.decodeComponent(rawSegment);
      } catch (e) {
        throw ConfigurationException(
          'file:// URL contains malformed percent-encoding: $e',
          parameter: 'url',
          value: original,
        );
      }
      if (decoded == '.' || decoded == '..') {
        throw ConfigurationException(
          'file:// URL path must not contain "." or ".." segments',
          parameter: 'url',
          value: original,
        );
      }
      if (decoded.contains('/') || decoded.contains(r'\')) {
        throw ConfigurationException(
          'file:// URL path segment must not contain an encoded path '
          'separator',
          parameter: 'url',
          value: original,
        );
      }
    }
  }

  /// Returns the path component of a `file://` URL as it appeared in
  /// [original] — before `Uri.parse` normalized away any `.`/`..`
  /// dot-segments — for use by [_validateFileUrl]'s traversal check. Only
  /// called after the caller has already confirmed the URL parses with an
  /// empty `host`, so the only two shapes to handle are `file:///path`
  /// (empty authority) and the unusual-but-valid `file:/path` (no
  /// authority at all).
  static String _rawFilePath(String original) {
    var rest = original.substring(original.indexOf(':') + 1);
    if (rest.startsWith('//')) {
      rest = rest.substring(2);
    }
    // Strip a query string / fragment, which are not part of the path.
    final queryIndex = rest.indexOf('?');
    final fragmentIndex = rest.indexOf('#');
    var end = rest.length;
    if (queryIndex != -1 && queryIndex < end) end = queryIndex;
    if (fragmentIndex != -1 && fragmentIndex < end) end = fragmentIndex;
    return rest.substring(0, end);
  }

  /// Validates a MediaItem that carries a DRM configuration.
  ///
  /// When [item.drmConfig] is non-null the media URL itself must also use
  /// HTTPS — an HTTP media URL with DRM would expose the stream to interception
  /// even if the license request is secured.  Non-DRM items are not affected.
  static void validateMediaItemWithDrm(MediaItem item) {
    if (item.drmConfig == null) return;

    validateUrl(item.url, requireHttps: true);
    validateDrmConfig(item.drmConfig!);
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

    // B-12 wave 2 / gate item: minWidevineSecurityLevel only makes sense
    // for DrmScheme.widevine — see WidevineSecurityLevel's dartdoc for why
    // there is no FairPlay/iOS equivalent. Reject the misconfiguration here,
    // before it ever reaches native code, rather than silently ignoring it.
    if (config.minWidevineSecurityLevel != null &&
        config.scheme != DrmScheme.widevine) {
      throw ConfigurationException(
        'minWidevineSecurityLevel only applies to DrmScheme.widevine '
        '(got ${config.scheme.name})',
        parameter: 'minWidevineSecurityLevel',
      );
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
