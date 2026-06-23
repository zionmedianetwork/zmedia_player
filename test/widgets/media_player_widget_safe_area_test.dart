// Tests for the MediaConfig.respectSafeArea and MediaConfig.immersiveLandscape
// flags as they interact with MediaPlayerWidget.
//
// A full widget pump that reaches _hasNativeView == true is not feasible in
// headless tests because UiKitView/AndroidView cannot be registered without a
// running native platform.  We therefore test three levels:
//
//  1. MediaConfig field values + controller.config propagation — unit tests
//     that confirm the flags are readable via MediaController.config.
//  2. MediaPlayerWidget construction with both flag values — smoke tests that
//     confirm the widget tree builds without error in both modes.
//  3. SafeArea presence in the placeholder branch — when no media is loaded
//     (no native view yet), the placeholder path must not inject a spurious
//     SafeArea regardless of the flag.
//
// The authoritative SafeArea-wraps-native-video behaviour is exercised via the
// MediaConfig round-trip tests in test/core/media_config_test.dart; the
// wrapping logic itself lives in _MediaPlayerWidgetState._buildVideoSurface
// and is straightforward: SafeArea(child: nativeContent) vs nativeContent.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

// ---------------------------------------------------------------------------
// Shared channel mock
// ---------------------------------------------------------------------------

const _channel = MethodChannel('zmedia_player');

void _setUpMockChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (MethodCall call) async => null);
}

void _tearDownMockChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null);
}

// ---------------------------------------------------------------------------
// Helper: pump MediaPlayerWidget with a given config, returns the controller
// ---------------------------------------------------------------------------

Future<MediaController> _pumpPlayerWidget(
  WidgetTester tester, {
  required MediaConfig config,
  String playerId = 'safe-area-test',
}) async {
  final controller = MediaController.create(playerId: playerId, config: config);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 640,
          height: 360,
          child: MediaPlayerWidget(
            controller: controller,
            showControls: false,
          ),
        ),
      ),
    ),
  );

  // Allow initState post-frame callbacks to fire (player initialize call)
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));

  return controller;
}

Future<void> _cleanUp(MediaController controller, WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pumpWidget(const SizedBox.shrink());
  controller.dispose();
  await tester.pump();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Warm up static cleanup timer before any testWidgets run so it is not
    // flagged as "new" during a test.
    _setUpMockChannel();
    final warmup =
        MediaController.create(playerId: 'warmup-safe-area-static-timer');
    warmup.dispose();
    _tearDownMockChannel();
  });

  setUp(_setUpMockChannel);
  tearDown(_tearDownMockChannel);

  // -------------------------------------------------------------------------
  group('MediaConfig flag propagation via MediaController.config', () {
    test('controller.config.respectSafeArea reflects MediaConfig default', () {
      final controller = MediaController.create(playerId: 'rsa-default');
      expect(controller.config.respectSafeArea, false);
      controller.dispose();
    });

    test('controller.config.respectSafeArea reflects true when set', () {
      final controller = MediaController.create(
        playerId: 'rsa-true',
        config: const MediaConfig(respectSafeArea: true),
      );
      expect(controller.config.respectSafeArea, true);
      controller.dispose();
    });

    test('controller.config.immersiveLandscape reflects MediaConfig default',
        () {
      final controller = MediaController.create(playerId: 'il-default');
      expect(controller.config.immersiveLandscape, false);
      controller.dispose();
    });

    test('controller.config.immersiveLandscape reflects true when set', () {
      final controller = MediaController.create(
        playerId: 'il-true',
        config: const MediaConfig(immersiveLandscape: true),
      );
      expect(controller.config.immersiveLandscape, true);
      controller.dispose();
    });

    test('both flags can be true simultaneously via controller', () {
      final controller = MediaController.create(
        playerId: 'both-true',
        config: const MediaConfig(
          respectSafeArea: true,
          immersiveLandscape: true,
        ),
      );
      expect(controller.config.respectSafeArea, true);
      expect(controller.config.immersiveLandscape, true);
      controller.dispose();
    });

    test('other config fields are preserved when new flags are set', () {
      final controller = MediaController.create(
        playerId: 'flags-plus-boxfit',
        config: const MediaConfig(
          boxFit: BoxFit.cover,
          volume: 0.7,
          respectSafeArea: true,
          immersiveLandscape: true,
        ),
      );
      expect(controller.config.boxFit, BoxFit.cover);
      expect(controller.config.volume, 0.7);
      expect(controller.config.respectSafeArea, true);
      expect(controller.config.immersiveLandscape, true);
      controller.dispose();
    });
  });

  // -------------------------------------------------------------------------
  group('MediaPlayerWidget — smoke tests with respectSafeArea', () {
    testWidgets('builds without error when respectSafeArea is false (default)',
        (tester) async {
      final controller = await _pumpPlayerWidget(
        tester,
        config: const MediaConfig(respectSafeArea: false),
        playerId: 'smoke-rsa-false',
      );
      // Widget tree exists
      expect(find.byType(MediaPlayerWidget), findsOneWidget);
      await _cleanUp(controller, tester);
    });

    testWidgets('builds without error when respectSafeArea is true',
        (tester) async {
      final controller = await _pumpPlayerWidget(
        tester,
        config: const MediaConfig(respectSafeArea: true),
        playerId: 'smoke-rsa-true',
      );
      expect(find.byType(MediaPlayerWidget), findsOneWidget);
      await _cleanUp(controller, tester);
    });

    testWidgets(
        'builds without error when immersiveLandscape is false (default)',
        (tester) async {
      final controller = await _pumpPlayerWidget(
        tester,
        config: const MediaConfig(immersiveLandscape: false),
        playerId: 'smoke-il-false',
      );
      expect(find.byType(MediaPlayerWidget), findsOneWidget);
      await _cleanUp(controller, tester);
    });

    testWidgets('builds without error when immersiveLandscape is true',
        (tester) async {
      final controller = await _pumpPlayerWidget(
        tester,
        config: const MediaConfig(immersiveLandscape: true),
        playerId: 'smoke-il-true',
      );
      expect(find.byType(MediaPlayerWidget), findsOneWidget);
      await _cleanUp(controller, tester);
    });

    testWidgets('builds without error when both flags are true',
        (tester) async {
      final controller = await _pumpPlayerWidget(
        tester,
        config: const MediaConfig(
          respectSafeArea: true,
          immersiveLandscape: true,
        ),
        playerId: 'smoke-both-true',
      );
      expect(find.byType(MediaPlayerWidget), findsOneWidget);
      await _cleanUp(controller, tester);
    });
  });

  // -------------------------------------------------------------------------
  // SafeArea presence in the placeholder/no-media branch
  //
  // When no media is loaded (_hasNativeView == false), _buildVideoSurface is
  // NOT on the render path; instead the placeholder is shown.  The SafeArea
  // that guards the native view must NOT appear here regardless of the flag.
  // -------------------------------------------------------------------------
  group('MediaPlayerWidget — SafeArea not injected in placeholder branch', () {
    testWidgets(
        'no extra SafeArea widget in tree when respectSafeArea false and no media',
        (tester) async {
      final controller = await _pumpPlayerWidget(
        tester,
        config: const MediaConfig(respectSafeArea: false),
        playerId: 'no-sa-false',
      );

      // In the placeholder branch there should be no SafeArea at all
      // (the no-media placeholder is a Container with an icon and text).
      expect(find.byType(SafeArea), findsNothing);

      await _cleanUp(controller, tester);
    });

    testWidgets(
        'no extra SafeArea widget in tree when respectSafeArea true and no media',
        (tester) async {
      // Even with the flag true, SafeArea is only injected around the native
      // view — which does not exist in the placeholder branch.
      final controller = await _pumpPlayerWidget(
        tester,
        config: const MediaConfig(respectSafeArea: true),
        playerId: 'no-sa-true',
      );

      // The SafeArea from _buildVideoSurface is gated on _hasNativeView; the
      // placeholder branch does not add a SafeArea.
      expect(find.byType(SafeArea), findsNothing);

      await _cleanUp(controller, tester);
    });
  });

  // -------------------------------------------------------------------------
  // copyWith round-trip: flags survive a copyWith and update correctly
  // -------------------------------------------------------------------------
  group('MediaConfig copyWith — flag round-trips', () {
    test('false → true via copyWith', () {
      const original = MediaConfig();
      expect(original.respectSafeArea, false);
      expect(original.immersiveLandscape, false);

      final updated = original.copyWith(
        respectSafeArea: true,
        immersiveLandscape: true,
      );
      expect(updated.respectSafeArea, true);
      expect(updated.immersiveLandscape, true);
    });

    test('true → false via copyWith', () {
      const original =
          MediaConfig(respectSafeArea: true, immersiveLandscape: true);
      final updated = original.copyWith(
        respectSafeArea: false,
        immersiveLandscape: false,
      );
      expect(updated.respectSafeArea, false);
      expect(updated.immersiveLandscape, false);
    });

    test('copyWith with no args preserves flag values', () {
      const original =
          MediaConfig(respectSafeArea: true, immersiveLandscape: true);
      final copy = original.copyWith();
      expect(copy.respectSafeArea, true);
      expect(copy.immersiveLandscape, true);
    });

    test('updating only respectSafeArea leaves immersiveLandscape intact', () {
      const original =
          MediaConfig(respectSafeArea: false, immersiveLandscape: true);
      final updated = original.copyWith(respectSafeArea: true);
      expect(updated.respectSafeArea, true);
      expect(updated.immersiveLandscape, true); // unchanged
    });

    test('updating only immersiveLandscape leaves respectSafeArea intact', () {
      const original =
          MediaConfig(respectSafeArea: true, immersiveLandscape: false);
      final updated = original.copyWith(immersiveLandscape: true);
      expect(updated.respectSafeArea, true); // unchanged
      expect(updated.immersiveLandscape, true);
    });
  });
}
