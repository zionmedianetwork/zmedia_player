// C-03 (part a): CacheService gains a route from a cached file to actual
// playback — getCachedFileUri()/getCachedMediaItem() — instead of only
// getCachedMedia(), which loads the whole file into memory. These tests
// were verified to FAIL against the pre-change tree (getCachedFileUri and
// getCachedMediaItem did not exist / getCachedMediaItem always returned
// null for a DRM-protected item because the accessors themselves didn't
// exist yet — see task report).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

Uint8List _bytes(int size) => Uint8List(size)..fillRange(0, size, 0x42);

const _plainItem = MediaItem(
  id: 'playback-item-1',
  title: 'Plain item',
  url: 'https://example.com/item1.mp4',
);

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('zmedia_cache_playback_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('CacheService.getCachedFileUri', () {
    test('returns a file:// URI for a cached entry', () async {
      final config = CacheConfig(
        cacheDirectory: tempDir.path,
        cacheExpiration: const Duration(hours: 1),
      );
      final service = CacheService(config);
      await service.initialize();

      await service.cacheMedia('playback-item-1', _bytes(64), _plainItem);

      final uri = await service.getCachedFileUri('playback-item-1');

      expect(uri, isNotNull);
      expect(uri, startsWith('file://'));

      // The URI must resolve to a real, readable file on disk with the
      // bytes that were cached.
      final resolvedPath = Uri.parse(uri!).toFilePath();
      final file = File(resolvedPath);
      expect(await file.exists(), isTrue);
      expect((await file.readAsBytes()).length, 64);

      await service.dispose();
    });

    test('returns null for an absent entry', () async {
      final config = CacheConfig(cacheDirectory: tempDir.path);
      final service = CacheService(config);
      await service.initialize();

      final uri = await service.getCachedFileUri('does-not-exist');

      expect(uri, isNull);

      await service.dispose();
    });

    test('returns null for an expired entry', () async {
      final config = CacheConfig(
        cacheDirectory: tempDir.path,
        cacheExpiration: const Duration(milliseconds: 1),
      );
      final service = CacheService(config);
      await service.initialize();

      await service.cacheMedia('playback-item-1', _bytes(32), _plainItem);

      // Wait just enough for the entry to expire.
      await Future<void>.delayed(const Duration(milliseconds: 5));

      final uri = await service.getCachedFileUri('playback-item-1');

      expect(uri, isNull,
          reason: 'An expired cache entry must not yield a playable URI');

      await service.dispose();
    });
  });

  group('CacheService.getCachedMediaItem', () {
    test('returns a MediaItem pointing at the local file, id/title preserved',
        () async {
      final config = CacheConfig(
        cacheDirectory: tempDir.path,
        cacheExpiration: const Duration(hours: 1),
      );
      final service = CacheService(config);
      await service.initialize();

      await service.cacheMedia('playback-item-1', _bytes(48), _plainItem);

      final cached = await service.getCachedMediaItem('playback-item-1');

      expect(cached, isNotNull);
      expect(cached!.id, _plainItem.id);
      expect(cached.title, _plainItem.title);
      expect(cached.url, startsWith('file://'));
      expect(cached.url, isNot(_plainItem.url));

      await service.dispose();
    });

    test('returns null for an absent entry', () async {
      final config = CacheConfig(cacheDirectory: tempDir.path);
      final service = CacheService(config);
      await service.initialize();

      final cached = await service.getCachedMediaItem('does-not-exist');

      expect(cached, isNull);

      await service.dispose();
    });

    test('returns null for an expired entry', () async {
      final config = CacheConfig(
        cacheDirectory: tempDir.path,
        cacheExpiration: const Duration(milliseconds: 1),
      );
      final service = CacheService(config);
      await service.initialize();

      await service.cacheMedia('playback-item-1', _bytes(32), _plainItem);
      await Future<void>.delayed(const Duration(milliseconds: 5));

      final cached = await service.getCachedMediaItem('playback-item-1');

      expect(cached, isNull);

      await service.dispose();
    });

    test(
        'a cached DRM item is still rejected by validation on the local '
        'playback path (offline DRM is not supported)', () async {
      final drmItem = MediaItem(
        id: 'drm-item-1',
        title: 'DRM item',
        url: 'https://example.com/drm-item.mp4',
        drmConfig: DrmConfig.widevine(
          licenseUrl: 'https://license.example.com/widevine',
        ),
      );

      final config = CacheConfig(
        cacheDirectory: tempDir.path,
        cacheExpiration: const Duration(hours: 1),
      );
      final service = CacheService(config);
      await service.initialize();

      await service.cacheMedia('drm-item-1', _bytes(32), drmItem);

      final cached = await service.getCachedMediaItem('drm-item-1');

      // The cache itself does not — and should not — know about DRM: it
      // hands back a MediaItem with drmConfig preserved and a file:// URL.
      expect(cached, isNotNull);
      expect(cached!.drmConfig, isNotNull);
      expect(cached.url, startsWith('file://'));

      // But the normal validation path this item would go through before
      // playback (MediaController.load()/MediaPlayer.load()) must still
      // reject it: DRM requires an HTTPS media URL, and a cached copy is
      // always file://, so offline DRM playback is correctly impossible.
      expect(
        () => InputValidator.validateMediaItemWithDrm(cached),
        throwsA(isA<ConfigurationException>()),
      );

      await service.dispose();
    });
  });
}
