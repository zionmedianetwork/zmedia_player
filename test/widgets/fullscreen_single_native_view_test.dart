// Regression tests for the fullscreen single-native-view bug.
//
// Root cause: when FullscreenMediaPlayer pushes a new route, it mounts a
// second MediaPlayerWidget for the same controller/playerId.  On Android the
// second host calls MediaPlayerViewFactory.create() which returns the cached
// singleton PlayerView; that PlayerView is then ripped from the inline host's
// hierarchy (a View can only have one parent), leaving the inline host showing
// black while the fullscreen host may also show black due to timing.
//
// Fix summary:
//   - Android native: getPlayerView() now creates a NEW MediaPlayerView per
//     host, detaching the ExoPlayer from the old view first.
//   - Dart: _onPlatformViewCreated calls reclaimVideoSurface() via method
//     channel to re-attach the ExoPlayer to the newest PlayerView.
//   - didChangeDependencies calls reclaimVideoSurface() when the inline player
//     returns to screen after the fullscreen route pops.
//   - iOS: getPlayerView() already creates one AVPlayerLayer per host (AVPlayer
//     supports multiple layers); a no-op reclaimVideoSurface handler is
//     registered so the Dart call does not raise a PlatformException.
//
// These tests verify the Dart-layer MethodChannel contract only (no native
// compilation in headless tests).  On-device integration testing is required
// to confirm the native re-parenting works correctly.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

const _channel = MethodChannel('zmedia_player');

List<MethodCall> _installCapture() {
  final calls = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (MethodCall call) async {
    calls.add(call);
    return null;
  });
  return calls;
}

void _resetHandler() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MediaPlayer.reclaimVideoSurface — method channel contract', () {
    late MediaPlayer player;
    late List<MethodCall> calls;

    setUp(() {
      calls = _installCapture();
      player = MediaPlayer(playerId: 'test_reclaim');
    });

    tearDown(() {
      _resetHandler();
      // Dispose is fire-and-forget in tests; ignore errors.
      player.dispose().ignore();
    });

    test('reclaimVideoSurface sends correct method and playerId', () async {
      // Initialize first so isInitialized is true and the call is forwarded.
      await player.initialize();

      await player.reclaimVideoSurface();

      final reclaimCalls =
          calls.where((c) => c.method == 'reclaimVideoSurface').toList();
      expect(reclaimCalls, hasLength(1),
          reason:
              'Exactly one reclaimVideoSurface call must be sent to the channel');

      final args = reclaimCalls.first.arguments as Map;
      expect(args['playerId'], equals('test_reclaim'),
          reason: 'playerId must match the player instance');
    });

    test('reclaimVideoSurface is a no-op when player is not yet initialized',
        () async {
      // Do NOT call initialize() — player.isInitialized == false.
      await player.reclaimVideoSurface();

      final reclaimCalls =
          calls.where((c) => c.method == 'reclaimVideoSurface').toList();
      expect(reclaimCalls, isEmpty,
          reason:
              'No channel call must be made when the player is not initialized');
    });

    test('reclaimVideoSurface does not throw when native returns an error',
        () async {
      // Override handler to simulate a native error (e.g. older plugin version
      // that returns UNIMPLEMENTED).
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (MethodCall call) async {
        if (call.method == 'reclaimVideoSurface') {
          throw PlatformException(code: 'UNIMPLEMENTED');
        }
        return null;
      });

      await player.initialize();

      // Must not throw — reclaimVideoSurface swallows PlatformException.
      await expectLater(player.reclaimVideoSurface(), completes);
    });

    test('reclaimVideoSurface does not throw on generic error', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (MethodCall call) async {
        if (call.method == 'reclaimVideoSurface') {
          throw Exception('unexpected error');
        }
        return null;
      });

      await player.initialize();

      await expectLater(player.reclaimVideoSurface(), completes);
    });
  });
}
