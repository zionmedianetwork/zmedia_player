import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

// ---------------------------------------------------------------------------
// Helper — build a named QualityTrack quickly
// ---------------------------------------------------------------------------

QualityTrack _track(String id, int bitrateKbps) => QualityTrack(
      id: id,
      name: id,
      bitrate: bitrateKbps * 1000,
      isAvailable: true,
    );

QualityTrack _unavailableTrack(String id, int bitrateKbps) => QualityTrack(
      id: id,
      name: id,
      bitrate: bitrateKbps * 1000,
      isAvailable: false,
    );

void main() {
  // =========================================================================
  group('StreamingService — initial state', () {
    test('estimatedBandwidth starts at 0', () {
      final s = StreamingService(const StreamingConfig());
      expect(s.estimatedBandwidth, 0);
      s.dispose();
    });

    test('availableQualityTracks starts empty', () {
      final s = StreamingService(const StreamingConfig());
      expect(s.availableQualityTracks, isEmpty);
      s.dispose();
    });

    test('currentQualityTrack starts null', () {
      final s = StreamingService(const StreamingConfig());
      expect(s.currentQualityTrack, isNull);
      s.dispose();
    });
  });

  // =========================================================================
  group('StreamingService — getRecommendedQuality (bandwidth threshold)', () {
    // Default config has qualitySwitchThreshold = 0.8, so effective bitrate
    // budget is bandwidth * 0.8.

    test('returns null when no tracks are set', () {
      final s = StreamingService(const StreamingConfig());
      s.updateBandwidth(10000000); // 10 Mbps
      expect(s.getRecommendedQuality(), isNull);
      s.dispose();
    });

    test('returns null when bandwidth is still 0', () {
      final s = StreamingService(const StreamingConfig());
      s.setAvailableQualityTracks([
        _track('q-360', 1000),
        _track('q-720', 3000),
      ]);
      // No bandwidth injected yet (_estimatedBandwidth == 0)
      expect(s.getRecommendedQuality(), isNull);
      s.dispose();
    });

    test('returns highest track that fits within 80% of bandwidth', () {
      final s = StreamingService(const StreamingConfig());
      s.setAvailableQualityTracks([
        _track('q-360', 1000), // 1 Mbps
        _track('q-720', 3000), // 3 Mbps
        _track('q-1080', 5000), // 5 Mbps
      ]);

      // Bandwidth = 4 Mbps → effective budget = 4 * 0.8 = 3.2 Mbps
      // → q-720 (3 Mbps) fits, q-1080 (5 Mbps) does not.
      s.updateBandwidth(4000000);

      final rec = s.getRecommendedQuality();
      expect(rec, isNotNull);
      expect(rec!.id, 'q-720',
          reason:
              'q-720 (3 Mbps) is the highest track under the 3.2 Mbps budget');
      s.dispose();
    });

    test('returns lowest track when bandwidth is too small for any track', () {
      final s = StreamingService(const StreamingConfig());
      s.setAvailableQualityTracks([
        _track('q-360', 1000), // 1 Mbps
        _track('q-720', 3000), // 3 Mbps
      ]);

      // Bandwidth = 100 kbps → effective budget = 80 kbps → no track fits
      // → fall back to first (lowest) track.
      s.updateBandwidth(100000);

      final rec = s.getRecommendedQuality();
      expect(rec, isNotNull);
      expect(rec!.id, 'q-360',
          reason: 'Must fall back to lowest track when nothing fits');
      s.dispose();
    });

    test('returns highest available track when bandwidth is very high', () {
      final s = StreamingService(const StreamingConfig());
      s.setAvailableQualityTracks([
        _track('q-360', 1000),
        _track('q-720', 3000),
        _track('q-1080', 5000),
        _track('q-4k', 20000),
      ]);

      // Bandwidth = 100 Mbps → effective budget = 80 Mbps → all tracks fit
      s.updateBandwidth(100000000);

      final rec = s.getRecommendedQuality();
      expect(rec!.id, 'q-4k',
          reason: 'Highest track must be selected when bandwidth is unlimited');
      s.dispose();
    });

    test('skips unavailable tracks', () {
      final s = StreamingService(const StreamingConfig());
      s.setAvailableQualityTracks([
        _track('q-360', 1000),
        _unavailableTrack('q-720', 3000), // unavailable
        _track('q-1080', 5000),
      ]);

      // Budget = 4 * 0.8 = 3.2 Mbps → q-1080 does not fit, q-720 is unavailable,
      // → q-360 is the recommendation.
      s.updateBandwidth(4000000);

      final rec = s.getRecommendedQuality();
      expect(rec!.id, 'q-360',
          reason: 'Unavailable tracks must not be recommended');
      s.dispose();
    });

    test('respects minBitrate constraint', () {
      final s = StreamingService(
        const StreamingConfig(
          minBitrate: 2000000, // 2 Mbps minimum
        ),
      );
      s.setAvailableQualityTracks([
        _track('q-360', 500), // 0.5 Mbps — below min
        _track('q-720', 3000), // 3 Mbps — above min
      ]);

      // Budget = 10 * 0.8 = 8 Mbps → q-720 fits and is above min.
      s.updateBandwidth(10000000);

      final rec = s.getRecommendedQuality();
      expect(rec!.id, 'q-720',
          reason: 'Tracks below minBitrate must be excluded');
      s.dispose();
    });

    test('respects maxBitrate constraint', () {
      final s = StreamingService(
        const StreamingConfig(
          maxBitrate: 3000000, // 3 Mbps maximum
        ),
      );
      s.setAvailableQualityTracks([
        _track('q-720', 3000), // exactly at max
        _track('q-1080', 5000), // above max
      ]);

      s.updateBandwidth(100000000);

      final rec = s.getRecommendedQuality();
      expect(rec!.id, 'q-720',
          reason: 'Tracks above maxBitrate must be excluded');
      s.dispose();
    });
  });

  // =========================================================================
  group('StreamingService — hysteresis / qualitySwitchThreshold', () {
    test(
        'qualitySwitchThreshold = 0.8 means only 80% of bandwidth is usable for quality selection',
        () {
      final s = StreamingService(
        const StreamingConfig(qualitySwitchThreshold: 0.8),
      );
      s.setAvailableQualityTracks([
        _track('q-720', 3000), // 3 Mbps
        _track('q-1080', 5000), // 5 Mbps
      ]);

      // Bandwidth exactly at 5 Mbps — effective budget = 5 * 0.8 = 4 Mbps.
      // q-1080 requires 5 Mbps, which exceeds the 4 Mbps budget.
      s.updateBandwidth(5000000);

      final rec = s.getRecommendedQuality();
      expect(rec!.id, 'q-720',
          reason:
              'At exactly target bitrate, threshold prevents recommending highest track');
      s.dispose();
    });

    test('qualitySwitchThreshold = 1.0 allows selection at 100% of bandwidth',
        () {
      final s = StreamingService(
        const StreamingConfig(qualitySwitchThreshold: 1.0),
      );
      s.setAvailableQualityTracks([
        _track('q-720', 3000),
        _track('q-1080', 5000),
      ]);

      // At threshold = 1.0, budget equals bandwidth exactly.
      s.updateBandwidth(5000000);

      final rec = s.getRecommendedQuality();
      expect(rec!.id, 'q-1080',
          reason:
              'With threshold=1.0, track exactly matching bandwidth is allowed');
      s.dispose();
    });

    test('shouldSwitchQuality returns false when no current track', () {
      final s = StreamingService(
        const StreamingConfig(enableAutoQualitySwitch: true),
      );
      s.setAvailableQualityTracks([
        _track('q-720', 3000),
        _track('q-1080', 5000),
      ]);
      s.updateBandwidth(5000000);

      // No current track set → should not switch (nothing to switch FROM).
      expect(s.shouldSwitchQuality(), isFalse,
          reason:
              'shouldSwitchQuality must return false when currentQualityTrack is null');
      s.dispose();
    });

    test('shouldSwitchQuality returns false when auto-switch is disabled', () {
      final s = StreamingService(
        const StreamingConfig(enableAutoQualitySwitch: false),
      );
      final tracks = [
        _track('q-720', 3000),
        _track('q-1080', 5000),
      ];
      s.setAvailableQualityTracks(tracks);
      s.selectQualityTrack(tracks.first);
      s.updateBandwidth(100000000); // more than enough for either track

      expect(s.shouldSwitchQuality(), isFalse);
      s.dispose();
    });

    test(
        'shouldSwitchQuality returns true when recommended is more than 20% different',
        () {
      final s = StreamingService(
        const StreamingConfig(enableAutoQualitySwitch: true),
      );
      final tracks = [
        _track('q-low', 500), // 0.5 Mbps
        _track('q-high', 5000), // 5 Mbps
      ];
      s.setAvailableQualityTracks(tracks);

      // Manually set current track to q-high.
      s.selectQualityTrack(tracks[1]);

      // Low bandwidth: recommended = q-low (fallback), current = q-high
      // Diff = |0.5M - 5M| = 4.5M; threshold = 5M * 0.2 = 1M → should switch.
      s.updateBandwidth(300000); // 300 kbps — way below q-low's bitrate

      expect(s.shouldSwitchQuality(), isTrue,
          reason: 'Large bitrate difference must trigger a quality switch');
      s.dispose();
    });
  });

  // =========================================================================
  group('StreamingService — bandwidth moving average', () {
    test('single measurement sets estimated bandwidth immediately', () {
      final s = StreamingService(const StreamingConfig());
      s.updateBandwidth(5000000);
      expect(s.estimatedBandwidth, 5000000);
      s.dispose();
    });

    test('average of multiple measurements is returned', () {
      final s = StreamingService(const StreamingConfig());
      s.updateBandwidth(4000000);
      s.updateBandwidth(6000000);
      // Average = (4M + 6M) / 2 = 5M
      expect(s.estimatedBandwidth, 5000000);
      s.dispose();
    });

    test('resetBandwidth clears history and resets to 0', () {
      final s = StreamingService(const StreamingConfig());
      s.updateBandwidth(5000000);
      s.updateBandwidth(8000000);
      s.resetBandwidth();
      expect(s.estimatedBandwidth, 0);
      expect(s.getRecommendedQuality(), isNull,
          reason: 'After reset bandwidth=0 → no recommendation');
      s.dispose();
    });

    test('bandwidth stream emits updated values', () async {
      final s = StreamingService(const StreamingConfig());
      final values = <int>[];
      s.bandwidthStream.listen(values.add);

      s.updateBandwidth(1000000);
      s.updateBandwidth(2000000);
      await Future<void>.delayed(Duration.zero);

      expect(values, isNotEmpty,
          reason: 'bandwidthStream must emit values on update');
      s.dispose();
    });
  });

  // =========================================================================
  group('StreamingService — manual track selection', () {
    test('selectQualityTrack sets currentQualityTrack', () {
      final s = StreamingService(const StreamingConfig());
      final tracks = [_track('q-1', 1000), _track('q-2', 3000)];
      s.setAvailableQualityTracks(tracks);

      s.selectQualityTrack(tracks[1]);

      expect(s.currentQualityTrack?.id, 'q-2');
      s.dispose();
    });

    test('selectQualityTrack with unknown id throws StreamingException', () {
      final s = StreamingService(const StreamingConfig());
      s.setAvailableQualityTracks([_track('q-1', 1000)]);

      const unknown = QualityTrack(id: 'ghost', name: 'Ghost', bitrate: 0);
      expect(
        () => s.selectQualityTrack(unknown),
        throwsA(isA<StreamingException>()),
      );
      s.dispose();
    });

    test('enableAutoQuality clears currentQualityTrack', () {
      final s = StreamingService(const StreamingConfig());
      final tracks = [_track('q-1', 1000)];
      s.setAvailableQualityTracks(tracks);
      s.selectQualityTrack(tracks.first);

      s.enableAutoQuality();

      expect(s.currentQualityTrack, isNull,
          reason: 'enableAutoQuality must clear manual selection');
      s.dispose();
    });

    test('getHighestQuality returns track with largest bitrate', () {
      final s = StreamingService(const StreamingConfig());
      s.setAvailableQualityTracks([
        _track('q-low', 500),
        _track('q-mid', 3000),
        _track('q-high', 8000),
      ]);

      expect(s.getHighestQuality()?.id, 'q-high');
      s.dispose();
    });

    test('getLowestQuality returns track with smallest bitrate', () {
      final s = StreamingService(const StreamingConfig());
      s.setAvailableQualityTracks([
        _track('q-low', 500),
        _track('q-mid', 3000),
        _track('q-high', 8000),
      ]);

      expect(s.getLowestQuality()?.id, 'q-low');
      s.dispose();
    });

    test('getQualityTrackById returns correct track', () {
      final s = StreamingService(const StreamingConfig());
      s.setAvailableQualityTracks([
        _track('q-a', 1000),
        _track('q-b', 3000),
      ]);

      expect(s.getQualityTrackById('q-b')?.id, 'q-b');
    });

    test('getQualityTrackById returns null for unknown id', () {
      final s = StreamingService(const StreamingConfig());
      s.setAvailableQualityTracks([_track('q-a', 1000)]);

      expect(s.getQualityTrackById('nonexistent'), isNull);
      s.dispose();
    });

    test('setAvailableQualityTracks sorts tracks by ascending bitrate', () {
      final s = StreamingService(const StreamingConfig());
      s.setAvailableQualityTracks([
        _track('q-high', 5000),
        _track('q-low', 500),
        _track('q-mid', 2000),
      ]);

      final ids = s.availableQualityTracks.map((t) => t.id).toList();
      expect(ids, ['q-low', 'q-mid', 'q-high'],
          reason: 'Tracks must be sorted ascending by bitrate');
      s.dispose();
    });
  });

  // =========================================================================
  group('StreamingService — formatted helpers', () {
    test('getFormattedBandwidth uses bps for small values', () {
      final s = StreamingService(const StreamingConfig());
      s.updateBandwidth(500);
      expect(s.getFormattedBandwidth(), contains('bps'));
      s.dispose();
    });

    test('getFormattedBandwidth uses Kbps for kilo range', () {
      final s = StreamingService(const StreamingConfig());
      s.updateBandwidth(500000);
      expect(s.getFormattedBandwidth(), contains('Kbps'));
      s.dispose();
    });

    test('getFormattedBandwidth uses Mbps for mega range', () {
      final s = StreamingService(const StreamingConfig());
      s.updateBandwidth(5000000);
      expect(s.getFormattedBandwidth(), contains('Mbps'));
      s.dispose();
    });
  });

  // =========================================================================
  group('StreamingService — dispose safety', () {
    test('dispose is idempotent', () {
      final s = StreamingService(const StreamingConfig());
      s.dispose();
      expect(() => s.dispose(), returnsNormally);
    });

    test('updateBandwidth after dispose is a no-op (does not throw)', () {
      final s = StreamingService(const StreamingConfig());
      s.dispose();
      expect(() => s.updateBandwidth(5000000), returnsNormally);
    });
  });
}
