import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

/// Issue #125 — `PlayerState.error` is terminal until a host command.
///
/// ## What these tests prove
///
/// A failed load used to end in `paused` (iOS) or `idle` (Android), never
/// `error`. `errorStream` was always correct; `PlaybackState.state` was not.
/// The cause was ordering, not missing error reporting: both platforms emit
/// a *quiescent* state event as a direct consequence of the failure, and it
/// arrives immediately after `onError`, which `_handleStateChanged` then
/// applied unconditionally.
///
/// These tests drive the exact native event sequences each platform
/// produces, through the real `MethodChannel` event router, and assert the
/// error survives.
///
/// ## What these tests do NOT cover
///
/// - **The native suppressions (layer A).** `MediaPlayerManager.kt`'s
///   `isInReportedError()` guard on `onPlaybackStateChanged`/
///   `onIsPlayingChanged`, and `MediaPlayerManager.swift`'s `.failed` guard
///   in `handleTimeControlStatusChange`, are Kotlin/Swift and are not part
///   of this package's Dart test pipeline (see CLAUDE.md's "Gaps"). They are
///   verified by inspection and require on-device confirmation. Everything
///   asserted here is the Dart latch (layer B), which is deliberately
///   redundant with them: it is the only protection for new Dart running
///   against an older cached native build that still emits the trailing
///   event.
/// - **The iOS main-thread hop** (`invokeOnMainThread`) — inspection and
///   on-device only.
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

  group('a reported error is not erased by the next native state event', () {
    /// iOS's shape: an `AVPlayerItem` failure drives `timeControlStatus` to
    /// `.paused`, which `handleTimeControlStatusChange` reported as an
    /// ordinary `"paused"` knowing nothing about the failure. The result was
    /// byte-identical to a viewer pause — the reporter's exact complaint.
    test('iOS shape: onError then "paused" stays PlayerState.error', () async {
      final player = MediaPlayer(playerId: 'terminal-error-ios');
      await player.initialize();

      await injectEvent('onError', {
        'playerId': 'terminal-error-ios',
        'error': 'The requested URL was not found on this server',
        'category': 'HTTP',
        'httpStatusCode': 404,
      });
      await Future<void>.delayed(Duration.zero);
      expect(player.currentState.state, PlayerState.error);

      await injectEvent('onStateChanged', {
        'playerId': 'terminal-error-ios',
        'state': 'paused',
        'isBuffering': false,
        'bufferPercentage': 0.0,
      });
      await Future<void>.delayed(Duration.zero);

      expect(player.currentState.state, PlayerState.error,
          reason: 'A post-failure "paused" is error-derived noise, not a '
              'viewer pause — it must not overwrite the error.');
      expect(player.currentState.errorMessage,
          'The requested URL was not found on this server');

      await player.dispose();
    });

    /// Android's shape: ExoPlayer goes to `STATE_IDLE` on error, reported as
    /// `"idle"`. Media3 1.11.0 queues `EVENT_PLAYER_ERROR` before
    /// `EVENT_PLAYBACK_STATE_CHANGED`, so the error genuinely arrives first
    /// and was then clobbered.
    test('Android shape: onError then "idle" stays PlayerState.error',
        () async {
      final player = MediaPlayer(playerId: 'terminal-error-android');
      await player.initialize();

      await injectEvent('onError', {
        'playerId': 'terminal-error-android',
        'error': 'Unable to connect',
        'category': 'NETWORK',
        'nativeErrorCode': 'ERROR_CODE_IO_NETWORK_CONNECTION_FAILED',
      });
      await injectEvent('onStateChanged', {
        'playerId': 'terminal-error-android',
        'state': 'idle',
        'isBuffering': false,
        'bufferPercentage': 0.0,
      });
      await Future<void>.delayed(Duration.zero);

      expect(player.currentState.state, PlayerState.error);
      expect(player.currentState.errorMessage, 'Unable to connect');

      await player.dispose();
    });

    /// `ready` is included because it is a *quiescent* state too: a native
    /// build that reports "ready" after a failure is describing a player
    /// sitting still, not one playing. Only genuine forward progress
    /// (`playing`/`completed`) ends the latch.
    test('onError then "ready" stays PlayerState.error', () async {
      final player = MediaPlayer(playerId: 'terminal-error-ready');
      await player.initialize();

      await injectEvent('onError', {
        'playerId': 'terminal-error-ready',
        'error': 'Source error',
        'category': 'SOURCE',
      });
      await injectEvent('onStateChanged', {
        'playerId': 'terminal-error-ready',
        'state': 'ready',
        'isBuffering': false,
        'bufferPercentage': 0.0,
      });
      await Future<void>.delayed(Duration.zero);

      expect(player.currentState.state, PlayerState.error);

      await player.dispose();
    });

    test('the latch survives a whole run of quiescent events', () async {
      final player = MediaPlayer(playerId: 'terminal-error-run');
      await player.initialize();

      await injectEvent('onError', {
        'playerId': 'terminal-error-run',
        'error': 'Decoder init failed',
        'category': 'DECODER',
      });
      for (final state in const ['idle', 'paused', 'buffering', 'ready']) {
        await injectEvent('onStateChanged', {
          'playerId': 'terminal-error-run',
          'state': state,
          'isBuffering': state == 'buffering',
          'bufferPercentage': 0.0,
        });
        await Future<void>.delayed(Duration.zero);
        expect(player.currentState.state, PlayerState.error,
            reason: '"$state" after an error must not clear it');
      }

      await player.dispose();
    });

    /// Buffer telemetry is deliberately NOT held back by the latch — a host
    /// watching buffer health to decide whether to retry needs it to keep
    /// updating after a failure. Only the coarse `state` is pinned.
    test('buffer telemetry still flows through while latched', () async {
      final player = MediaPlayer(playerId: 'terminal-error-telemetry');
      await player.initialize();

      await injectEvent('onError', {
        'playerId': 'terminal-error-telemetry',
        'error': 'Network unreachable',
        'category': 'NETWORK',
      });
      await injectEvent('onStateChanged', {
        'playerId': 'terminal-error-telemetry',
        'state': 'buffering',
        'isBuffering': true,
        'bufferPercentage': 42.0,
      });
      await Future<void>.delayed(Duration.zero);

      expect(player.currentState.state, PlayerState.error);
      expect(player.currentState.isBuffering, isTrue);
      expect(player.currentState.bufferPercentage, 42.0);

      await player.dispose();
    });

    test('a DRM session error is latched the same way', () async {
      final player = MediaPlayer(playerId: 'terminal-error-drm');
      await player.initialize();

      final now = DateTime.now();
      await injectEvent('onDrmSessionUpdate', {
        'playerId': 'terminal-error-drm',
        'id': 'session-1',
        'state': 'error',
        'license': null,
        'errorMessage': 'License server rejected request',
        'createdAt': now.millisecondsSinceEpoch,
        'updatedAt': now.millisecondsSinceEpoch,
      });
      await injectEvent('onStateChanged', {
        'playerId': 'terminal-error-drm',
        'state': 'idle',
        'isBuffering': false,
        'bufferPercentage': 0.0,
      });
      await Future<void>.delayed(Duration.zero);

      expect(player.currentState.state, PlayerState.error);
      expect(
          player.currentState.errorMessage, 'License server rejected request');

      await player.dispose();
    });
  });

  group('the latch is released', () {
    test('by native reporting real forward progress ("playing")', () async {
      final player = MediaPlayer(playerId: 'terminal-error-clear-playing');
      await player.initialize();

      await injectEvent('onError', {
        'playerId': 'terminal-error-clear-playing',
        'error': 'Transient failure',
        'category': 'NETWORK',
      });
      await Future<void>.delayed(Duration.zero);
      expect(player.currentState.state, PlayerState.error);

      await injectEvent('onStateChanged', {
        'playerId': 'terminal-error-clear-playing',
        'state': 'playing',
        'isBuffering': false,
        'bufferPercentage': 0.0,
      });
      await Future<void>.delayed(Duration.zero);

      expect(player.currentState.state, PlayerState.playing);

      // And a later quiescent event is honoured again — the latch is gone,
      // not merely bypassed once.
      await injectEvent('onStateChanged', {
        'playerId': 'terminal-error-clear-playing',
        'state': 'paused',
        'isBuffering': false,
        'bufferPercentage': 0.0,
      });
      await Future<void>.delayed(Duration.zero);
      expect(player.currentState.state, PlayerState.paused);

      await player.dispose();
    });

    test('by native reporting "completed"', () async {
      final player = MediaPlayer(playerId: 'terminal-error-clear-completed');
      await player.initialize();

      await injectEvent('onError', {
        'playerId': 'terminal-error-clear-completed',
        'error': 'Transient failure',
        'category': 'NETWORK',
      });
      await injectEvent('onStateChanged', {
        'playerId': 'terminal-error-clear-completed',
        'state': 'completed',
        'isBuffering': false,
        'bufferPercentage': 100.0,
      });
      await Future<void>.delayed(Duration.zero);

      expect(player.currentState.state, PlayerState.completed);

      await player.dispose();
    });

    test('by an explicit host play() — the retry path', () async {
      final player = MediaPlayer(playerId: 'terminal-error-clear-play');
      await player.initialize();

      await injectEvent('onError', {
        'playerId': 'terminal-error-clear-play',
        'error': 'Transient failure',
        'category': 'NETWORK',
      });
      await Future<void>.delayed(Duration.zero);
      expect(player.currentState.state, PlayerState.error);

      await player.play();

      await injectEvent('onStateChanged', {
        'playerId': 'terminal-error-clear-play',
        'state': 'paused',
        'isBuffering': false,
        'bufferPercentage': 0.0,
      });
      await Future<void>.delayed(Duration.zero);

      expect(player.currentState.state, PlayerState.paused,
          reason: 'After an explicit host command the latch is gone and '
              'native state is reported verbatim again.');

      await player.dispose();
    });

    test('by an explicit host stop()', () async {
      final player = MediaPlayer(playerId: 'terminal-error-clear-stop');
      await player.initialize();

      await injectEvent('onError', {
        'playerId': 'terminal-error-clear-stop',
        'error': 'Transient failure',
        'category': 'NETWORK',
      });
      await player.stop();
      expect(player.currentState.state, PlayerState.idle);

      await injectEvent('onStateChanged', {
        'playerId': 'terminal-error-clear-stop',
        'state': 'idle',
        'isBuffering': false,
        'bufferPercentage': 0.0,
      });
      await Future<void>.delayed(Duration.zero);
      expect(player.currentState.state, PlayerState.idle);

      await player.dispose();
    });

    test('by an explicit host load()', () async {
      final player = MediaPlayer(playerId: 'terminal-error-clear-load');
      await player.initialize();

      await injectEvent('onError', {
        'playerId': 'terminal-error-clear-load',
        'error': 'Transient failure',
        'category': 'NETWORK',
      });
      await Future<void>.delayed(Duration.zero);
      expect(player.currentState.state, PlayerState.error);

      await player.load(const MediaItem(
        id: 'retry-1',
        url: 'https://example.com/video.mp4',
        title: 'Retry',
      ));
      expect(player.currentState.state, PlayerState.buffering);

      await player.dispose();
    });
  });

  group('errorStream is unaffected by the latch', () {
    test('emits exactly one typed exception per onError, with its category',
        () async {
      final player = MediaPlayer(playerId: 'terminal-error-stream');
      await player.initialize();

      final received = <MediaPlayerException>[];
      final sub = player.errorStream.listen(received.add);

      await injectEvent('onError', {
        'playerId': 'terminal-error-stream',
        'error': 'Unable to connect',
        'category': 'NETWORK',
      });
      // The trailing quiescent event must not produce a second exception.
      await injectEvent('onStateChanged', {
        'playerId': 'terminal-error-stream',
        'state': 'idle',
        'isBuffering': false,
        'bufferPercentage': 0.0,
      });
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single, isA<NetworkException>());
      expect((received.single as NetworkException).isTimeout, isFalse);

      await injectEvent('onError', {
        'playerId': 'terminal-error-stream',
        'error': 'Licence expired',
        'category': 'DRM',
        'nativeErrorCode': 'ERROR_CODE_DRM_LICENSE_EXPIRED',
      });
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(2));
      expect(received[1], isA<DrmException>());
      expect((received[1] as DrmException).errorCode,
          'ERROR_CODE_DRM_LICENSE_EXPIRED');

      await sub.cancel();
      await player.dispose();
    });

    test('an HTTP category still carries its status code', () async {
      final player = MediaPlayer(playerId: 'terminal-error-http');
      await player.initialize();

      final errorFuture = player.errorStream.first;
      await injectEvent('onError', {
        'playerId': 'terminal-error-http',
        'error': 'Not found',
        'category': 'HTTP',
        'httpStatusCode': 404,
      });

      final error = await errorFuture.timeout(const Duration(seconds: 2));
      expect(error, isA<MediaLoadException>());
      expect((error as MediaLoadException).statusCode, 404);

      await player.dispose();
    });
  });
}
