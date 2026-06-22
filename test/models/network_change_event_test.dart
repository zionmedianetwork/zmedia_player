import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

/// Tests for Fix 5: inverted qualityImproved / qualityDegraded flags.
///
/// NetworkQuality enum order (lower index = better):
///   excellent = 0, good = 1, fair = 2, poor = 3, offline = 4, unknown = 5
///
/// qualityImproved must be true when moving to a LOWER index (better quality).
/// qualityDegraded must be true when moving to a HIGHER index (worse quality).
void main() {
  // A fixed timestamp for deterministic tests.
  final ts = DateTime(2025, 1, 1);

  // Helper to build a minimal NetworkStatus for a given quality level.
  NetworkStatus status(NetworkQuality q) => NetworkStatus(
        quality: q,
        downloadSpeed: 0,
        isMetered: false,
        connectionType: ConnectionType.wifi,
        timestamp: ts,
      );

  group('NetworkChangeEvent quality flags', () {
    // --- qualityImproved ---

    test('qualityImproved is true when quality goes from poor to excellent',
        () {
      final event = NetworkChangeEvent(
        previousStatus: status(NetworkQuality.poor),
        currentStatus: status(NetworkQuality.excellent),
      );

      expect(event.qualityImproved, isTrue,
          reason: 'poor(3) → excellent(0): index decreased → improved');
      expect(event.qualityDegraded, isFalse);
    });

    test('qualityImproved is true when quality goes from fair to good', () {
      final event = NetworkChangeEvent(
        previousStatus: status(NetworkQuality.fair),
        currentStatus: status(NetworkQuality.good),
      );

      expect(event.qualityImproved, isTrue,
          reason: 'fair(2) → good(1): index decreased → improved');
      expect(event.qualityDegraded, isFalse);
    });

    test('qualityImproved is true when quality goes from good to excellent',
        () {
      final event = NetworkChangeEvent(
        previousStatus: status(NetworkQuality.good),
        currentStatus: status(NetworkQuality.excellent),
      );

      expect(event.qualityImproved, isTrue);
      expect(event.qualityDegraded, isFalse);
    });

    // --- qualityDegraded ---

    test('qualityDegraded is true when quality goes from excellent to poor',
        () {
      final event = NetworkChangeEvent(
        previousStatus: status(NetworkQuality.excellent),
        currentStatus: status(NetworkQuality.poor),
      );

      expect(event.qualityDegraded, isTrue,
          reason: 'excellent(0) → poor(3): index increased → degraded');
      expect(event.qualityImproved, isFalse);
    });

    test('qualityDegraded is true when quality goes from good to fair', () {
      final event = NetworkChangeEvent(
        previousStatus: status(NetworkQuality.good),
        currentStatus: status(NetworkQuality.fair),
      );

      expect(event.qualityDegraded, isTrue,
          reason: 'good(1) → fair(2): index increased → degraded');
      expect(event.qualityImproved, isFalse);
    });

    test('qualityDegraded is true when quality goes from excellent to fair',
        () {
      final event = NetworkChangeEvent(
        previousStatus: status(NetworkQuality.excellent),
        currentStatus: status(NetworkQuality.fair),
      );

      expect(event.qualityDegraded, isTrue);
      expect(event.qualityImproved, isFalse);
    });

    // --- no change ---

    test('neither flag set when quality stays the same', () {
      final event = NetworkChangeEvent(
        previousStatus: status(NetworkQuality.good),
        currentStatus: status(NetworkQuality.good),
      );

      expect(event.qualityImproved, isFalse);
      expect(event.qualityDegraded, isFalse);
    });

    // --- no previous status ---

    test('neither flag set when previousStatus is null', () {
      final event = NetworkChangeEvent(
        previousStatus: null,
        currentStatus: status(NetworkQuality.excellent),
      );

      expect(event.qualityImproved, isFalse);
      expect(event.qualityDegraded, isFalse);
    });

    // --- connection lost / restored remain unaffected ---

    test(
        'connectionLost is true when previous was available and current is not',
        () {
      final event = NetworkChangeEvent(
        previousStatus: status(NetworkQuality.good),
        currentStatus: status(NetworkQuality.offline),
      );

      expect(event.connectionLost, isTrue);
      expect(event.connectionRestored, isFalse);
    });

    test(
        'connectionRestored is true when previous was offline and current is available',
        () {
      final event = NetworkChangeEvent(
        previousStatus: status(NetworkQuality.offline),
        currentStatus: status(NetworkQuality.good),
      );

      expect(event.connectionRestored, isTrue);
      expect(event.connectionLost, isFalse);
    });

    // --- isSignificant reflects corrected flags ---

    test('isSignificant is true when quality improved', () {
      final event = NetworkChangeEvent(
        previousStatus: status(NetworkQuality.poor),
        currentStatus: status(NetworkQuality.excellent),
      );

      expect(event.isSignificant, isTrue);
    });

    test('isSignificant is true when quality degraded', () {
      final event = NetworkChangeEvent(
        previousStatus: status(NetworkQuality.excellent),
        currentStatus: status(NetworkQuality.poor),
      );

      expect(event.isSignificant, isTrue);
    });

    test('isSignificant is false when nothing changed', () {
      final event = NetworkChangeEvent(
        previousStatus: status(NetworkQuality.good),
        currentStatus: status(NetworkQuality.good),
      );

      expect(event.isSignificant, isFalse);
    });
  });
}
