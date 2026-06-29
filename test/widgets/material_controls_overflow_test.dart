import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

// ---------------------------------------------------------------------------
// Mock channel — identical pattern to controls_semantics_test.dart
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

// Drain timers and dispose controller — same approach as controls_semantics_test.
Future<void> _cleanUp(MediaController controller, WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pumpWidget(const SizedBox.shrink());
  controller.dispose();
  await tester.pump();
}

// ---------------------------------------------------------------------------
// Regression: MaterialMediaControls must not overflow in an inline 16:9 box
//
// Root cause: the main-controls Container used Column + Spacers.  Spacers
// only absorb *positive* free space; when the fixed children (top-bar +
// center 56dp button + bottom-bar + SafeArea insets) exceed the box height
// (≈ 202dp on a 360dp-wide phone), the Column overflows.
//
// Fix: replace the Column+Spacers with a Stack+Positioned overlay so the
// three zones are never additive.  This test must FAIL on the Column build
// and PASS on the Stack build.
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Warm up the static MediaPlayer cleanup timer before any testWidgets run
    // (same technique as controls_semantics_test.dart).
    _setUpMockChannel();
    final warmup = MediaController.create(playerId: 'warmup-overflow-timer');
    warmup.dispose();
    _tearDownMockChannel();
  });

  setUp(_setUpMockChannel);
  tearDown(_tearDownMockChannel);

  group('MaterialMediaControls — RenderFlex overflow regression', () {
    // ------------------------------------------------------------------
    // Case 1: inline 16:9 box (~202dp tall) on a phone-sized screen.
    // With Column+Spacers the children sum to > 202dp → overflow.
    // With Stack+Positioned they overlay and never overflow.
    // ------------------------------------------------------------------
    testWidgets(
      'inline 16:9 AspectRatio on a 360dp-wide phone does not overflow',
      (tester) async {
        // 720×1600 physical @ DPR 2.0 → 360×800 logical dp.
        tester.view.physicalSize = const Size(720, 1600);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final controller =
            MediaController.create(playerId: 'overflow-inline-16x9');

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => MediaQuery(
                  // Simulate a device with notch (top 24dp) and gesture
                  // navigation bar (bottom 48dp) — this makes SafeArea add
                  // significant padding and pushes the Column over the edge.
                  data: MediaQuery.of(context).copyWith(
                    padding: const EdgeInsets.only(top: 24, bottom: 48),
                  ),
                  child: AspectRatio(
                    // 360dp wide → 202.5dp tall: the inline player height
                    aspectRatio: 16 / 9,
                    child: MaterialMediaControls(
                      controller: controller,
                      // Disable navigation-triggering buttons to keep the
                      // test hermetic (no fullscreen push / PiP channels).
                      showFullscreen: false,
                      showPip: false,
                      showSettings: false,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        // Let the fade-in animation complete (300 ms) and all frames settle.
        await tester.pumpAndSettle();

        // A RenderFlex overflow is reported as a FlutterError and surfaces
        // through tester.takeException().  Before the Column→Stack fix this
        // returns a non-null FlutterError; after the fix it must be null.
        expect(tester.takeException(), isNull,
            reason:
                'MaterialMediaControls must not overflow in an inline 16:9 box '
                'on a 360dp-wide phone with top:24/bottom:48 safe-area insets.');

        await _cleanUp(controller, tester);
      },
    );

    // ------------------------------------------------------------------
    // Case 2: fullscreen-height box (700dp tall).  Spacers had room here,
    // so no overflow even before the fix — the Stack path stays clean too.
    // ------------------------------------------------------------------
    testWidgets(
      'fullscreen-height 700dp box does not overflow',
      (tester) async {
        tester.view.physicalSize = const Size(720, 1600);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final controller =
            MediaController.create(playerId: 'overflow-fullscreen-700');

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 700,
                child: MaterialMediaControls(
                  controller: controller,
                  showFullscreen: false,
                  showPip: false,
                  showSettings: false,
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason:
                'MaterialMediaControls must not overflow in a 700dp-tall box '
                '(fullscreen path).');

        await _cleanUp(controller, tester);
      },
    );
  });
}
