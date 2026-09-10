import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

/// Issue #125 — `MediaConfig.loadTimeout`.
///
/// Covers the three things a new `MediaConfig` field has to get right in
/// this codebase: the default, `copyWith` (including the `clearLoadTimeout`
/// escape hatch this field needs and the other nullable fields do not), and
/// serialization — which for this field means asserting it is *absent* from
/// every payload that crosses the MethodChannel.
///
/// Note on "equality": `MediaConfig` deliberately has no `operator ==` /
/// `hashCode` today (nor did it before this change — see
/// `test/models/value_model_equality_test.dart`, which covers the value
/// models that do). Adding one as a side effect of this fix would silently
/// change how host widgets that compare configs with `!=` decide whether to
/// reload. Equality is therefore asserted field-wise below, which is what
/// the class actually offers.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('zmedia_player');

  group('default', () {
    test('is 30 seconds — generous enough that a slow load is not killed', () {
      const config = MediaConfig();
      expect(config.loadTimeout, const Duration(seconds: 30));
    });

    test('can be set explicitly, including to null to opt out', () {
      const custom = MediaConfig(loadTimeout: Duration(seconds: 5));
      expect(custom.loadTimeout, const Duration(seconds: 5));

      const disabled = MediaConfig(loadTimeout: null);
      expect(disabled.loadTimeout, isNull);
    });
  });

  group('copyWith', () {
    test('preserves the field when not mentioned', () {
      const config = MediaConfig(loadTimeout: Duration(seconds: 7));
      expect(config.copyWith(autoPlay: true).loadTimeout,
          const Duration(seconds: 7));
    });

    test('replaces the field when given a value', () {
      const config = MediaConfig();
      expect(
          config.copyWith(loadTimeout: const Duration(seconds: 2)).loadTimeout,
          const Duration(seconds: 2));
    });

    /// The `??` idiom every other nullable field uses reads a passed `null`
    /// as "leave unchanged", which for this field would make opting out
    /// impossible after construction — hence the explicit flag, following
    /// `PlaybackState.copyWith`'s `clearLiveEdgeOffset` convention.
    test('passing null does NOT clear it; clearLoadTimeout does', () {
      const config = MediaConfig(loadTimeout: Duration(seconds: 7));

      expect(config.copyWith(loadTimeout: null).loadTimeout,
          const Duration(seconds: 7));
      expect(config.copyWith(clearLoadTimeout: true).loadTimeout, isNull);
    });

    test('clearLoadTimeout wins over a simultaneously passed value', () {
      const config = MediaConfig();
      final cleared = config.copyWith(
        loadTimeout: const Duration(seconds: 9),
        clearLoadTimeout: true,
      );
      expect(cleared.loadTimeout, isNull);
    });

    test('leaves every other field untouched', () {
      const config = MediaConfig(
        autoPlay: true,
        volume: 0.4,
        speed: 1.5,
        showControls: false,
      );
      final copy = config.copyWith(clearLoadTimeout: true);

      expect(copy.autoPlay, config.autoPlay);
      expect(copy.volume, config.volume);
      expect(copy.speed, config.speed);
      expect(copy.showControls, config.showControls);
    });
  });

  test('toString includes loadTimeout', () {
    expect(const MediaConfig().toString(), contains('loadTimeout'));
  });

  group('serialization — the field is Dart-side only', () {
    /// The watchdog timer lives entirely in `MediaPlayer`; neither native
    /// platform reads this value. Sending it would be a silent data-contract
    /// addition of exactly the kind CLAUDE.md calls the easiest to miss (a
    /// key native ignores produces zero analyzer errors and zero failing
    /// tests), so this asserts the negative explicitly.
    test('loadTimeout never crosses the MethodChannel', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));

      final player = MediaPlayer(
        playerId: 'config-load-timeout',
        config: const MediaConfig(loadTimeout: Duration(seconds: 11)),
      );
      await player.initialize();
      await player.load(const MediaItem(
        id: 'i',
        url: 'https://example.com/v.mp4',
        title: 'i',
      ));
      await player.updateConfig(
        const MediaConfig(loadTimeout: Duration(seconds: 12)),
      );

      // Every call that carries a serialized config: initialize, load,
      // updateConfig.
      final configCarrying = calls.where(
        (c) => (c.arguments as Map?)?.containsKey('config') ?? false,
      );
      expect(configCarrying, isNotEmpty,
          reason: 'The capture is broken if no call carried a config at all.');

      for (final call in configCarrying) {
        final config =
            (call.arguments as Map)['config'] as Map<dynamic, dynamic>;
        expect(config.containsKey('loadTimeout'), isFalse,
            reason: '"${call.method}" serialized loadTimeout, which no native '
                'code reads. Either remove it from _configToMap, or wire it '
                'up natively on BOTH platforms and document the new key in '
                'docs/api-reference/events.md.');
      }

      await player.dispose();
    });
  });
}
