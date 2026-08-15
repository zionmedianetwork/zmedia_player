// H-08 regression coverage: buffer-health polling (BufferingService's 500ms
// Timer.periodic, which round-trips to native via `getBufferHealth`) must
// stop on every path that leaves an actively-playing session — not just
// pause(), but also stop() and native-driven `completed`/`error`/`idle`
// transitions delivered via `onStateChanged`.
//
// See lib/src/core/media_player.dart (play/pause/stop, _handleStateChanged)
// and lib/src/services/buffering_service.dart (startMonitoring/stopMonitoring).

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

const _channel = MethodChannel('zmedia_player');

/// Installs a mock handler that answers `getBufferHealth` with an empty
/// (but valid) map and records every outgoing call.
List<MethodCall> _installCapture() {
  final calls = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (MethodCall call) async {
    calls.add(call);
    if (call.method == 'getBufferHealth') {
      return <String, dynamic>{
        'bufferedDurationMs': 5000,
        'bufferedPercentage': 50.0,
      };
    }
    return null;
  });
  return calls;
}

void _resetHandler() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null);
}

/// Sends a fake `onStateChanged` native event for [playerId].
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

/// Waits long enough for at least one 500ms polling tick to have had a
/// chance to fire, then returns whether any `getBufferHealth` call arrived.
Future<bool> _pollHappened(List<MethodCall> calls) async {
  await Future<void>.delayed(const Duration(milliseconds: 650));
  return calls.any((c) => c.method == 'getBufferHealth');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(_resetHandler);

  group('H-08 — buffer-health polling stops on every non-playing path', () {
    test('play() starts polling', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'h08-play-starts');
      await player.initialize();
      await player.play();
      calls.clear();

      expect(await _pollHappened(calls), isTrue,
          reason: 'play() must start buffer-health polling');

      await player.dispose();
    });

    test('pause() stops polling', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'h08-pause-stops');
      await player.initialize();
      await player.play();
      await _pollHappened(calls); // let it warm up
      await player.pause();
      calls.clear();

      expect(await _pollHappened(calls), isFalse,
          reason: 'pause() must stop buffer-health polling');

      await player.dispose();
    });

    test('stop() stops polling', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'h08-stop-stops');
      await player.initialize();
      await player.play();
      await _pollHappened(calls); // let it warm up
      await player.stop();
      calls.clear();

      expect(await _pollHappened(calls), isFalse,
          reason: 'stop() must stop buffer-health polling — previously it '
              'was the one terminal path pause() did not cover');

      await player.dispose();
    });

    test('native "completed" event stops polling', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'h08-completed-stops');
      await player.initialize();
      await player.play();
      await _pollHappened(calls); // let it warm up
      calls.clear();

      await _injectStateChanged('h08-completed-stops', 'completed');

      expect(await _pollHappened(calls), isFalse,
          reason: 'a native "completed" transition must stop buffer-health '
              'polling even though pause()/stop() were never called');

      await player.dispose();
    });

    test('native "error" event stops polling', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'h08-error-stops');
      await player.initialize();
      await player.play();
      await _pollHappened(calls); // let it warm up
      calls.clear();

      await _injectStateChanged('h08-error-stops', 'error');

      expect(await _pollHappened(calls), isFalse,
          reason: 'a native "error" transition must stop buffer-health '
              'polling even though pause()/stop() were never called');

      await player.dispose();
    });

    test('native "idle" event stops polling (native-initiated stop)', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'h08-idle-stops');
      await player.initialize();
      await player.play();
      await _pollHappened(calls); // let it warm up
      calls.clear();

      await _injectStateChanged('h08-idle-stops', 'idle');

      expect(await _pollHappened(calls), isFalse,
          reason: 'a native "idle" transition must stop buffer-health '
              'polling');

      await player.dispose();
    });

    test('native "buffering" event does NOT stop polling', () async {
      // Buffering is exactly when buffer-health visibility matters most
      // (e.g. a mid-playback rebuffer stall) — it must not be treated as a
      // "leaves playing" transition.
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'h08-buffering-keeps-polling');
      await player.initialize();
      await player.play();
      await _pollHappened(calls); // let it warm up
      calls.clear();

      await _injectStateChanged('h08-buffering-keeps-polling', 'buffering');

      expect(await _pollHappened(calls), isTrue,
          reason: 'a native "buffering" transition must NOT stop '
              'buffer-health polling — that is exactly when it is needed');

      await player.dispose();
    });
  });
}
