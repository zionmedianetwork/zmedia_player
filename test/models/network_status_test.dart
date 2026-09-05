import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

/// Regression tests for issue #112: `NetworkStatus.fromPlatform` used to
/// discard the platform's `quality` string and always recompute it from
/// `downloadSpeed` via [NetworkQuality.fromBandwidth]. On Android API >= 23,
/// `downloadSpeed` derives from `NetworkCapabilities
/// .linkDownstreamBandwidthKbps`, which Android documents as a hint that
/// may legitimately be `0` on a live, connected network — so a `0` hint
/// misreported a connected device as offline.
///
/// `fromPlatform` now honours `data['quality']` when it parses to a real
/// [NetworkQuality] member, falling back to `fromBandwidth` only when the
/// key is absent or unparseable — see that factory's doc comment in
/// `lib/src/models/network_status.dart`.
void main() {
  final ts = DateTime(2025, 1, 1);

  group('NetworkStatus.fromPlatform honours platform quality (issue #112)', () {
    test(
        'the exact failure from issue #112: wifi + downloadSpeed 0 + '
        'quality "good" is NOT offline', () {
      final status = NetworkStatus.fromPlatform({
        'connectionType': 'wifi',
        'downloadSpeed': 0,
        'quality': 'good',
        'isMetered': false,
      });

      expect(status.quality, NetworkQuality.good,
          reason: 'the platform-reported quality must win over a '
              'zero/degenerate bandwidth hint');
      expect(status.isAvailable, isTrue);
      expect(status.connectionType, ConnectionType.wifi);
      expect(status.downloadSpeed, 0);
    });

    test(
        'every quality string both natives can emit round-trips to the '
        'right enum value', () {
      const cases = {
        'excellent': NetworkQuality.excellent,
        'good': NetworkQuality.good,
        'fair': NetworkQuality.fair,
        'poor': NetworkQuality.poor,
        'offline': NetworkQuality.offline,
      };

      for (final entry in cases.entries) {
        final status = NetworkStatus.fromPlatform({
          'connectionType': 'wifi',
          'downloadSpeed': 1000000,
          'quality': entry.key,
          'isMetered': false,
        });
        expect(status.quality, entry.value,
            reason: 'quality "${entry.key}" should parse to '
                '${entry.value}');
      }
    });

    test(
        'an absent quality key falls back to fromBandwidth (backward '
        'compatibility with an older native build)', () {
      final status = NetworkStatus.fromPlatform({
        'connectionType': 'wifi',
        'downloadSpeed': 10000000, // 80 Mbps -> excellent bucket
        'isMetered': false,
      });

      expect(status.quality, NetworkQuality.excellent);
      expect(
        status.quality,
        NetworkQuality.fromBandwidth(10000000),
        reason: 'no "quality" key means the bandwidth-derived value must '
            'be used, unchanged from pre-#112 behavior',
      );
    });

    test(
        'a null quality value falls back to fromBandwidth like an absent '
        'key', () {
      final status = NetworkStatus.fromPlatform({
        'connectionType': 'wifi',
        'downloadSpeed': 0,
        'quality': null,
        'isMetered': false,
      });

      expect(status.quality, NetworkQuality.offline);
    });

    test(
        'an unparseable/garbage quality string degrades to fromBandwidth '
        'instead of throwing', () {
      expect(
        () => NetworkStatus.fromPlatform({
          'connectionType': 'wifi',
          'downloadSpeed': 10000000,
          'quality': 'super-duper-fast',
          'isMetered': false,
        }),
        returnsNormally,
      );

      final status = NetworkStatus.fromPlatform({
        'connectionType': 'wifi',
        'downloadSpeed': 10000000,
        'quality': 'super-duper-fast',
        'isMetered': false,
      });
      expect(status.quality, NetworkQuality.fromBandwidth(10000000));
    });

    test(
        'a non-string quality value degrades to fromBandwidth instead of '
        'throwing', () {
      expect(
        () => NetworkStatus.fromPlatform({
          'connectionType': 'wifi',
          'downloadSpeed': 62500,
          'quality': 42,
          'isMetered': false,
        }),
        returnsNormally,
      );

      final status = NetworkStatus.fromPlatform({
        'connectionType': 'wifi',
        'downloadSpeed': 62500,
        'quality': 42,
        'isMetered': false,
      });
      expect(status.quality, NetworkQuality.fromBandwidth(62500));
    });

    test(
        'quality string matching is case-insensitive, like '
        'ConnectionType.fromString', () {
      final status = NetworkStatus.fromPlatform({
        'connectionType': 'wifi',
        'downloadSpeed': 0,
        'quality': 'GOOD',
        'isMetered': false,
      });

      expect(status.quality, NetworkQuality.good);
    });

    test('toMap() -> fromPlatform() round-trips the quality field', () {
      final original = NetworkStatus(
        quality: NetworkQuality.fair,
        downloadSpeed: 0,
        isMetered: true,
        connectionType: ConnectionType.cellular,
        timestamp: ts,
      );

      final roundTripped = NetworkStatus.fromPlatform(original.toMap());

      expect(roundTripped.quality, original.quality,
          reason: 'toMap() writes quality.name; fromPlatform() must parse '
              'it back to the same member, independent of downloadSpeed');
      expect(roundTripped.downloadSpeed, original.downloadSpeed);
      expect(roundTripped.isMetered, original.isMetered);
      expect(roundTripped.connectionType, original.connectionType);
    });

    test(
        'toMap() -> fromPlatform() round-trips every NetworkQuality '
        'value', () {
      for (final quality in NetworkQuality.values) {
        final original = NetworkStatus(
          quality: quality,
          downloadSpeed: 500000,
          isMetered: false,
          connectionType: ConnectionType.wifi,
          timestamp: ts,
        );

        final roundTripped = NetworkStatus.fromPlatform(original.toMap());
        expect(roundTripped.quality, quality,
            reason: '$quality must round-trip through toMap()/fromPlatform()');
      }
    });
  });
}
