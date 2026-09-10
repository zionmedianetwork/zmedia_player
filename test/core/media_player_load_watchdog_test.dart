import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

/// Issue #125 — the `MediaConfig.loadTimeout` load watchdog.
///
/// `load()` completing means "the item was handed to the platform", not "it
/// loaded". A load that is accepted and then never resolves either way — no
/// `onError`, no `ready`/`playing` — leaves the player in `buffering`
/// forever with nothing on any stream. The watchdog turns that silence into
/// a real, typed failure.
///
/// The default is 30s; these tests inject a short timeout instead of waiting
/// on it. The *negative* cases matter as much as the positive one: a false
/// "this stream is dead" is a worse failure than a late true one, which is
/// why the watchdog re-checks both the state and the position before firing.
///
/// Not covered here: the native side, which knows nothing about this — the
/// timer is Dart-only and `loadTimeout` deliberately never crosses the
/// MethodChannel (asserted in `media_config_load_timeout_test.dart`).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> injectEvent(String method, Map<String, dynamic> args) async {
    const codec = StandardMethodCodec();
    final data = codec.encodeMethodCall(MethodCall(method, args));
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage('zmedia_player', data, (_) {});
  }

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('zmedia_player'),
      (_) async => null,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('zmedia_player'), null);
  });

  const item = MediaItem(
    id: 'watchdog-item',
    url: 'https://example.com/never-resolves.m3u8',
    title: 'Never resolves',
  );

  const shortTimeout = Duration(milliseconds: 120);

  MediaPlayer buildPlayer(String id, {Duration? timeout = shortTimeout}) {
    return MediaPlayer(
      playerId: id,
      // The constructor takes `loadTimeout` directly, so `null` here really
      // does mean "disabled" (unlike `copyWith`, where clearing needs the
      // explicit `clearLoadTimeout` flag — see its own test).
      config: MediaConfig(loadTimeout: timeout),
    );
  }

  group('fires when a load never resolves', () {
    test('reports a NetworkException and PlayerState.error', () async {
      final player = buildPlayer('watchdog-fires');
      await player.initialize();

      final errorFuture = player.errorStream.first;
      await player.load(item);
      expect(player.currentState.state, PlayerState.buffering);

      final error = await errorFuture.timeout(const Duration(seconds: 3));

      expect(error, isA<NetworkException>());
      expect((error as NetworkException).isTimeout, isTrue,
          reason: 'A watchdog failure is a timeout, and a host filtering on '
              'isTimeout should see it as one.');
      expect(error.message, contains('loadTimeout'));
      expect(player.currentState.state, PlayerState.error);
      expect(player.currentState.errorMessage, isNotNull);

      await player.dispose();
    });

    test('the synthesized error is latched like a native one', () async {
      final player = buildPlayer('watchdog-latched');
      await player.initialize();

      final errorFuture = player.errorStream.first;
      await player.load(item);
      await errorFuture.timeout(const Duration(seconds: 3));

      await injectEvent('onStateChanged', {
        'playerId': 'watchdog-latched',
        'state': 'idle',
        'isBuffering': false,
        'bufferPercentage': 0.0,
      });
      await Future<void>.delayed(Duration.zero);

      expect(player.currentState.state, PlayerState.error);

      await player.dispose();
    });
  });

  group('does not fire — the false-positive guards', () {
    /// The primary guard: any definitive outcome disarms the watchdog.
    test('when native reports "ready" before the timeout', () async {
      final player = buildPlayer('watchdog-ready');
      await player.initialize();

      var errorEmitted = false;
      final sub = player.errorStream.listen((_) => errorEmitted = true);

      await player.load(item);
      await injectEvent('onStateChanged', {
        'playerId': 'watchdog-ready',
        'state': 'ready',
        'isBuffering': false,
        'bufferPercentage': 0.0,
      });

      await Future<void>.delayed(shortTimeout * 3);

      expect(errorEmitted, isFalse,
          reason: 'A load that became ready must never be reported as a '
              'timeout, however slow it was.');
      expect(player.currentState.state, PlayerState.ready);

      await sub.cancel();
      await player.dispose();
    });

    test('when native reports "playing" before the timeout', () async {
      final player = buildPlayer('watchdog-playing');
      await player.initialize();

      var errorEmitted = false;
      final sub = player.errorStream.listen((_) => errorEmitted = true);

      await player.load(item);
      await injectEvent('onStateChanged', {
        'playerId': 'watchdog-playing',
        'state': 'playing',
        'isBuffering': false,
        'bufferPercentage': 0.0,
      });
      await Future<void>.delayed(shortTimeout * 3);

      expect(errorEmitted, isFalse);
      expect(player.currentState.state, PlayerState.playing);

      await sub.cancel();
      await player.dispose();
    });

    /// The second guard, independent of the first: still `buffering`, but
    /// the playhead has moved, so the load is slow rather than dead. This is
    /// the case that protects a long DRM handshake or a cold-CDN manifest
    /// fetch on a bad connection.
    test('when still buffering but the position has advanced', () async {
      final player = buildPlayer('watchdog-progress');
      await player.initialize();

      var errorEmitted = false;
      final sub = player.errorStream.listen((_) => errorEmitted = true);

      await player.load(item);
      expect(player.currentState.state, PlayerState.buffering);

      await injectEvent('onPositionChanged', {
        'playerId': 'watchdog-progress',
        'position': 2500,
      });
      await Future<void>.delayed(shortTimeout * 3);

      expect(errorEmitted, isFalse,
          reason: 'A load that is progressing is not a dead load.');
      expect(player.currentState.state, PlayerState.buffering);

      await sub.cancel();
      await player.dispose();
    });

    test('when native already reported an error of its own', () async {
      final player = buildPlayer('watchdog-native-error');
      await player.initialize();

      final errors = <MediaPlayerException>[];
      final sub = player.errorStream.listen(errors.add);

      await player.load(item);
      await injectEvent('onError', {
        'playerId': 'watchdog-native-error',
        'error': 'Not found',
        'category': 'HTTP',
        'httpStatusCode': 404,
      });
      await Future<void>.delayed(shortTimeout * 3);

      expect(errors, hasLength(1),
          reason: 'The real failure has already been reported; a synthesized '
              'timeout on top of it would be noise.');
      expect(errors.single, isA<MediaLoadException>());

      await sub.cancel();
      await player.dispose();
    });

    test('after pause() abandons the wait', () async {
      final player = buildPlayer('watchdog-pause');
      await player.initialize();

      var errorEmitted = false;
      final sub = player.errorStream.listen((_) => errorEmitted = true);

      await player.load(item);
      await player.pause();
      await Future<void>.delayed(shortTimeout * 3);

      expect(errorEmitted, isFalse);

      await sub.cancel();
      await player.dispose();
    });

    test('after stop() abandons the wait', () async {
      final player = buildPlayer('watchdog-stop');
      await player.initialize();

      var errorEmitted = false;
      final sub = player.errorStream.listen((_) => errorEmitted = true);

      await player.load(item);
      await player.stop();
      await Future<void>.delayed(shortTimeout * 3);

      expect(errorEmitted, isFalse);

      await sub.cancel();
      await player.dispose();
    });

    /// A timer that outlived its player would fire against a disposed
    /// instance and throw from a closed stream controller.
    test('after dispose(), with nothing thrown', () async {
      final player = buildPlayer('watchdog-dispose');
      await player.initialize();
      await player.load(item);
      await player.dispose();

      await Future<void>.delayed(shortTimeout * 3);
      // Reaching here without an unhandled exception is the assertion.
      expect(true, isTrue);
    });

    test('when loadTimeout is null (watchdog disabled)', () async {
      final player = buildPlayer('watchdog-disabled', timeout: null);
      await player.initialize();
      expect(player.config.loadTimeout, isNull);

      var errorEmitted = false;
      final sub = player.errorStream.listen((_) => errorEmitted = true);

      await player.load(item);
      await Future<void>.delayed(shortTimeout * 4);

      expect(errorEmitted, isFalse,
          reason: 'Opting out must restore the pre-#125 "wait forever" '
              'behaviour exactly.');
      expect(player.currentState.state, PlayerState.buffering);

      await sub.cancel();
      await player.dispose();
    });
  });

  test('a second load() re-arms the watchdog rather than stacking timers',
      () async {
    final player = buildPlayer('watchdog-rearm');
    await player.initialize();

    final errors = <MediaPlayerException>[];
    final sub = player.errorStream.listen(errors.add);

    await player.load(item);
    await player.load(item);
    await Future<void>.delayed(shortTimeout * 3);

    expect(errors, hasLength(1),
        reason: 'Two loads in flight must not produce two timeouts.');

    await sub.cancel();
    await player.dispose();
  });
}
