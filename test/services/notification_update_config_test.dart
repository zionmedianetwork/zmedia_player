// Regression tests for NotificationService.updateConfig.
//
// Found by on-device testing: toggling NotificationConfig.showSeekForward /
// showSeekBackward in the example app changed nothing on the lock screen. The
// flags themselves were wired to native (issue #81, see
// notification_seek_flags_test.dart) — what was missing was any way to *change*
// the config after construction:
//
//   * NotificationConfig was stored as `final NotificationConfig _config`;
//   * only initialize() ever sent `'config': _config.toMap()` to native
//     (method `initializeNotification`);
//   * show() renders from whatever config native already holds and re-sends
//     nothing.
//
// So a consumer had to build an entirely new NotificationService and
// re-initialize it to change a single flag. updateConfig() closes that gap: it
// stores the new config, re-sends it over the same `initializeNotification`
// call (both plugins rebuild their per-player handler from that payload and
// replace the registered one), and re-renders an already-showing notification
// so the change is visible immediately.
//
// These tests pin the half of the contract that crosses the MethodChannel —
// which calls are made, in which order, with which payload — since the native
// rendering itself is Kotlin/Swift and has no automated coverage in this repo.
//
// Harness: same as notification_state_sync_test.dart /
// notification_seek_flags_test.dart — a mock method-call handler to capture
// outgoing calls, plus handlePlatformMessage + StandardMethodCodec to inject
// native → Dart events.

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

/// Capture handler that fails every call named [failing], so the
/// error-swallowing paths can be exercised.
List<MethodCall> _installFailingCapture(String failing) {
  final calls = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (MethodCall call) async {
    calls.add(call);
    if (call.method == failing) {
      throw PlatformException(code: 'NOTIFICATION_INIT_ERROR');
    }
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

List<MethodCall> _named(List<MethodCall> calls, String method) =>
    calls.where((c) => c.method == method).toList();

/// The `config` map of the last `initializeNotification` call.
Map<Object?, Object?> _lastConfig(List<MethodCall> calls) {
  final init = _named(calls, 'initializeNotification');
  expect(init, isNotEmpty, reason: 'expected an initializeNotification call');
  final args = init.last.arguments as Map<Object?, Object?>;
  return args['config']! as Map<Object?, Object?>;
}

Map<Object?, Object?> _argsOf(MethodCall call) =>
    call.arguments as Map<Object?, Object?>;

const _item = MediaItem(
  id: 'update-config-item',
  title: 'Update Config Track',
  url: 'https://example.com/track.mp4',
  duration: Duration(minutes: 3),
);

const _playing = PlaybackState(
  state: PlayerState.playing,
  position: Duration(seconds: 1),
  duration: Duration(minutes: 3),
);

const _paused = PlaybackState(
  state: PlayerState.paused,
  position: Duration(seconds: 1),
  duration: Duration(minutes: 3),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  // =========================================================================
  group('updateConfig — re-sends the config to native', () {
    test('issues a second initializeNotification with the new flag values',
        () async {
      final calls = _installCapture();

      final service = NotificationService(const NotificationConfig(
        showSeekForward: false,
        showSeekBackward: false,
        seekInterval: 10,
      ));
      await service.initialize('uc-resend');

      expect(_lastConfig(calls)['showSeekForward'], false);

      calls.clear();
      await service.updateConfig(
        const NotificationConfig(
          showSeekForward: true,
          showSeekBackward: true,
          seekInterval: 30,
        ),
        playerId: 'uc-resend',
      );

      final init = _named(calls, 'initializeNotification');
      expect(init, hasLength(1),
          reason: 'updateConfig must re-send the config exactly once');
      expect(_argsOf(init.single)['playerId'], 'uc-resend');

      final config = _lastConfig(calls);
      expect(config['showSeekForward'], true);
      expect(config['showSeekBackward'], true);
      expect(config['seekInterval'], 30);

      service.dispose();
    });

    test('turning the flags back off puts explicit `false` on the wire',
        () async {
      final calls = _installCapture();

      final service = NotificationService(const NotificationConfig(
        showSeekForward: true,
        showSeekBackward: true,
      ));
      await service.initialize('uc-off');

      calls.clear();
      await service.updateConfig(
        const NotificationConfig(
          showSeekForward: false,
          showSeekBackward: false,
        ),
        playerId: 'uc-off',
      );

      // An omitted key means "keep whatever you had" to Android's
      // `config["showSeekForward"] as? Boolean ?: showSeekForward`, so an
      // opt-out must be present and false, never dropped.
      final config = _lastConfig(calls);
      expect(config.containsKey('showSeekForward'), isTrue);
      expect(config['showSeekForward'], false);
      expect(config['showSeekBackward'], false);

      service.dispose();
    });

    test('sends the whole config map, not just the changed fields', () async {
      final calls = _installCapture();

      final service = NotificationService(const NotificationConfig());
      await service.initialize('uc-whole-map');

      calls.clear();
      await service.updateConfig(
        const NotificationConfig(
          channelId: 'uc_channel',
          channelName: 'UC Channel',
          showPlayPause: true,
          showNext: false,
          showPrevious: false,
          showStop: true,
          showSeekForward: true,
          seekInterval: 15,
          showWhenPaused: false,
          priority: NotificationPriority.high,
          dismissible: true,
        ),
        playerId: 'uc-whole-map',
      );

      final config = _lastConfig(calls);
      expect(config['channelId'], 'uc_channel');
      expect(config['channelName'], 'UC Channel');
      expect(config['showNext'], false);
      expect(config['showPrevious'], false);
      expect(config['showStop'], true);
      expect(config['showSeekForward'], true);
      expect(config['seekInterval'], 15);
      expect(config['showWhenPaused'], false);
      expect(config['priority'], 'high');
      expect(config['dismissible'], true);

      service.dispose();
    });

    test('a failing native call is swallowed but the config is still stored',
        () async {
      final calls = _installFailingCapture('initializeNotification');

      final service = NotificationService(const NotificationConfig());
      await service.initialize('uc-failure');

      calls.clear();
      await expectLater(
        service.updateConfig(
          const NotificationConfig(showSeekForward: true),
          playerId: 'uc-failure',
        ),
        completes,
      );
      expect(_named(calls, 'initializeNotification'), hasLength(1));

      service.dispose();
    });
  });

  // =========================================================================
  group('updateConfig — re-render behaviour', () {
    test('a showing notification is re-rendered after the config is re-sent',
        () async {
      final calls = _installCapture();

      final service = NotificationService(const NotificationConfig());
      await service.initialize('uc-rerender');
      await service.show(
          mediaItem: _item, state: _playing, playerId: 'uc-rerender');
      expect(service.isShowing, isTrue);

      calls.clear();
      await service.updateConfig(
        const NotificationConfig(showSeekForward: true),
        playerId: 'uc-rerender',
      );

      // Order matters: native rebuilds its handler from initializeNotification,
      // so the re-render must come after it or it would render with the old
      // config (and on Android the tray would keep the old handler's post).
      expect(calls.map((c) => c.method).toList(),
          ['initializeNotification', 'showNotification']);

      final show = _named(calls, 'showNotification').single;
      final args = _argsOf(show);
      expect(args['playerId'], 'uc-rerender');
      final mediaItem = args['mediaItem']! as Map<Object?, Object?>;
      expect(mediaItem['id'], _item.id);
      expect(mediaItem['title'], _item.title);
      final state = args['state']! as Map<Object?, Object?>;
      expect(state['state'], 'playing');
      expect(state['position'], _playing.position.inMilliseconds);

      expect(service.isShowing, isTrue);
      service.dispose();
    });

    test('a notification that is not showing is never spuriously displayed',
        () async {
      final calls = _installCapture();

      final service = NotificationService(const NotificationConfig());
      await service.initialize('uc-not-showing');
      expect(service.isShowing, isFalse);

      calls.clear();
      await service.updateConfig(
        const NotificationConfig(showSeekForward: true),
        playerId: 'uc-not-showing',
      );

      expect(_named(calls, 'initializeNotification'), hasLength(1));
      expect(_named(calls, 'showNotification'), isEmpty);
      expect(service.isShowing, isFalse);

      service.dispose();
    });

    test('a dismissed notification is not re-rendered', () async {
      final calls = _installCapture();

      final service = NotificationService(const NotificationConfig());
      await service.initialize('uc-dismissed');
      await service.show(
          mediaItem: _item, state: _playing, playerId: 'uc-dismissed');
      await service.dismiss('uc-dismissed');
      expect(service.isShowing, isFalse);

      calls.clear();
      await service.updateConfig(
        const NotificationConfig(showSeekBackward: true),
        playerId: 'uc-dismissed',
      );

      expect(_named(calls, 'showNotification'), isEmpty);

      service.dispose();
    });

    test('the re-render replays the most recent state, not the one show() saw',
        () async {
      final calls = _installCapture();

      final service = NotificationService(const NotificationConfig());
      await service.initialize('uc-latest-state');
      await service.show(
          mediaItem: _item, state: _playing, playerId: 'uc-latest-state');

      const advanced = PlaybackState(
        state: PlayerState.playing,
        position: Duration(seconds: 42),
        duration: Duration(minutes: 3),
      );
      await service.updateState(state: advanced, playerId: 'uc-latest-state');

      calls.clear();
      await service.updateConfig(
        const NotificationConfig(showSeekForward: true),
        playerId: 'uc-latest-state',
      );

      final state = _argsOf(_named(calls, 'showNotification').single)['state']!
          as Map<Object?, Object?>;
      expect(state['position'], advanced.position.inMilliseconds);

      service.dispose();
    });

    test(
        'the re-render honours the new showWhenPaused: false by dismissing '
        'instead of showing', () async {
      final calls = _installCapture();

      final service = NotificationService(const NotificationConfig());
      await service.initialize('uc-when-paused');
      await service.show(
          mediaItem: _item, state: _paused, playerId: 'uc-when-paused');
      expect(service.isShowing, isTrue);

      calls.clear();
      await service.updateConfig(
        const NotificationConfig(showWhenPaused: false),
        playerId: 'uc-when-paused',
      );

      expect(calls.map((c) => c.method).toList(),
          ['initializeNotification', 'dismissNotification']);
      expect(service.isShowing, isFalse);

      service.dispose();
    });
  });

  // =========================================================================
  group('updateConfig — enabled transitions', () {
    test('disabling dismisses a showing notification and sends no config',
        () async {
      final calls = _installCapture();

      final service = NotificationService(const NotificationConfig());
      await service.initialize('uc-disable');
      await service.show(
          mediaItem: _item, state: _playing, playerId: 'uc-disable');

      calls.clear();
      await service.updateConfig(
        const NotificationConfig(enabled: false),
        playerId: 'uc-disable',
      );

      // The dismiss must happen while the *old* (enabled) config still allows
      // it — every method, dismiss() included, no-ops once disabled, so a
      // notification torn down afterwards would be stuck on screen forever.
      expect(calls.map((c) => c.method).toList(), ['dismissNotification']);
      expect(service.isShowing, isFalse);

      // And nothing at all is sent afterwards.
      calls.clear();
      await service.show(
          mediaItem: _item, state: _playing, playerId: 'uc-disable');
      expect(calls, isEmpty);

      service.dispose();
    });

    test('disabling while nothing is showing sends nothing at all', () async {
      final calls = _installCapture();

      final service = NotificationService(const NotificationConfig());
      await service.initialize('uc-disable-idle');

      calls.clear();
      await service.updateConfig(
        const NotificationConfig(enabled: false),
        playerId: 'uc-disable-idle',
      );

      expect(calls, isEmpty);

      service.dispose();
    });

    test('enabling a service initialized while disabled completes the setup',
        () async {
      final calls = _installCapture();

      // initialize() with enabled: false sends nothing (native has no handler
      // for this player at all).
      final service = NotificationService(const NotificationConfig(
        enabled: false,
        showSeekForward: true,
      ));
      await service.initialize('uc-enable');
      expect(calls, isEmpty);

      await service.updateConfig(
        const NotificationConfig(enabled: true, showSeekForward: true),
        playerId: 'uc-enable',
      );

      final config = _lastConfig(calls);
      expect(config['enabled'], true);
      expect(config['showSeekForward'], true);

      // ...and the service is fully usable afterwards.
      calls.clear();
      await service.show(
          mediaItem: _item, state: _playing, playerId: 'uc-enable');
      expect(_named(calls, 'showNotification'), hasLength(1));
      expect(service.isShowing, isTrue);

      service.dispose();
    });

    test('re-enabling after a disable works and does not resurrect the old one',
        () async {
      final calls = _installCapture();

      final service = NotificationService(const NotificationConfig());
      await service.initialize('uc-round-trip');
      await service.show(
          mediaItem: _item, state: _playing, playerId: 'uc-round-trip');

      await service.updateConfig(
        const NotificationConfig(enabled: false),
        playerId: 'uc-round-trip',
      );
      expect(service.isShowing, isFalse);

      calls.clear();
      await service.updateConfig(
        const NotificationConfig(enabled: true, showStop: true),
        playerId: 'uc-round-trip',
      );

      // The config is re-sent, but nothing is displayed: the notification was
      // dismissed on the way down and the consumer never asked for it back.
      expect(_named(calls, 'initializeNotification'), hasLength(1));
      expect(_lastConfig(calls)['showStop'], true);
      expect(_named(calls, 'showNotification'), isEmpty);
      expect(service.isShowing, isFalse);

      service.dispose();
    });
  });

  // =========================================================================
  group('updateConfig — before initialize()', () {
    test('does not throw and touches the channel not at all', () async {
      final calls = _installCapture();

      final service = NotificationService(const NotificationConfig());

      await expectLater(
        service.updateConfig(
          const NotificationConfig(showSeekForward: true),
          playerId: 'uc-early',
        ),
        completes,
      );
      expect(calls, isEmpty,
          reason: 'no native handler exists yet, and creating one here would '
              'leave it without any action/state wiring');

      service.dispose();
    });

    test('the stored config is the one the next initialize() sends', () async {
      final calls = _installCapture();

      final service = NotificationService(const NotificationConfig(
        showSeekForward: false,
        seekInterval: 10,
      ));

      await service.updateConfig(
        const NotificationConfig(showSeekForward: true, seekInterval: 30),
        playerId: 'uc-early-then-init',
      );
      expect(calls, isEmpty);

      await service.initialize('uc-early-then-init');

      final config = _lastConfig(calls);
      expect(config['showSeekForward'], true);
      expect(config['seekInterval'], 30);

      service.dispose();
    });
  });

  // =========================================================================
  group('updateConfig — subscription hygiene', () {
    test('repeated calls never duplicate forwarded action events', () async {
      _installCapture();

      final player = MediaPlayer(playerId: 'uc-no-dupes');
      await player.initialize();

      final service = NotificationService(const NotificationConfig());
      await service.initialize('uc-no-dupes', mediaPlayer: player);

      final received = <String>[];
      final sub =
          service.actionEventStream.listen((e) => received.add(e.action));

      for (var i = 0; i < 3; i++) {
        await service.updateConfig(
          NotificationConfig(showSeekForward: i.isEven),
          playerId: 'uc-no-dupes',
        );
      }

      await _injectEvent('onNotificationAction', {
        'playerId': 'uc-no-dupes',
        'action': 'play',
      });
      await Future<void>.delayed(Duration.zero);

      expect(received, ['play'],
          reason: 'a duplicated stateStream/action subscription would emit the '
              'same action once per updateConfig call');

      await sub.cancel();
      service.dispose();
      await player.dispose();
    });

    test(
        'enabling via updateConfig wires the MediaPlayer that initialize() '
        'could not', () async {
      final calls = _installCapture();

      final player = MediaPlayer(playerId: 'uc-late-wiring');
      await player.initialize();

      // Disabled at initialize() time: the native send *and* the stream wiring
      // are both skipped, but the MediaPlayer reference is retained.
      final service =
          NotificationService(const NotificationConfig(enabled: false));
      await service.initialize('uc-late-wiring', mediaPlayer: player);

      await service.updateConfig(
        const NotificationConfig(enabled: true),
        playerId: 'uc-late-wiring',
      );
      await service.show(
          mediaItem: _item, state: _playing, playerId: 'uc-late-wiring');

      calls.clear();
      await _injectEvent('onStateChanged', {
        'playerId': 'uc-late-wiring',
        'state': 'paused',
        'isBuffering': false,
        'bufferPercentage': 0.0,
      });
      await Future<void>.delayed(Duration.zero);

      expect(_named(calls, 'updateNotificationState'), isNotEmpty,
          reason: 'the stateStream subscription must exist after enabling');

      service.dispose();
      await player.dispose();
    });
  });
}
