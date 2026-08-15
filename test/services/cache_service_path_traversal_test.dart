// M-08 regression coverage: CacheService.cacheMedia (and the streaming
// download path, _downloadAndCacheToFile) previously interpolated a
// caller-supplied `mediaId` directly into an on-disk cache filename with no
// sanitisation, so a malicious/unexpected id (`../`, an absolute path, or
// one containing a null byte) could escape the intended cache directory.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zmedia_player/zmedia_player.dart';

void main() {
  group('CacheService.cacheMedia — path traversal (M-08)', () {
    late Directory tempDir;
    late Directory parentDir;

    setUp(() async {
      parentDir = await Directory.systemTemp.createTemp('zmedia_pt_parent_');
      tempDir = Directory('${parentDir.path}/cache');
      await tempDir.create();
    });

    tearDown(() async {
      if (await parentDir.exists()) {
        await parentDir.delete(recursive: true);
      }
    });

    /// Every file directly inside [dir] (non-recursive), by name.
    Future<List<String>> entriesOf(Directory dir) async {
      if (!await dir.exists()) return [];
      final entries = await dir.list().toList();
      return entries.map((e) => e.path.split('/').last).toList();
    }

    test('"../" segments in mediaId cannot escape the cache directory',
        () async {
      final service = CacheService(CacheConfig(cacheDirectory: tempDir.path));
      await service.initialize();

      const maliciousId = '../../evil';
      final data = Uint8List.fromList([1, 2, 3, 4]);
      const item = MediaItem(
        id: maliciousId,
        title: 'Evil',
        url: 'https://cdn.example.com/evil.mp4',
      );

      await service.cacheMedia(maliciousId, data, item);

      // Nothing must have been written outside the cache directory: the
      // parent directory (one level above the cache dir) must contain only
      // the cache dir itself.
      final parentEntries = await entriesOf(parentDir);
      expect(parentEntries, equals(['cache']),
          reason: 'No file may be written outside the cache directory');

      // The cache dir itself must contain a file, and it must not have
      // grabbed a literal ".." component into its name.
      final cacheEntries = await entriesOf(tempDir);
      expect(cacheEntries, isNotEmpty);
      for (final name in cacheEntries) {
        expect(name, isNot(contains('..')));
        expect(name, isNot(contains('/')));
      }
    });

    test('absolute-path mediaId cannot escape the cache directory', () async {
      final service = CacheService(CacheConfig(cacheDirectory: tempDir.path));
      await service.initialize();

      // An absolute path elsewhere on disk that must never be written to.
      final targetOutside = File('${parentDir.path}/should-not-exist.cache');

      const maliciousId = '/etc/passwd';
      final data = Uint8List.fromList([9, 9, 9]);
      const item = MediaItem(
        id: maliciousId,
        title: 'Absolute path',
        url: 'https://cdn.example.com/x.mp4',
      );

      await service.cacheMedia(maliciousId, data, item);

      expect(await targetOutside.exists(), isFalse);
      final parentEntries = await entriesOf(parentDir);
      expect(parentEntries, equals(['cache']));
    });

    test('null byte in mediaId is rejected outright', () async {
      final service = CacheService(CacheConfig(cacheDirectory: tempDir.path));
      await service.initialize();

      const maliciousId = 'evil\x00.txt';
      final data = Uint8List.fromList([1]);
      const item = MediaItem(
        id: maliciousId,
        title: 'Null byte',
        url: 'https://cdn.example.com/x.mp4',
      );

      await expectLater(
        service.cacheMedia(maliciousId, data, item),
        throwsA(isA<CacheException>()),
      );
    });

    test(
        'cached data with a traversal-style id remains retrievable via '
        'the original (unsanitized) mediaId', () async {
      final service = CacheService(CacheConfig(cacheDirectory: tempDir.path));
      await service.initialize();

      const maliciousId = '../sneaky';
      final data = Uint8List.fromList([5, 6, 7]);
      const item = MediaItem(
        id: maliciousId,
        title: 'Sneaky',
        url: 'https://cdn.example.com/sneaky.mp4',
      );

      await service.cacheMedia(maliciousId, data, item);

      expect(await service.isCached(maliciousId), isTrue);
      final cached = await service.getCachedMedia(maliciousId);
      expect(cached, equals(data));
    });
  });

  group('CacheService.downloadAndCache — path traversal (M-08)', () {
    late Directory tempDir;
    late Directory parentDir;

    setUp(() async {
      parentDir =
          await Directory.systemTemp.createTemp('zmedia_pt_stream_parent_');
      tempDir = Directory('${parentDir.path}/cache');
      await tempDir.create();
    });

    tearDown(() async {
      if (await parentDir.exists()) {
        await parentDir.delete(recursive: true);
      }
    });

    Future<List<String>> entriesOf(Directory dir) async {
      if (!await dir.exists()) return [];
      final entries = await dir.list().toList();
      return entries.map((e) => e.path.split('/').last).toList();
    }

    test(
        '"../" segments in a downloaded item id cannot escape the cache '
        'directory', () async {
      final client = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.value([1, 2, 3]),
          200,
          contentLength: 3,
        );
      });

      final service = CacheService(
        CacheConfig(cacheDirectory: tempDir.path),
        httpClientFactory: () => client,
      );
      await service.initialize();

      const maliciousId = '../../escaped';
      const item = MediaItem(
        id: maliciousId,
        title: 'Escaped',
        url: 'https://cdn.example.com/escaped.mp4',
      );

      await service.downloadAndCache(item);

      final parentEntries = await entriesOf(parentDir);
      expect(parentEntries, equals(['cache']),
          reason: 'No file may be written outside the cache directory');

      final cacheEntries = await entriesOf(tempDir);
      for (final name in cacheEntries) {
        expect(name, isNot(contains('..')));
      }

      expect(await service.isCached(maliciousId), isTrue);
    });
  });
}
