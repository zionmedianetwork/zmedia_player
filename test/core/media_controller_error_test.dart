import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

// ---------------------------------------------------------------------------
// C-01: DRM failures must be reachable through the documented facade
// (MediaController), not only through MediaPlayer/MediaPlayer.errorStream.
//
// Three things previously compounded into one hole:
//  1. MediaPlayer._handleDrmSessionUpdate emitted on errorStream but never
//     called _updateState, so PlaybackState.state never became
//     PlayerState.error for a DRM session failure.
//  2. MediaController.hasError is derived purely from
//     _currentState.state == PlayerState.error, so it never became true.
//  3. MediaController never forwarded errorStream at all, so a consumer
//     following CLAUDE.md's own guidance ("Use MediaController when...")
//     had zero way to observe a DRM failure without reaching around the
//     facade via `controller.player.errorStream`.
//
// These tests exercise the fix through MediaController only — none of them
// touch `controller.player` — to prove the facade itself is now sufficient.
// ---------------------------------------------------------------------------

Future<void> _injectEvent(String method, Map<String, dynamic> arguments) async {
  final codec = const StandardMethodCodec();
  final data = codec.encodeMethodCall(MethodCall(method, arguments));
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    'zmedia_player',
    data,
    (_) {},
  );
}

/// Waits for the next [MediaController.notifyListeners] call, or times out.
Future<void> _waitForNotify(MediaController controller,
    [Duration timeout = const Duration(seconds: 2)]) {
  final completer = Completer<void>();
  void listener() {
    if (!completer.isCompleted) completer.complete();
  }

  controller.addListener(listener);
  return completer.future.timeout(timeout).whenComplete(() {
    controller.removeListener(listener);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('C-01: DRM session error reachable via MediaController', () {
    test(
        'DRM session error drives PlayerState.error and hasError becomes '
        'true', () async {
      final controller = MediaController.create(playerId: 'ctrl-drm-err-1');
      await controller.initialize();

      expect(controller.hasError, isFalse);

      final notified = _waitForNotify(controller);
      final now = DateTime.now();

      await _injectEvent('onDrmSessionUpdate', {
        'playerId': 'ctrl-drm-err-1',
        'id': 'session-ctrl-1',
        'state': 'error',
        'license': null,
        'errorMessage': 'License server rejected request',
        'createdAt': now.millisecondsSinceEpoch,
        'updatedAt': now.millisecondsSinceEpoch,
      });

      await notified;

      expect(controller.hasError, isTrue);
      expect(controller.state.state, PlayerState.error);

      controller.dispose();
    });

    test(
        'DRM failure is observable through MediaController.errorStream '
        'without reaching into .player', () async {
      final controller = MediaController.create(playerId: 'ctrl-drm-err-2');
      await controller.initialize();

      final errorFuture = controller.errorStream.first;
      final now = DateTime.now();

      await _injectEvent('onDrmSessionUpdate', {
        'playerId': 'ctrl-drm-err-2',
        'id': 'session-ctrl-2',
        'state': 'error',
        'license': null,
        'errorMessage': 'License server rejected request',
        'createdAt': now.millisecondsSinceEpoch,
        'updatedAt': now.millisecondsSinceEpoch,
      });

      final error = await errorFuture.timeout(const Duration(seconds: 2));
      expect(error, isA<DrmException>());
      expect(error.message, 'License server rejected request');

      controller.dispose();
    });

    test('MediaController.error exposes the last typed error synchronously',
        () async {
      final controller = MediaController.create(playerId: 'ctrl-drm-err-3');
      await controller.initialize();

      expect(controller.error, isNull);

      final notified = _waitForNotify(controller);
      final now = DateTime.now();

      await _injectEvent('onDrmSessionUpdate', {
        'playerId': 'ctrl-drm-err-3',
        'id': 'session-ctrl-3',
        'state': 'error',
        'license': null,
        'errorMessage': 'License server rejected request',
        'createdAt': now.millisecondsSinceEpoch,
        'updatedAt': now.millisecondsSinceEpoch,
      });

      await notified;

      expect(controller.error, isA<DrmException>());
      expect(controller.error!.message, 'License server rejected request');

      controller.dispose();
    });

    test(
        'MediaController.error clears once the player recovers from the '
        'error state', () async {
      final controller = MediaController.create(playerId: 'ctrl-drm-err-4');
      await controller.initialize();

      final firstNotify = _waitForNotify(controller);
      final now = DateTime.now();

      await _injectEvent('onDrmSessionUpdate', {
        'playerId': 'ctrl-drm-err-4',
        'id': 'session-ctrl-4',
        'state': 'error',
        'license': null,
        'errorMessage': 'License server rejected request',
        'createdAt': now.millisecondsSinceEpoch,
        'updatedAt': now.millisecondsSinceEpoch,
      });
      await firstNotify;

      expect(controller.hasError, isTrue);
      expect(controller.error, isNotNull);

      final secondNotify = _waitForNotify(controller);

      // A subsequent successful state transition (e.g. after a retry/reload)
      // should clear the stale error.
      await _injectEvent('onStateChanged', {
        'playerId': 'ctrl-drm-err-4',
        'state': 'buffering',
        'isBuffering': true,
        'bufferPercentage': 0.0,
      });
      await secondNotify;

      expect(controller.hasError, isFalse);
      expect(controller.error, isNull);

      controller.dispose();
    });
  });
}
