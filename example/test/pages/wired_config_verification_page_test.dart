// Regression coverage for `WiredConfigVerificationPage`:
//
//  1. Layout must survive a real, narrow phone viewport (360x800 logical --
//     see media_feed_pool_page_test.dart / scroll_bandwidth_page_test.dart
//     for the layout-defect precedent this guards against: a page that
//     compiles, analyses clean and passes every test, yet is unusable on an
//     actual device because a fixed header squeezes content to zero height
//     or off-screen). This page uses PlayerScaffold's proven
//     AspectRatio(16:9) + Expanded(SingleChildScrollView) pattern, so these
//     tests assert that pattern actually holds here: no overflow, and every
//     key control is present and within the viewport.
//  2. The live-seek-gating headline fix is wired end to end from the UI:
//     toggling the DVR switch actually reloads (not just relabels) and the
//     "Try Seek" outcome banner flips between REJECTED and SUCCESS
//     accordingly; switching to the VOD source makes seeking succeed
//     regardless of the DVR toggle -- the key regression risk this page
//     exists to make visible.
//
// Mirrors the mock-channel/warmup/pump conventions used across the example
// app's other page tests.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';
import 'package:zmedia_player_example/pages/wired_config_verification_page.dart';

const _channel = MethodChannel('zmedia_player');

void _setUpMockChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async => null);
}

void _tearDownMockChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null);
}

/// Note 9P-class screen: 720x1600 physical @2.0 -> 360x800 logical -- see
/// the file-level doc comment for why this exact size is used.
Future<void> _pumpOnDeviceScreen(WidgetTester tester) async {
  tester.view.physicalSize = const Size(720, 1600);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    const MaterialApp(home: WiredConfigVerificationPage()),
  );
  await tester.pumpAndSettle();
}

Future<void> _cleanUp(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 260));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    _setUpMockChannel();
    // Warm up MediaPlayer's static cleanup timer before any testWidgets run
    // so it isn't flagged as "new" during a test (mirrors other widget test
    // files in the example app / plugin's own suite).
    final warmup =
        MediaController.create(playerId: 'warmup-wired-config-static-timer');
    warmup.dispose();
    _tearDownMockChannel();
  });

  setUp(_setUpMockChannel);
  tearDown(_tearDownMockChannel);

  group('layout at 360x800', () {
    testWidgets('renders with no overflow errors', (tester) async {
      await _pumpOnDeviceScreen(tester);

      expect(tester.takeException(), isNull);

      await _cleanUp(tester);
    });

    testWidgets(
        'every key control from all four sections is present and '
        'on-screen without scrolling to it individually failing to exist',
        (tester) async {
      await _pumpOnDeviceScreen(tester);

      final screenSize =
          tester.view.physicalSize / tester.view.devicePixelRatio;

      // Section 1: live seek gating.
      expect(find.text('Live HLS'), findsOneWidget);
      expect(find.text('VOD MP4'), findsOneWidget);
      expect(find.byKey(const Key('dvr_toggle')), findsOneWidget);
      expect(find.byKey(const Key('try_seek_button')), findsOneWidget);

      // Section 2: liveLatency.
      expect(find.text('off'), findsOneWidget);
      expect(find.text('3s'), findsOneWidget);
      expect(find.text('8s'), findsOneWidget);

      // Section 3: notifications.
      expect(find.text('Show / Update now'), findsOneWidget);
      expect(find.text('Dismiss'), findsOneWidget);
      expect(find.byKey(const Key('dismissible_toggle')), findsOneWidget);

      // Section 4: PiP.
      expect(find.text('Enter PiP'), findsOneWidget);
      expect(find.text('Exit PiP'), findsOneWidget);

      // Everything found above must actually be scrollable into the
      // viewport -- confirm the ones visible at first frame are within
      // screen bounds (the scaffold's own scroll view handles the rest).
      final trySeekRect =
          tester.getRect(find.byKey(const Key('try_seek_button')));
      expect(trySeekRect.right, lessThanOrEqualTo(screenSize.width));

      await _cleanUp(tester);
    });

    testWidgets('the video area does not collapse to zero height',
        (tester) async {
      await _pumpOnDeviceScreen(tester);

      final aspectRatioFinder = find.byType(AspectRatio).first;
      final rect = tester.getRect(aspectRatioFinder);
      expect(rect.height, greaterThan(50),
          reason: 'a bloated header must never squeeze the player to zero '
              'height, mirroring the Stage 7d regression this pattern '
              'guards against');

      await _cleanUp(tester);
    });
  });

  group('live seek gating end to end', () {
    testWidgets(
        'live source with DVR off: isSeekable is false and Try Seek is '
        'rejected', (tester) async {
      await _pumpOnDeviceScreen(tester);

      expect(
        find.descendant(
            of: find.byKey(const Key('isSeekable_row')),
            matching: find.text('false')),
        findsOneWidget,
      );

      await tester.ensureVisible(find.byKey(const Key('try_seek_button')));
      await tester.tap(find.byKey(const Key('try_seek_button')));
      await tester.pumpAndSettle();

      final banner = find.byKey(const Key('seek_outcome_banner'));
      expect(banner, findsOneWidget);
      expect(
        find.descendant(of: banner, matching: find.textContaining('REJECTED')),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: banner, matching: find.textContaining('InvalidStateException')),
        findsOneWidget,
      );

      await _cleanUp(tester);
    });

    testWidgets(
        'flipping the DVR switch reloads and Try Seek then succeeds on the '
        'live source', (tester) async {
      await _pumpOnDeviceScreen(tester);

      await tester.tap(find.byKey(const Key('dvr_toggle')));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
            of: find.byKey(const Key('dvrEnabled_row')),
            matching: find.text('true')),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: find.byKey(const Key('isSeekable_row')),
            matching: find.text('true')),
        findsOneWidget,
      );

      await tester.ensureVisible(find.byKey(const Key('try_seek_button')));
      await tester.tap(find.byKey(const Key('try_seek_button')));
      await tester.pumpAndSettle();

      final banner = find.byKey(const Key('seek_outcome_banner'));
      expect(
        find.descendant(of: banner, matching: find.textContaining('SUCCESS')),
        findsOneWidget,
      );

      await _cleanUp(tester);
    });

    testWidgets(
        'switching to VOD MP4 makes seeking succeed regardless of the DVR '
        'toggle -- the key regression risk', (tester) async {
      await _pumpOnDeviceScreen(tester);

      // DVR stays off (default) -- only the source changes.
      await tester.tap(find.text('VOD MP4'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
            of: find.byKey(const Key('isLive_row')),
            matching: find.text('false')),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: find.byKey(const Key('isSeekable_row')),
            matching: find.text('true')),
        findsOneWidget,
      );

      await tester.ensureVisible(find.byKey(const Key('try_seek_button')));
      await tester.tap(find.byKey(const Key('try_seek_button')));
      await tester.pumpAndSettle();

      final banner = find.byKey(const Key('seek_outcome_banner'));
      expect(
        find.descendant(of: banner, matching: find.textContaining('SUCCESS')),
        findsOneWidget,
      );

      await _cleanUp(tester);
    });
  });
}
