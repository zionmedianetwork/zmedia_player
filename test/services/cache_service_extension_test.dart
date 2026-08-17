// Regression coverage for the iOS cache-playback bug: CacheService built
// every cached filename as `${safeMediaId}_${timestamp}.cache`, discarding
// the source media's real extension. Android's ExoPlayer sniffs the
// container from the bytes and plays it anyway; iOS's AVURLAsset infers
// type from the file extension, so a `.cache` file fails to load with
// AVErrorFileFormatNotRecognized (-11828) even though the bytes are fine.
//
// These tests were verified to FAIL against the pre-fix tree: every cached
// file ended in the literal `.cache` extension, and a hostile "extension"
// smuggled in via the media URL was never sanitized (indeed, `.cache` was
// hardcoded and the URL wasn't consulted at all).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zmedia_player/zmedia_player.dart';

Uint8List _bytes(int size) => Uint8List(size)..fillRange(0, size, 0x42);

/// Every file directly inside [dir] (non-recursive), by name.
Future<List<String>> _entriesOf(Directory dir) async {
  if (!await dir.exists()) return [];
  final entries = await dir.list().toList();
  return entries.map((e) => e.path.split('/').last).toList();
}

void main() {
  group('CacheService — cached filename preserves source extension', () {
    late Directory tempDir;

    setUp(() async {
      tempDir =
          await Directory.systemTemp.createTemp('zmedia_cache_ext_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('a plain URL extension is preserved on the cached file', () async {
      final service = CacheService(CacheConfig(cacheDirectory: tempDir.path));
      await service.initialize();

      const item = MediaItem(
        id: 'plain-item',
        title: 'Plain',
        url: 'https://cdn.example.com/videos/movie.mp4',
      );

      await service.cacheMedia('plain-item', _bytes(16), item);

      final entries = await _entriesOf(tempDir);
      final cachedFile =
          entries.where((e) => e != 'cache_metadata.json').single;

      expect(cachedFile, endsWith('.mp4'),
          reason: 'iOS AVURLAsset infers container type from the file '
              'extension; a `.cache` (or any wrong) extension makes an '
              'otherwise-valid file unplayable there.');
      expect(cachedFile, isNot(endsWith('.cache')));

      await service.dispose();
    });

    test('a query string and fragment are stripped before taking the '
        'extension', () async {
      final service = CacheService(CacheConfig(cacheDirectory: tempDir.path));
      await service.initialize();

      const item = MediaItem(
        id: 'signed-item',
        title: 'Signed',
        url: 'https://cdn.example.com/videos/movie.mp4'
            '?token=abc&expires=123#t=10',
      );

      await service.cacheMedia('signed-item', _bytes(16), item);

      final entries = await _entriesOf(tempDir);
      final cachedFile =
          entries.where((e) => e != 'cache_metadata.json').single;

      expect(cachedFile, endsWith('.mp4'));
      expect(cachedFile, isNot(contains('token')));
      expect(cachedFile, isNot(contains('?')));
      expect(cachedFile, isNot(contains('#')));

      await service.dispose();
    });

    test(
        'a hostile "extension" embedded in the URL cannot escape the cache '
        'directory or inject path separators/dots into the filename',
        () async {
      final service = CacheService(CacheConfig(cacheDirectory: tempDir.path));
      await service.initialize();

      const item = MediaItem(
        id: 'hostile-item',
        title: 'Hostile',
        url: 'https://cdn.example.com/videos/movie.mp4%00../../evil',
      );

      await service.cacheMedia('hostile-item', _bytes(16), item);

      final entries = await _entriesOf(tempDir);
      final cachedFile =
          entries.where((e) => e != 'cache_metadata.json').single;

      // Only [A-Za-z0-9_-] plus a single leading dot for the extension may
      // appear; no traversal, no separators, no null bytes.
      expect(cachedFile, isNot(contains('..')));
      expect(cachedFile, isNot(contains('/')));
      expect(cachedFile, isNot(contains('\x00')));
      expect(RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(cachedFile), isTrue,
          reason: 'Cached filename must not contain characters outside a '
              'strict whitelist: "$cachedFile"');

      await service.dispose();
    });

    test('an excessively long "extension" is capped rather than adopted '
        'verbatim', () async {
      final service = CacheService(CacheConfig(cacheDirectory: tempDir.path));
      await service.initialize();

      final longExt = 'a' * 200;
      final item = MediaItem(
        id: 'long-ext-item',
        title: 'Long extension',
        url: 'https://cdn.example.com/videos/movie.$longExt',
      );

      await service.cacheMedia('long-ext-item', _bytes(16), item);

      final entries = await _entriesOf(tempDir);
      final cachedFile =
          entries.where((e) => e != 'cache_metadata.json').single;
      final ext = cachedFile.contains('.') ? cachedFile.split('.').last : '';

      expect(ext.length, lessThanOrEqualTo(8),
          reason: 'A pathologically long "extension" must be capped, not '
              'copied verbatim into the filename.');

      await service.dispose();
    });

    test('a URL with no extension and no mimeType omits the extension '
        'rather than reintroducing the `.cache` bug', () async {
      final service = CacheService(CacheConfig(cacheDirectory: tempDir.path));
      await service.initialize();

      const item = MediaItem(
        id: 'no-ext-item',
        title: 'No extension',
        url: 'https://cdn.example.com/videos/stream',
      );

      await service.cacheMedia('no-ext-item', _bytes(16), item);

      final entries = await _entriesOf(tempDir);
      final cachedFile =
          entries.where((e) => e != 'cache_metadata.json').single;

      expect(cachedFile, isNot(endsWith('.cache')),
          reason: 'Falling back to `.cache` reproduces the exact iOS bug '
              'this fix addresses.');

      await service.dispose();
    });

    test('mimeType is used to infer an extension when the URL has none',
        () async {
      final service = CacheService(CacheConfig(cacheDirectory: tempDir.path));
      await service.initialize();

      const item = MediaItem(
        id: 'mime-item',
        title: 'Mime-derived',
        url: 'https://cdn.example.com/videos/stream',
        mimeType: 'video/mp4',
      );

      await service.cacheMedia('mime-item', _bytes(16), item);

      final entries = await _entriesOf(tempDir);
      final cachedFile =
          entries.where((e) => e != 'cache_metadata.json').single;

      expect(cachedFile, endsWith('.mp4'));

      await service.dispose();
    });

    test('getCachedFileUri on a cached item still resolves to an existing, '
        'correctly-named file', () async {
      final service = CacheService(CacheConfig(cacheDirectory: tempDir.path));
      await service.initialize();

      const item = MediaItem(
        id: 'roundtrip-item',
        title: 'Roundtrip',
        url: 'https://cdn.example.com/videos/clip.mov',
      );

      await service.cacheMedia('roundtrip-item', _bytes(16), item);
      final uri = await service.getCachedFileUri('roundtrip-item');

      expect(uri, isNotNull);
      expect(uri, endsWith('.mov'));

      await service.dispose();
    });
  });

  group('CacheService.downloadAndCache — cached filename preserves source '
      'extension', () {
    late Directory tempDir;

    setUp(() async {
      tempDir =
          await Directory.systemTemp.createTemp('zmedia_cache_ext_dl_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('a plain URL extension is preserved for a streamed download',
        () async {
      final client = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.value([1, 2, 3, 4]),
          200,
          contentLength: 4,
        );
      });

      final service = CacheService(
        CacheConfig(cacheDirectory: tempDir.path),
        httpClientFactory: () => client,
      );
      await service.initialize();

      const item = MediaItem(
        id: 'download-item',
        title: 'Download',
        url: 'https://cdn.example.com/videos/movie.webm',
      );

      await service.downloadAndCache(item);

      final entries = await _entriesOf(tempDir);
      final cachedFile =
          entries.where((e) => e != 'cache_metadata.json').single;

      expect(cachedFile, endsWith('.webm'));
    });

    test(
        'the response Content-Type is used when the download URL has no '
        'extension', () async {
      final client = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.value([1, 2, 3, 4]),
          200,
          contentLength: 4,
          headers: {'content-type': 'video/mp4; charset=binary'},
        );
      });

      final service = CacheService(
        CacheConfig(cacheDirectory: tempDir.path),
        httpClientFactory: () => client,
      );
      await service.initialize();

      const item = MediaItem(
        id: 'download-no-ext-item',
        title: 'Download no ext',
        url: 'https://cdn.example.com/videos/stream',
      );

      await service.downloadAndCache(item);

      final entries = await _entriesOf(tempDir);
      final cachedFile =
          entries.where((e) => e != 'cache_metadata.json').single;

      expect(cachedFile, endsWith('.mp4'));
    });
  });

  group('CacheService — legacy `.cache`-suffixed entries are invalidated on '
      'load', () {
    late Directory tempDir;

    setUp(() async {
      tempDir =
          await Directory.systemTemp.createTemp('zmedia_cache_legacy_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('a pre-fix `.cache` entry is dropped (file deleted, metadata '
        'removed) the next time the cache initializes', () async {
      // Simulate what the pre-fix code left behind: a cache file literally
      // named `<id>_<timestamp>.cache`, plus a metadata entry pointing at
      // it, written directly to disk (bypassing CacheService, which no
      // longer produces this shape).
      const mediaId = 'legacy-item';
      const legacyFileName = 'legacy-item_1234567890.cache';
      final legacyFile = File('${tempDir.path}/$legacyFileName');
      await legacyFile.writeAsBytes(_bytes(8));

      const legacyItem = MediaItem(
        id: mediaId,
        title: 'Legacy',
        url: 'https://cdn.example.com/videos/legacy.mp4',
      );
      final metadata = <String, dynamic>{
        mediaId: {
          'mediaId': mediaId,
          'fileName': legacyFileName,
          'size': 8,
          'mediaItem': legacyItem.toMap(),
          'createdAt': DateTime.now().millisecondsSinceEpoch,
          'lastAccessed': DateTime.now().millisecondsSinceEpoch,
          'expiresAt': DateTime.now()
              .add(const Duration(hours: 1))
              .millisecondsSinceEpoch,
        },
      };
      final metadataFile = File('${tempDir.path}/cache_metadata.json');
      await metadataFile.writeAsString(json.encode(metadata));

      final service = CacheService(CacheConfig(cacheDirectory: tempDir.path));
      await service.initialize();

      expect(await service.isCached(mediaId), isFalse,
          reason: 'A legacy `.cache`-suffixed entry is unplayable on iOS '
              'and must not be presented as a valid cache hit.');
      expect(await legacyFile.exists(), isFalse,
          reason: 'The stale, unplayable file should be cleaned up, not '
              'just hidden from metadata.');

      await service.dispose();
    });
  });
}
