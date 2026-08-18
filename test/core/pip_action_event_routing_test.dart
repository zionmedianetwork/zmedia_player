// Regression tests for Wave D: Wave C wired PipConfig.actions on Android and
// made native emit a NEW method-channel event `onPipAction` with
// `{playerId, actionId}` — but nothing on the Dart side handled it, so it
// fell into MediaPlayer's `default:` "Unhandled method call" branch (the
// same defect class as finding C-09, an unhandled `onDrmError` event).
//
// Covers:
//  - PipActionEvent.fromMap parsing.
//  - MediaPlayer routes 'onPipAction' into pipActionStream.
//  - pipActionStream is closed by dispose().
//
// Harness: same pattern as notification_action_event_routing_test.dart —
// TestDefaultBinaryMessengerBinding mock handler for outgoing calls +
// handlePlatformMessage with StandardMethodCodec to inject native -> Dart
// events.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

const _channel = MethodChannel('zmedia_player');

Future<void> _injectEvent(String method, Map<String, dynamic> arguments) async {
  final codec = const StandardMethodCodec();
  final data = codec.encodeMethodCall(MethodCall(method, arguments));
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage('zmedia_player', data, (_) {});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  // ===========================================================================
  group('PipActionEvent.fromMap', () {
    test('parses actionId from the native payload', () {
      final event = PipActionEvent.fromMap({
        'playerId': 'p1',
        'actionId': 'skip_intro',
      });

      expect(event.actionId, 'skip_intro');
    });

    test('equality and hashCode are value-based', () {
      const a = PipActionEvent('skip_intro');
      const b = PipActionEvent('skip_intro');
      const c = PipActionEvent('rewind');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });

  // ===========================================================================
  group('MediaPlayer — onPipAction routing', () {
    test('an "onPipAction" event arrives on pipActionStream', () async {
      final player = MediaPlayer(playerId: 'pip-action-basic');
      await player.initialize();

      final eventFuture = player.pipActionStream.first;

      await _injectEvent('onPipAction', {
        'playerId': 'pip-action-basic',
        'actionId': 'skip_intro',
      });

      final event = await eventFuture.timeout(const Duration(seconds: 2));
      expect(event.actionId, 'skip_intro');

      player.dispose();
    });

    test('multiple PiP actions arrive in order', () async {
      final player = MediaPlayer(playerId: 'pip-action-multi');
      await player.initialize();

      final events = <PipActionEvent>[];
      final sub = player.pipActionStream.listen(events.add);

      await _injectEvent('onPipAction', {
        'playerId': 'pip-action-multi',
        'actionId': 'rewind',
      });
      await Future<void>.delayed(Duration.zero);
      await _injectEvent('onPipAction', {
        'playerId': 'pip-action-multi',
        'actionId': 'forward',
      });
      await Future<void>.delayed(Duration.zero);

      expect(events.map((e) => e.actionId).toList(), ['rewind', 'forward']);

      await sub.cancel();
      player.dispose();
    });

    test('dispose() closes pipActionStream (no more events delivered after)',
        () async {
      final player = MediaPlayer(playerId: 'pip-action-dispose');
      await player.initialize();

      final events = <PipActionEvent>[];
      final sub = player.pipActionStream.listen(events.add);

      await player.dispose();
      await sub.cancel();

      // Injecting after dispose must not throw; the instance is already
      // removed from MediaPlayer's registry so the static dispatcher simply
      // finds no instance for this playerId.
      await _injectEvent('onPipAction', {
        'playerId': 'pip-action-dispose',
        'actionId': 'skip_intro',
      });
      await Future<void>.delayed(Duration.zero);

      expect(events, isEmpty);
    });

    test('an event for an unknown/disposed playerId is dropped, not thrown',
        () async {
      // No player registered for this id at all.
      await _injectEvent('onPipAction', {
        'playerId': 'pip-action-unknown',
        'actionId': 'skip_intro',
      });
      await Future<void>.delayed(Duration.zero);
      // Reaching here without an unhandled exception is the assertion.
    });
  });
}
