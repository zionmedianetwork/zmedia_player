import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

// ---------------------------------------------------------------------------
// Helpers — same pattern as media_controller_test.dart
// ---------------------------------------------------------------------------

const _channel = MethodChannel('zmedia_player');

void _resetHandler() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null);
}

void _installBlockingHandler(
  String methodToBlock,
  Future<void> Function() blockUntil,
) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (MethodCall call) async {
    if (call.method == methodToBlock) {
      await blockUntil();
    }
    return null;
  });
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(_resetHandler);

  // =========================================================================
  group('Operation lock — non-critical path (Bug 1 regression)', () {
    // The bug: _isNonCriticalOperation() used closure.toString() which never
    // contains the method name in Dart (especially AOT), so non-critical ops
    // always fell through to the critical path → StateError instead of
    // OperationBusyException.
    //
    // Fix: _executeOperation now accepts an explicit `isCritical` flag.
    // setVolume / setSpeed / setSubtitleTrack / toggleMute pass
    // isCritical: false; all others default to isCritical: true.

    test(
        'concurrent setVolume while another op is in-flight throws '
        'OperationBusyException (not StateError)', () async {
      final holdCompleter = Completer<void>();
      _installBlockingHandler('setVolume', () => holdCompleter.future);

      final c = MediaController.create(playerId: 'lock-nc-vol');
      await c.initialize();

      // First setVolume acquires the lock and stalls in the mock handler.
      final firstFuture = c.setVolume(0.5);

      // Let the first op reach the mock handler and acquire the lock.
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // A second concurrent setVolume must be rejected as non-critical.
      await expectLater(
        c.setVolume(0.9),
        throwsA(isA<OperationBusyException>()),
        reason: 'setVolume is non-critical: concurrent call must throw '
            'OperationBusyException',
      );

      // Release the first op and verify the lock clears.
      holdCompleter.complete();
      await firstFuture;

      expect(c.isOperationInProgress, isFalse,
          reason: 'Lock must be released after first op completes');

      // A subsequent op must now succeed without hitting the busy guard.
      await expectLater(
        c.setVolume(0.3),
        completes,
        reason: 'Lock-free subsequent op must complete normally',
      );

      c.dispose();
    });

    test(
        'concurrent setSpeed while another op is in-flight throws '
        'OperationBusyException', () async {
      final holdCompleter = Completer<void>();
      _installBlockingHandler('setSpeed', () => holdCompleter.future);

      final c = MediaController.create(playerId: 'lock-nc-speed');
      await c.initialize();

      final firstFuture = c.setSpeed(1.5);

      await Future<void>.delayed(const Duration(milliseconds: 10));

      await expectLater(
        c.setSpeed(2.0),
        throwsA(isA<OperationBusyException>()),
        reason: 'setSpeed is non-critical: must throw OperationBusyException',
      );

      holdCompleter.complete();
      await firstFuture;

      expect(c.isOperationInProgress, isFalse);

      // After lock release, normal op succeeds.
      await expectLater(c.setSpeed(1.0), completes);

      c.dispose();
    });

    test(
        'critical op (play) while lock is held does NOT throw '
        'OperationBusyException — takes the wait-then-StateError path',
        () async {
      // This test guards the critical path: isCritical: true ops should wait
      // the full 100 + 200 ms then throw StateError (not OperationBusyException).
      final holdCompleter = Completer<void>();
      _installBlockingHandler('play', () => holdCompleter.future);

      final c = MediaController.create(playerId: 'lock-critical-play');
      await c.initialize();

      // First play acquires the lock.
      final firstFuture = c.play();

      await Future<void>.delayed(const Duration(milliseconds: 10));

      // A second play() is critical — it must NOT throw OperationBusyException;
      // instead it waits and then throws StateError.
      await expectLater(
        c.play(),
        throwsA(isA<StateError>()),
        reason: 'Critical op while lock is held must throw StateError, not '
            'OperationBusyException',
      );

      holdCompleter.complete();
      await firstFuture;

      c.dispose();
    });
  });
}
