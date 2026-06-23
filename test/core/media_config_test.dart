import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

/// Phase 1: Core MediaConfig tests
void main() {
  group('MediaConfig', () {
    test('creates with default values', () {
      const config = MediaConfig();

      expect(config.autoPlay, false);
      expect(config.looping, false);
      expect(config.volume, 1.0);
      expect(config.speed, 1.0);
      expect(config.startMuted, false);
      expect(config.showControls, true);
      expect(config.boxFit, BoxFit.contain);
      expect(config.httpHeaders?.isEmpty ?? true, true);
    });

    test('creates with custom values', () {
      final config = MediaConfig(
        autoPlay: true,
        looping: true,
        volume: 0.5,
        speed: 1.5,
        startMuted: true,
        showControls: false,
        boxFit: BoxFit.cover,
        httpHeaders: {'Authorization': 'Bearer token'},
        controlsTimeout: const Duration(seconds: 5),
        allowBackgroundPlayback: true,
        useHardwareAcceleration: true,
      );

      expect(config.autoPlay, true);
      expect(config.looping, true);
      expect(config.volume, 0.5);
      expect(config.speed, 1.5);
      expect(config.startMuted, true);
      expect(config.showControls, false);
      expect(config.boxFit, BoxFit.cover);
      expect(config.httpHeaders?['Authorization'], 'Bearer token');
      expect(config.controlsTimeout, const Duration(seconds: 5));
      expect(config.allowBackgroundPlayback, true);
      expect(config.useHardwareAcceleration, true);
    });

    test('validates volume range', () {
      const config1 = MediaConfig(volume: -0.5);
      const config2 = MediaConfig(volume: 0.0);
      const config3 = MediaConfig(volume: 1.0);
      const config4 = MediaConfig(volume: 1.5);

      expect(config1.volume, -0.5); // Will be clamped by player
      expect(config2.volume, 0.0);
      expect(config3.volume, 1.0);
      expect(config4.volume, 1.5); // Will be clamped by player
    });

    test('validates speed range', () {
      const config1 = MediaConfig(speed: 0.1);
      const config2 = MediaConfig(speed: 0.25);
      const config3 = MediaConfig(speed: 2.0);
      const config4 = MediaConfig(speed: 4.0);
      const config5 = MediaConfig(speed: 5.0);

      expect(config1.speed, 0.1); // Will be clamped by player
      expect(config2.speed, 0.25);
      expect(config3.speed, 2.0);
      expect(config4.speed, 4.0);
      expect(config5.speed, 5.0); // Will be clamped by player
    });

    test('copyWith creates modified config', () {
      const original = MediaConfig(
        autoPlay: false,
        volume: 1.0,
        showControls: true,
      );

      final modified = original.copyWith(
        autoPlay: true,
        volume: 0.5,
      );

      expect(modified.autoPlay, true);
      expect(modified.volume, 0.5);
      expect(modified.showControls, true); // Unchanged
    });

    test('copyWith preserves original when no changes', () {
      const original = MediaConfig(
        autoPlay: true,
        looping: true,
        volume: 0.8,
      );

      final copy = original.copyWith();

      expect(copy.autoPlay, original.autoPlay);
      expect(copy.looping, original.looping);
      expect(copy.volume, original.volume);
    });

    group('BoxFit values', () {
      test('supports all BoxFit options', () {
        const configs = [
          MediaConfig(boxFit: BoxFit.contain),
          MediaConfig(boxFit: BoxFit.cover),
          MediaConfig(boxFit: BoxFit.fill),
          MediaConfig(boxFit: BoxFit.fitWidth),
          MediaConfig(boxFit: BoxFit.fitHeight),
          MediaConfig(boxFit: BoxFit.none),
          MediaConfig(boxFit: BoxFit.scaleDown),
        ];

        expect(configs[0].boxFit, BoxFit.contain);
        expect(configs[1].boxFit, BoxFit.cover);
        expect(configs[2].boxFit, BoxFit.fill);
        expect(configs[3].boxFit, BoxFit.fitWidth);
        expect(configs[4].boxFit, BoxFit.fitHeight);
        expect(configs[5].boxFit, BoxFit.none);
        expect(configs[6].boxFit, BoxFit.scaleDown);
      });
    });

    group('HTTP Headers', () {
      test('supports custom headers', () {
        final config = MediaConfig(
          httpHeaders: {
            'Authorization': 'Bearer token123',
            'User-Agent': 'FlutterApp/1.0',
            'X-Custom-Header': 'custom-value',
          },
        );

        expect(config.httpHeaders?['Authorization'], 'Bearer token123');
        expect(config.httpHeaders?['User-Agent'], 'FlutterApp/1.0');
        expect(config.httpHeaders?['X-Custom-Header'], 'custom-value');
      });

      test('handles empty headers', () {
        const config = MediaConfig(httpHeaders: {});
        expect(config.httpHeaders?.isEmpty ?? true, true);
      });
    });

    group('Background Playback', () {
      test('allows background playback when enabled', () {
        const config = MediaConfig(allowBackgroundPlayback: true);
        expect(config.allowBackgroundPlayback, true);
      });

      test('disables background playback by default', () {
        const config = MediaConfig();
        expect(config.allowBackgroundPlayback, false);
      });
    });

    group('Hardware Acceleration', () {
      test('enables hardware acceleration when requested', () {
        const config = MediaConfig(useHardwareAcceleration: true);
        expect(config.useHardwareAcceleration, true);
      });

      test('enables hardware acceleration by default', () {
        const config = MediaConfig();
        expect(config.useHardwareAcceleration, true);
      });
    });

    group('Controls Configuration', () {
      test('configures controls timeout', () {
        const config1 = MediaConfig(controlsTimeout: Duration(seconds: 3));
        const config2 = MediaConfig(controlsTimeout: Duration(seconds: 10));

        expect(config1.controlsTimeout, const Duration(seconds: 3));
        expect(config2.controlsTimeout, const Duration(seconds: 10));
      });

      test('uses default controls timeout', () {
        const config = MediaConfig();
        expect(config.controlsTimeout, const Duration(seconds: 3));
      });
    });

    group('Equality', () {
      test('configs with same values are equal', () {
        const config1 = MediaConfig(
          autoPlay: true,
          volume: 0.8,
          looping: true,
        );

        const config2 = MediaConfig(
          autoPlay: true,
          volume: 0.8,
          looping: true,
        );

        expect(config1 == config2, true);
      });

      test('configs with different values are not equal', () {
        const config1 = MediaConfig(autoPlay: true);
        const config2 = MediaConfig(autoPlay: false);

        expect(config1 == config2, false);
      });
    });

    // -------------------------------------------------------------------------
    // respectSafeArea
    // -------------------------------------------------------------------------
    group('respectSafeArea', () {
      test('defaults to false', () {
        const config = MediaConfig();
        expect(config.respectSafeArea, false);
      });

      test('can be set to true', () {
        const config = MediaConfig(respectSafeArea: true);
        expect(config.respectSafeArea, true);
      });

      test('copyWith updates respectSafeArea', () {
        const original = MediaConfig(respectSafeArea: false);
        final updated = original.copyWith(respectSafeArea: true);
        expect(updated.respectSafeArea, true);
        // Other fields preserved
        expect(updated.autoPlay, original.autoPlay);
        expect(updated.volume, original.volume);
      });

      test('copyWith preserves respectSafeArea when not specified', () {
        const original = MediaConfig(respectSafeArea: true);
        final copy = original.copyWith();
        expect(copy.respectSafeArea, true);
      });

      test(
          'equality: same respectSafeArea value produces equal const instances',
          () {
        const a = MediaConfig(respectSafeArea: true);
        const b = MediaConfig(respectSafeArea: true);
        expect(a == b, true);
      });

      test('equality: differing respectSafeArea produces unequal instances',
          () {
        const a = MediaConfig(respectSafeArea: false);
        const b = MediaConfig(respectSafeArea: true);
        expect(a == b, false);
      });

      test('toString includes respectSafeArea', () {
        const config = MediaConfig(respectSafeArea: true);
        expect(config.toString(), contains('respectSafeArea: true'));
      });
    });

    // -------------------------------------------------------------------------
    // immersiveLandscape
    // -------------------------------------------------------------------------
    group('immersiveLandscape', () {
      test('defaults to false', () {
        const config = MediaConfig();
        expect(config.immersiveLandscape, false);
      });

      test('can be set to true', () {
        const config = MediaConfig(immersiveLandscape: true);
        expect(config.immersiveLandscape, true);
      });

      test('copyWith updates immersiveLandscape', () {
        const original = MediaConfig(immersiveLandscape: false);
        final updated = original.copyWith(immersiveLandscape: true);
        expect(updated.immersiveLandscape, true);
        // Other fields preserved
        expect(updated.autoPlay, original.autoPlay);
        expect(updated.looping, original.looping);
      });

      test('copyWith preserves immersiveLandscape when not specified', () {
        const original = MediaConfig(immersiveLandscape: true);
        final copy = original.copyWith();
        expect(copy.immersiveLandscape, true);
      });

      test(
          'equality: same immersiveLandscape value produces equal const instances',
          () {
        const a = MediaConfig(immersiveLandscape: true);
        const b = MediaConfig(immersiveLandscape: true);
        expect(a == b, true);
      });

      test('equality: differing immersiveLandscape produces unequal instances',
          () {
        const a = MediaConfig(immersiveLandscape: false);
        const b = MediaConfig(immersiveLandscape: true);
        expect(a == b, false);
      });

      test('toString includes immersiveLandscape', () {
        const config = MediaConfig(immersiveLandscape: true);
        expect(config.toString(), contains('immersiveLandscape: true'));
      });
    });

    // -------------------------------------------------------------------------
    // Both flags together
    // -------------------------------------------------------------------------
    group('respectSafeArea + immersiveLandscape together', () {
      test('both flags can be set independently', () {
        const config = MediaConfig(
          respectSafeArea: true,
          immersiveLandscape: true,
        );
        expect(config.respectSafeArea, true);
        expect(config.immersiveLandscape, true);
      });

      test('copyWith can update both flags independently', () {
        const original = MediaConfig();
        final updated =
            original.copyWith(respectSafeArea: true, immersiveLandscape: true);
        expect(updated.respectSafeArea, true);
        expect(updated.immersiveLandscape, true);
      });

      test('copyWith updates one flag without touching the other', () {
        const original =
            MediaConfig(respectSafeArea: true, immersiveLandscape: false);
        final updated = original.copyWith(immersiveLandscape: true);
        expect(updated.respectSafeArea, true); // unchanged
        expect(updated.immersiveLandscape, true); // changed
      });

      test('equality: two const instances with same flag combo are equal', () {
        const a = MediaConfig(respectSafeArea: true, immersiveLandscape: true);
        const b = MediaConfig(respectSafeArea: true, immersiveLandscape: true);
        expect(a == b, true);
      });

      test('equality: differing flag combo produces unequal instances', () {
        const a = MediaConfig(respectSafeArea: true, immersiveLandscape: false);
        const b = MediaConfig(respectSafeArea: true, immersiveLandscape: true);
        expect(a == b, false);
      });

      test('toString includes both flags', () {
        const config =
            MediaConfig(respectSafeArea: true, immersiveLandscape: true);
        final str = config.toString();
        expect(str, contains('respectSafeArea: true'));
        expect(str, contains('immersiveLandscape: true'));
      });

      test('existing fields (boxFit, volume) are unaffected when new flags set',
          () {
        const config = MediaConfig(
          boxFit: BoxFit.cover,
          volume: 0.5,
          respectSafeArea: true,
          immersiveLandscape: true,
        );
        expect(config.boxFit, BoxFit.cover);
        expect(config.volume, 0.5);
        expect(config.respectSafeArea, true);
        expect(config.immersiveLandscape, true);
      });
    });
  });
}
