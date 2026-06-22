import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

// ---------------------------------------------------------------------------
// Minimal mock for platform channel — prevents MissingPluginException in tests
// ---------------------------------------------------------------------------

void _setUpMockChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('zmedia_player'),
    (MethodCall methodCall) async => null,
  );
}

void _tearDownMockChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('zmedia_player'),
    null,
  );
}

// ---------------------------------------------------------------------------
// Helper to pump MediaControls inside a Material app with a mock controller.
// Returns the controller; callers are responsible for calling
// controller.dispose() and tester.pumpAndSettle() before the test ends
// so that no synthetic timers are left pending.
// ---------------------------------------------------------------------------

Future<MediaController> pumpMediaControls(
  WidgetTester tester, {
  String playerId = 'test-semantics',
}) async {
  final controller = MediaController.create(playerId: playerId);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 640,
          height: 360,
          child: MediaControls(
            controller: controller,
            allowFullscreen: true,
            // showCastButton uses Platform.isIOS; skip cast for tests
            showCastButton: false,
            // PiP only appears when isPipAvailable is true; leave false
            showPipButton: false,
            showSettingsButton: true,
          ),
        ),
      ),
    ),
  );

  // Settle animations so the FadeTransition completes
  await tester.pumpAndSettle();
  return controller;
}

// Drain pending timers then dispose the controller.
// The MediaPlayer keeps a static 5-minute periodic cleanup Timer.  We replace
// the pumped widget with an empty Container first so the widget tree no longer
// holds references, then dispose the controller (which cancels its timers),
// then remove the widget and pump to let the framework verify no timers remain
// *from this widget subtree*.  The static MediaPlayer timer is a shared
// infrastructure timer that exists for the lifetime of the test run — it does
// NOT cause a test failure because we pump the widget away before the
// framework checks.
Future<void> cleanUp(MediaController controller, WidgetTester tester) async {
  // Settle any running animations
  await tester.pumpAndSettle();
  // Replace widget tree with empty to deregister listeners
  await tester.pumpWidget(const SizedBox.shrink());
  // Dispose controller (cancels _controlsTimer and other instance timers)
  controller.dispose();
  // Final pump
  await tester.pump();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // The MediaPlayer class uses a static 5-minute periodic cleanup Timer
    // (created lazily via _ensureCleanupTimer).  Creating and immediately
    // disposing a player here "warms up" the static timer so it exists
    // before any testWidgets run — the test framework only flags timers that
    // are *newly created* during a test, not ones that already existed at
    // test start.
    _setUpMockChannel();
    final warmup = MediaController.create(playerId: 'warmup-static-timer');
    warmup.dispose();
    _tearDownMockChannel();
  });

  setUp(_setUpMockChannel);
  tearDown(_tearDownMockChannel);

  group('MediaControls — Semantics labels', () {
    testWidgets('Play/Pause button has "Play" or "Pause" Semantics label',
        (tester) async {
      final controller =
          await pumpMediaControls(tester, playerId: 'sem-play-pause');

      final semanticsWidgets =
          tester.widgetList<Semantics>(find.byType(Semantics));
      final playPauseNodes = semanticsWidgets
          .where((s) =>
              s.properties.label == 'Play' || s.properties.label == 'Pause')
          .toList();

      expect(
        playPauseNodes,
        isNotEmpty,
        reason: 'A Semantics node labelled "Play" or "Pause" must exist',
      );

      await cleanUp(controller, tester);
    });

    testWidgets('Rewind button has "Rewind 10 seconds" Semantics label',
        (tester) async {
      final controller =
          await pumpMediaControls(tester, playerId: 'sem-rewind');

      final semanticsWidgets =
          tester.widgetList<Semantics>(find.byType(Semantics));
      final rewindNodes = semanticsWidgets
          .where((s) => s.properties.label == 'Rewind 10 seconds')
          .toList();

      expect(
        rewindNodes,
        isNotEmpty,
        reason: 'A Semantics node labelled "Rewind 10 seconds" must exist',
      );

      await cleanUp(controller, tester);
    });

    testWidgets('Forward button has "Forward 10 seconds" Semantics label',
        (tester) async {
      final controller =
          await pumpMediaControls(tester, playerId: 'sem-forward');

      final semanticsWidgets =
          tester.widgetList<Semantics>(find.byType(Semantics));
      final forwardNodes = semanticsWidgets
          .where((s) => s.properties.label == 'Forward 10 seconds')
          .toList();

      expect(
        forwardNodes,
        isNotEmpty,
        reason: 'A Semantics node labelled "Forward 10 seconds" must exist',
      );

      await cleanUp(controller, tester);
    });

    testWidgets('Settings button has "Settings" Semantics label',
        (tester) async {
      final controller =
          await pumpMediaControls(tester, playerId: 'sem-settings');

      final semanticsWidgets =
          tester.widgetList<Semantics>(find.byType(Semantics));
      final settingsNodes = semanticsWidgets
          .where((s) => s.properties.label == 'Settings')
          .toList();

      expect(
        settingsNodes,
        isNotEmpty,
        reason: 'A Semantics node labelled "Settings" must exist',
      );

      await cleanUp(controller, tester);
    });

    testWidgets('Fullscreen button has "Fullscreen" Semantics label',
        (tester) async {
      final controller =
          await pumpMediaControls(tester, playerId: 'sem-fullscreen');

      final semanticsWidgets =
          tester.widgetList<Semantics>(find.byType(Semantics));
      final fullscreenNodes = semanticsWidgets
          .where((s) => s.properties.label == 'Fullscreen')
          .toList();

      expect(
        fullscreenNodes,
        isNotEmpty,
        reason: 'A Semantics node labelled "Fullscreen" must exist',
      );

      await cleanUp(controller, tester);
    });

    testWidgets('Back button has "Exit fullscreen" Semantics label',
        (tester) async {
      final controller =
          await pumpMediaControls(tester, playerId: 'sem-exit-fs');

      final semanticsWidgets =
          tester.widgetList<Semantics>(find.byType(Semantics));
      final exitNodes = semanticsWidgets
          .where((s) => s.properties.label == 'Exit fullscreen')
          .toList();

      expect(
        exitNodes,
        isNotEmpty,
        reason:
            'A Semantics node labelled "Exit fullscreen" must exist on the back button',
      );

      await cleanUp(controller, tester);
    });
  });

  group('MediaControls — minimum button count', () {
    testWidgets('At least 4 Semantics(button: true) nodes are present',
        (tester) async {
      // Expected minimum: play/pause + rewind + forward + settings
      final controller = await pumpMediaControls(tester, playerId: 'sem-count');

      final semanticsWidgets =
          tester.widgetList<Semantics>(find.byType(Semantics));
      final buttonNodes =
          semanticsWidgets.where((s) => s.properties.button == true).toList();

      expect(
        buttonNodes.length,
        greaterThanOrEqualTo(4),
        reason:
            'Must have at least 4 button Semantics nodes: play/pause, rewind, forward, settings or fullscreen',
      );

      await cleanUp(controller, tester);
    });
  });
}
