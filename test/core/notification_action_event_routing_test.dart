// Regression tests for M-02: lock-screen / Control Center "seekTo" (dragging
// the scrub bar) previously could not reach Dart with a position at all.
//
// Covers:
//  - NotificationActionEvent.fromMap parsing (int/num position, missing
//    position, every platform payload shape Android/iOS actually send).
//  - MediaPlayer routes 'onNotificationAction' into BOTH
//    notificationActionEventStream (typed, carries position) and the
//    deprecated notificationActionStream (String, action only) so existing
//    consumers keep working unchanged.
//  - NotificationService.initialize(mediaPlayer:) forwards MediaPlayer's
//    typed event stream into its own actionEventStream (and mirrors the
//    action-only value onto the deprecated actionStream).
//
// Harness: same pattern as media_player_events_test.dart and
// notification_state_sync_test.dart — TestDefaultBinaryMessengerBinding
// mock handler for outgoing calls + handlePlatformMessage with
// StandardMethodCodec to inject native → Dart events.

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
  group('NotificationActionEvent.fromMap', () {
    test('parses an action with no position (e.g. "play")', () {
      final event = NotificationActionEvent.fromMap({
        'playerId': 'p1',
        'action': 'play',
      });

      expect(event.action, 'play');
      expect(event.position, isNull);
    });

    test('parses "seekTo" with an int position (Android payload shape)', () {
      final event = NotificationActionEvent.fromMap({
        'playerId': 'p1',
        'action': 'seekTo',
        'position': 45000,
      });

      expect(event.action, 'seekTo');
      expect(event.position, const Duration(milliseconds: 45000));
    });

    test('parses "seekTo" with a num (double) position defensively', () {
      // StandardMethodCodec always decodes whole-number platform Int64/Long
      // values as Dart int, but this guards against any codec that hands
      // back a double for the same logical value.
      final event = NotificationActionEvent.fromMap({
        'playerId': 'p1',
        'action': 'seekTo',
        'position': 45000.0,
      });

      expect(event.action, 'seekTo');
      expect(event.position, const Duration(milliseconds: 45000));
    });

    test('position is null when the key is absent entirely', () {
      final event = NotificationActionEvent.fromMap({
        'playerId': 'p1',
        'action': 'seekForward',
      });

      expect(event.position, isNull);
    });

    test('equality and hashCode are value-based', () {
      const a =
          NotificationActionEvent('seekTo', position: Duration(seconds: 5));
      const b =
          NotificationActionEvent('seekTo', position: Duration(seconds: 5));
      const c =
          NotificationActionEvent('seekTo', position: Duration(seconds: 6));

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });

  // ===========================================================================
  group('MediaPlayer — onNotificationAction routing (M-02)', () {
    test(
        'a "seekTo" event with a position arrives on notificationActionEventStream',
        () async {
      final player = MediaPlayer(playerId: 'notif-seekto-event');
      await player.initialize();

      final eventFuture = player.notificationActionEventStream.first;

      await _injectEvent('onNotificationAction', {
        'playerId': 'notif-seekto-event',
        'action': 'seekTo',
        'position': 30000,
      });

      final event = await eventFuture.timeout(const Duration(seconds: 2));
      expect(event.action, 'seekTo');
      expect(event.position, const Duration(milliseconds: 30000));

      player.dispose();
    });

    test(
        'the SAME "seekTo" event still arrives on the deprecated '
        'notificationActionStream as the bare action string (no position, '
        'but not dropped)', () async {
      final player = MediaPlayer(playerId: 'notif-seekto-legacy');
      await player.initialize();

      // ignore: deprecated_member_use
      final legacyFuture = player.notificationActionStream.first;

      await _injectEvent('onNotificationAction', {
        'playerId': 'notif-seekto-legacy',
        'action': 'seekTo',
        'position': 12345,
      });

      final action = await legacyFuture.timeout(const Duration(seconds: 2));
      expect(action, 'seekTo');

      player.dispose();
    });

    test('an action with no position (e.g. "play") carries position == null',
        () async {
      final player = MediaPlayer(playerId: 'notif-play-event');
      await player.initialize();

      final eventFuture = player.notificationActionEventStream.first;

      await _injectEvent('onNotificationAction', {
        'playerId': 'notif-play-event',
        'action': 'play',
      });

      final event = await eventFuture.timeout(const Duration(seconds: 2));
      expect(event.action, 'play');
      expect(event.position, isNull);

      player.dispose();
    });

    test('both streams receive every event, in order, for multiple actions',
        () async {
      final player = MediaPlayer(playerId: 'notif-multi-event');
      await player.initialize();

      final events = <NotificationActionEvent>[];
      // ignore: deprecated_member_use
      final legacyActions = <String>[];
      final eventSub = player.notificationActionEventStream.listen(events.add);
      // ignore: deprecated_member_use
      final legacySub =
          // ignore: deprecated_member_use
          player.notificationActionStream.listen(legacyActions.add);

      await _injectEvent('onNotificationAction', {
        'playerId': 'notif-multi-event',
        'action': 'pause',
      });
      await Future<void>.delayed(Duration.zero);
      await _injectEvent('onNotificationAction', {
        'playerId': 'notif-multi-event',
        'action': 'seekTo',
        'position': 5000,
      });
      await Future<void>.delayed(Duration.zero);

      expect(events.map((e) => e.action).toList(), ['pause', 'seekTo']);
      expect(events[1].position, const Duration(milliseconds: 5000));
      expect(legacyActions, ['pause', 'seekTo']);

      await eventSub.cancel();
      await legacySub.cancel();
      player.dispose();
    });
  });

  // ===========================================================================
  group(
      'NotificationService — actionEventStream forwards MediaPlayer events (M-02)',
      () {
    test(
        'a "seekTo" event with a position reaches NotificationService.actionEventStream',
        () async {
      final player = MediaPlayer(playerId: 'notif-svc-seekto');
      await player.initialize();

      final service = NotificationService(const NotificationConfig());
      await service.initialize('notif-svc-seekto', mediaPlayer: player);

      final eventFuture = service.actionEventStream.first;

      await _injectEvent('onNotificationAction', {
        'playerId': 'notif-svc-seekto',
        'action': 'seekTo',
        'position': 60000,
      });

      final event = await eventFuture.timeout(const Duration(seconds: 2));
      expect(event.action, NotificationActions.seekTo);
      expect(event.position, const Duration(minutes: 1));

      service.dispose();
      await player.dispose();
    });

    test(
        'the deprecated actionStream still receives "seekTo" as a bare '
        'string (mirrors actionEventStream, no position)', () async {
      final player = MediaPlayer(playerId: 'notif-svc-seekto-legacy');
      await player.initialize();

      final service = NotificationService(const NotificationConfig());
      await service.initialize('notif-svc-seekto-legacy', mediaPlayer: player);

      // ignore: deprecated_member_use
      final legacyFuture = service.actionStream.first;

      await _injectEvent('onNotificationAction', {
        'playerId': 'notif-svc-seekto-legacy',
        'action': 'seekTo',
        'position': 7000,
      });

      final action = await legacyFuture.timeout(const Duration(seconds: 2));
      expect(action, 'seekTo');

      service.dispose();
      await player.dispose();
    });

    test('play/pause/next/previous/stop still forward with null position',
        () async {
      final player = MediaPlayer(playerId: 'notif-svc-basic-actions');
      await player.initialize();

      final service = NotificationService(const NotificationConfig());
      await service.initialize('notif-svc-basic-actions', mediaPlayer: player);

      final events = <NotificationActionEvent>[];
      final sub = service.actionEventStream.listen(events.add);

      for (final action in ['play', 'pause', 'next', 'previous', 'stop']) {
        await _injectEvent('onNotificationAction', {
          'playerId': 'notif-svc-basic-actions',
          'action': action,
        });
        await Future<void>.delayed(Duration.zero);
      }

      expect(events.map((e) => e.action).toList(),
          ['play', 'pause', 'next', 'previous', 'stop']);
      expect(events.every((e) => e.position == null), isTrue);

      await sub.cancel();
      service.dispose();
      await player.dispose();
    });

    test('dispose() closes actionEventStream (no more events delivered after)',
        () async {
      final player = MediaPlayer(playerId: 'notif-svc-dispose-event');
      await player.initialize();

      final service = NotificationService(const NotificationConfig());
      await service.initialize('notif-svc-dispose-event', mediaPlayer: player);

      final events = <NotificationActionEvent>[];
      final sub = service.actionEventStream.listen(events.add);

      service.dispose();
      await sub.cancel();

      // Injecting after dispose must not throw even though the underlying
      // MediaPlayer subscription was cancelled by NotificationService.dispose().
      await _injectEvent('onNotificationAction', {
        'playerId': 'notif-svc-dispose-event',
        'action': 'play',
      });
      await Future<void>.delayed(Duration.zero);

      expect(events, isEmpty);

      await player.dispose();
    });
  });
}
