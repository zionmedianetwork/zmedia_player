// H-12 regression coverage: CacheService.downloadAndCache must stream the
// HTTP response directly to disk instead of accumulating it into an
// in-memory `List<int>` first (the prior implementation used roughly
// 8-17x the downloaded file's size in RAM before ever touching disk).
//
// Precisely measuring peak memory from a Dart unit test isn't practical, so
// this file instead asserts the behavioural contract that streaming-to-disk
// implies:
//   - a successful download ends up correctly and completely on disk, and
//     is registered as a valid, retrievable cache entry;
//   - a failed (non-200) or interrupted (stream error) download commits
//     nothing: no cache entry is registered, and no partial `.part` file is
//     left behind on disk masquerading as (or in the way of) a valid entry.
//
// What remains UNPROVEN by this file: that peak resident memory during the
// download is actually O(chunk size) rather than O(file size). That would
// require an instrumented/real-device run (e.g. observing RSS while
// downloading a large fixture through the real network stack), which is out
// of reach for a `flutter test` unit test using `MockClient`.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zmedia_player/zmedia_player.dart';

void main() {
  group('CacheService — streaming download to disk (H-12)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir =
          await Directory.systemTemp.createTemp('zmedia_cache_stream_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    const item = MediaItem(
      id: 'stream-item-1',
      title: 'Streamed Video',
      url: 'https://cdn.example.com/video.mp4',
      mediaType: MediaType.video,
    );

    /// Every file directly inside [tempDir] (non-recursive), by name.
    Future<List<String>> cacheDirEntries() async {
      final entries = await tempDir.list().toList();
      return entries
          .map((e) => e.path.split(Platform.pathSeparator).last)
          .toList();
    }

    test('successful download is written to disk intact and becomes cached',
        () async {
      // ~256KB of deterministic content, delivered in multiple chunks so the
      // streaming path actually exercises more than one `sink.add` call.
      final expected = Uint8List.fromList(
        List<int>.generate(256 * 1024, (i) => i % 256),
      );
      const chunkSize = 16 * 1024;

      final client = MockClient.streaming((request, bodyStream) async {
        Stream<List<int>> chunked() async* {
          for (var offset = 0; offset < expected.length; offset += chunkSize) {
            final end = (offset + chunkSize < expected.length)
                ? offset + chunkSize
                : expected.length;
            yield expected.sublist(offset, end);
          }
        }

        return http.StreamedResponse(
          chunked(),
          200,
          contentLength: expected.length,
        );
      });

      final service = CacheService(
        CacheConfig(cacheDirectory: tempDir.path),
        httpClientFactory: () => client,
      );
      await service.initialize();

      await service.downloadAndCache(item);

      expect(await service.isCached(item.id), isTrue);

      final cached = await service.getCachedMedia(item.id);
      expect(cached, isNotNull);
      expect(cached, equals(expected),
          reason: 'streamed bytes on disk must exactly match what was sent');

      final entries = await cacheDirEntries();
      expect(entries.any((e) => e.endsWith('.part')), isFalse,
          reason: 'no temp .part file must remain after a successful, '
              'committed download');
      expect(entries.any((e) => e.endsWith('.cache')), isTrue,
          reason: 'the committed cache file must exist on disk');
    });

    test('a non-200 response leaves no cache entry and no partial file',
        () async {
      final client = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([
            [1, 2, 3]
          ]),
          404,
        );
      });

      final service = CacheService(
        CacheConfig(cacheDirectory: tempDir.path),
        httpClientFactory: () => client,
      );
      await service.initialize();

      await expectLater(
        service.downloadAndCache(item),
        throwsA(isA<CacheException>()),
      );

      expect(await service.isCached(item.id), isFalse);

      final entries = await cacheDirEntries();
      expect(entries.any((e) => e.endsWith('.part')), isFalse,
          reason: 'a failed download must not leave a partial file on disk');
      expect(entries.any((e) => e.endsWith('.cache')), isFalse,
          reason: 'a failed download must not produce a committed cache '
              'entry');
    });

    test(
        'a stream error mid-download leaves no cache entry and no partial file',
        () async {
      final client = MockClient.streaming((request, bodyStream) async {
        Stream<List<int>> erroring() async* {
          yield List<int>.filled(4096, 7);
          // Simulate a connection drop partway through the body.
          throw Exception('simulated connection drop');
        }

        return http.StreamedResponse(
          erroring(),
          200,
          contentLength: 1024 * 1024, // advertises far more than is sent
        );
      });

      final service = CacheService(
        CacheConfig(cacheDirectory: tempDir.path),
        httpClientFactory: () => client,
      );
      await service.initialize();

      await expectLater(
        service.downloadAndCache(item),
        throwsA(isA<CacheException>()),
      );

      expect(await service.isCached(item.id), isFalse);

      final entries = await cacheDirEntries();
      expect(entries.any((e) => e.endsWith('.part')), isFalse,
          reason: 'an interrupted download must clean up its temp file '
              'rather than leaving a partial download on disk');
      expect(entries.any((e) => e.endsWith('.cache')), isFalse);
    });
  });
}
