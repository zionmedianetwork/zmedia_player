/// Configuration for Digital Rights Management (DRM)
class DrmConfig {
  /// Type of DRM protection
  final DrmType type;

  /// License server URL
  final String licenseUrl;

  /// Authentication token for license requests
  final String? token;

  /// Additional headers for license requests
  final Map<String, String>? headers;

  /// Certificate data for FairPlay (iOS)
  final String? certificateUrl;

  /// Key system identifier
  final String? keySystem;

  /// Additional DRM-specific configuration
  final Map<String, dynamic>? config;

  const DrmConfig({
    required this.type,
    required this.licenseUrl,
    this.token,
    this.headers,
    this.certificateUrl,
    this.keySystem,
    this.config,
  });

  /// Creates a copy of this DRM config with updated values
  DrmConfig copyWith({
    DrmType? type,
    String? licenseUrl,
    String? token,
    Map<String, String>? headers,
    String? certificateUrl,
    String? keySystem,
    Map<String, dynamic>? config,
  }) {
    return DrmConfig(
      type: type ?? this.type,
      licenseUrl: licenseUrl ?? this.licenseUrl,
      token: token ?? this.token,
      headers: headers ?? this.headers,
      certificateUrl: certificateUrl ?? this.certificateUrl,
      keySystem: keySystem ?? this.keySystem,
      config: config ?? this.config,
    );
  }

  /// Converts the DRM config to a map for serialization
  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'licenseUrl': licenseUrl,
      'token': token,
      'headers': headers,
      'certificateUrl': certificateUrl,
      'keySystem': keySystem,
      'config': config,
    };
  }

  /// Creates a DRM config from a map
  factory DrmConfig.fromMap(Map<String, dynamic> map) {
    return DrmConfig(
      type: DrmType.values.firstWhere(
        (type) => type.name == map['type'],
        orElse: () => DrmType.none,
      ),
      licenseUrl: map['licenseUrl'] as String,
      token: map['token'] as String?,
      headers: map['headers'] != null
          ? Map<String, String>.from(map['headers'] as Map)
          : null,
      certificateUrl: map['certificateUrl'] as String?,
      keySystem: map['keySystem'] as String?,
      config: map['config'] as Map<String, dynamic>?,
    );
  }

  /// Factory constructor for Widevine DRM (Android)
  factory DrmConfig.widevine({
    required String licenseUrl,
    String? token,
    Map<String, String>? headers,
    Map<String, dynamic>? config,
  }) {
    return DrmConfig(
      type: DrmType.widevine,
      licenseUrl: licenseUrl,
      token: token,
      headers: headers,
      keySystem: 'com.widevine.alpha',
      config: config,
    );
  }

  /// Factory constructor for FairPlay DRM (iOS)
  factory DrmConfig.fairPlay({
    required String licenseUrl,
    required String certificateUrl,
    String? token,
    Map<String, String>? headers,
    Map<String, dynamic>? config,
  }) {
    return DrmConfig(
      type: DrmType.fairPlay,
      licenseUrl: licenseUrl,
      certificateUrl: certificateUrl,
      token: token,
      headers: headers,
      keySystem: 'com.apple.fps.1_0',
      config: config,
    );
  }

  /// Factory constructor for token-based DRM
  factory DrmConfig.token({
    required String licenseUrl,
    required String token,
    Map<String, String>? headers,
    Map<String, dynamic>? config,
  }) {
    return DrmConfig(
      type: DrmType.token,
      licenseUrl: licenseUrl,
      token: token,
      headers: headers,
      config: config,
    );
  }

  /// Factory constructor for EZDRM
  factory DrmConfig.ezdrm({
    required String licenseUrl,
    String? token,
    Map<String, String>? headers,
    Map<String, dynamic>? config,
  }) {
    return DrmConfig(
      type: DrmType.ezdrm,
      licenseUrl: licenseUrl,
      token: token,
      headers: headers,
      config: config,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DrmConfig &&
        other.type == type &&
        other.licenseUrl == licenseUrl &&
        other.token == token &&
        other.certificateUrl == certificateUrl &&
        other.keySystem == keySystem;
  }

  @override
  int get hashCode {
    return Object.hash(
      type,
      licenseUrl,
      token,
      certificateUrl,
      keySystem,
    );
  }

  @override
  String toString() {
    return 'DrmConfig(type: $type, licenseUrl: $licenseUrl, keySystem: $keySystem)';
  }
}

/// Types of DRM protection
enum DrmType {
  /// No DRM protection
  none,

  /// Widevine DRM (Google - Android)
  widevine,

  /// FairPlay DRM (Apple - iOS)
  fairPlay,

  /// Token-based DRM
  token,

  /// EZDRM service
  ezdrm,
}
