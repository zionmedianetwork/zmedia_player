import 'package:zmedia_player/zmedia_player.dart';

/// Mock DRM configurations for testing
class MockDrmConfigs {
  static DrmConfig get widevine => DrmConfig.widevine(
        licenseUrl: 'https://test-license-server.com/widevine',
        headers: {'X-Test-Header': 'test-value'},
      );

  static DrmConfig get fairplay => DrmConfig.fairplay(
        licenseUrl: 'https://test-license-server.com/fairplay',
        certificateUrl: 'https://test-server.com/certificate.cer',
        contentId: 'test-content-id',
      );

  static DrmConfig get tokenBased => DrmConfig.token(
        licenseUrl: 'https://test-license-server.com/license',
        token: 'test-jwt-token-12345',
        keyId: 'test-key-id',
      );

  static DrmConfig get clearkey => const DrmConfig(
        scheme: DrmScheme.clearkey,
        licenseUrl: 'https://test-clearkey-server.com/license',
      );

  static DrmConfig get ezdrm => DrmConfig.ezdrm(
        ezdrmConfig: EzdrmConfig.widevine(
          customerId: 'test-customer-123',
          apiKey: 'test-api-key',
          contentId: 'test-content',
        ),
      );
}

/// Mock media items for testing
class MockMediaItems {
  static MediaItem get plainVideo => const MediaItem(
        id: 'plain-video-1',
        title: 'Plain Test Video',
        url: 'https://test-cdn.com/video.mp4',
        mediaType: MediaType.video,
      );

  static MediaItem get widevineProtected => MediaItem(
        id: 'drm-video-widevine',
        title: 'Widevine Protected Video',
        url: 'https://test-cdn.com/protected.mpd',
        drmConfig: MockDrmConfigs.widevine,
        mediaType: MediaType.video,
      );

  static MediaItem get fairplayProtected => MediaItem(
        id: 'drm-video-fairplay',
        title: 'FairPlay Protected Video',
        url: 'https://test-cdn.com/protected.m3u8',
        drmConfig: MockDrmConfigs.fairplay,
        mediaType: MediaType.video,
      );

  static MediaItem get tokenProtected => MediaItem(
        id: 'drm-video-token',
        title: 'Token Protected Video',
        url: 'https://test-cdn.com/protected.mp4',
        drmConfig: MockDrmConfigs.tokenBased,
        mediaType: MediaType.video,
      );

  static MediaItem get withMetadata => MediaItem(
        id: 'video-with-metadata',
        title: 'Video With Complete Metadata',
        url: 'https://test-cdn.com/video.mp4',
        artist: 'Test Artist',
        album: 'Test Album',
        duration: const Duration(minutes: 10),
        artworkUrl: 'https://test-cdn.com/artwork.jpg',
        httpHeaders: {'Authorization': 'Bearer test-token'},
        metadata: {
          'genre': 'Test',
          'year': 2024,
        },
      );

  static List<MediaItem> get playlist => [
        plainVideo,
        widevineProtected,
        fairplayProtected,
      ];
}

/// Mock DRM licenses for testing
class MockDrmLicenses {
  static DrmLicense get active => DrmLicense(
        id: 'license-active-123',
        keyData: 'mock-encrypted-key-data',
        expirationTime: DateTime.now().add(const Duration(days: 30)),
        playbackDuration: 7200,
        status: DrmLicenseStatus.active,
      );

  static DrmLicense get expired => DrmLicense(
        id: 'license-expired-456',
        keyData: 'mock-expired-key-data',
        expirationTime: DateTime.now().subtract(const Duration(days: 1)),
        status: DrmLicenseStatus.expired,
      );

  static DrmLicense get expiringSoon => DrmLicense(
        id: 'license-expiring-789',
        keyData: 'mock-expiring-key-data',
        expirationTime: DateTime.now().add(const Duration(minutes: 30)),
        status: DrmLicenseStatus.active,
      );

  static DrmLicense get pending => const DrmLicense(
        id: 'license-pending-101',
        keyData: '',
        status: DrmLicenseStatus.pending,
      );

  static DrmLicense get failed => const DrmLicense(
        id: 'license-failed-102',
        keyData: '',
        status: DrmLicenseStatus.failed,
      );
}

/// Mock DRM sessions for testing
class MockDrmSessions {
  static DrmSession get idle {
    final now = DateTime.now();
    return DrmSession(
      id: 'session-idle-1',
      state: DrmSessionState.idle,
      createdAt: now,
      updatedAt: now,
    );
  }

  static DrmSession get acquiringLicense {
    final now = DateTime.now();
    return DrmSession(
      id: 'session-acquiring-2',
      state: DrmSessionState.acquiringLicense,
      createdAt: now.subtract(const Duration(seconds: 5)),
      updatedAt: now,
    );
  }

  static DrmSession get licensed {
    final now = DateTime.now();
    return DrmSession(
      id: 'session-licensed-3',
      state: DrmSessionState.licensed,
      license: MockDrmLicenses.active,
      createdAt: now.subtract(const Duration(minutes: 5)),
      updatedAt: now,
    );
  }

  static DrmSession get renewing {
    final now = DateTime.now();
    return DrmSession(
      id: 'session-renewing-4',
      state: DrmSessionState.renewing,
      license: MockDrmLicenses.expiringSoon,
      createdAt: now.subtract(const Duration(hours: 1)),
      updatedAt: now,
    );
  }

  static DrmSession get error {
    final now = DateTime.now();
    return DrmSession(
      id: 'session-error-5',
      state: DrmSessionState.error,
      errorMessage: 'Mock license acquisition error',
      createdAt: now.subtract(const Duration(seconds: 30)),
      updatedAt: now,
    );
  }

  static DrmSession get closed {
    final now = DateTime.now();
    return DrmSession(
      id: 'session-closed-6',
      state: DrmSessionState.closed,
      createdAt: now.subtract(const Duration(hours: 2)),
      updatedAt: now,
    );
  }
}

/// Mock cast devices for testing
class MockCastDevices {
  static CastDevice get chromecast => const CastDevice(
        id: 'chromecast-living-room',
        name: 'Living Room TV',
        type: CastDeviceType.chromecast,
        isConnected: false,
      );

  static CastDevice get airplay => const CastDevice(
        id: 'airplay-apple-tv',
        name: 'Apple TV',
        type: CastDeviceType.airplay,
        isConnected: false,
      );

  static CastDevice get connected => const CastDevice(
        id: 'device-connected',
        name: 'Connected Device',
        type: CastDeviceType.chromecast,
        isConnected: true,
      );

  static List<CastDevice> get all => [
        chromecast,
        airplay,
      ];
}

/// Test helpers
class TestHelpers {
  /// Create a test EZDRM config
  static EzdrmConfig createEzdrmConfig({
    String customerId = 'test-customer',
    String apiKey = 'test-api-key',
    String contentId = 'test-content',
    bool isWidevine = true,
    String? certificateUrl,
  }) {
    return EzdrmConfig(
      customerId: customerId,
      apiKey: apiKey,
      contentId: contentId,
      isWidevine: isWidevine,
      isFairPlay: !isWidevine,
      certificateUrl:
          !isWidevine ? (certificateUrl ?? 'https://test.com/cert.cer') : null,
    );
  }

  /// Create a test DRM config with custom parameters
  static DrmConfig createDrmConfig({
    DrmScheme scheme = DrmScheme.widevine,
    String? licenseUrl,
    String? certificateUrl,
    Map<String, String>? headers,
    String? token,
  }) {
    return DrmConfig(
      scheme: scheme,
      licenseUrl: licenseUrl ?? 'https://test.com/license',
      certificateUrl: certificateUrl,
      headers: headers,
      token: token,
    );
  }

  /// Create a test media item with custom DRM
  static MediaItem createProtectedMediaItem({
    required String id,
    required String title,
    required String url,
    DrmConfig? drmConfig,
  }) {
    return MediaItem(
      id: id,
      title: title,
      url: url,
      drmConfig: drmConfig ?? MockDrmConfigs.widevine,
    );
  }

  /// Simulate license expiration time scenarios
  static DateTime expirationInFuture(Duration duration) {
    return DateTime.now().add(duration);
  }

  static DateTime expirationInPast(Duration duration) {
    return DateTime.now().subtract(duration);
  }

  /// Validate DRM configuration
  static bool isValidDrmConfig(DrmConfig config) {
    if (config.licenseUrl.isEmpty) return false;
    if (config.scheme == DrmScheme.fairplay && config.certificateUrl == null) {
      return false;
    }
    return true;
  }
}
