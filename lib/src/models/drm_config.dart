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

  /// Whether to allow offline playback
  final bool allowOffline;

  /// Offline license duration in seconds
  final int? offlineLicenseDuration;

  /// Whether to automatically renew licenses
  final bool autoRenewLicense;

  /// Custom license request data
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

  const DrmConfig({
    required this.scheme,
    required this.licenseUrl,
    this.certificateUrl,
    this.headers,
    this.token,
    this.keyId,
    this.contentId,
    this.allowOffline = false,
    this.offlineLicenseDuration,
    this.autoRenewLicense = true,
    this.customData,
    this.ezdrmConfig,
    this.certificatePinning,
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
    bool allowOffline = false,
    int? offlineLicenseDuration,
    Map<String, dynamic>? customData,
    CertificatePinningConfig? certificatePinning,
  }) {
    return DrmConfig(
      scheme: DrmScheme.widevine,
      licenseUrl: licenseUrl,
      headers: headers,
      allowOffline: allowOffline,
      offlineLicenseDuration: offlineLicenseDuration,
      customData: customData,
      certificatePinning: certificatePinning,
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
    bool allowOffline = false,
    CertificatePinningConfig? certificatePinning,
  }) {
    return DrmConfig(
      scheme: DrmScheme.ezdrm,
      licenseUrl: ezdrmConfig.licenseUrl,
      certificateUrl: ezdrmConfig.certificateUrl,
      headers: ezdrmConfig.headers,
      allowOffline: allowOffline,
      ezdrmConfig: ezdrmConfig,
      certificatePinning: certificatePinning,
    );
  }

  /// Convert to map for platform channel
  Map<String, dynamic> toMap() {
    return {
      'scheme': scheme.name,
      'licenseUrl': licenseUrl,
      'certificateUrl': certificateUrl,
      'headers': headers,
      'token': token,
      'keyId': keyId,
      'contentId': contentId,
      'allowOffline': allowOffline,
      'offlineLicenseDuration': offlineLicenseDuration,
      'autoRenewLicense': autoRenewLicense,
      'customData': customData,
      'ezdrmConfig': ezdrmConfig?.toMap(),
      'certificatePinning': certificatePinning?.toMap(),
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
      allowOffline: map['allowOffline'] as bool? ?? false,
      offlineLicenseDuration: map['offlineLicenseDuration'] as int?,
      autoRenewLicense: map['autoRenewLicense'] as bool? ?? true,
      customData: map['customData'] as Map<String, dynamic>?,
      ezdrmConfig: map['ezdrmConfig'] != null
          ? EzdrmConfig.fromMap(map['ezdrmConfig'] as Map<String, dynamic>)
          : null,
      certificatePinning: pinning,
    );
  }

  DrmConfig copyWith({
    DrmScheme? scheme,
    String? licenseUrl,
    String? certificateUrl,
    Map<String, String>? headers,
    String? token,
    String? keyId,
    String? contentId,
    bool? allowOffline,
    int? offlineLicenseDuration,
    bool? autoRenewLicense,
    Map<String, dynamic>? customData,
    EzdrmConfig? ezdrmConfig,
    CertificatePinningConfig? certificatePinning,
  }) {
    return DrmConfig(
      scheme: scheme ?? this.scheme,
      licenseUrl: licenseUrl ?? this.licenseUrl,
      certificateUrl: certificateUrl ?? this.certificateUrl,
      headers: headers ?? this.headers,
      token: token ?? this.token,
      keyId: keyId ?? this.keyId,
      contentId: contentId ?? this.contentId,
      allowOffline: allowOffline ?? this.allowOffline,
      offlineLicenseDuration:
          offlineLicenseDuration ?? this.offlineLicenseDuration,
      autoRenewLicense: autoRenewLicense ?? this.autoRenewLicense,
      customData: customData ?? this.customData,
      ezdrmConfig: ezdrmConfig ?? this.ezdrmConfig,
      certificatePinning: certificatePinning ?? this.certificatePinning,
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
