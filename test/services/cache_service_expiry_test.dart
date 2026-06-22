import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Uint8List _bytes(int size) => Uint8List(size)..fillRange(0, size, 0x42);

const _testItem1 = MediaItem(
  id: 'cache-item-1',
  title: 'Item 1',
  url: 'https://example.com/item1.mp4',
);

const _testItem2 = MediaItem(
  id: 'cache-item-2',
  title: 'Item 2',
  url: 'https://example.com/item2.mp4',
);

const _testItem3 = MediaItem(
  id: 'cache-item-3',
  title: 'Item 3',
  url: 'https://example.com/item3.mp4',
);

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('zmedia_cache_expiry_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  // =========================================================================
  group('CacheService — expiry', () {
    // NOTE: CacheService has a re-entrant initialization bug:
    // `removeFromCache` / `cacheMedia` etc. call
    // `if (!_isInitialized) await initialize()` but they can be invoked
    // from within `initialize()` itself (via `_cleanupExpiredEntries`),
    // causing a `LateInitializationError` because `late final _cacheDir` is
    // set twice. Tests here avoid creating a second CacheService instance
    // over the same directory after calling dispose() to not trigger that
    // code path. This product bug is documented in the test report.

    test('expired entry is not returned by getCachedMedia', () async {
      // Use a short expiration so the entry expires while still alive.
      final config = CacheConfig(
        cacheDirectory: tempDir.path,
        cacheExpiration: const Duration(milliseconds: 1),
      );
      final service = CacheService(config);
      await service.initialize();

      await service.cacheMedia('cache-item-1', _bytes(64), _testItem1);

      // Wait just enough for the entry to expire.
      await Future<void>.delayed(const Duration(milliseconds: 5));

      // getCachedMedia checks CacheEntry.isValid() which evaluates
      // DateTime.now().isBefore(expiresAt). Since the entry is expired it
      // must return null — all on the same already-initialized service.
      final result = await service.getCachedMedia('cache-item-1');
      expect(result, isNull, reason: 'Expired entry must not be returned');

      await service.dispose();
    });

    test('non-expired entry is returned by getCachedMedia', () async {
      final config = CacheConfig(
        cacheDirectory: tempDir.path,
        cacheExpiration: const Duration(hours: 24),
      );
      final service = CacheService(config);
      await service.initialize();

      final data = _bytes(128);
      await service.cacheMedia('cache-item-1', data, _testItem1);

      final result = await service.getCachedMedia('cache-item-1');
      expect(result, isNotNull, reason: 'Non-expired entry must be returned');
      expect(result!.length, 128);

      await service.dispose();
    });

    test('isCached returns false for expired entry', () async {
      final config = CacheConfig(
        cacheDirectory: tempDir.path,
        cacheExpiration: const Duration(milliseconds: 1),
      );
      final service = CacheService(config);
      await service.initialize();

      await service.cacheMedia('cache-item-1', _bytes(32), _testItem1);
      await Future<void>.delayed(const Duration(milliseconds: 5));

      // isCached checks entry.isValid which checks DateTime comparison.
      // Using the same initialized service avoids the re-entrancy bug.
      final cached = await service.isCached('cache-item-1');
      expect(cached, isFalse,
          reason: 'isCached must return false for expired entries');

      await service.dispose();
    });

    test('isCached returns true for fresh entry', () async {
      final config = CacheConfig(
        cacheDirectory: tempDir.path,
        cacheExpiration: const Duration(hours: 1),
      );
      final service = CacheService(config);
      await service.initialize();

      await service.cacheMedia('cache-item-2', _bytes(64), _testItem2);

      final cached = await service.isCached('cache-item-2');
      expect(cached, isTrue);

      await service.dispose();
    });
  });

  // =========================================================================
  group('CacheService — LRU eviction on size limit', () {
    test('oldest entry is evicted when cache is full', () async {
      // Give each item 100 bytes; cap at 250 bytes → only 2 items fit.
      const entrySize = 100;
      final config = CacheConfig(
        cacheDirectory: tempDir.path,
        maxCacheSize: 250,
        cacheExpiration: const Duration(hours: 24),
      );
      final service = CacheService(config);
      await service.initialize();

      // Cache item-1 first (oldest), then item-2.
      await service.cacheMedia('cache-item-1', _bytes(entrySize), _testItem1);
      await service.cacheMedia('cache-item-2', _bytes(entrySize), _testItem2);

      // Both should be cached now (200 bytes used, 250 limit).
      expect(await service.isCached('cache-item-1'), isTrue);
      expect(await service.isCached('cache-item-2'), isTrue);

      // Adding item-3 (100 bytes) would push total to 300 > 250.
      // LRU: item-1 was accessed least recently → it gets evicted.
      await service.cacheMedia('cache-item-3', _bytes(entrySize), _testItem3);

      expect(await service.isCached('cache-item-1'), isFalse,
          reason: 'Oldest (LRU) entry must be evicted to make room');
      expect(await service.isCached('cache-item-3'), isTrue,
          reason: 'Newly cached item must survive eviction');

      await service.dispose();
    });

    test('getCacheInfo reports correct entry count and size', () async {
      final config = CacheConfig(
        cacheDirectory: tempDir.path,
        maxCacheSize: 1024 * 1024,
        cacheExpiration: const Duration(hours: 1),
      );
      final service = CacheService(config);
      await service.initialize();

      await service.cacheMedia('cache-item-1', _bytes(200), _testItem1);
      await service.cacheMedia('cache-item-2', _bytes(300), _testItem2);

      final info = await service.getCacheInfo();
      expect(info.entryCount, 2);
      expect(info.totalSize, 500,
          reason: 'Total size must reflect bytes of both cached entries');
      expect(info.enabled, isTrue);

      await service.dispose();
    });
  });

  // =========================================================================
  group('CacheService — remove and clear', () {
    test('removeFromCache removes the specific entry', () async {
      final config = CacheConfig(
        cacheDirectory: tempDir.path,
        cacheExpiration: const Duration(hours: 1),
      );
      final service = CacheService(config);
      await service.initialize();

      await service.cacheMedia('cache-item-1', _bytes(100), _testItem1);
      await service.cacheMedia('cache-item-2', _bytes(100), _testItem2);

      await service.removeFromCache('cache-item-1');

      expect(await service.isCached('cache-item-1'), isFalse);
      expect(await service.isCached('cache-item-2'), isTrue,
          reason: 'Removing one entry must not affect others');

      await service.dispose();
    });

    test('clearCache removes all entries', () async {
      final config = CacheConfig(
        cacheDirectory: tempDir.path,
        cacheExpiration: const Duration(hours: 1),
      );
      final service = CacheService(config);
      await service.initialize();

      await service.cacheMedia('cache-item-1', _bytes(50), _testItem1);
      await service.cacheMedia('cache-item-2', _bytes(50), _testItem2);

      await service.clearCache();

      final info = await service.getCacheInfo();
      expect(info.entryCount, 0);
      expect(info.totalSize, 0);

      await service.dispose();
    });

    test('cacheMedia is idempotent — second call overwrites', () async {
      final config = CacheConfig(
        cacheDirectory: tempDir.path,
        cacheExpiration: const Duration(hours: 1),
      );
      final service = CacheService(config);
      await service.initialize();

      await service.cacheMedia('cache-item-1', _bytes(50), _testItem1);
      // Second call for the same id must not throw.
      await expectLater(
        service.cacheMedia('cache-item-1', _bytes(50), _testItem1),
        completes,
      );

      await service.dispose();
    });

    test('removeFromCache on unknown id is a no-op', () async {
      final config = CacheConfig(
        cacheDirectory: tempDir.path,
        cacheExpiration: const Duration(hours: 1),
      );
      final service = CacheService(config);
      await service.initialize();

      await expectLater(
        service.removeFromCache('nonexistent-id'),
        completes,
        reason: 'removeFromCache for unknown id must not throw',
      );

      await service.dispose();
    });
  });

  // =========================================================================
  group('CacheService — CacheInfo helpers', () {
    test('usagePercentage is 0 when no entries are cached', () async {
      final config = CacheConfig(
        cacheDirectory: tempDir.path,
        maxCacheSize: 1024 * 1024,
      );
      final service = CacheService(config);
      await service.initialize();

      final info = await service.getCacheInfo();
      expect(info.usagePercentage, 0.0);

      await service.dispose();
    });

    test('formattedTotalSize returns B for sub-KB sizes', () {
      const info = CacheInfo(
        totalSize: 512,
        maxSize: 1024 * 1024,
        entryCount: 1,
        enabled: true,
      );
      expect(info.formattedTotalSize, endsWith('B'));
    });

    test('formattedTotalSize returns KB for kilobyte sizes', () {
      const info = CacheInfo(
        totalSize: 2048, // 2 KB
        maxSize: 1024 * 1024,
        entryCount: 1,
        enabled: true,
      );
      expect(info.formattedTotalSize, contains('KB'));
    });
  });
}
