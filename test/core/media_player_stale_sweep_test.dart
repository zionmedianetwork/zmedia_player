// H-10 regression coverage: the periodic stale-instance sweep
// (`MediaPlayer._cleanupStaleInstances`) must not dispose a paused instance
// the app still holds a live reference to, while still reclaiming instances
// that are genuinely abandoned.
//
// "Still referenced" is determined by MediaPlayer._isReferencedByLiveConsumer:
//   1. an explicit attach()/detach() reference count > 0, or
//   2. a live subscription on one of the "primary" broadcast streams a
//      typical consumer listens to for its own lifetime (stateStream /
//      positionStream) — this covers MediaController, which subscribes in
//      its constructor and only unsubscribes in its own dispose(), without
//      requiring any change to MediaController itself.
//
// The sweep normally only runs every 5 minutes against a 15-minute
// inactivity threshold; `MediaPlayer.debugRunStaleSweepForTest()` and
// `MediaPlayer.debugMarkStaleForTest()` are `@visibleForTesting` hooks that
// let this test exercise it deterministically without waiting on real
// wall-clock time.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

const _channel = MethodChannel('zmedia_player');

void _installNoopHandler() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (MethodCall call) async => null);
}

void _resetHandler() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null);
}

/// `isPlaying` reflects the last `PlaybackState` pushed via the native
/// `onStateChanged` event — play() itself only issues the channel call, it
/// does not optimistically flip local state. Inject the event to make a
/// player genuinely "playing" for tests that need it.
Future<void> _injectStateChanged(String playerId, String state) async {
  final codec = const StandardMethodCodec();
  final data = codec.encodeMethodCall(MethodCall(
    'onStateChanged',
    {
      'playerId': playerId,
      'state': state,
      'isBuffering': false,
      'bufferPercentage': 0.0,
    },
  ));
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage('zmedia_player', data, (_) {});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(_installNoopHandler);
  tearDown(_resetHandler);

  group('H-10 — stale-instance sweep respects live references', () {
    test('an abandoned paused instance IS reclaimed by the sweep', () async {
      final player = MediaPlayer(playerId: 'h10-abandoned');
      await player.initialize();
      await player.play();
      await _injectStateChanged(player.playerId, 'playing');
      await player.pause();
      await _injectStateChanged(player.playerId, 'paused');
      expect(player.isPlaying, isFalse);

      expect(player.isDisposed, isFalse);

      MediaPlayer.debugMarkStaleForTest('h10-abandoned');
      MediaPlayer.debugRunStaleSweepForTest();

      // Sweep disposal is asynchronous (dispose() is awaited internally via
      // catchError, not blocking the sweep call itself); give it a tick.
      await Future<void>.delayed(Duration.zero);

      expect(player.isDisposed, isTrue,
          reason: 'a genuinely abandoned paused instance must still be '
              'reclaimed — this must not become a leak');
    });

    test('a paused instance with a live stream subscription survives the sweep',
        () async {
      final player = MediaPlayer(playerId: 'h10-referenced-via-stream');
      await player.initialize();
      await player.play();
      await _injectStateChanged(player.playerId, 'playing');
      await player.pause();
      await _injectStateChanged(player.playerId, 'paused');
      expect(player.isPlaying, isFalse);

      // Mimic what MediaController does: subscribe to stateStream for the
      // lifetime of the consumer, without ever calling attach().
      final sub = player.stateStream.listen((_) {});

      MediaPlayer.debugMarkStaleForTest('h10-referenced-via-stream');
      MediaPlayer.debugRunStaleSweepForTest();
      await Future<void>.delayed(Duration.zero);

      expect(player.isDisposed, isFalse,
          reason: 'a live stateStream listener must protect the instance '
              'from the sweep even though it is paused and "stale" by '
              'inactivity alone');

      // Once the listener goes away and enough time passes again, it must
      // become eligible for reclamation — the fallback isn't a permanent
      // exemption.
      await sub.cancel();
      MediaPlayer.debugMarkStaleForTest('h10-referenced-via-stream');
      MediaPlayer.debugRunStaleSweepForTest();
      await Future<void>.delayed(Duration.zero);

      expect(player.isDisposed, isTrue,
          reason: 'once the stream subscription is cancelled and the '
              'instance goes stale again, it must be reclaimed');
    });

    test('a paused instance with an explicit attach() survives the sweep',
        () async {
      final player = MediaPlayer(playerId: 'h10-referenced-via-attach');
      await player.initialize();
      await player.play();
      await _injectStateChanged(player.playerId, 'playing');
      await player.pause();
      await _injectStateChanged(player.playerId, 'paused');
      expect(player.isPlaying, isFalse);

      player.attach();

      MediaPlayer.debugMarkStaleForTest('h10-referenced-via-attach');
      MediaPlayer.debugRunStaleSweepForTest();
      await Future<void>.delayed(Duration.zero);

      expect(player.isDisposed, isFalse,
          reason: 'attach() must protect the instance from the sweep '
              'regardless of playback state or elapsed inactivity');

      // After detach(), it gets a fresh activity grace period rather than
      // being immediately eligible — mark it stale again explicitly.
      player.detach();
      MediaPlayer.debugMarkStaleForTest('h10-referenced-via-attach');
      MediaPlayer.debugRunStaleSweepForTest();
      await Future<void>.delayed(Duration.zero);

      expect(player.isDisposed, isTrue,
          reason: 'once detached (and stale again), the instance must be '
              'reclaimed — attach()/detach() must not be a permanent '
              'exemption');
    });

    test('a playing instance is never swept regardless of references',
        () async {
      final player = MediaPlayer(playerId: 'h10-playing-survives');
      await player.initialize();
      await player.play();
      await _injectStateChanged('h10-playing-survives', 'playing');
      expect(player.isPlaying, isTrue);

      MediaPlayer.debugMarkStaleForTest('h10-playing-survives');
      MediaPlayer.debugRunStaleSweepForTest();
      await Future<void>.delayed(Duration.zero);

      expect(player.isDisposed, isFalse,
          reason: 'an actively playing instance must never be swept');

      await player.dispose();
    });

    test('ordinary interaction (seekTo) refreshes activity', () async {
      final player = MediaPlayer(playerId: 'h10-seek-refreshes-activity');
      await player.initialize();
      await player.play();
      await _injectStateChanged(player.playerId, 'playing');
      await player.pause();
      await _injectStateChanged(player.playerId, 'paused');
      expect(player.isPlaying, isFalse);

      // Go stale, then interact (seekTo) without attach()/listeners, then
      // sweep immediately — the seek should have reset the activity clock,
      // so a sweep run right after must NOT reclaim it.
      MediaPlayer.debugMarkStaleForTest('h10-seek-refreshes-activity');
      await player.seekTo(const Duration(seconds: 5));
      MediaPlayer.debugRunStaleSweepForTest();
      await Future<void>.delayed(Duration.zero);

      expect(player.isDisposed, isFalse,
          reason: 'seekTo() must count as activity and reset the staleness '
              'clock, so a sweep immediately afterwards must not reclaim '
              'the instance');

      await player.dispose();
    });
  });
}
