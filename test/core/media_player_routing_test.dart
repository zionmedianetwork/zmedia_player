import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

/// Sends a platform-side method call to the Dart handler through
/// TestDefaultBinaryMessenger (simulates the native side firing an event).
Future<void> _injectPlatformCall(
  String method,
  Map<String, dynamic> arguments,
) async {
  final codec = const StandardMethodCodec();
  final data = codec.encodeMethodCall(MethodCall(method, arguments));

  // Deliver via the test messenger's simulation path.
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    'zmedia_player',
    data,
    (ByteData? reply) {},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('zmedia_player'),
      (MethodCall methodCall) async => null,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('zmedia_player'), null);
  });

  group('Multi-instance routing (Fix 1)', () {
    test('two instances with different playerIds receive independent events',
        () async {
      final p1 = MediaPlayer(playerId: 'routing_p1');
      final p2 = MediaPlayer(playerId: 'routing_p2');
      await p1.initialize();
      await p2.initialize();

      final p1States = <PlayerState>[];
      final p2States = <PlayerState>[];

      p1.stateStream.listen((s) => p1States.add(s.state));
      p2.stateStream.listen((s) => p2States.add(s.state));

      // Inject an onStateChanged for p1 only.
      await _injectPlatformCall('onStateChanged', {
        'playerId': 'routing_p1',
        'state': 'playing',
        'isBuffering': false,
        'bufferPercentage': 0.0,
      });

      // Give microtasks a cycle.
      await Future<void>.delayed(Duration.zero);

      expect(p1States, contains(PlayerState.playing),
          reason: 'p1 should receive the event directed at routing_p1');
      expect(p2States, isEmpty,
          reason: 'p2 must not receive an event directed at routing_p1');

      p1.dispose();
      p2.dispose();
    });

    test('event with unknown playerId does not throw', () async {
      // Should silently drop unknown playerIds without crashing.
      await expectLater(
        _injectPlatformCall('onStateChanged', {
          'playerId': 'nonexistent_player_xyz',
          'state': 'playing',
          'isBuffering': false,
          'bufferPercentage': 0.0,
        }),
        completes,
      );
    });

    test('event missing playerId does not throw', () async {
      await expectLater(
        _injectPlatformCall('onStateChanged', {
          'state': 'playing',
          'isBuffering': false,
          'bufferPercentage': 0.0,
          // intentionally no 'playerId'
        }),
        completes,
      );
    });

    test('dispose removes instance so it no longer receives events', () async {
      final p = MediaPlayer(playerId: 'routing_dispose_test');
      await p.initialize();

      final states = <PlayerState>[];
      p.stateStream.listen((s) => states.add(s.state));

      p.dispose();
      await Future<void>.delayed(Duration.zero);

      // After disposal the stream is closed; inject should not crash.
      await expectLater(
        _injectPlatformCall('onStateChanged', {
          'playerId': 'routing_dispose_test',
          'state': 'playing',
          'isBuffering': false,
          'bufferPercentage': 0.0,
        }),
        completes,
      );
    });
  });

  group('drmSessionStream (Fix 2)', () {
    test('onDrmSessionUpdate emits a DrmSession on the stream', () async {
      final p = MediaPlayer(playerId: 'drm_stream_test');
      await p.initialize();

      final now = DateTime.now();

      final sessionFuture = p.drmSessionStream.first;

      await _injectPlatformCall('onDrmSessionUpdate', {
        'playerId': 'drm_stream_test',
        'id': 'session-abc',
        'state': 'licensed',
        'license': null,
        'errorMessage': null,
        'createdAt': now.millisecondsSinceEpoch,
        'updatedAt': now.millisecondsSinceEpoch,
      });

      final session = await sessionFuture.timeout(const Duration(seconds: 2));

      expect(session.id, 'session-abc');
      expect(session.state, DrmSessionState.licensed);

      p.dispose();
    });

    test('onDrmSessionUpdate for wrong playerId is not emitted', () async {
      final p = MediaPlayer(playerId: 'drm_wrong_id_test');
      await p.initialize();

      final now = DateTime.now();
      var emitted = false;
      p.drmSessionStream.listen((_) => emitted = true);

      await _injectPlatformCall('onDrmSessionUpdate', {
        'playerId': 'some_other_player',
        'id': 'session-xyz',
        'state': 'licensed',
        'license': null,
        'errorMessage': null,
        'createdAt': now.millisecondsSinceEpoch,
        'updatedAt': now.millisecondsSinceEpoch,
      });

      await Future<void>.delayed(Duration.zero);

      expect(emitted, isFalse,
          reason: 'Event directed at another playerId must not be emitted');

      p.dispose();
    });
  });
}
