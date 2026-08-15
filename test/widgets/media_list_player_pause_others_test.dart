// Regression tests for M-01: MediaListPlayerConfig.pauseOthersOnPlay.
//
// Before this fix, `pauseOthersOnPlay` was declared on MediaListPlayerConfig
// (defaulted `true`) but never read anywhere in `lib/` — so mounting several
// MediaListPlayer widgets never actually paused sibling players when one
// started playing, despite the flag's contract.
//
// `_MediaListPlaybackCoordinator` (private, inside media_list_player.dart) is
// a process-wide registry that every mounted MediaListPlayer's controller
// registers with on initState/unregisters from on dispose. When a
// registered controller transitions not-playing -> playing (an edge, not a
// state "tick") and its own widget's pauseOthersOnPlay is true, every other
// registered controller that is currently playing is paused.
//
// Because the coordinator class is private to media_list_player.dart, these
// tests exercise it exclusively through the public MediaListPlayer widget +
// MediaController surface, injecting native onStateChanged/onPositionChanged
// events the same way test/services/notification_state_sync_test.dart does.
//
// No media is ever loaded (`controller.currentItem` stays null), so
// MediaPlayerWidget never attempts to mount a native AndroidView/UiKitView —
// see test/widgets/media_player_widget_safe_area_test.dart for why that
// matters in headless tests.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

// ---------------------------------------------------------------------------
// Shared channel helpers (mirrors notification_state_sync_test.dart style)
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

void _resetHandler() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null);
}

Future<void> _injectEvent(String method, Map<String, dynamic> arguments) async {
  final codec = const StandardMethodCodec();
  final data = codec.encodeMethodCall(MethodCall(method, arguments));
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage('zmedia_player', data, (_) {});
}

/// Injects an onStateChanged event marking [playerId] as playing/paused.
Future<void> _injectState(String playerId, String state) => _injectEvent(
      'onStateChanged',
      {
        'playerId': playerId,
        'state': state,
        'isBuffering': false,
        'bufferPercentage': 0.0,
      },
    );

/// Injects a large-jump onPositionChanged event so MediaController's 500ms/
/// 1000ms throttle guard (`_shouldUpdatePosition`) is bypassed and a
/// notifyListeners() "tick" fires without touching playback state.
Future<void> _injectPositionTick(String playerId, int ms) => _injectEvent(
      'onPositionChanged',
      {'playerId': playerId, 'position': ms},
    );

/// Mounts two MediaListPlayer widgets side by side, each bound to its own
/// MediaController, and returns both controllers plus the captured channel
/// calls. Visibility-driven auto-play/auto-pause is disabled throughout so
/// only the explicit event injections below drive isPlaying.
Future<(MediaController, MediaController, List<MethodCall>)> _pumpTwoPlayers(
  WidgetTester tester, {
  required String idA,
  required String idB,
  bool pauseOthersOnPlayA = true,
  bool pauseOthersOnPlayB = true,
}) async {
  final calls = _installCapture();

  final controllerA = MediaController.create(playerId: idA);
  final controllerB = MediaController.create(playerId: idB);

  const noAutoConfig = MediaListPlayerConfig(
    autoPlay: false,
    autoPause: false,
    muteWhenNotVisible: false,
  );

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            SizedBox(
              width: 320,
              height: 180,
              child: MediaListPlayer(
                controller: controllerA,
                showControls: false,
                config: MediaListPlayerConfig(
                  autoPlay: noAutoConfig.autoPlay,
                  autoPause: noAutoConfig.autoPause,
                  muteWhenNotVisible: noAutoConfig.muteWhenNotVisible,
                  pauseOthersOnPlay: pauseOthersOnPlayA,
                ),
              ),
            ),
            SizedBox(
              width: 320,
              height: 180,
              child: MediaListPlayer(
                controller: controllerB,
                showControls: false,
                config: MediaListPlayerConfig(
                  autoPlay: noAutoConfig.autoPlay,
                  autoPause: noAutoConfig.autoPause,
                  muteWhenNotVisible: noAutoConfig.muteWhenNotVisible,
                  pauseOthersOnPlay: pauseOthersOnPlayB,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));

  return (controllerA, controllerB, calls);
}

Future<void> _teardown(
  WidgetTester tester,
  List<MediaController> controllers,
) async {
  // Flush any pending timers (e.g. MediaPlayerWidget.refreshVideoSurface)
  // while the widget tree is still mounted — mirrors
  // media_player_widget_safe_area_test.dart's _cleanUp.
  await tester.pumpAndSettle();
  await tester.pumpWidget(const SizedBox.shrink());
  for (final c in controllers) {
    c.dispose();
  }
  await tester.pump();
  _resetHandler();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Warm up static cleanup timer before any testWidgets run so it is not
    // flagged as "new" during a test (mirrors other widget test files).
    final calls = _installCapture();
    final warmup =
        MediaController.create(playerId: 'warmup-pause-others-static-timer');
    warmup.dispose();
    calls.clear();
    _resetHandler();
  });

  group('MediaListPlayerConfig.pauseOthersOnPlay', () {
    testWidgets(
        'starting playback on A pauses B when A.pauseOthersOnPlay is true and B is playing',
        (tester) async {
      final (controllerA, controllerB, calls) = await _pumpTwoPlayers(
        tester,
        idA: 'pause-others-a1',
        idB: 'pause-others-b1',
      );

      // B starts out playing.
      await _injectState('pause-others-b1', 'playing');
      await tester.pump();
      expect(controllerB.isPlaying, isTrue);

      calls.clear();

      // A starts playing — should pause B.
      await _injectState('pause-others-a1', 'playing');
      await tester.pump();

      final pauseCallsForB = calls
          .where((c) =>
              c.method == 'pause' &&
              (c.arguments as Map)['playerId'] == 'pause-others-b1')
          .toList();

      expect(
        pauseCallsForB,
        isNotEmpty,
        reason: 'A starting to play must pause B via the pauseOthersOnPlay '
            'coordinator',
      );

      await _teardown(tester, [controllerA, controllerB]);
    });

    testWidgets(
        'starting playback on A does NOT pause B when A.pauseOthersOnPlay is false',
        (tester) async {
      final (controllerA, controllerB, calls) = await _pumpTwoPlayers(
        tester,
        idA: 'pause-others-a2',
        idB: 'pause-others-b2',
        pauseOthersOnPlayA: false,
      );

      await _injectState('pause-others-b2', 'playing');
      await tester.pump();

      calls.clear();

      await _injectState('pause-others-a2', 'playing');
      await tester.pump();

      final pauseCallsForB = calls
          .where((c) =>
              c.method == 'pause' &&
              (c.arguments as Map)['playerId'] == 'pause-others-b2')
          .toList();

      expect(
        pauseCallsForB,
        isEmpty,
        reason: 'pauseOthersOnPlay=false on A must not pause B',
      );

      await _teardown(tester, [controllerA, controllerB]);
    });

    testWidgets(
        "B is paused by A's pauseOthersOnPlay even when B's own pauseOthersOnPlay is false "
        '(the flag governs pausing others, not opting out of being paused)',
        (tester) async {
      final (controllerA, controllerB, calls) = await _pumpTwoPlayers(
        tester,
        idA: 'pause-others-a3',
        idB: 'pause-others-b3',
        pauseOthersOnPlayB: false,
      );

      await _injectState('pause-others-b3', 'playing');
      await tester.pump();

      calls.clear();

      await _injectState('pause-others-a3', 'playing');
      await tester.pump();

      final pauseCallsForB = calls
          .where((c) =>
              c.method == 'pause' &&
              (c.arguments as Map)['playerId'] == 'pause-others-b3')
          .toList();

      expect(pauseCallsForB, isNotEmpty);

      await _teardown(tester, [controllerA, controllerB]);
    });

    testWidgets(
        'is edge-triggered: a state tick while A is already playing does not '
        're-pause B again', (tester) async {
      final (controllerA, controllerB, calls) = await _pumpTwoPlayers(
        tester,
        idA: 'pause-others-a4',
        idB: 'pause-others-b4',
      );

      await _injectState('pause-others-b4', 'playing');
      await tester.pump();

      // First play edge on A: pauses B.
      await _injectState('pause-others-a4', 'playing');
      await tester.pump();

      // B "resumes" for the purposes of this test.
      await _injectState('pause-others-b4', 'playing');
      await tester.pump();

      calls.clear();

      // A emits a position tick (large jump bypasses the 500ms/1000ms
      // throttle) while remaining in the "playing" state — not a play edge.
      await _injectPositionTick('pause-others-a4', 5000);
      await tester.pump();

      final pauseCallsForB = calls
          .where((c) =>
              c.method == 'pause' &&
              (c.arguments as Map)['playerId'] == 'pause-others-b4')
          .toList();

      expect(
        pauseCallsForB,
        isEmpty,
        reason: 'A state tick while already playing must not re-trigger a '
            'pause sweep — only the not-playing -> playing edge does',
      );

      await _teardown(tester, [controllerA, controllerB]);
    });

    testWidgets(
        'a disposed controller is not retained by the coordinator and is never paused',
        (tester) async {
      final (controllerA, controllerB, calls) = await _pumpTwoPlayers(
        tester,
        idA: 'pause-others-a5',
        idB: 'pause-others-b5',
      );

      await _injectState('pause-others-b5', 'playing');
      await tester.pump();

      // Unmount everything (both MediaListPlayer states dispose, which
      // unregisters both controllers) and dispose B explicitly, simulating
      // a host app that owns/disposes the controller independently of the
      // widget lifecycle. Flush pending timers while still mounted first —
      // mirrors media_player_widget_safe_area_test.dart's _cleanUp.
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      controllerB.dispose();
      await tester.pump();

      calls.clear();

      // Re-play A alone; must not crash and must not attempt to pause the
      // disposed/unregistered B.
      await _injectState('pause-others-a5', 'playing');
      await tester.pump();

      final pauseCallsForB = calls
          .where((c) =>
              c.method == 'pause' &&
              (c.arguments as Map)['playerId'] == 'pause-others-b5')
          .toList();

      expect(pauseCallsForB, isEmpty);

      controllerA.dispose();
      await tester.pump();
      _resetHandler();
    });
  });
}
