/// DRM (Digital Rights Management) configuration and models
library;

import '../security/certificate_pinning.dart';

export '../security/certificate_pinning.dart' show CertificatePinningConfig;

/// DRM scheme types
enum DrmScheme {
  /// Token-based DRM (custom authentication)
  token,

  /// Google Widevine (Android)
  widevine,

  /// Apple FairPlay (iOS)
  fairplay,

  /// EZDRM service
  ezdrm,

  /// PlayReady (Microsoft)
  playready,

  /// Clear Key (for testing)
  clearkey,
}

/// Widevine security levels, from most to least secure.
///
/// **Android/Widevine only.** FairPlay (iOS) has no directly comparable,
/// queryable device security tier — Apple's trust model for FairPlay is
/// built into code-signing and hardware attestation at the OS level rather
/// than exposed as an app-queryable enum the way `MediaDrm.getPropertyString
/// ("securityLevel")` is on Android. Setting
/// [DrmConfig.minWidevineSecurityLevel] has no effect on iOS: the `fairplay`
/// scheme is the only one iOS's native `DrmHandler` accepts at all, so a
/// `widevine` [DrmConfig] (the only scheme this field is meaningful for)
/// never reaches iOS DRM code in the first place. See
/// `DrmHandler.validateDrmConfig` (Android) / the class doc on
/// `DrmHandler.swift` (iOS) for where this is enforced natively.
enum WidevineSecurityLevel {
  /// Hardware-backed cryptography operations and key storage in a trusted
  /// execution environment (TEE). Widevine's highest security tier.
  l1,

  /// Software-based cryptography with some hardware isolation. Rarely seen
  /// on shipping devices; included for completeness of the enum space
  /// `MediaDrm` can report.
  l2,

  /// Software-only cryptography with no hardware protection. Widevine's
  /// lowest security tier.
  l3,
}

/// Wire-format helpers for [WidevineSecurityLevel], matching the string
/// values `android.media.MediaDrm.getPropertyString("securityLevel")`
/// returns on Android (`"L1"` / `"L2"` / `"L3"`).
extension WidevineSecurityLevelWire on WidevineSecurityLevel {
  /// Serializes to the string native `DrmHandler.getWidevineSecurityLevel()`
  /// compares against.
  String get wireValue {
    switch (this) {
      case WidevineSecurityLevel.l1:
        return 'L1';
      case WidevineSecurityLevel.l2:
        return 'L2';
      case WidevineSecurityLevel.l3:
        return 'L3';
    }
  }
}

/// Parses a [WidevineSecurityLevel] from its wire value ([wireValue]).
/// Returns `null` for an unrecognized/absent value rather than throwing —
/// callers decide how to treat an unparseable level (typically: fail
/// closed, exactly like the native fail-closed policy this field drives).
WidevineSecurityLevel? widevineSecurityLevelFromWire(String? value) {
  if (value == null) return null;
  switch (value.trim().toUpperCase()) {
    case 'L1':
      return WidevineSecurityLevel.l1;
    case 'L2':
      return WidevineSecurityLevel.l2;
    case 'L3':
      return WidevineSecurityLevel.l3;
    default:
      return null;
  }
}

/// DRM configuration
class DrmConfig {
  /// DRM scheme to use
  final DrmScheme scheme;

  /// License server URL
  final String licenseUrl;

  /// Certificate URL (required for FairPlay)
  final String? certificateUrl;

  /// Custom HTTP headers for license requests
  final Map<String, String>? headers;

  /// Authentication token
  final String? token;

  /// Key ID (for token-based DRM)
  final String? keyId;

  /// Content ID (for FairPlay)
  final String? contentId;

  /// Custom license (key) request data, applied as additional HTTP headers
  /// on the license request only — distinct from [headers], which applies to
  /// every DRM-related HTTP request (Android: every request made through the
  /// shared `HttpDataSource.Factory`, including provisioning; iOS: both the
  /// FairPlay certificate fetch and the license POST).
  ///
  /// Native wiring:
  ///  - **Android:** each entry is set via
  ///    `HttpMediaDrmCallback.setKeyRequestProperty(key, value)`, which
  ///    Media3/ExoPlayer applies to key/license requests specifically (see
  ///    `DrmHandler.applyCustomDataKeyRequestProperties`).
  ///  - **iOS:** each entry is set as an HTTP header on the license `POST`
  ///    request built in `DrmHandler.requestLicense` — **not** on the
  ///    certificate `GET` in `DrmHandler.loadCertificate(from:)`.
  ///
  /// Value conversion (values are `dynamic`, so not everything is naturally
  /// a header-safe `String`):
  ///  - [String] values pass through unchanged.
  ///  - [bool]/[int]/[double] values use their own unambiguous string
  ///    representation (e.g. `"true"`, `"42"`, `"3.14"`).
  ///  - Nested [Map]/[List] values are JSON-encoded (via `org.json` on
  ///    Android, `JSONSerialization` on iOS) — **not** converted with a
  ///    platform's default/debug string representation, which would produce
  ///    a non-parseable value on the wire.
  ///  - `null` entries and any other unsupported value type are skipped
  ///    (logged as a warning natively) rather than sent as the literal
  ///    string `"null"`.
  final Map<String, dynamic>? customData;

  /// EZDRM configuration
  final EzdrmConfig? ezdrmConfig;

  /// Optional certificate pinning configuration for the DRM license server.
  ///
  /// When set, native code (Android: OkHttp CertificatePinner;
  /// iOS: URLSessionDelegate) enforces SHA-256/SPKI pins on every TLS
  /// connection made to the license server host.  If the server certificate
  /// chain does not contain a certificate matching one of the configured pins,
  /// the connection is rejected and a DRM error is emitted.
  ///
  /// Leave null to use the platform's default TLS validation (no pinning).
  final CertificatePinningConfig? certificatePinning;

  /// Opt-in, fail-closed minimum Widevine security level (B-12 wave 2 / gate
  /// item "Wire validateDrmConfig / getWidevineSecurityLevel into the load
  /// path").
  ///
  /// **Android/Widevine only** — see [WidevineSecurityLevel] for why there
  /// is no iOS/FairPlay equivalent. Default `null` means "no policy" and
  /// preserves existing behaviour exactly (no device is rejected on
  /// security-level grounds unless a host app opts in here).
  ///
  /// When set, native `DrmHandler.validateDrmConfig()` (Android) checks the
  /// device's actual Widevine security level (`getWidevineSecurityLevel()`)
  /// against this minimum **before** a DRM session manager is created, and
  /// refuses to create one — failing the load rather than falling back to
  /// unprotected playback — when:
  ///   - the device's level is below the requested minimum, or
  ///   - the device's level cannot be determined at all (fail-closed: an
  ///     indeterminate level is always treated as not meeting the policy).
  ///
  /// Only meaningful when [scheme] is [DrmScheme.widevine];
  /// [InputValidator.validateDrmConfig] rejects any other combination.
  final WidevineSecurityLevel? minWidevineSecurityLevel;

  const DrmConfig({
    required this.scheme,
    required this.licenseUrl,
    this.certificateUrl,
    this.headers,
    this.token,
    this.keyId,
    this.contentId,
    this.customData,
    this.ezdrmConfig,
    this.certificatePinning,
    this.minWidevineSecurityLevel,
  });

  /// Create a token-based DRM configuration
  factory DrmConfig.token({
    required String licenseUrl,
    required String token,
    String? keyId,
    Map<String, String>? headers,
    Map<String, dynamic>? customData,
    CertificatePinningConfig? certificatePinning,
  }) {
    return DrmConfig(
      scheme: DrmScheme.token,
      licenseUrl: licenseUrl,
      token: token,
      keyId: keyId,
      headers: headers,
      customData: customData,
      certificatePinning: certificatePinning,
    );
  }

  /// Create a Widevine DRM configuration (Android)
  factory DrmConfig.widevine({
    required String licenseUrl,
    Map<String, String>? headers,
    Map<String, dynamic>? customData,
    CertificatePinningConfig? certificatePinning,
    WidevineSecurityLevel? minWidevineSecurityLevel,
  }) {
    return DrmConfig(
      scheme: DrmScheme.widevine,
      licenseUrl: licenseUrl,
      headers: headers,
      customData: customData,
      certificatePinning: certificatePinning,
      minWidevineSecurityLevel: minWidevineSecurityLevel,
    );
  }

  /// Create a FairPlay DRM configuration (iOS)
  factory DrmConfig.fairplay({
    required String licenseUrl,
    required String certificateUrl,
    String? contentId,
    Map<String, String>? headers,
    Map<String, dynamic>? customData,
    CertificatePinningConfig? certificatePinning,
  }) {
    return DrmConfig(
      scheme: DrmScheme.fairplay,
      licenseUrl: licenseUrl,
      certificateUrl: certificateUrl,
      contentId: contentId,
      headers: headers,
      customData: customData,
      certificatePinning: certificatePinning,
    );
  }

  /// Create an EZDRM configuration
  factory DrmConfig.ezdrm({
    required EzdrmConfig ezdrmConfig,
    CertificatePinningConfig? certificatePinning,
  }) {
    return DrmConfig(
      scheme: DrmScheme.ezdrm,
      licenseUrl: ezdrmConfig.licenseUrl,
      certificateUrl: ezdrmConfig.certificateUrl,
      headers: ezdrmConfig.headers,
      ezdrmConfig: ezdrmConfig,
      certificatePinning: certificatePinning,
    );
  }

  /// Convert to map for platform channel
  ///
  /// The returned map holds *copies* of this object's collection fields
  /// rather than live references, so mutating the result never mutates
  /// this config, and two calls never hand out the same inner collection. The
  /// copies are shallow: a collection nested inside a `Map<String, dynamic>`
  /// value is still shared. A `null` field stays `null` — it is never widened
  /// to an empty collection, so the MethodChannel payload shape is unchanged.
  Map<String, dynamic> toMap() {
    return {
      'scheme': scheme.name,
      'licenseUrl': licenseUrl,
      'certificateUrl': certificateUrl,
      'headers': headers == null ? null : Map<String, String>.from(headers!),
      'token': token,
      'keyId': keyId,
      'contentId': contentId,
      'customData':
          customData == null ? null : Map<String, dynamic>.from(customData!),
      'ezdrmConfig': ezdrmConfig?.toMap(),
      'certificatePinning': certificatePinning?.toMap(),
      'minWidevineSecurityLevel': minWidevineSecurityLevel?.wireValue,
    };
  }

  /// Create from map
  factory DrmConfig.fromMap(Map<String, dynamic> map) {
    final pinningRaw = map['certificatePinning'];
    final CertificatePinningConfig? pinning = pinningRaw != null
        ? CertificatePinningConfig.fromMap(
            Map<String, dynamic>.from(pinningRaw as Map),
          )
        : null;

    return DrmConfig(
      scheme: DrmScheme.values.firstWhere(
        (e) => e.name == map['scheme'],
        orElse: () => DrmScheme.token,
      ),
      licenseUrl: map['licenseUrl'] as String,
      certificateUrl: map['certificateUrl'] as String?,
      headers: map['headers'] != null
          ? Map<String, String>.from(map['headers'] as Map)
          : null,
      token: map['token'] as String?,
      keyId: map['keyId'] as String?,
      contentId: map['contentId'] as String?,
      customData: map['customData'] as Map<String, dynamic>?,
      ezdrmConfig: map['ezdrmConfig'] != null
          ? EzdrmConfig.fromMap(map['ezdrmConfig'] as Map<String, dynamic>)
          : null,
      certificatePinning: pinning,
      minWidevineSecurityLevel: widevineSecurityLevelFromWire(
          map['minWidevineSecurityLevel'] as String?),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DrmConfig &&
        other.scheme == scheme &&
        other.licenseUrl == licenseUrl &&
        other.certificateUrl == certificateUrl &&
        other.token == token &&
        other.keyId == keyId &&
        other.contentId == contentId;
  }

  @override
  int get hashCode => Object.hash(
        scheme,
        licenseUrl,
        certificateUrl,
        token,
        keyId,
        contentId,
      );

  DrmConfig copyWith({
    DrmScheme? scheme,
    String? licenseUrl,
    String? certificateUrl,
    Map<String, String>? headers,
    String? token,
    String? keyId,
    String? contentId,
    Map<String, dynamic>? customData,
    EzdrmConfig? ezdrmConfig,
    CertificatePinningConfig? certificatePinning,
    WidevineSecurityLevel? minWidevineSecurityLevel,
  }) {
    return DrmConfig(
      scheme: scheme ?? this.scheme,
      licenseUrl: licenseUrl ?? this.licenseUrl,
      certificateUrl: certificateUrl ?? this.certificateUrl,
      headers: headers ?? this.headers,
      token: token ?? this.token,
      keyId: keyId ?? this.keyId,
      contentId: contentId ?? this.contentId,
      customData: customData ?? this.customData,
      ezdrmConfig: ezdrmConfig ?? this.ezdrmConfig,
      certificatePinning: certificatePinning ?? this.certificatePinning,
      minWidevineSecurityLevel:
          minWidevineSecurityLevel ?? this.minWidevineSecurityLevel,
    );
  }
}

/// EZDRM service configuration
class EzdrmConfig {
  /// EZDRM customer ID
  final String customerId;

  /// EZDRM API key
  final String apiKey;

  /// Content ID
  final String contentId;

  /// FairPlay certificate URL.
  ///
  /// Required when [_isFairPlay] is true. Must be provided explicitly via
  /// [EzdrmConfig.fairplay]; there is no default fallback URL.
  final String? _certificateUrl;

  /// License URL (auto-generated from customer ID)
  String get licenseUrl {
    // Widevine license URL
    if (_isWidevine) {
      return 'https://widevine-dash.ezdrm.com/widevine-php/widevine-foreignkey.php?pX=$customerId';
    }
    // FairPlay license URL
    return 'https://fps.ezdrm.com/api/licenses/$customerId';
  }

  /// Certificate URL for FairPlay.
  ///
  /// Returns null for non-FairPlay configurations. For FairPlay configurations
  /// this returns the URL supplied at construction time.
  String? get certificateUrl => _isFairPlay ? _certificateUrl : null;

  /// HTTP headers for EZDRM requests
  Map<String, String> get headers {
    return {
      'X-EZDRM-CUSTOMER-ID': customerId,
      'X-EZDRM-API-KEY': apiKey,
      'X-EZDRM-CONTENT-ID': contentId,
    };
  }

  final bool _isWidevine;
  final bool _isFairPlay;

  EzdrmConfig({
    required this.customerId,
    required this.apiKey,
    required this.contentId,
    bool isWidevine = false,
    bool isFairPlay = false,
    String? certificateUrl,
  })  : _isWidevine = isWidevine,
        _isFairPlay = isFairPlay,
        _certificateUrl = certificateUrl;

  /// Create EZDRM config for Widevine (Android)
  factory EzdrmConfig.widevine({
    required String customerId,
    required String apiKey,
    required String contentId,
  }) {
    return EzdrmConfig(
      customerId: customerId,
      apiKey: apiKey,
      contentId: contentId,
      isWidevine: true,
    );
  }

  /// Create EZDRM config for FairPlay (iOS).
  ///
  /// [certificateUrl] is required and must point to the FPS certificate for
  /// the content provider. There is no default fallback URL.
  factory EzdrmConfig.fairplay({
    required String customerId,
    required String apiKey,
    required String contentId,
    required String certificateUrl,
  }) {
    return EzdrmConfig(
      customerId: customerId,
      apiKey: apiKey,
      contentId: contentId,
      isFairPlay: true,
      certificateUrl: certificateUrl,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EzdrmConfig &&
        other.customerId == customerId &&
        other.apiKey == apiKey &&
        other.contentId == contentId &&
        other._isWidevine == _isWidevine &&
        other._isFairPlay == _isFairPlay &&
        other._certificateUrl == _certificateUrl;
  }

  @override
  int get hashCode => Object.hash(
        customerId,
        apiKey,
        contentId,
        _isWidevine,
        _isFairPlay,
        _certificateUrl,
      );

  Map<String, dynamic> toMap() {
    return {
      'customerId': customerId,
      'apiKey': apiKey,
      'contentId': contentId,
      'isWidevine': _isWidevine,
      'isFairPlay': _isFairPlay,
      'certificateUrl': _certificateUrl,
    };
  }

  factory EzdrmConfig.fromMap(Map<String, dynamic> map) {
    return EzdrmConfig(
      customerId: map['customerId'] as String,
      apiKey: map['apiKey'] as String,
      contentId: map['contentId'] as String,
      isWidevine: map['isWidevine'] as bool? ?? false,
      isFairPlay: map['isFairPlay'] as bool? ?? false,
      certificateUrl: map['certificateUrl'] as String?,
    );
  }
}

/// DRM license information
class DrmLicense {
  /// License ID
  final String id;

  /// License key data
  final String keyData;

  /// License expiration timestamp
  final DateTime? expirationTime;

  /// Playback duration limit in seconds
  final int? playbackDuration;

  /// License renewal URL
  final String? renewalUrl;

  /// License status
  final DrmLicenseStatus status;

  const DrmLicense({
    required this.id,
    required this.keyData,
    this.expirationTime,
    this.playbackDuration,
    this.renewalUrl,
    this.status = DrmLicenseStatus.active,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DrmLicense && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  /// Check if license is expired
  bool get isExpired {
    if (expirationTime == null) return false;
    return DateTime.now().isAfter(expirationTime!);
  }

  /// Check if license is about to expire (within 1 hour)
  bool get isExpiringSoon {
    if (expirationTime == null) return false;
    final oneHourFromNow = DateTime.now().add(const Duration(hours: 1));
    return expirationTime!.isBefore(oneHourFromNow);
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'keyData': keyData,
      'expirationTime': expirationTime?.millisecondsSinceEpoch,
      'playbackDuration': playbackDuration,
      'renewalUrl': renewalUrl,
      'status': status.name,
    };
  }

  factory DrmLicense.fromMap(Map<String, dynamic> map) {
    return DrmLicense(
      id: map['id'] as String,
      keyData: map['keyData'] as String,
      expirationTime: map['expirationTime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['expirationTime'] as int)
          : null,
      playbackDuration: map['playbackDuration'] as int?,
      renewalUrl: map['renewalUrl'] as String?,
      status: DrmLicenseStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => DrmLicenseStatus.active,
      ),
    );
  }
}

/// DRM license status
enum DrmLicenseStatus {
  /// License is active and valid
  active,

  /// License has expired
  expired,

  /// License is pending acquisition
  pending,

  /// License acquisition failed
  failed,

  /// License has been revoked
  revoked,
}

/// DRM session state
enum DrmSessionState {
  /// DRM session not initialized
  idle,

  /// Acquiring license from server
  acquiringLicense,

  /// License acquired successfully
  licensed,

  /// License renewal in progress
  renewing,

  /// DRM session error
  error,

  /// DRM session closed
  closed,
}

/// DRM session information
class DrmSession {
  /// Session ID
  final String id;

  /// Current state
  final DrmSessionState state;

  /// Associated license
  final DrmLicense? license;

  /// Error message if state is error
  final String? errorMessage;

  /// Session creation time
  final DateTime createdAt;

  /// Last updated time
  final DateTime updatedAt;

  const DrmSession({
    required this.id,
    required this.state,
    this.license,
    this.errorMessage,
    required this.createdAt,
    required this.updatedAt,
  });

  DrmSession copyWith({
    String? id,
    DrmSessionState? state,
    DrmLicense? license,
    String? errorMessage,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DrmSession(
      id: id ?? this.id,
      state: state ?? this.state,
      license: license ?? this.license,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'state': state.name,
      'license': license?.toMap(),
      'errorMessage': errorMessage,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory DrmSession.fromMap(Map<String, dynamic> map) {
    return DrmSession(
      id: map['id'] as String,
      state: DrmSessionState.values.firstWhere(
        (e) => e.name == map['state'],
        orElse: () => DrmSessionState.idle,
      ),
      license: map['license'] != null
          ? DrmLicense.fromMap(map['license'] as Map<String, dynamic>)
          : null,
      errorMessage: map['errorMessage'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int),
    );
  }
}
