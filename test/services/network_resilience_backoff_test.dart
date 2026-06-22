import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/src/services/network_resilience_service.dart';

/// Tests for Fix 2: true exponential backoff in RetryConfig.calculateDelay.
///
/// Default config: initialDelay=1s, backoffMultiplier=2.0, maxDelay=30s
///
///   attempt 1 → 1s   (1000 * 2^0)
///   attempt 2 → 2s   (1000 * 2^1)
///   attempt 3 → 4s   (1000 * 2^2)
///   attempt 4 → 8s   (1000 * 2^3)
///   attempt 5 → 16s  (1000 * 2^4)
///   attempt 6 → 30s  (capped at maxDelay: 1000 * 2^5 = 32s > 30s)
void main() {
  group('RetryConfig.calculateDelay — exponential backoff', () {
    const defaultConfig = RetryConfig();

    // -------------------------------------------------------------------
    // Attempt-number edge cases
    // -------------------------------------------------------------------

    test('attempt 0 returns Duration.zero', () {
      expect(defaultConfig.calculateDelay(0), Duration.zero);
    });

    test('negative attempt returns Duration.zero', () {
      expect(defaultConfig.calculateDelay(-1), Duration.zero);
    });

    // -------------------------------------------------------------------
    // Default config delay sequence (1s initial, 2× multiplier, 30s cap)
    // -------------------------------------------------------------------

    test('attempt 1 returns initialDelay (1 second)', () {
      expect(defaultConfig.calculateDelay(1), const Duration(seconds: 1));
    });

    test('attempt 2 returns initialDelay * multiplier (2 seconds)', () {
      expect(defaultConfig.calculateDelay(2), const Duration(seconds: 2));
    });

    test('attempt 3 returns initialDelay * multiplier^2 (4 seconds)', () {
      expect(defaultConfig.calculateDelay(3), const Duration(seconds: 4));
    });

    test('attempt 4 returns 8 seconds', () {
      expect(defaultConfig.calculateDelay(4), const Duration(seconds: 8));
    });

    test('attempt 5 returns 16 seconds', () {
      expect(defaultConfig.calculateDelay(5), const Duration(seconds: 16));
    });

    test('attempt 6 is capped at maxDelay (30 seconds)', () {
      // 1000ms * 2^5 = 32000ms > 30000ms → capped at 30s.
      expect(defaultConfig.calculateDelay(6), const Duration(seconds: 30));
    });

    test('very high attempt number is also capped at maxDelay', () {
      expect(defaultConfig.calculateDelay(100), const Duration(seconds: 30));
    });

    // -------------------------------------------------------------------
    // Delay is strictly increasing before the cap
    // -------------------------------------------------------------------

    test('each successive attempt has a longer (or equal) delay', () {
      Duration previous = Duration.zero;
      for (var i = 1; i <= 10; i++) {
        final current = defaultConfig.calculateDelay(i);
        expect(current >= previous, isTrue,
            reason: 'attempt $i delay (${current.inMilliseconds}ms) must be '
                '>= previous (${previous.inMilliseconds}ms)');
        previous = current;
      }
    });

    // -------------------------------------------------------------------
    // Aggressive config (500ms initial, 1.5× multiplier, 15s cap)
    // -------------------------------------------------------------------

    test('aggressive config — attempt 1 returns 500ms', () {
      final config = RetryConfig.aggressive();
      expect(config.calculateDelay(1), const Duration(milliseconds: 500));
    });

    test('aggressive config — attempt 2 returns 750ms', () {
      final config = RetryConfig.aggressive();
      expect(config.calculateDelay(2), const Duration(milliseconds: 750));
    });

    test('aggressive config — attempt 3 returns 1125ms', () {
      final config = RetryConfig.aggressive();
      expect(config.calculateDelay(3), const Duration(milliseconds: 1125));
    });

    test('aggressive config — high attempt is capped at 15 seconds', () {
      final config = RetryConfig.aggressive();
      expect(config.calculateDelay(50), const Duration(seconds: 15));
    });

    // -------------------------------------------------------------------
    // Conservative config (2s initial, 3× multiplier, 60s cap)
    // -------------------------------------------------------------------

    test('conservative config — attempt 1 returns 2 seconds', () {
      final config = RetryConfig.conservative();
      expect(config.calculateDelay(1), const Duration(seconds: 2));
    });

    test('conservative config — attempt 2 returns 6 seconds', () {
      final config = RetryConfig.conservative();
      expect(config.calculateDelay(2), const Duration(seconds: 6));
    });

    test('conservative config — attempt 3 returns 18 seconds', () {
      final config = RetryConfig.conservative();
      expect(config.calculateDelay(3), const Duration(seconds: 18));
    });

    test('conservative config — attempt 4 is capped at 60 seconds', () {
      // 2000 * 3^3 = 54000ms < 60000ms (not yet capped).
      // 2000 * 3^4 = 162000ms > 60000ms (capped).
      final config = RetryConfig.conservative();
      expect(config.calculateDelay(5), const Duration(seconds: 60));
    });

    // -------------------------------------------------------------------
    // Custom config — verify formula correctness
    // -------------------------------------------------------------------

    test('custom config: initialDelay=100ms, multiplier=4.0, cap=10s', () {
      const custom = RetryConfig(
        initialDelay: Duration(milliseconds: 100),
        backoffMultiplier: 4.0,
        maxDelay: Duration(seconds: 10),
      );

      // attempt 1: 100ms * 4^0 = 100ms
      expect(custom.calculateDelay(1), const Duration(milliseconds: 100));
      // attempt 2: 100ms * 4^1 = 400ms
      expect(custom.calculateDelay(2), const Duration(milliseconds: 400));
      // attempt 3: 100ms * 4^2 = 1600ms
      expect(custom.calculateDelay(3), const Duration(milliseconds: 1600));
      // attempt 4: 100ms * 4^3 = 6400ms
      expect(custom.calculateDelay(4), const Duration(milliseconds: 6400));
      // attempt 5: 100ms * 4^4 = 25600ms → capped at 10000ms
      expect(custom.calculateDelay(5), const Duration(seconds: 10));
    });
  });
}
