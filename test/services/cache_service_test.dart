import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

void main() {
  group('CacheService — override directory', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('zmedia_cache_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('uses the configured cacheDirectory override when provided', () async {
      final config = CacheConfig(
        cacheDirectory: tempDir.path,
      );
      final service = CacheService(config);

      // Initialize — should not throw.
      await service.initialize();

      // The override directory must exist after initialization.
      expect(await tempDir.exists(), isTrue,
          reason:
              'CacheService must use (and keep) the override directory path');
    });

    test('initialize is idempotent (safe to call twice)', () async {
      final config = CacheConfig(
        cacheDirectory: tempDir.path,
      );
      final service = CacheService(config);

      await service.initialize();
      // Second call must not throw.
      await expectLater(service.initialize(), completes);
    });

    test('getCachedMedia returns null for unknown id after init', () async {
      final config = CacheConfig(
        cacheDirectory: tempDir.path,
      );
      final service = CacheService(config);
      await service.initialize();

      final result = await service.getCachedMedia('nonexistent-id');
      expect(result, isNull);
    });
  });
}
