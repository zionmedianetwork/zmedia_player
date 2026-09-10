import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

void main() {
  group('MediaItem', () {
    test('creates MediaItem with required fields', () {
      final item = MediaItem(
        id: '1',
        title: 'Test Video',
        url: 'https://example.com/video.mp4',
      );

      expect(item.id, '1');
      expect(item.title, 'Test Video');
      expect(item.url, 'https://example.com/video.mp4');
      expect(item.mediaType, MediaType.video);
      expect(item.drmConfig, isNull);
    });

    test('creates MediaItem with DRM configuration', () {
      final drmConfig = DrmConfig.widevine(
        licenseUrl: 'https://example.com/license',
      );

      final item = MediaItem(
        id: '1',
        title: 'Protected Video',
        url: 'https://example.com/video.mpd',
        drmConfig: drmConfig,
      );

      expect(item.drmConfig, isNotNull);
      expect(item.drmConfig?.scheme, DrmScheme.widevine);
      expect(item.drmConfig?.licenseUrl, 'https://example.com/license');
    });

    test('creates MediaItem with all optional fields', () {
      final drmConfig = DrmConfig.fairplay(
        licenseUrl: 'https://example.com/license',
        certificateUrl: 'https://example.com/cert.cer',
      );

      final item = MediaItem(
        id: '1',
        title: 'Complete Video',
        url: 'https://example.com/video.m3u8',
        artist: 'Artist Name',
        album: 'Album Name',
        duration: Duration(minutes: 5),
        artworkUrl: 'https://example.com/art.jpg',
        mimeType: 'application/x-mpegURL',
        httpHeaders: {'Authorization': 'Bearer token'},
        mediaType: MediaType.video,
        drmConfig: drmConfig,
        metadata: {'custom': 'value'},
      );

      expect(item.artist, 'Artist Name');
      expect(item.album, 'Album Name');
      expect(item.duration, Duration(minutes: 5));
      expect(item.artworkUrl, 'https://example.com/art.jpg');
      expect(item.mimeType, 'application/x-mpegURL');
      expect(item.httpHeaders?['Authorization'], 'Bearer token');
      expect(item.drmConfig, isNotNull);
      expect(item.metadata?['custom'], 'value');
    });

    group('Serialization', () {
      test('toMap() includes DRM config', () {
        final drmConfig = DrmConfig.token(
          licenseUrl: 'https://example.com/license',
          token: 'test_token',
        );

        final item = MediaItem(
          id: '1',
          title: 'Test',
          url: 'https://example.com/video.mp4',
          drmConfig: drmConfig,
        );

        final map = item.toMap();

        expect(map['id'], '1');
        expect(map['title'], 'Test');
        expect(map['url'], 'https://example.com/video.mp4');
        expect(map['drmConfig'], isNotNull);
        expect(map['drmConfig']['scheme'], 'token');
        expect(map['drmConfig']['licenseUrl'], 'https://example.com/license');
      });

      test('fromMap() deserializes DRM config', () {
        final map = {
          'id': '1',
          'title': 'Test',
          'url': 'https://example.com/video.mp4',
          'mediaType': 'video',
          'drmConfig': {
            'scheme': 'widevine',
            'licenseUrl': 'https://example.com/license',
          },
        };

        final item = MediaItem.fromMap(map);

        expect(item.id, '1');
        expect(item.drmConfig, isNotNull);
        expect(item.drmConfig?.scheme, DrmScheme.widevine);
        expect(item.drmConfig?.licenseUrl, 'https://example.com/license');
      });

      test('round-trip serialization with DRM preserves data', () {
        final drmConfig = DrmConfig.fairplay(
          licenseUrl: 'https://example.com/license',
          certificateUrl: 'https://example.com/cert.cer',
          contentId: 'content123',
        );

        final original = MediaItem(
          id: '1',
          title: 'Test Video',
          url: 'https://example.com/video.m3u8',
          drmConfig: drmConfig,
          httpHeaders: {'Auth': 'Bearer token'},
        );

        final map = original.toMap();
        final deserialized = MediaItem.fromMap(map);

        expect(deserialized.id, original.id);
        expect(deserialized.title, original.title);
        expect(deserialized.url, original.url);
        expect(deserialized.drmConfig?.scheme, original.drmConfig?.scheme);
        expect(
          deserialized.drmConfig?.licenseUrl,
          original.drmConfig?.licenseUrl,
        );
        expect(
          deserialized.drmConfig?.certificateUrl,
          original.drmConfig?.certificateUrl,
        );
      });
    });

    group('httpHeaders serialization', () {
      /// Issue #127 companion. Be clear about what this does and does not
      /// prove: it passes today, and it passed *before* the Android fix too,
      /// because every test in this suite mocks the `MethodChannel` — the
      /// Dart side has always serialized every header faithfully, and it was
      /// Android's `MediaPlayerManager.loadMediaItem` that then dropped all
      /// but the last one when handing them to
      /// `DefaultHttpDataSource.Factory.setDefaultRequestProperties`. The
      /// actual guard for #127 is
      /// `test/native_contract/android_http_headers_test.dart`, which parses
      /// the Kotlin source. This test exists to pin the Dart half of the
      /// contract so a future regression can be localised to one side or the
      /// other.
      test('toMap round-trips every header, not just the last one', () {
        const headers = {
          'Authorization': 'Bearer token',
          'Referer': 'https://example.com/',
          'X-Custom': 'custom-value',
          'Cookie': 'CloudFront-Signature=abc',
        };

        final item = MediaItem(
          id: '1',
          title: 'Test Video',
          url: 'https://example.com/video.m3u8',
          httpHeaders: headers,
        );

        final serialized = item.toMap()['httpHeaders'] as Map<String, String>;

        expect(serialized, hasLength(headers.length));
        expect(serialized, equals(headers));
      });

      test('fromMap restores every header', () {
        const headers = {
          'Authorization': 'Bearer token',
          'Referer': 'https://example.com/',
          'X-Custom': 'custom-value',
        };

        final restored = MediaItem.fromMap(
          MediaItem(
            id: '1',
            title: 'Test Video',
            url: 'https://example.com/video.m3u8',
            httpHeaders: headers,
          ).toMap(),
        );

        expect(restored.httpHeaders, equals(headers));
      });
    });

    group('copyWith', () {
      test('can update DRM config', () {
        final original = MediaItem(
          id: '1',
          title: 'Test',
          url: 'https://example.com/video.mp4',
        );

        final drmConfig = DrmConfig.widevine(
          licenseUrl: 'https://example.com/license',
        );

        final modified = original.copyWith(drmConfig: drmConfig);

        expect(modified.id, original.id);
        expect(modified.title, original.title);
        expect(modified.drmConfig, isNotNull);
        expect(modified.drmConfig?.scheme, DrmScheme.widevine);
      });

      test('can replace DRM config', () {
        final oldDrm = DrmConfig.widevine(
          licenseUrl: 'https://old.com/license',
        );

        final original = MediaItem(
          id: '1',
          title: 'Test',
          url: 'https://example.com/video.mp4',
          drmConfig: oldDrm,
        );

        final newDrm = DrmConfig.fairplay(
          licenseUrl: 'https://new.com/license',
          certificateUrl: 'https://new.com/cert.cer',
        );

        final modified = original.copyWith(drmConfig: newDrm);

        expect(modified.drmConfig?.scheme, DrmScheme.fairplay);
        expect(modified.drmConfig?.licenseUrl, 'https://new.com/license');
      });
    });

    group('Equality', () {
      test('MediaItems with same id are equal', () {
        final item1 = MediaItem(
          id: '1',
          title: 'Test',
          url: 'https://example.com/video.mp4',
        );

        final item2 = MediaItem(
          id: '1',
          title: 'Different Title',
          url: 'https://different.com/video.mp4',
        );

        expect(item1, equals(item2));
        expect(item1.hashCode, equals(item2.hashCode));
      });

      test('MediaItems with different ids are not equal', () {
        final item1 = MediaItem(
          id: '1',
          title: 'Test',
          url: 'https://example.com/video.mp4',
        );

        final item2 = MediaItem(
          id: '2',
          title: 'Test',
          url: 'https://example.com/video.mp4',
        );

        expect(item1, isNot(equals(item2)));
      });
    });
  });
}
