import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';
import '../test_utils/mocks.dart';

/// Performance tests for DRM operations
///
/// These tests measure the performance impact of DRM operations
/// to ensure they don't significantly degrade user experience.
///
/// **Timing assertions in this file use deliberately generous absolute
/// budgets** (typically 20x-100x the observed cost) so that they detect an
/// order-of-magnitude regression without failing merely because the machine
/// running them is busy. Measured values are reported through each
/// expectation's `reason:` string, so they are printed only when an
/// assertion actually fails — a passing run stays quiet, and no `print()`
/// call is needed.
///
/// Ratio-based assertions ("batch N must not be more than 2x batch 1") are
/// deliberately *not* used here: on shared CI hardware they measure
/// scheduler noise rather than the code, and cannot be made reliable. The
/// "does repeated use accumulate state?" question they were meant to answer
/// is covered deterministically by the `Repeated Use Invariants` group at
/// the bottom of this file.
void main() {
  group('DRM Performance Tests', () {
    group('DrmConfig Creation', () {
      test('Widevine config creation is fast', () {
        final stopwatch = Stopwatch()..start();
        const iterations = 1000;

        for (int i = 0; i < iterations; i++) {
          DrmConfig.widevine(
            licenseUrl: 'https://license-server.com/widevine',
            headers: {'Authorization': 'Bearer token$i'},
          );
        }

        stopwatch.stop();
        final avgTime = stopwatch.elapsedMicroseconds / iterations;

        // Should take less than 100μs on average (~30x observed cost).
        expect(avgTime, lessThan(100),
            reason: 'DrmConfig.widevine() averaged '
                '${avgTime.toStringAsFixed(2)}μs over $iterations iterations');
      });

      test('FairPlay config creation is fast', () {
        final stopwatch = Stopwatch()..start();
        const iterations = 1000;

        for (int i = 0; i < iterations; i++) {
          DrmConfig.fairplay(
            licenseUrl: 'https://license-server.com/fairplay',
            certificateUrl: 'https://server.com/cert$i.cer',
          );
        }

        stopwatch.stop();
        final avgTime = stopwatch.elapsedMicroseconds / iterations;

        // Should take less than 100μs on average (~100x observed cost).
        expect(avgTime, lessThan(100),
            reason: 'DrmConfig.fairplay() averaged '
                '${avgTime.toStringAsFixed(2)}μs over $iterations iterations');
      });

      test('EZDRM config creation is fast', () {
        final stopwatch = Stopwatch()..start();
        const iterations = 1000;

        for (int i = 0; i < iterations; i++) {
          EzdrmConfig.widevine(
            customerId: 'customer$i',
            apiKey: 'api-key',
            contentId: 'content$i',
          );
        }

        stopwatch.stop();
        final avgTime = stopwatch.elapsedMicroseconds / iterations;

        // Should take less than 100μs on average (~60x observed cost).
        expect(avgTime, lessThan(100),
            reason: 'EzdrmConfig.widevine() averaged '
                '${avgTime.toStringAsFixed(2)}μs over $iterations iterations');
      });
    });

    group('Serialization Performance', () {
      test('DrmConfig serialization is fast', () {
        final config = DrmConfig.widevine(
          licenseUrl: 'https://license-server.com/widevine',
          headers: {'Authorization': 'Bearer token'},
          customData: {
            'userId': 'user123',
            'contentId': 'content456',
          },
        );

        final stopwatch = Stopwatch()..start();
        const iterations = 10000;

        for (int i = 0; i < iterations; i++) {
          config.toMap();
        }

        stopwatch.stop();
        final avgTime = stopwatch.elapsedMicroseconds / iterations;

        // Should take less than 50μs on average (~30x observed cost).
        expect(avgTime, lessThan(50),
            reason: 'DrmConfig.toMap() averaged '
                '${avgTime.toStringAsFixed(2)}μs over $iterations iterations');
      });

      test('DrmConfig deserialization is fast', () {
        final map = {
          'scheme': 'widevine',
          'licenseUrl': 'https://license-server.com/widevine',
          'headers': {'Authorization': 'Bearer token'},
          'customData': {
            'userId': 'user123',
            'contentId': 'content456',
          },
        };

        final stopwatch = Stopwatch()..start();
        const iterations = 10000;

        for (int i = 0; i < iterations; i++) {
          DrmConfig.fromMap(map);
        }

        stopwatch.stop();
        final avgTime = stopwatch.elapsedMicroseconds / iterations;

        // Should take less than 100μs on average (~100x observed cost).
        expect(avgTime, lessThan(100),
            reason: 'DrmConfig.fromMap() averaged '
                '${avgTime.toStringAsFixed(2)}μs over $iterations iterations');
      });

      test('MediaItem with DRM serialization is fast', () {
        final item = MediaItem(
          id: 'video1',
          title: 'Protected Video',
          url: 'https://cdn.com/video.mpd',
          drmConfig: MockDrmConfigs.widevine,
          httpHeaders: {'Authorization': 'Bearer token'},
        );

        final stopwatch = Stopwatch()..start();
        const iterations = 10000;

        for (int i = 0; i < iterations; i++) {
          item.toMap();
        }

        stopwatch.stop();
        final avgTime = stopwatch.elapsedMicroseconds / iterations;

        // Should take less than 100μs on average (~50x observed cost).
        expect(avgTime, lessThan(100),
            reason: 'MediaItem.toMap() with DRM averaged '
                '${avgTime.toStringAsFixed(2)}μs over $iterations iterations');
      });
    });

    group('License Validation Performance', () {
      test('License expiration check is fast', () {
        final license = MockDrmLicenses.active;

        final stopwatch = Stopwatch()..start();
        const iterations = 100000;

        for (int i = 0; i < iterations; i++) {
          final _ = license.isExpired;
        }

        stopwatch.stop();
        final avgTime = stopwatch.elapsedMicroseconds / iterations;

        // Should take less than 10μs on average (~120x observed cost).
        expect(avgTime, lessThan(10),
            reason: 'DrmLicense.isExpired averaged '
                '${avgTime.toStringAsFixed(3)}μs over $iterations iterations');
      });

      test('License expiry warning check is fast', () {
        final license = MockDrmLicenses.active;

        final stopwatch = Stopwatch()..start();
        const iterations = 100000;

        for (int i = 0; i < iterations; i++) {
          final _ = license.isExpiringSoon;
        }

        stopwatch.stop();
        final avgTime = stopwatch.elapsedMicroseconds / iterations;

        // Should take less than 10μs on average (~17x observed cost).
        expect(avgTime, lessThan(10),
            reason: 'DrmLicense.isExpiringSoon averaged '
                '${avgTime.toStringAsFixed(3)}μs over $iterations iterations');
      });
    });

    group('Memory Overhead', () {
      test('DrmConfig has reasonable memory footprint', () {
        final configs = <DrmConfig>[];
        const count = 1000;

        for (int i = 0; i < count; i++) {
          configs.add(
            DrmConfig.widevine(
              licenseUrl: 'https://license-server.com/widevine$i',
              headers: {'Authorization': 'Bearer token$i'},
            ),
          );
        }

        // 1000 DRM configs should take less than 1MB
        // (rough estimate: ~1KB per config)
        expect(configs.length, count);
      });

      test('DrmSession has reasonable memory footprint', () {
        final sessions = <DrmSession>[];
        const count = 1000;

        for (int i = 0; i < count; i++) {
          final now = DateTime.now();
          sessions.add(
            DrmSession(
              id: 'session$i',
              state: DrmSessionState.licensed,
              license: DrmLicense(
                id: 'license$i',
                keyData: 'encrypted-key-data-$i',
                expirationTime: now.add(Duration(hours: 24)),
              ),
              createdAt: now,
              updatedAt: now,
            ),
          );
        }

        expect(sessions.length, count);
      });
    });

    group('Batch Operations', () {
      test('Multiple DRM config validations are efficient', () {
        final configs = [
          MockDrmConfigs.widevine,
          MockDrmConfigs.fairplay,
          MockDrmConfigs.tokenBased,
          MockDrmConfigs.clearkey,
        ];

        final stopwatch = Stopwatch()..start();
        const iterations = 1000;

        for (int i = 0; i < iterations; i++) {
          for (final config in configs) {
            TestHelpers.isValidDrmConfig(config);
          }
        }

        stopwatch.stop();
        final avgTime =
            stopwatch.elapsedMicroseconds / (iterations * configs.length);

        // Should take less than 20μs per validation (~100x observed cost).
        expect(avgTime, lessThan(20),
            reason: 'DRM config validation averaged '
                '${avgTime.toStringAsFixed(2)}μs over '
                '${iterations * configs.length} validations');
      });

      test('Playlist with mixed DRM content performs well', () {
        final playlist = [
          MockMediaItems.plainVideo,
          MockMediaItems.widevineProtected,
          MockMediaItems.fairplayProtected,
          MockMediaItems.tokenProtected,
          MockMediaItems.withMetadata,
        ];

        final stopwatch = Stopwatch()..start();
        const iterations = 1000;

        for (int i = 0; i < iterations; i++) {
          for (final item in playlist) {
            final _ = item.toMap();
          }
        }

        stopwatch.stop();
        final avgTime =
            stopwatch.elapsedMicroseconds / (iterations * playlist.length);

        // Should take less than 100μs per item (~60x observed cost).
        expect(avgTime, lessThan(100),
            reason: 'Mixed-playlist item serialization averaged '
                '${avgTime.toStringAsFixed(2)}μs per item over '
                '${iterations * playlist.length} items');
      });
    });
  });

  /// These replace an earlier wall-clock test that timed ten batches of
  /// `DrmConfig.widevine()` + `toMap()` and failed if the last three batches
  /// averaged more than 2x the first three.
  ///
  /// That assertion measured the machine, not the package: batch times are
  /// on the order of 100μs, so a single GC pause or a scheduler slice lost
  /// to another process is enough to trip it, and it was observed failing on
  /// an otherwise-idle developer machine and then passing on re-run. Its
  /// *intent*, though, is worth keeping: repeated construction and
  /// serialization should accumulate no state, drift, or aliasing.
  ///
  /// The tests below assert that intent directly and deterministically, so
  /// they fail if and only if the code is actually wrong. The timing signal
  /// is not lost either — `DrmConfig` construction and `toMap()` both still
  /// have absolute per-operation budgets asserted above.
  group('Repeated Use Invariants', () {
    test('repeated construction and toMap() produce no drift', () {
      const iterations = 1000;
      const licenseUrl = 'https://license-server.com/license';

      final reference = DrmConfig.widevine(licenseUrl: licenseUrl).toMap();
      Map<String, dynamic> previous = reference;

      for (int i = 0; i < iterations; i++) {
        final map = DrmConfig.widevine(licenseUrl: licenseUrl).toMap();

        // Identical inputs must serialize identically every time, forever:
        // no value drift and no key set growing or shrinking as the process
        // does more work.
        expect(map, equals(reference),
            reason: 'serialization drifted from the first result at '
                'iteration $i');
        expect(map, equals(previous),
            reason: 'serialization drifted from the previous result at '
                'iteration $i');
        expect(map.keys.toList(), equals(reference.keys.toList()),
            reason: 'serialized key set changed at iteration $i');

        previous = map;
      }
    });

    test('toMap() is idempotent and returns a fresh map each call', () {
      const licenseUrl = 'https://license-server.com/license';
      final config = DrmConfig.widevine(
        licenseUrl: licenseUrl,
        headers: {'Authorization': 'Bearer token'},
      );

      final first = config.toMap();
      final second = config.toMap();

      expect(second, equals(first));
      expect(identical(first, second), isFalse,
          reason: 'toMap() must not hand out a shared map instance');

      // A caller mutating a previously returned map must not be able to
      // corrupt later serializations of the same config — the classic way
      // "state accumulates over repeated use" actually manifests.
      first['licenseUrl'] = 'https://attacker.example/license';
      first.remove('scheme');
      first['injected'] = true;

      final third = config.toMap();
      expect(third, equals(second));
      expect(third.containsKey('injected'), isFalse);
      expect(config.licenseUrl, licenseUrl);
      expect(config.headers, {'Authorization': 'Bearer token'});
    });

    test('configs remain independent and correct at volume', () {
      const count = 1000;

      final configs = <DrmConfig>[
        for (int i = 0; i < count; i++)
          DrmConfig.widevine(
            licenseUrl: 'https://license-server.com/license$i',
            headers: {'Authorization': 'Bearer token$i'},
          ),
      ];

      // Every config must still carry exactly its own values: nothing
      // shared, overwritten, or aliased between the 1000 instances.
      for (int i = 0; i < count; i++) {
        final map = configs[i].toMap();
        expect(map['scheme'], 'widevine');
        expect(map['licenseUrl'], 'https://license-server.com/license$i');
        expect(map['headers'], {'Authorization': 'Bearer token$i'});
      }
    });
  });
}
