import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

/// Regression suite for issue #86 — `MediaController`'s operation lock never
/// queued.
///
/// Before the fix, `_executeOperation` held a per-controller boolean lock and,
/// when it was already held by a live operation:
///   * "non-critical" ops (`setVolume`, `toggleMute`, `setSpeed`,
///     `setSubtitleTrack`, `setSecureSurface`) were rejected immediately with
///     `OperationBusyException`;
///   * "critical" ops slept 100 ms, then 200 ms, then threw a bare
///     `StateError`.
///
/// So ordinary interleaved user input ("pause A, then play B") could fail
/// purely on timing, and because these calls are routinely fire-and-forget in
/// feed UIs the throw vanished and the operation simply never happened.
///
/// This file supersedes `operation_lock_non_critical_test.dart`, which
/// asserted exactly that (now-removed) throwing behaviour.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('zmedia_player');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Installs a handler that records every outgoing call and optionally
  /// stalls the calls named in [blockMethods] until [gate] resolves.
  List<MethodCall> installHandler({
    Set<String> blockMethods = const {},
    Future<void>? gate,
    bool blockFirstCallOnly = false,
  }) {
    final calls = <MethodCall>[];
    final blockedCounts = <String, int>{};

    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      if (blockMethods.contains(call.method) && gate != null) {
        final seen = (blockedCounts[call.method] ?? 0) + 1;
        blockedCounts[call.method] = seen;
        if (!blockFirstCallOnly || seen == 1) {
          await gate;
        }
      }
      return null;
    });
    return calls;
  }

  List<String> methodsIn(List<MethodCall> calls, Set<String> of) =>
      calls.map((c) => c.method).where(of.contains).toList();

  const item = MediaItem(
    id: 'queue-item',
    title: 'Queue Item',
    url: 'https://cdn.example.com/video.mp4',
  );

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  // =========================================================================
  group('MediaController operation queue — interleaving never throws', () {
    test('play() immediately followed by pause() both run, in order', () async {
      final gate = Completer<void>();
      final calls = installHandler(blockMethods: {'play'}, gate: gate.future);

      final c = MediaController.create(playerId: 'queue-play-pause');
      await c.initialize();
      calls.clear();

      // The exact shape from the issue: two transport commands issued back to
      // back with no await between them. `play` stalls in the mock handler, so
      // `pause` is submitted while `play` is unambiguously still in flight.
      final playing = c.play();
      final pausing = c.pause();

      // Let both reach the queue, then release the stalled play.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      gate.complete();

      await expectLater(playing, completes);
      await expectLater(pausing, completes,
          reason: 'pause() submitted while play() is in flight must be '
              'queued, not rejected with OperationBusyException/StateError');

      expect(methodsIn(calls, {'play', 'pause'}), ['play', 'pause'],
          reason: 'Operations must reach native in submission order');

      c.dispose();
    });

    test('rapid A/B interleaving (play/pause x3) preserves FIFO order',
        () async {
      final gate = Completer<void>();
      final calls = installHandler(
        blockMethods: {'play'},
        gate: gate.future,
        blockFirstCallOnly: true,
      );

      final c = MediaController.create(playerId: 'queue-ab-swipe');
      await c.initialize();
      calls.clear();

      // Mimics a fast A→B→A→B feed swipe landing on one controller.
      final futures = <Future<void>>[
        c.play(),
        c.pause(),
        c.play(),
        c.pause(),
        c.play(),
        c.pause(),
      ];

      await Future<void>.delayed(const Duration(milliseconds: 20));
      gate.complete();

      await expectLater(Future.wait(futures), completes);

      expect(
        methodsIn(calls, {'play', 'pause'}),
        ['play', 'pause', 'play', 'pause', 'play', 'pause'],
        reason: 'Every submitted op must run exactly once, in order — the '
            'losing pause() must not be silently dropped (issue #86)',
      );

      c.dispose();
    });

    test('the last op of an interleaved burst wins the final state', () async {
      final gate = Completer<void>();
      final calls = installHandler(blockMethods: {'play'}, gate: gate.future);

      final c = MediaController.create(playerId: 'queue-last-wins');
      await c.initialize();
      calls.clear();

      final playing = c.play();
      final pausing = c.pause();

      await Future<void>.delayed(const Duration(milliseconds: 20));
      gate.complete();
      await Future.wait([playing, pausing]);

      expect(methodsIn(calls, {'play', 'pause'}).last, 'pause',
          reason: 'A short that the host asked to pause must end up paused');

      c.dispose();
    });
  });

  // =========================================================================
  group('MediaController operation queue — formerly "non-critical" ops', () {
    test('setVolume() during an in-flight load() succeeds instead of throwing',
        () async {
      final gate = Completer<void>();
      final calls = installHandler(blockMethods: {'load'}, gate: gate.future);

      final c = MediaController.create(playerId: 'queue-vol-during-load');
      await c.initialize();
      calls.clear();

      final loading = c.load(item);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // The scenario the issue calls out explicitly: a feed wants to mute a
      // player precisely while it is loading.
      final volume = c.setVolume(0.0);

      gate.complete();
      await expectLater(loading, completes);
      await expectLater(volume, completes,
          reason: 'setVolume() while a load is in flight must be queued, not '
              'rejected with OperationBusyException');

      expect(methodsIn(calls, {'load', 'setVolume'}), ['load', 'setVolume']);

      c.dispose();
    });

    test('toggleMute() / setSpeed() / setSubtitleTrack() all queue behind load',
        () async {
      final gate = Completer<void>();
      final calls = installHandler(blockMethods: {'load'}, gate: gate.future);

      final c = MediaController.create(playerId: 'queue-nc-batch');
      await c.initialize();
      calls.clear();

      final loading = c.load(item);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final muting = c.toggleMute();
      final speeding = c.setSpeed(1.5);
      final subtitling = c.setSubtitleTrack(null);

      gate.complete();
      await expectLater(
        Future.wait([loading, muting, speeding, subtitling]),
        completes,
      );

      expect(
        methodsIn(calls, {'load', 'setMuted', 'setSpeed', 'setSubtitleTrack'}),
        ['load', 'setMuted', 'setSpeed', 'setSubtitleTrack'],
      );

      c.dispose();
    });

    test('two concurrent setVolume() calls both reach native', () async {
      final gate = Completer<void>();
      final calls = installHandler(
        blockMethods: {'setVolume'},
        gate: gate.future,
        blockFirstCallOnly: true,
      );

      final c = MediaController.create(playerId: 'queue-vol-vol');
      await c.initialize();
      calls.clear();

      final first = c.setVolume(0.5);
      final second = c.setVolume(0.9);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      gate.complete();

      await expectLater(Future.wait([first, second]), completes);
      expect(methodsIn(calls, {'setVolume'}).length, 2);

      c.dispose();
    });
  });

  // =========================================================================
  group('MediaController operation queue — failure isolation', () {
    test('a failing operation does not poison the ops queued behind it',
        () async {
      final calls = installHandler();
      final c = MediaController.create(playerId: 'queue-failure-isolation');
      await c.initialize();
      calls.clear();

      // No quality tracks were reported, so this throws InvalidStateException
      // from the player.
      const ghost = QualityTrack(id: 'ghost', name: 'Ghost', bitrate: 0);
      final failing = c.setQualityTrack(ghost);
      final following = c.play();

      await expectLater(failing, throwsA(isA<MediaPlayerException>()));
      await expectLater(following, completes,
          reason: 'The queue must advance past a failed operation');

      expect(methodsIn(calls, {'play'}), ['play']);
      expect(c.isOperationInProgress, isFalse,
          reason: 'The in-progress flag must clear even when an op throws');

      c.dispose();
    });
  });

  // =========================================================================
  group('MediaController operation queue — dispose()', () {
    test('an operation still queued when dispose() runs resolves as a no-op',
        () async {
      final gate = Completer<void>();
      final calls = installHandler(blockMethods: {'load'}, gate: gate.future);

      final c = MediaController.create(playerId: 'queue-dispose-drop');
      await c.initialize();
      calls.clear();

      final loading = c.load(item);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Queued behind the stalled load.
      final queuedPause = c.pause();

      // Dispose while `pause` is still waiting its turn.
      c.dispose();
      gate.complete();

      // The in-flight load may fail against the torn-down player; that is
      // pre-existing behaviour and not what this test is about.
      await loading.catchError((_) {});

      await expectLater(queuedPause, completes,
          reason: 'A dropped queued op must resolve, never hang or leak');
      expect(calls.any((call) => call.method == 'pause'), isFalse,
          reason: 'A dropped queued op must never touch the disposed player');
    });

    test('operations submitted after dispose() resolve as a no-op too',
        () async {
      final calls = installHandler();
      final c = MediaController.create(playerId: 'queue-dispose-after');
      await c.initialize();
      c.dispose();
      calls.clear();

      await expectLater(c.play(), completes);
      await expectLater(c.setVolume(0.4), completes);
      expect(methodsIn(calls, {'play', 'setVolume'}), isEmpty);
    });

    test('a dropped queued op leaves no pending auto-hide timer behind',
        () async {
      final gate = Completer<void>();
      installHandler(blockMethods: {'load'}, gate: gate.future);

      final c = MediaController.create(playerId: 'queue-dispose-timer');
      await c.initialize();

      final loading = c.load(item);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // play()'s post-operation side effect is _showControlsTemporarily(),
      // which arms a Timer. It must not be armed on a disposed controller.
      final queuedPlay = c.play();
      c.dispose();
      gate.complete();

      await loading.catchError((_) {});
      await queuedPlay;
      expect(c.controlsVisible, isFalse);
      // If a Timer had been armed post-dispose, the test binding would fail
      // this test with "A Timer is still pending".
    });
  });

  // =========================================================================
  group('MediaController operation queue — head-of-line timeout guard', () {
    test(
        'a wedged native call fails with TimeoutException and the queue '
        'then advances', () async {
      final gate = Completer<void>();
      final calls = installHandler(
        blockMethods: {'play'},
        gate: gate.future,
        blockFirstCallOnly: true,
      );

      final c = MediaController.create(playerId: 'queue-timeout');
      await c.initialize();
      calls.clear();

      // This one never returns from the mock handler.
      final wedged = c.play();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Queued behind the wedged op: it must eventually run, not hang forever.
      final behind = c.pause();

      await expectLater(wedged, throwsA(isA<TimeoutException>()),
          reason: 'The per-operation timeout must bound head-of-line blocking');
      await expectLater(behind, completes,
          reason: 'The queue must advance once the wedged op times out');

      expect(methodsIn(calls, {'play', 'pause'}), ['play', 'pause']);
      expect(c.isOperationInProgress, isFalse);

      // Release the abandoned handler call so nothing is left stalled.
      gate.complete();
      c.dispose();
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  // =========================================================================
  group('MediaController operation queue — isOperationInProgress', () {
    test('is false before, true during, and false after an operation',
        () async {
      final gate = Completer<void>();
      installHandler(blockMethods: {'play'}, gate: gate.future);

      final c = MediaController.create(playerId: 'queue-flag');
      await c.initialize();

      expect(c.isOperationInProgress, isFalse);

      final playing = c.play();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.isOperationInProgress, isTrue,
          reason: 'The flag reports the running operation');

      gate.complete();
      await playing;
      expect(c.isOperationInProgress, isFalse);

      c.dispose();
    });

    test('resetOperationState() is a safe no-op and does not break the queue',
        () async {
      final calls = installHandler();
      final c = MediaController.create(playerId: 'queue-reset');
      await c.initialize();
      calls.clear();

      c.resetOperationState();
      expect(c.isOperationInProgress, isFalse);

      await expectLater(c.play(), completes);
      expect(methodsIn(calls, {'play'}), ['play']);

      c.dispose();
    });
  });
}
