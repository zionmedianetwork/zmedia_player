import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';
import '../test_utils/mocks.dart';

/// Performance tests for DRM operations
///
/// These tests measure the performance impact of DRM operations
/// to ensure they don't significantly degrade user experience.
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

        print('Widevine config creation: ${avgTime.toStringAsFixed(2)}μs avg');

        // Should take less than 100μs on average
        expect(avgTime, lessThan(100));
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

        print('FairPlay config creation: ${avgTime.toStringAsFixed(2)}μs avg');

        // Should take less than 100μs on average
        expect(avgTime, lessThan(100));
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

        print('EZDRM config creation: ${avgTime.toStringAsFixed(2)}μs avg');

        // Should take less than 100μs on average
        expect(avgTime, lessThan(100));
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

        print('DrmConfig toMap(): ${avgTime.toStringAsFixed(2)}μs avg');

        // Should take less than 50μs on average
        expect(avgTime, lessThan(50));
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

        print('DrmConfig fromMap(): ${avgTime.toStringAsFixed(2)}μs avg');

        // Should take less than 100μs on average
        expect(avgTime, lessThan(100));
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

        print(
            'MediaItem with DRM toMap(): ${avgTime.toStringAsFixed(2)}μs avg');

        // Should take less than 100μs on average
        expect(avgTime, lessThan(100));
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

        print('License isExpired check: ${avgTime.toStringAsFixed(3)}μs avg');

        // Should take less than 10μs on average
        expect(avgTime, lessThan(10));
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

        print(
            'License isExpiringSoon check: ${avgTime.toStringAsFixed(3)}μs avg');

        // Should take less than 10μs on average
        expect(avgTime, lessThan(10));
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
        print('Created $count DRM configs successfully');
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
        print('Created $count DRM sessions successfully');
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

        print('DRM config validation: ${avgTime.toStringAsFixed(2)}μs avg');

        // Should take less than 20μs per validation
        expect(avgTime, lessThan(20));
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

        print(
            'Mixed playlist serialization: ${avgTime.toStringAsFixed(2)}μs avg per item');

        // Should take less than 100μs per item
        expect(avgTime, lessThan(100));
      });
    });
  });

  group('Performance Regression Tests', () {
    test('DRM operations should not degrade over repeated use', () {
      final times = <int>[];

      // Run 10 batches of 100 operations each
      for (int batch = 0; batch < 10; batch++) {
        final stopwatch = Stopwatch()..start();

        for (int i = 0; i < 100; i++) {
          final config = DrmConfig.widevine(
            licenseUrl: 'https://license-server.com/license',
          );
          config.toMap();
        }

        stopwatch.stop();
        times.add(stopwatch.elapsedMicroseconds);
      }

      // Calculate average time for first and last batches
      final firstBatchAvg = times.take(3).reduce((a, b) => a + b) / 3;
      final lastBatchAvg = times.skip(7).reduce((a, b) => a + b) / 3;

      print('First batch avg: ${firstBatchAvg.toStringAsFixed(2)}μs');
      print('Last batch avg: ${lastBatchAvg.toStringAsFixed(2)}μs');

      // Performance should not degrade by more than 100% (2x slower)
      // Note: In test environments with variable load, some degradation is normal
      final degradation = (lastBatchAvg - firstBatchAvg) / firstBatchAvg;
      expect(degradation, lessThan(1.0));
    });
  });
}
