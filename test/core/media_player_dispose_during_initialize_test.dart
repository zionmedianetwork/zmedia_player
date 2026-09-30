// Issue #139 regression coverage: disposing a MediaPlayer/MediaController
// while `initialize` (or a `load` waiting on it) is still in flight must not
// leave a native player with no Dart owner.

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

const _channel = MethodChannel('zmedia_player');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;

  /// Records every call; calls named in [gated] wait on their completer
  /// (first call per method), calls in [failing] throw.
  void install({
    Map<String, Completer<void>> gated = const {},
    Set<String> failing = const {},
  }) {
    calls = [];
    final seen = <String>{};
    messenger.setMockMethodCallHandler(_channel, (MethodCall call) async {
      calls.add(call);
      if (failing.contains(call.method)) {
        throw PlatformException(code: 'X_ERROR', message: 'boom');
      }
      final gate = gated[call.method];
      if (gate != null && seen.add(call.method)) await gate.future;
      return null;
    });
  }

  List<String> methods() => calls.map((c) => c.method).toList();
  Iterable<String> playerCmds() => methods().where(
      (m) => const {'load', 'play', 'setSpeed', 'setPlaylist'}.contains(m));

  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  const item = MediaItem(
    id: 'i',
    title: 'T',
    url: 'https://cdn.example.com/live.m3u8',
  );

  group('MediaPlayer.dispose during in-flight initialize', () {
    test('sends native dispose after initialize answers, and nothing else',
        () async {
      final gate = Completer<void>();
      install(gated: {'initialize': gate});

      final player = MediaPlayer(playerId: 'd139-a');
      final init = player.initialize();
      final initResult =
          expectLater(init, throwsA(isA<PlayerDisposedException>()));
      await Future<void>.delayed(Duration.zero);

      final disposing = player.dispose();
      // Synchronous part of dispose() still happens up front.
      expect(player.isDisposed, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(methods(), ['initialize'],
          reason: 'must not race the pending initialize');

      gate.complete();
      await initResult;
      await disposing;
      expect(methods(), ['initialize', 'dispose']);
    });

    test('a load() waiting on initialize never reaches native', () async {
      final gate = Completer<void>();
      install(gated: {'initialize': gate});

      final player = MediaPlayer(playerId: 'd139-b');
      final load = player.load(item);
      final loadResult =
          expectLater(load, throwsA(isA<PlayerDisposedException>()));
      await Future<void>.delayed(Duration.zero);

      final disposing = player.dispose();
      gate.complete();
      await loadResult;
      await disposing;

      expect(playerCmds(), isEmpty);
      expect(methods(), ['initialize', 'dispose']);
    });

    test('a failed initialize sends no native dispose', () async {
      install(failing: {'initialize'});
      final player = MediaPlayer(playerId: 'd139-c');
      final init = player.initialize();
      final initResult =
          expectLater(init, throwsA(isA<MediaPlayerException>()));
      await Future<void>.delayed(Duration.zero);
      await player.dispose();
      await initResult;
      expect(methods(), ['initialize']);
    });

    test('a never-initialized player still sends no native dispose', () async {
      install();
      final player = MediaPlayer(playerId: 'd139-d');
      await player.dispose();
      expect(methods(), isEmpty);
    });

    test('setSpeed-before-load cannot be followed by a native load', () async {
      install();
      final player = MediaPlayer(playerId: 'd139-e');
      await player.initialize();
      // Put the player at a non-1.0 speed so load() awaits setSpeed(1.0).
      await player.setSpeed(2.0);
      calls.clear();

      final gate = Completer<void>();
      install(gated: {'setSpeed': gate});
      final load = player.load(item);
      final loadResult =
          expectLater(load, throwsA(isA<PlayerDisposedException>()));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final disposing = player.dispose();
      gate.complete();
      await loadResult;
      await disposing;

      expect(methods().contains('load'), isFalse);
      expect(methods().last, 'dispose');
    });

    test(
        'a replacement with the same playerId is not killed by the old '
        'instance\'s late dispose', () async {
      final gate = Completer<void>();
      install(gated: {'initialize': gate});

      final old = MediaPlayer(playerId: 'd139-reuse');
      final oldInit = old.initialize();
      final oldInitResult =
          expectLater(oldInit, throwsA(isA<PlayerDisposedException>()));
      await Future<void>.delayed(Duration.zero);
      final oldDispose = old.dispose();

      final replacement = MediaPlayer(playerId: 'd139-reuse');
      expect(identical(replacement, old), isFalse);
      final replacementInit = replacement.initialize();
      await Future<void>.delayed(Duration.zero);

      gate.complete();
      await oldInitResult;
      await replacementInit;
      await oldDispose;

      expect(methods(), ['initialize', 'initialize'],
          reason: 'native initializePlayer disposes the old instance itself; '
              'a dispose keyed by the shared id would kill the replacement');
      await replacement.dispose();
      expect(methods().last, 'dispose');
    });

    test('dispose stops waiting after a bounded time and sends best-effort',
        () {
      fakeAsync((async) {
        final gate = Completer<void>();
        install(gated: {'initialize': gate});

        final player = MediaPlayer(playerId: 'd139-timeout');
        unawaited(player.initialize().catchError((Object _) {}));
        async.flushMicrotasks();

        var done = false;
        unawaited(player.dispose().then((_) => done = true));
        async.elapse(const Duration(seconds: 4));
        expect(done, isFalse);
        expect(methods(), ['initialize']);

        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(done, isTrue);
        expect(methods(), ['initialize', 'dispose']);
      });
    });
  });

  group('MediaController.release / dispose', () {
    test('release() stops, then disposes, in that order', () async {
      install();
      final c = MediaController.create(playerId: 'd139-rel-order');
      await c.initialize();
      calls.clear();

      await c.release();
      expect(methods(), ['stop', 'dispose']);
      expect(c.isDisposed, isTrue);
    });

    test('release() on a never-initialized controller does not initialize it',
        () async {
      install();
      final c = MediaController.create(playerId: 'd139-rel-idle');
      await c.release();
      expect(methods(), isEmpty);
    });

    test('release() waits behind an in-flight load: load, stop, dispose',
        () async {
      final gate = Completer<void>();
      install(gated: {'load': gate});
      final c = MediaController.create(playerId: 'd139-rel-load');
      await c.initialize();
      calls.clear();

      final load = c.load(item);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final release = c.release();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(methods(), ['load'], reason: 'stop must queue behind the load');

      gate.complete();
      await load;
      await release;
      expect(methods(), ['load', 'stop', 'dispose']);
    });

    test(
        'release() during the initialize a load is waiting on: the load '
        'finishes, then stop and dispose clean it up', () async {
      final gate = Completer<void>();
      install(gated: {'initialize': gate});
      final c = MediaController.create(playerId: 'd139-rel-init');

      final load = c.load(item);
      await Future<void>.delayed(Duration.zero);
      final release = c.release();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      gate.complete();
      await load;
      await release;

      expect(methods(), ['initialize', 'load', 'stop', 'dispose'],
          reason: 'release() deliberately waits behind the running load, so '
              'the load is stopped and then disposed rather than orphaned');
    });

    test('a stop that never answers is abandoned after half the timeout',
        () async {
      final gate = Completer<void>();
      install(gated: {'stop': gate});
      final c = MediaController.create(playerId: 'd139-rel-stop-hang');
      await c.initialize();
      calls.clear();

      await c.release(timeout: const Duration(milliseconds: 400));
      expect(methods(), ['stop', 'dispose']);
      gate.complete();
    });

    test(
        'release() throws TimeoutException when native dispose hangs, but '
        'local teardown is done', () async {
      final gate = Completer<void>();
      install(gated: {'dispose': gate});
      final c = MediaController.create(playerId: 'd139-rel-dispose-hang');
      await c.initialize();

      await expectLater(
        c.release(timeout: const Duration(milliseconds: 200)),
        throwsA(isA<TimeoutException>()),
      );
      expect(c.isDisposed, isTrue);
      gate.complete();
    });

    test('release() is idempotent and concurrent calls share one teardown',
        () async {
      install();
      final c = MediaController.create(playerId: 'd139-rel-idem');
      await c.initialize();
      calls.clear();

      final a = c.release();
      final b = c.release();
      expect(identical(a, b), isTrue);
      await Future.wait([a, b]);
      await c.release();
      expect(methods(), ['stop', 'dispose']);
    });

    test('dispose() after release() is a no-op', () async {
      install();
      final c = MediaController.create(playerId: 'd139-rel-then-dispose');
      await c.initialize();
      await c.release();
      calls.clear();
      c.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(methods(), isEmpty);
    });

    test('release() after dispose() awaits that dispose\'s native teardown',
        () async {
      final gate = Completer<void>();
      install(gated: {'dispose': gate});
      final c = MediaController.create(playerId: 'd139-dispose-then-rel');
      await c.initialize();
      calls.clear();

      c.dispose();
      var released = false;
      final release = c.release().then((_) => released = true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(released, isFalse);
      expect(methods(), ['dispose'], reason: 'no stop after dispose()');

      gate.complete();
      await release;
      expect(released, isTrue);
    });

    test('dispose() with a failing native dispose raises no unhandled error',
        () async {
      install(failing: {'dispose'});
      final c = MediaController.create(playerId: 'd139-dispose-fail');
      await c.initialize();

      final errors = <Object>[];
      await runZonedGuarded(() async {
        c.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }, (e, _) => errors.add(e));
      expect(errors, isEmpty);
      expect(methods().last, 'dispose');
    });
  });
}
