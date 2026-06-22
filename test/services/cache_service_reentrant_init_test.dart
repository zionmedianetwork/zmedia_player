import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Uint8List _bytes(int size) => Uint8List(size)..fillRange(0, size, 0xAB);

const _item = MediaItem(
  id: 'ci-reentrant-1',
  title: 'Re-entrant test item',
  url: 'https://example.com/reentrant.mp4',
);

/// Writes a cache-metadata file into [dir] that contains a single already-
/// expired entry.  This simulates a disk store that was populated on a
/// previous run and whose entries have since expired.
Future<void> _writeExpiredMetadata(Directory dir) async {
  // Timestamp so far in the past that it is definitely expired.
  final pastMs =
      DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch;

  final entry = {
    'mediaId': _item.id,
    'fileName': '${_item.id}_expired.cache',
    'size': 64,
    'mediaItem': _item.toMap(),
    'createdAt': pastMs,
    'lastAccessed': pastMs,
    'expiresAt': pastMs, // already expired
  };

  final metadataFile = File('${dir.path}/cache_metadata.json');
  await metadataFile.writeAsString(json.encode({_item.id: entry}));
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir =
        await Directory.systemTemp.createTemp('zmedia_cache_reentrant_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  // =========================================================================
  group('CacheService — re-entrant initialize regression (Bug 2)', () {
    // Bug: initialize() set _isInitialized = true only AFTER calling
    // _cleanupExpiredEntries(), which called the public removeFromCache(),
    // which called initialize() again via `if (!_isInitialized) await
    // initialize()` → second assignment of `late final _cacheDir` →
    // LateInitializationError.
    //
    // Fix: _cleanupExpiredEntries() now calls _deleteEntry() directly,
    // bypassing the _isInitialized guard.

    test(
        'initialize does not throw when the store has an already-expired entry '
        '(cleanup runs inside init without re-entering initialize)', () async {
      // Pre-seed the directory with an expired metadata entry.
      await _writeExpiredMetadata(tempDir);

      final config = CacheConfig(
        cacheDirectory: tempDir.path,
        cacheExpiration: const Duration(hours: 1),
      );
      final service = CacheService(config);

      // This must NOT throw LateInitializationError (or any other error).
      await expectLater(
        service.initialize(),
        completes,
        reason: 'initialize must handle an expired on-disk entry without '
            're-entering itself',
      );

      // The expired entry must have been cleaned up.
      final cached = await service.isCached(_item.id);
      expect(cached, isFalse,
          reason:
              'Expired entry must be removed during initialization cleanup');

      await service.dispose();
    });

    test(
        'a second CacheService initialized over the same directory '
        '(with an expired entry written by the first) also initializes cleanly',
        () async {
      // ---- First service: cache an item with a 1 ms TTL. ----
      final config1 = CacheConfig(
        cacheDirectory: tempDir.path,
        cacheExpiration: const Duration(milliseconds: 1),
        maxCacheSize: 1024 * 1024,
      );
      final service1 = CacheService(config1);
      await service1.initialize();
      await service1.cacheMedia(_item.id, _bytes(64), _item);
      await service1.dispose();

      // Let the entry expire before the second service starts.
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // ---- Second service: opens the same directory. ----
      // The metadata file now contains an expired entry.  initialize() will
      // call _cleanupExpiredEntries(), which must NOT re-enter initialize().
      final config2 = CacheConfig(
        cacheDirectory: tempDir.path,
        cacheExpiration: const Duration(hours: 1),
        maxCacheSize: 1024 * 1024,
      );
      final service2 = CacheService(config2);

      await expectLater(
        service2.initialize(),
        completes,
        reason: 'Second CacheService over the same directory must initialize '
            'without LateInitializationError',
      );

      // The previously cached (now expired) entry must be absent.
      final cached = await service2.isCached(_item.id);
      expect(cached, isFalse,
          reason:
              'Entry expired between service1.dispose and service2.initialize '
              'must be cleaned up');

      await service2.dispose();
    });
  });
}
