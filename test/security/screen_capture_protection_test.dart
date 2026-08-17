import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

// ---------------------------------------------------------------------------
// Item 1 (B-12 BLOCKER): opt-in screen-capture protection.
//
// Covers the Dart-side contract only:
//   - MediaPlayer.setSecureSurface() sends "setSecureSurface" with the
//     correct payload, and defaults to OFF (no call unless opted in).
//   - MediaConfig.secureSurface drives the initial value applied at
//     initialize(), and updateConfig() propagates changes.
//   - onScreenCaptureChanged native events are parsed and delivered via
//     screenCaptureStream / screenCaptureStatus.
//
// Native enforcement (Android FLAG_SECURE via SecureSurfaceHandler.kt, iOS
// UIScreen.isCaptured monitoring via ScreenCaptureHandler.swift) has no
// automated test coverage — see CLAUDE.md's native testing gap and the task
// report for what remains unverified.
// ---------------------------------------------------------------------------

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
  final codec = const StandardMethodCodec();
  final data = codec.encodeMethodCall(MethodCall(method, arguments));
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage('zmedia_player', data, (_) {});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Default no-op handler so tests that don't need to inspect outgoing
    // calls (e.g. the onScreenCaptureChanged event-delivery group below)
    // don't have to install their own — mirrors
    // media_player_network_status_test.dart's setUp/tearDown pattern.
    // Tests that DO need to capture calls install their own handler via
    // _installCapture(), which simply replaces this one.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  group('ScreenCaptureStatus', () {
    test('fromMap parses isCaptured', () {
      final status = ScreenCaptureStatus.fromMap({'isCaptured': true});
      expect(status.isCaptured, isTrue);
    });

    test('fromMap defaults isCaptured to false when missing', () {
      final status = ScreenCaptureStatus.fromMap({});
      expect(status.isCaptured, isFalse);
    });

    test('equality is value-based', () {
      expect(
        const ScreenCaptureStatus(isCaptured: true),
        const ScreenCaptureStatus(isCaptured: true),
      );
      expect(
        const ScreenCaptureStatus(isCaptured: true) ==
            const ScreenCaptureStatus(isCaptured: false),
        isFalse,
      );
    });
  });

  group('MediaConfig.secureSurface default', () {
    test('defaults to false (opt-in, no existing consumer changes)', () {
      const config = MediaConfig();
      expect(config.secureSurface, isFalse);
    });

    test('copyWith updates secureSurface and preserves other fields', () {
      const base = MediaConfig(autoPlay: true);
      final updated = base.copyWith(secureSurface: true);
      expect(updated.secureSurface, isTrue);
      expect(updated.autoPlay, isTrue);
    });
  });

  group('MediaPlayer.setSecureSurface — outgoing contract', () {
    test('is OFF by default — initialize() sends no "setSecureSurface" call',
        () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'secsurf-default-off');
      await player.initialize();

      expect(calls.where((c) => c.method == 'setSecureSurface'), isEmpty,
          reason: 'setSecureSurface must default to OFF — no existing '
              'consumer should see a behaviour change');
      expect(player.isSecureSurfaceEnabled, isFalse);

      player.dispose();
    });

    test('explicit setSecureSurface(true) sends the method with playerId',
        () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'secsurf-explicit');
      await player.initialize();
      calls.clear();

      await player.setSecureSurface(true);

      final call =
          calls.firstWhere((c) => c.method == 'setSecureSurface', orElse: () {
        fail('No "setSecureSurface" call found');
      });
      expect(call.arguments['playerId'], 'secsurf-explicit');
      expect(call.arguments['enabled'], isTrue);
      expect(player.isSecureSurfaceEnabled, isTrue);

      player.dispose();
    });

    test('setSecureSurface(false) after true sends enabled:false', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'secsurf-toggle-off');
      await player.initialize();
      await player.setSecureSurface(true);
      calls.clear();

      await player.setSecureSurface(false);

      final call = calls.firstWhere((c) => c.method == 'setSecureSurface');
      expect(call.arguments['enabled'], isFalse);
      expect(player.isSecureSurfaceEnabled, isFalse);

      player.dispose();
    });

    test('MediaConfig(secureSurface: true) auto-applies at initialize()',
        () async {
      final calls = _installCapture();
      final player = MediaPlayer(
        playerId: 'secsurf-config-init',
        config: const MediaConfig(secureSurface: true),
      );
      await player.initialize();

      final call =
          calls.firstWhere((c) => c.method == 'setSecureSurface', orElse: () {
        fail(
            'MediaConfig.secureSurface=true must trigger "setSecureSurface" '
            'at initialize()');
      });
      expect(call.arguments['playerId'], 'secsurf-config-init');
      expect(call.arguments['enabled'], isTrue);
      expect(player.isSecureSurfaceEnabled, isTrue);

      player.dispose();
    });

    test('updateConfig toggling secureSurface sends "setSecureSurface"',
        () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'secsurf-update-config');
      await player.initialize();
      calls.clear();

      await player.updateConfig(player.config.copyWith(secureSurface: true));

      final call =
          calls.firstWhere((c) => c.method == 'setSecureSurface', orElse: () {
        fail('updateConfig toggling secureSurface must send '
            '"setSecureSurface"');
      });
      expect(call.arguments['enabled'], isTrue);
      expect(player.isSecureSurfaceEnabled, isTrue);

      player.dispose();
    });

    test(
        'updateConfig without a secureSurface change does NOT send '
        '"setSecureSurface"', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'secsurf-update-noop');
      await player.initialize();
      calls.clear();

      await player.updateConfig(player.config.copyWith(volume: 0.5));

      expect(calls.where((c) => c.method == 'setSecureSurface'), isEmpty,
          reason: 'no secureSurface change means no redundant native call');

      player.dispose();
    });
  });

  group('onScreenCaptureChanged → screenCaptureStream / screenCaptureStatus',
      () {
    test('a captured=true event is parsed and delivered', () async {
      final player = MediaPlayer(playerId: 'secsurf-event-true');
      await player.initialize();

      final statusFuture = player.screenCaptureStream.first;
      await _injectEvent('onScreenCaptureChanged', {
        'playerId': 'secsurf-event-true',
        'isCaptured': true,
      });

      final status = await statusFuture.timeout(const Duration(seconds: 2));
      expect(status.isCaptured, isTrue);
      expect(player.screenCaptureStatus.isCaptured, isTrue);

      player.dispose();
    });

    test('screenCaptureStatus defaults to isCaptured:false before any event',
        () async {
      final player = MediaPlayer(playerId: 'secsurf-event-default');
      await player.initialize();

      expect(player.screenCaptureStatus.isCaptured, isFalse);

      player.dispose();
    });

    test('event for a different playerId does NOT update this instance',
        () async {
      final player = MediaPlayer(playerId: 'secsurf-event-wrong-id');
      await player.initialize();

      var emitted = false;
      player.screenCaptureStream.listen((_) => emitted = true);

      await _injectEvent('onScreenCaptureChanged', {
        'playerId': 'SOME-OTHER-PLAYER',
        'isCaptured': true,
      });
      await Future<void>.delayed(Duration.zero);

      expect(emitted, isFalse);
      expect(player.screenCaptureStatus.isCaptured, isFalse);

      player.dispose();
    });
  });
}
