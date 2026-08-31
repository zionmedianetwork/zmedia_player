// Regression tests for issue #81: NotificationConfig.showSeekForward /
// showSeekBackward were honoured on neither platform.
//
// Android read both flags into private fields it never used again, so the seek
// buttons were never added regardless of config. iOS ignored the flags entirely
// and gated skipForwardCommand/skipBackwardCommand on `isSeekable` alone, so any
// seekable VOD item got the commands even when the consumer explicitly asked for
// `showSeekForward: false`.
//
// The fix adopts one contract on both platforms:
//
//     a seek control is offered  <=>  flag == true AND item is seekable
//
// The gating itself lives in Kotlin/Swift and cannot be exercised from Dart (the
// native layer has no automated tests in this repo — a documented gap). What Dart
// *can* and must guarantee is the half of the contract that crosses the
// MethodChannel: that `showSeekForward`, `showSeekBackward` and `seekInterval`
// are actually serialized into the `initializeNotification` payload under exactly
// the keys the two handlers read
// (`NotificationHandler.kt`'s `config["showSeekForward"] as? Boolean` /
// `config["seekInterval"] as? Number`, and `NotificationHandler.swift`'s
// `config["showSeekForward"] as? Bool` / `config["seekInterval"] as? Int`), with
// the right value and the right runtime type — including on a config update, and
// including when the flags are `false` (a dropped `false` would let native fall
// back to a stale/default value instead of switching the control off).
//
// Also pins `NotificationActions.seekForward`/`seekBackward` to the wire values
// both platforms actually emit. They previously read `'seek_forward'` /
// `'seek_backward'`, which neither platform has ever sent, so a
// `case NotificationActions.seekForward:` branch was dead code.
//
// Harness: same pattern as notification_state_sync_test.dart —
// TestDefaultBinaryMessengerBinding mock handler to capture outgoing calls, plus
// handlePlatformMessage with StandardMethodCodec to inject native → Dart events.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

const _channel = MethodChannel('zmedia_player');

List<MethodCall> _installCapture() {
  final calls = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (MethodCall call) async {
    calls.add(call);
    return null;
  });
  return calls;
}

Future<void> _injectEvent(String method, Map<String, dynamic> arguments) async {
  const codec = StandardMethodCodec();
  final data = codec.encodeMethodCall(MethodCall(method, arguments));
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage('zmedia_player', data, (_) {});
}

/// Pulls the `config` map out of the (single) `initializeNotification` call.
Map<Object?, Object?> _configFrom(List<MethodCall> calls) {
  final init = calls.where((c) => c.method == 'initializeNotification');
  expect(init, hasLength(1),
      reason: 'expected exactly one initializeNotification call');
  final args = init.single.arguments as Map<Object?, Object?>;
  return args['config']! as Map<Object?, Object?>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  // ===========================================================================
  group('NotificationConfig.toMap — seek flag serialization', () {
    test('defaults are both flags off with a 10s interval', () {
      const config = NotificationConfig();

      expect(config.showSeekForward, isFalse);
      expect(config.showSeekBackward, isFalse);
      expect(config.seekInterval, 10);
    });

    test('emits the exact keys both native handlers read', () {
      final map = const NotificationConfig(
        showSeekForward: true,
        showSeekBackward: true,
        seekInterval: 30,
      ).toMap();

      expect(map.containsKey('showSeekForward'), isTrue);
      expect(map.containsKey('showSeekBackward'), isTrue);
      expect(map.containsKey('seekInterval'), isTrue);

      expect(map['showSeekForward'], true);
      expect(map['showSeekBackward'], true);
      expect(map['seekInterval'], 30);
    });

    test('a false flag is serialized as false, never dropped', () {
      // Android's parse is `config["showSeekForward"] as? Boolean ?: showSeekForward`
      // and iOS's is `config["showSeekForward"] as? Bool ?? false`: an omitted key
      // means "keep whatever you had", so an explicit opt-out MUST be on the wire.
      final map = const NotificationConfig(
        showSeekForward: false,
        showSeekBackward: false,
      ).toMap();

      expect(map['showSeekForward'], isNotNull);
      expect(map['showSeekBackward'], isNotNull);
      expect(map['showSeekForward'], false);
      expect(map['showSeekBackward'], false);
    });

    test('flags are bool and seekInterval is int (native cast compatibility)',
        () {
      // iOS casts with `as? Bool` / `as? Int`; a String or double here would
      // silently fall back to the default on that platform.
      final map = const NotificationConfig(
        showSeekForward: true,
        showSeekBackward: false,
        seekInterval: 15,
      ).toMap();

      expect(map['showSeekForward'], isA<bool>());
      expect(map['showSeekBackward'], isA<bool>());
      expect(map['seekInterval'], isA<int>());
    });

    test('copyWith carries each seek field through independently', () {
      const base = NotificationConfig();

      final forwardOnly = base.copyWith(showSeekForward: true);
      expect(forwardOnly.showSeekForward, isTrue);
      expect(forwardOnly.showSeekBackward, isFalse);

      final backwardOnly = base.copyWith(showSeekBackward: true);
      expect(backwardOnly.showSeekForward, isFalse);
      expect(backwardOnly.showSeekBackward, isTrue);

      final retimed = base.copyWith(seekInterval: 45);
      expect(retimed.seekInterval, 45);
      // Untouched fields must not be disturbed.
      expect(retimed.showSeekForward, isFalse);
      expect(retimed.showNext, isTrue);
    });
  });

  // ===========================================================================
  group('NotificationService.initialize — MethodChannel payload', () {
    test('forwards both seek flags and the interval to native', () async {
      final calls = _installCapture();

      final service = NotificationService(const NotificationConfig(
        showSeekForward: true,
        showSeekBackward: true,
        seekInterval: 30,
      ));
      await service.initialize('seek-flags-on');

      final config = _configFrom(calls);
      expect(config['showSeekForward'], true);
      expect(config['showSeekBackward'], true);
      expect(config['seekInterval'], 30);

      service.dispose();
    });

    test('forwards an explicit opt-out (false) rather than omitting it',
        () async {
      final calls = _installCapture();

      // The exact playlist case from issue #81: next/previous wanted, no ±10s
      // seek. iOS used to enable the skip commands anyway for a seekable item.
      final service = NotificationService(const NotificationConfig(
        showNext: true,
        showPrevious: true,
        showSeekForward: false,
        showSeekBackward: false,
      ));
      await service.initialize('seek-flags-off');

      final config = _configFrom(calls);
      expect(config['showNext'], true);
      expect(config['showPrevious'], true);
      expect(config['showSeekForward'], false);
      expect(config['showSeekBackward'], false);

      service.dispose();
    });

    test('mixed flags survive independently (forward on, backward off)',
        () async {
      final calls = _installCapture();

      final service = NotificationService(const NotificationConfig(
        showSeekForward: true,
        showSeekBackward: false,
        seekInterval: 5,
      ));
      await service.initialize('seek-flags-mixed');

      final config = _configFrom(calls);
      expect(config['showSeekForward'], true);
      expect(config['showSeekBackward'], false);
      expect(config['seekInterval'], 5);

      service.dispose();
    });

    test('nothing is sent at all when notifications are disabled', () async {
      final calls = _installCapture();

      final service = NotificationService(const NotificationConfig(
        enabled: false,
        showSeekForward: true,
      ));
      await service.initialize('seek-flags-disabled');

      expect(calls.where((c) => c.method == 'initializeNotification'), isEmpty);

      service.dispose();
    });
  });

  // ===========================================================================
  group('config update round-trip', () {
    test(
        're-initializing with a changed config re-sends the new seek gating '
        'to native', () async {
      final calls = _installCapture();

      const initial = NotificationConfig(
        showSeekForward: false,
        showSeekBackward: false,
        seekInterval: 10,
      );

      final first = NotificationService(initial);
      await first.initialize('seek-flags-update');

      var config = _configFrom(calls);
      expect(config['showSeekForward'], false);
      expect(config['showSeekBackward'], false);
      expect(config['seekInterval'], 10);
      first.dispose();

      // Runtime config update: the host app builds a new config (typically via
      // copyWith) and re-initializes. Native rebuilds its handler from this
      // payload, so the updated gating must be fully present here — nothing is
      // carried over implicitly.
      calls.clear();
      final updated = initial.copyWith(
        showSeekForward: true,
        showSeekBackward: true,
        seekInterval: 30,
      );
      final second = NotificationService(updated);
      await second.initialize('seek-flags-update');

      config = _configFrom(calls);
      expect(config['showSeekForward'], true);
      expect(config['showSeekBackward'], true);
      expect(config['seekInterval'], 30);
      second.dispose();
    });

    test('turning the flags back off round-trips too', () async {
      final calls = _installCapture();

      const on = NotificationConfig(
        showSeekForward: true,
        showSeekBackward: true,
        seekInterval: 30,
      );
      final off = on.copyWith(
        showSeekForward: false,
        showSeekBackward: false,
      );

      final service = NotificationService(off);
      await service.initialize('seek-flags-back-off');

      final config = _configFrom(calls);
      expect(config['showSeekForward'], false);
      expect(config['showSeekBackward'], false);
      // seekInterval is untouched by the opt-out and must survive.
      expect(config['seekInterval'], 30);

      service.dispose();
    });
  });

  // ===========================================================================
  group('NotificationActions seek wire values', () {
    test('match what both native handlers emit', () {
      // NotificationHandler.kt: sendActionToFlutter("seekForward") /
      // sendActionToFlutter("seekBackward").
      // NotificationHandler.swift: skipForwardCommand/skipBackwardCommand
      // targets send the same two strings.
      expect(NotificationActions.seekForward, 'seekForward');
      expect(NotificationActions.seekBackward, 'seekBackward');
    });

    test(
        'a native seek action matches the constant end-to-end through '
        'MediaPlayer', () async {
      _installCapture();

      final player = MediaPlayer(playerId: 'seek-flags-action');
      await player.initialize();

      final eventFuture = player.notificationActionEventStream.first;

      await _injectEvent('onNotificationAction', {
        'playerId': 'seek-flags-action',
        'action': 'seekForward',
      });

      final event = await eventFuture.timeout(const Duration(seconds: 2));
      expect(event.action, NotificationActions.seekForward);
      expect(event.position, isNull);

      await player.dispose();
    });
  });
}
