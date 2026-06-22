import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _channel = MethodChannel('zmedia_player');

/// Injects a native→Dart event through the test messenger.
Future<void> _injectEvent(String method, Map<String, dynamic> arguments) async {
  final codec = const StandardMethodCodec();
  final data = codec.encodeMethodCall(MethodCall(method, arguments));
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage('zmedia_player', data, (_) {});
}

/// Captures outgoing channel calls in [calls].
List<MethodCall> _installCapture([
  Future<dynamic> Function(MethodCall)? extra,
]) {
  final calls = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (MethodCall call) async {
    calls.add(call);
    return extra != null ? await extra(call) : null;
  });
  return calls;
}

void _resetHandler() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(_resetHandler);

  // =========================================================================
  group('MediaController — lifecycle', () {
    test('create() factory returns a non-null controller', () {
      _installCapture();
      final c = MediaController.create(playerId: 'mc-create-1');
      expect(c, isNotNull);
      c.dispose();
    });

    test('initialize() delegates to player and succeeds', () async {
      final calls = _installCapture();
      final c = MediaController.create(playerId: 'mc-init-1');

      await c.initialize();

      expect(c.isInitialized, isTrue);
      expect(calls.any((call) => call.method == 'initialize'), isTrue);

      c.dispose();
    });

    test('isDisposed is false before dispose and true after', () async {
      _installCapture();
      final c = MediaController.create(playerId: 'mc-disposed-1');

      expect(c.isDisposed, isFalse);
      c.dispose();
      expect(c.isDisposed, isTrue);
    });

    test('initialize on disposed controller throws StateError', () async {
      _installCapture();
      final c = MediaController.create(playerId: 'mc-init-disposed');
      c.dispose();

      await expectLater(
        c.initialize(),
        throwsA(isA<StateError>()),
        reason: 'initialize after dispose must throw StateError',
      );
    });

    test('dispose is idempotent', () {
      _installCapture();
      final c = MediaController.create(playerId: 'mc-dispose-idemp');
      c.dispose();
      expect(() => c.dispose(), returnsNormally,
          reason: 'Second dispose must not throw');
    });

    test('play/pause after dispose are no-ops (do not throw)', () async {
      _installCapture();
      final c = MediaController.create(playerId: 'mc-noop-1');
      await c.initialize();
      c.dispose();

      // These must not throw — they silently return when disposed.
      await expectLater(c.play(), completes);
      await expectLater(c.pause(), completes);
    });
  });

  // =========================================================================
  group('MediaController — delegates to player (channel calls)', () {
    test('play() sends "play" to native channel', () async {
      final calls = _installCapture();
      final c = MediaController.create(playerId: 'mc-play-1');
      await c.initialize();
      calls.clear();

      await c.play();

      expect(calls.any((call) => call.method == 'play'), isTrue,
          reason: 'play() must forward to the "play" channel method');
    });

    test('pause() sends "pause" to native channel', () async {
      final calls = _installCapture();
      final c = MediaController.create(playerId: 'mc-pause-1');
      await c.initialize();
      calls.clear();

      await c.pause();

      expect(calls.any((call) => call.method == 'pause'), isTrue);
    });

    test('stop() sends "stop" to native channel', () async {
      final calls = _installCapture();
      final c = MediaController.create(playerId: 'mc-stop-1');
      await c.initialize();
      calls.clear();

      await c.stop();

      expect(calls.any((call) => call.method == 'stop'), isTrue);
    });

    test('seekTo() sends "seekTo" with correct position', () async {
      final calls = _installCapture();
      final c = MediaController.create(playerId: 'mc-seek-1');
      // Give the controller a non-zero duration so seekTo doesn't clamp to 0.
      await c.initialize();
      // Inject a duration so clamp logic allows the seek through.
      await _injectEvent('onDurationChanged', {
        'playerId': 'mc-seek-1',
        'duration': 300000, // 5 minutes
      });
      calls.clear();

      await c.seekTo(const Duration(seconds: 45));

      final seekCall =
          calls.firstWhere((call) => call.method == 'seekTo', orElse: () {
        fail('No "seekTo" call found');
      });
      expect(seekCall.arguments['position'], 45000);
    });

    test('setVolume() sends "setVolume" to channel', () async {
      final calls = _installCapture();
      final c = MediaController.create(playerId: 'mc-vol-1');
      await c.initialize();
      calls.clear();

      await c.setVolume(0.5);

      expect(calls.any((call) => call.method == 'setVolume'), isTrue);
    });

    test('setSpeed() sends "setSpeed" to channel', () async {
      final calls = _installCapture();
      final c = MediaController.create(playerId: 'mc-speed-1');
      await c.initialize();
      calls.clear();

      await c.setSpeed(1.25);

      expect(calls.any((call) => call.method == 'setSpeed'), isTrue);
    });

    test('enableAutoQuality() sends "enableAutoQuality" to channel', () async {
      final calls = _installCapture();
      final c = MediaController.create(playerId: 'mc-auto-q-1');
      await c.initialize();
      calls.clear();

      await c.enableAutoQuality();

      expect(calls.any((call) => call.method == 'enableAutoQuality'), isTrue);
    });

    test('setQualityTrack() sends "setQualityTrack" when track is in list',
        () async {
      final calls = _installCapture();
      final c = MediaController.create(playerId: 'mc-qt-1');
      await c.initialize();

      // Inject tracks so validation passes.
      await _injectEvent('onQualityTracksChanged', {
        'playerId': 'mc-qt-1',
        'tracks': [
          {
            'id': 'q-720',
            'name': 'HD',
            'bitrate': 3000000,
            'isSelected': false,
            'isAvailable': true,
          },
        ],
      });
      calls.clear();

      const track = QualityTrack(
        id: 'q-720',
        name: 'HD',
        bitrate: 3000000,
      );
      await c.setQualityTrack(track);

      expect(calls.any((call) => call.method == 'setQualityTrack'), isTrue);
    });

    test('setAudioTrack() sends "setAudioTrack" when track is in list',
        () async {
      final calls = _installCapture();
      final c = MediaController.create(playerId: 'mc-at-1');
      await c.initialize();

      await _injectEvent('onAudioTracksChanged', {
        'playerId': 'mc-at-1',
        'tracks': [
          {
            'id': 'a-en',
            'name': 'English',
            'language': 'en',
            'isSelected': false,
            'isAvailable': true,
          },
        ],
      });
      calls.clear();

      const track = AudioTrack(id: 'a-en', name: 'English', language: 'en');
      await c.setAudioTrack(track);

      expect(calls.any((call) => call.method == 'setAudioTrack'), isTrue);
    });
  });

  // =========================================================================
  group('MediaController — operation lock serialization', () {
    // We use a Completer to hold the mock handler "in flight" so we can test
    // what happens to a second call while the first is still pending.

    test('lock is false initially', () {
      _installCapture();
      final c = MediaController.create(playerId: 'mc-lock-init');
      expect(c.isOperationInProgress, isFalse);
      c.dispose();
    });

    test('lock is released after a successful operation', () async {
      _installCapture();
      final c = MediaController.create(playerId: 'mc-lock-success');
      await c.initialize();

      await c.enableAutoQuality();

      expect(c.isOperationInProgress, isFalse,
          reason: 'Lock must be false after operation completes');
      c.dispose();
    });

    test('lock is released even when operation throws', () async {
      _installCapture();
      final c = MediaController.create(playerId: 'mc-lock-throw');
      await c.initialize();

      // setQualityTrack with a non-existent track throws InvalidStateException.
      const fakeTrack = QualityTrack(id: 'ghost', name: 'Ghost', bitrate: 0);
      try {
        await c.setQualityTrack(fakeTrack);
      } catch (_) {
        // Expected.
      }

      expect(c.isOperationInProgress, isFalse,
          reason: 'Lock must be released in finally block on error');

      // Subsequent operation must succeed without hitting busy guard.
      await expectLater(c.enableAutoQuality(), completes);
      c.dispose();
    });

    test('non-critical op while lock is held throws OperationBusyException',
        () async {
      // Hold the first call's response until we explicitly resolve it.
      final holdCompleter = Completer<void>();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (MethodCall call) async {
        if (call.method == 'setVolume') {
          // Block until holdCompleter resolves.
          await holdCompleter.future;
        }
        return null;
      });

      final c = MediaController.create(playerId: 'mc-lock-busy');
      await c.initialize();

      // Start first non-critical operation (volume) — it will block in the
      // handler. We deliberately do NOT await it yet.
      final firstOpFuture = c.setVolume(0.5);

      // Give the first op a moment to acquire the lock.
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // While the first op holds the lock, a concurrent non-critical op
      // (setVolume) must be rejected with OperationBusyException — not the
      // generic StateError — because isCritical: false is now passed
      // explicitly at the call site.
      await expectLater(
        c.setVolume(0.9),
        throwsA(isA<OperationBusyException>()),
        reason:
            'Non-critical op while lock is held must throw OperationBusyException',
      );

      // Release the first operation.
      holdCompleter.complete();
      await firstOpFuture;

      // After completion the lock must be clear.
      expect(c.isOperationInProgress, isFalse);
      await expectLater(c.setVolume(0.3), completes,
          reason: 'Lock must be free after first op completes');

      c.dispose();
    });

    test('resetOperationState() allows subsequent ops when called manually',
        () async {
      _installCapture();
      final c = MediaController.create(playerId: 'mc-lock-reset');
      await c.initialize();

      // Manually force the lock into the "in progress" state.
      // (This simulates a scenario where something went wrong mid-operation.)
      // We access isOperationInProgress as a read-only signal and call
      // the public resetOperationState() method to clear it.
      c.resetOperationState();
      expect(c.isOperationInProgress, isFalse,
          reason: 'resetOperationState must clear the flag');

      // Operations must proceed normally.
      await expectLater(c.enableAutoQuality(), completes);
      c.dispose();
    });
  });

  // =========================================================================
  group('MediaController — reactive: notifyListeners on stream events', () {
    test('state change event causes notifyListeners to fire', () async {
      _installCapture();
      final c = MediaController.create(playerId: 'mc-react-state');
      await c.initialize();

      var notifyCount = 0;
      c.addListener(() => notifyCount++);

      await _injectEvent('onStateChanged', {
        'playerId': 'mc-react-state',
        'state': 'playing',
        'isBuffering': false,
        'bufferPercentage': 0.0,
      });
      // Await microtasks so the stream listener fires.
      await Future<void>.delayed(Duration.zero);

      expect(notifyCount, greaterThan(0),
          reason: 'notifyListeners must be called when state changes');
      c.dispose();
    });

    test('duration change event causes notifyListeners to fire', () async {
      _installCapture();
      final c = MediaController.create(playerId: 'mc-react-dur');
      await c.initialize();

      var notifyCount = 0;
      c.addListener(() => notifyCount++);

      await _injectEvent('onDurationChanged', {
        'playerId': 'mc-react-dur',
        'duration': 90000,
      });
      await Future<void>.delayed(Duration.zero);

      expect(notifyCount, greaterThan(0));
      c.dispose();
    });

    test('position update causes notifyListeners to fire', () async {
      _installCapture();
      final c = MediaController.create(playerId: 'mc-react-pos');
      await c.initialize();

      var notifyCount = 0;
      c.addListener(() => notifyCount++);

      await _injectEvent('onPositionChanged', {
        'playerId': 'mc-react-pos',
        'position': 5000,
      });
      await Future<void>.delayed(Duration.zero);

      expect(notifyCount, greaterThan(0));
      c.dispose();
    });

    test('quality tracks change causes notifyListeners to fire', () async {
      _installCapture();
      final c = MediaController.create(playerId: 'mc-react-qt');
      await c.initialize();

      var notifyCount = 0;
      c.addListener(() => notifyCount++);

      await _injectEvent('onQualityTracksChanged', {
        'playerId': 'mc-react-qt',
        'tracks': [
          {
            'id': 'q-hd',
            'name': 'HD',
            'bitrate': 3000000,
            'isSelected': false,
            'isAvailable': true,
          },
        ],
      });
      await Future<void>.delayed(Duration.zero);

      expect(notifyCount, greaterThan(0));
      c.dispose();
    });

    test('audio tracks change causes notifyListeners to fire', () async {
      _installCapture();
      final c = MediaController.create(playerId: 'mc-react-at');
      await c.initialize();

      var notifyCount = 0;
      c.addListener(() => notifyCount++);

      await _injectEvent('onAudioTracksChanged', {
        'playerId': 'mc-react-at',
        'tracks': [
          {
            'id': 'a-en',
            'name': 'English',
            'language': 'en',
            'isSelected': true,
            'isAvailable': true,
          },
        ],
      });
      await Future<void>.delayed(Duration.zero);

      expect(notifyCount, greaterThan(0));
      c.dispose();
    });

    test('state is updated in controller after onStateChanged injection',
        () async {
      _installCapture();
      final c = MediaController.create(playerId: 'mc-react-state2');
      await c.initialize();

      expect(c.isPlaying, isFalse);

      await _injectEvent('onStateChanged', {
        'playerId': 'mc-react-state2',
        'state': 'playing',
        'isBuffering': false,
        'bufferPercentage': 0.0,
      });
      await Future<void>.delayed(Duration.zero);

      expect(c.isPlaying, isTrue,
          reason: 'isPlaying must reflect the playing state after injection');
      c.dispose();
    });

    test('isPaused is true after paused state event', () async {
      _installCapture();
      final c = MediaController.create(playerId: 'mc-react-pause');
      await c.initialize();

      await _injectEvent('onStateChanged', {
        'playerId': 'mc-react-pause',
        'state': 'paused',
        'isBuffering': false,
        'bufferPercentage': 0.0,
      });
      await Future<void>.delayed(Duration.zero);

      expect(c.isPaused, isTrue);
      c.dispose();
    });

    test('hasError is true after error state event', () async {
      _installCapture();
      final c = MediaController.create(playerId: 'mc-react-error');
      await c.initialize();

      await _injectEvent('onError', {
        'playerId': 'mc-react-error',
        'error': 'Network failure',
      });
      await Future<void>.delayed(Duration.zero);

      expect(c.hasError, isTrue);
      c.dispose();
    });
  });

  // =========================================================================
  group('MediaController — dispose cleanup', () {
    test('subscriptions are cancelled and no notifications fire after dispose',
        () async {
      _installCapture();
      final c = MediaController.create(playerId: 'mc-disp-clean');
      await c.initialize();

      var notifyCount = 0;
      c.addListener(() => notifyCount++);

      c.dispose();

      // Inject after dispose — no notifications should fire.
      await _injectEvent('onStateChanged', {
        'playerId': 'mc-disp-clean',
        'state': 'playing',
        'isBuffering': false,
        'bufferPercentage': 0.0,
      });
      await Future<void>.delayed(Duration.zero);

      expect(notifyCount, 0,
          reason: 'Disposed controller must not fire notifyListeners');
    });

    test('underlying player is disposed when controller is disposed', () async {
      _installCapture();
      final c = MediaController.create(playerId: 'mc-disp-player');
      await c.initialize();

      c.dispose();

      expect(c.player.isDisposed, isTrue,
          reason:
              'Disposing controller must also dispose the underlying player');
    });
  });

  // =========================================================================
  group('MediaController — computed properties', () {
    test('playerId returns the correct player id', () {
      _installCapture();
      final c = MediaController.create(playerId: 'mc-props-id');
      expect(c.playerId, 'mc-props-id');
      c.dispose();
    });

    test('isPlaying is false initially', () {
      _installCapture();
      final c = MediaController.create(playerId: 'mc-props-playing');
      expect(c.isPlaying, isFalse);
      c.dispose();
    });

    test('isPaused is false initially', () {
      _installCapture();
      final c = MediaController.create(playerId: 'mc-props-paused');
      expect(c.isPaused, isFalse);
      c.dispose();
    });

    test('position is zero initially', () {
      _installCapture();
      final c = MediaController.create(playerId: 'mc-props-pos');
      expect(c.position, Duration.zero);
      c.dispose();
    });

    test('duration is zero initially', () {
      _installCapture();
      final c = MediaController.create(playerId: 'mc-props-dur');
      expect(c.duration, Duration.zero);
      c.dispose();
    });

    test('formatDuration returns mm:ss for durations under 1 hour', () {
      _installCapture();
      final c = MediaController.create(playerId: 'mc-format-1');
      expect(
          c.formatDuration(const Duration(minutes: 2, seconds: 35)), '02:35');
      c.dispose();
    });

    test('formatDuration returns hh:mm:ss for durations over 1 hour', () {
      _installCapture();
      final c = MediaController.create(playerId: 'mc-format-2');
      expect(c.formatDuration(const Duration(hours: 1, minutes: 5, seconds: 3)),
          '01:05:03');
      c.dispose();
    });
  });
}
