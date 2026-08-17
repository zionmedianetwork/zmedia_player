import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

/// Tests for C-02 Stage 1 — local file playback.
///
/// `InputValidator.validateUrl` gained support for `file://` media URLs so
/// that a `MediaItem` can point at a file on the local filesystem. This must
/// hold without weakening any existing rule:
///   - `file://` is only accepted when `requireHttps` is NOT set (i.e. never
///     for a DRM license/certificate URL).
///   - `javascript:`/`data:` schemes remain rejected.
///   - Path-traversal segments (including percent-encoded ones) inside a
///     `file://` URL are rejected.
///   - A `file://` URL with a host component (`file://host/path`) is
///     rejected — this validator only supports local, single-machine paths.
void main() {
  group('InputValidator.validateUrl — file:// media URLs', () {
    test('accepts a well-formed file:// URL', () {
      expect(
        () => InputValidator.validateUrl('file:///var/mobile/Media/clip.mp4'),
        returnsNormally,
      );
    });

    test('accepts a file:// URL built via LocalMediaUtils.fileUri', () {
      final url = LocalMediaUtils.fileUri('/data/user/0/app/files/clip.mp4');
      expect(url, startsWith('file://'));
      expect(() => InputValidator.validateUrl(url), returnsNormally);
    });

    test('accepts a file:// URL whose path has percent-encoded spaces', () {
      expect(
        () => InputValidator.validateUrl(
          'file:///var/mobile/Media/My%20Clip.mp4',
        ),
        returnsNormally,
      );
    });

    test('rejects a file:// URL with an empty path', () {
      expect(
        () => InputValidator.validateUrl('file://'),
        throwsA(isA<ConfigurationException>()),
      );
    });

    test('rejects a file:// URL with a host component', () {
      expect(
        () => InputValidator.validateUrl('file://host/share/clip.mp4'),
        throwsA(isA<ConfigurationException>()),
      );
    });

    test('rejects a file:// URL with a ".." traversal segment', () {
      expect(
        () => InputValidator.validateUrl(
          'file:///var/mobile/Media/../../etc/passwd',
        ),
        throwsA(isA<ConfigurationException>()),
      );
    });

    test('rejects a file:// URL with a percent-encoded ".." segment', () {
      expect(
        () => InputValidator.validateUrl(
          'file:///var/mobile/%2e%2e/%2e%2e/etc/passwd',
        ),
        throwsA(isA<ConfigurationException>()),
      );
    });

    test('rejects a file:// URL with a "." segment', () {
      expect(
        () => InputValidator.validateUrl('file:///var/mobile/./clip.mp4'),
        throwsA(isA<ConfigurationException>()),
      );
    });

    test('rejects a file:// URL with an encoded separator inside a segment',
        () {
      expect(
        () => InputValidator.validateUrl(
          'file:///var/mobile/etc%2fpasswd',
        ),
        throwsA(isA<ConfigurationException>()),
      );
    });

    test('rejects file:// when requireHttps is set', () {
      expect(
        () => InputValidator.validateUrl(
          'file:///var/mobile/Media/clip.mp4',
          requireHttps: true,
        ),
        throwsA(isA<ConfigurationException>()),
      );
    });

    test('javascript: scheme is still rejected', () {
      expect(
        () => InputValidator.validateUrl('javascript:alert(1)'),
        throwsA(isA<ConfigurationException>()),
      );
    });

    test('data: scheme is still rejected', () {
      expect(
        () => InputValidator.validateUrl(
          'data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==',
        ),
        throwsA(isA<ConfigurationException>()),
      );
    });

    test('http/https/rtmp/rtsp remain accepted', () {
      expect(() => InputValidator.validateUrl('https://cdn.example.com/a.mp4'),
          returnsNormally);
      expect(() => InputValidator.validateUrl('http://cdn.example.com/a.mp4'),
          returnsNormally);
      expect(() => InputValidator.validateUrl('rtmp://cdn.example.com/live'),
          returnsNormally);
      expect(() => InputValidator.validateUrl('rtsp://cdn.example.com/live'),
          returnsNormally);
    });
  });

  group(
      'InputValidator.validateMediaItemWithDrm — local DRM must stay '
      'rejected', () {
    test('a local (file://) DRM license URL is still rejected', () {
      const localLicenseConfig = DrmConfig(
        scheme: DrmScheme.widevine,
        licenseUrl: 'file:///var/mobile/Media/license.bin',
      );
      final item = MediaItem(
        id: 'local-drm-license',
        title: 'Protected',
        url: 'https://cdn.example.com/protected.mpd',
        drmConfig: localLicenseConfig,
      );

      expect(
        () => InputValidator.validateMediaItemWithDrm(item),
        throwsA(isA<ConfigurationException>()),
        reason: 'A local license URL must never be accepted, even though '
            'local media URLs now are',
      );
    });

    test('a local (file://) FairPlay certificate URL is still rejected', () {
      const localCertConfig = DrmConfig(
        scheme: DrmScheme.fairplay,
        licenseUrl: 'https://license.example.com/fairplay',
        certificateUrl: 'file:///var/mobile/Media/cert.der',
      );
      final item = MediaItem(
        id: 'local-drm-cert',
        title: 'Protected',
        url: 'https://cdn.example.com/protected.m3u8',
        drmConfig: localCertConfig,
      );

      expect(
        () => InputValidator.validateMediaItemWithDrm(item),
        throwsA(isA<ConfigurationException>()),
      );
    });

    test('a DRM item with a local (file://) media URL is still rejected', () {
      // DRM always requires the media URL itself to be HTTPS (see
      // validateMediaItemWithDrm) — offline/local DRM playback is out of
      // scope for this stage, so this combination must remain blocked.
      const widevineConfig = DrmConfig(
        scheme: DrmScheme.widevine,
        licenseUrl: 'https://license.example.com/widevine',
      );
      final item = MediaItem(
        id: 'local-media-with-drm',
        title: 'Protected local file',
        url: 'file:///var/mobile/Media/protected.mp4',
        drmConfig: widevineConfig,
      );

      expect(
        () => InputValidator.validateMediaItemWithDrm(item),
        throwsA(isA<ConfigurationException>()),
      );
    });

    test('a non-DRM item with a local (file://) media URL is unaffected', () {
      final item = MediaItem(
        id: 'local-media-no-drm',
        title: 'Local clip',
        url: 'file:///var/mobile/Media/clip.mp4',
      );

      expect(
        () => InputValidator.validateMediaItemWithDrm(item),
        returnsNormally,
      );
    });
  });
}
