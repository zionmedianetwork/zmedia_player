import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

/// Tests for Fix 1: HTTPS enforcement for DRM-protected MediaItems.
///
/// InputValidator.validateMediaItemWithDrm() must:
///   - throw ConfigurationException when a DRM item has an http:// media URL
///   - pass when a DRM item has an https:// media URL
///   - pass for non-DRM items regardless of the URL scheme
void main() {
  // Minimal valid DRM config (Widevine, HTTPS license URL)
  const widevineConfig = DrmConfig(
    scheme: DrmScheme.widevine,
    licenseUrl: 'https://license.example.com/widevine',
  );

  group('InputValidator.validateMediaItemWithDrm', () {
    test('throws ConfigurationException for http:// media URL with DRM', () {
      final item = MediaItem(
        id: 'drm-item-1',
        title: 'Protected Video',
        url: 'http://media.example.com/video.mpd',
        drmConfig: widevineConfig,
      );

      expect(
        () => InputValidator.validateMediaItemWithDrm(item),
        throwsA(isA<ConfigurationException>()),
        reason: 'http:// media URL with DRM must be rejected',
      );
    });

    test('does not throw for https:// media URL with DRM', () {
      final item = MediaItem(
        id: 'drm-item-2',
        title: 'Protected Video',
        url: 'https://media.example.com/video.mpd',
        drmConfig: widevineConfig,
      );

      expect(
        () => InputValidator.validateMediaItemWithDrm(item),
        returnsNormally,
        reason: 'https:// media URL with DRM must pass',
      );
    });

    test('does not throw for non-DRM item with http:// URL', () {
      const item = MediaItem(
        id: 'plain-item',
        title: 'Unprotected Video',
        url: 'http://media.example.com/video.mp4',
        // No drmConfig — must not be affected by HTTPS check
      );

      expect(
        () => InputValidator.validateMediaItemWithDrm(item),
        returnsNormally,
        reason: 'http:// URL is fine when there is no DRM config',
      );
    });

    test('does not throw for non-DRM item with https:// URL', () {
      const item = MediaItem(
        id: 'plain-item-https',
        title: 'Unprotected Video',
        url: 'https://media.example.com/video.mp4',
      );

      expect(
        () => InputValidator.validateMediaItemWithDrm(item),
        returnsNormally,
      );
    });

    test('error message mentions HTTPS when DRM item has http:// URL', () {
      final item = MediaItem(
        id: 'drm-item-err',
        title: 'Protected Video',
        url: 'http://media.example.com/video.mpd',
        drmConfig: widevineConfig,
      );

      expect(
        () => InputValidator.validateMediaItemWithDrm(item),
        throwsA(
          isA<ConfigurationException>().having(
            (e) => e.toString().toLowerCase(),
            'message',
            contains('https'),
          ),
        ),
      );
    });

    test('also rejects when DRM license URL itself is http://', () {
      const insecureDrmConfig = DrmConfig(
        scheme: DrmScheme.widevine,
        licenseUrl: 'http://license.example.com/widevine',
      );
      final item = MediaItem(
        id: 'drm-item-bad-license',
        title: 'Protected Video',
        url: 'https://media.example.com/video.mpd',
        drmConfig: insecureDrmConfig,
      );

      // validateDrmConfig inside validateMediaItemWithDrm must catch this.
      expect(
        () => InputValidator.validateMediaItemWithDrm(item),
        throwsA(isA<ConfigurationException>()),
        reason: 'An http:// license URL must also be rejected',
      );
    });

    test('FairPlay requires certificate URL; missing cert is rejected', () {
      const fairplayMissingCert = DrmConfig(
        scheme: DrmScheme.fairplay,
        licenseUrl: 'https://license.example.com/fairplay',
        // certificateUrl intentionally omitted
      );
      final item = MediaItem(
        id: 'fp-item',
        title: 'FairPlay Video',
        url: 'https://media.example.com/video.m3u8',
        drmConfig: fairplayMissingCert,
      );

      expect(
        () => InputValidator.validateMediaItemWithDrm(item),
        throwsA(isA<ConfigurationException>()),
      );
    });
  });
}
