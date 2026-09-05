// Regression tests for the Stage 7a measurement #4 harness layout defect:
// on a narrow phone (Note 9P-class, 720x1600 @2.0 -> 360x800 logical), the
// `Wrap`-based action-button header grew to 400+dp tall (over half the
// screen), squeezing the feed's `Expanded` ListView down to a sliver and
// pushing the "Auto fling"/"Mark start"/"Mark end" buttons -- the primary,
// repeatable way this measurement is taken -- out of reach at any scroll
// position. See `scroll_bandwidth_page.dart`'s `bottomNavigationBar` doc
// comment for the fix (pinned bottom bar + horizontally-scrolling compact
// rows instead of a `Wrap` header).
//
// Mirrors the mock-channel/warmup conventions used by
// `test/widgets/media_list_player_pause_others_test.dart` in the plugin's
// own test suite.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:zmedia_player/zmedia_player.dart';
import 'package:zmedia_player_example/pages/measurement/scroll_bandwidth_page.dart';
import 'package:zmedia_player_example/widgets/measurement_log_panel.dart';

const _channel = MethodChannel('zmedia_player');

void _setUpMockChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async => null);
}

void _tearDownMockChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null);
}

/// Note 9P-class screen: 720x1600 physical @2.0 -> 360x800 logical. This is
/// deliberately narrow -- the defect this file guards against only shows up
/// once button labels/header content stop fitting on one line.
Future<void> _pumpOnNarrowScreen(WidgetTester tester) async {
  tester.view.physicalSize = const Size(720, 1600);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(const MaterialApp(home: ScrollBandwidthPage()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _cleanUp(WidgetTester tester) async {
  // Each on-screen _ScrollFeedItem creates its own MediaController and calls
  // initialize()/load() in initState, which starts that player's
  // BufferingService.startMonitoring 500ms periodic Timer once load()
  // resolves. That timer keeps invoking the mocked platform buffer-status
  // channel and scheduling a new frame forever -- pumpAndSettle can never
  // observe zero pending frames on this page, for as long as any item stays
  // mounted. Pump a bounded window to flush the async init/load chains'
  // microtasks, then unmount (which disposes every mounted item's
  // MediaController/BufferingService and cancels their timers) before a
  // final short flush.
  await tester.pump(const Duration(milliseconds: 60));
  await tester.pumpWidget(const SizedBox.shrink());
  // MediaListPlayer's own visibility-driven autoplay/pause debounce
  // (Future.delayed(300ms) in media_list_player.dart) can still be pending
  // for an item that changed visibility right before teardown (this test
  // drags the feed, which triggers exactly that) -- 350ms clears it with
  // margin, or flutter_test's "Timer is still pending" invariant trips.
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    _setUpMockChannel();
    // flutter_test fakes Timers via FakeAsync; VisibilityDetector's default
    // 500ms polling Timer would otherwise still be pending at teardown.
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    // Warm up MediaPlayer's static cleanup timer before any testWidgets run
    // so it isn't flagged as "new" during a test (mirrors other widget
    // test files in the plugin's own suite).
    final warmup =
        MediaController.create(playerId: 'warmup-scroll-bw-static-timer');
    warmup.dispose();
    _tearDownMockChannel();
  });

  setUp(_setUpMockChannel);
  tearDown(_tearDownMockChannel);

  group('action bar reachability', () {
    testWidgets(
        'Auto fling / Mark start / Mark end all exist and Auto fling down '
        'is on-screen without scrolling the feed', (tester) async {
      await _pumpOnNarrowScreen(tester);

      final screenSize =
          tester.view.physicalSize / tester.view.devicePixelRatio;

      for (final label in [
        'Auto fling ↓',
        'Auto fling ↑',
        'Mark start',
        'Mark end',
      ]) {
        expect(
          find.text(label, skipOffstage: false),
          findsOneWidget,
          reason: '"$label" must exist in the widget tree',
        );
      }

      // The primary, most-used action must be reachable with zero
      // scrolling (neither the feed nor the action bar itself) on a narrow
      // phone screen -- this is the specific claim the bug report
      // disputed ("could not be brought on screen at any scroll
      // position").
      final autoFlingDown = find.text('Auto fling ↓');
      expect(autoFlingDown, findsOneWidget);
      final rect = tester.getRect(autoFlingDown);
      expect(rect.bottom, lessThanOrEqualTo(screenSize.height));
      expect(rect.right, lessThanOrEqualTo(screenSize.width));

      await _cleanUp(tester);
    });

    testWidgets('action bar stays reachable after scrolling the feed',
        (tester) async {
      await _pumpOnNarrowScreen(tester);

      final listFinder = find.byType(ListView).first;
      await tester.drag(listFinder, const Offset(0, -3000));
      await tester.pump();
      await tester.drag(listFinder, const Offset(0, -3000));
      await tester.pump();

      // The action bar lives in `bottomNavigationBar`, outside the
      // scrollable feed entirely, so it must still be present and on
      // -screen after scrolling the feed as far as it will go.
      final screenSize =
          tester.view.physicalSize / tester.view.devicePixelRatio;
      final autoFlingDown = find.text('Auto fling ↓');
      expect(autoFlingDown, findsOneWidget);
      final rect = tester.getRect(autoFlingDown);
      expect(rect.bottom, lessThanOrEqualTo(screenSize.height));

      await _cleanUp(tester);
    });
  });

  group('item sizing', () {
    testWidgets(
        'a feed item is sized to a fixed 16:9-based height, not a full '
        'screen', (tester) async {
      await _pumpOnNarrowScreen(tester);

      final item0 =
          find.byKey(const ValueKey('scrollbw_item_0'), skipOffstage: false);
      expect(item0, findsOneWidget);
      final rect = tester.getRect(item0);

      // A 16:9 video at ~336dp wide (360 logical width - 24dp padding)
      // plus its label padding is ~205dp. A screen-height item on this
      // fixture would be ~800dp -- assert well below that so a regression
      // that re-introduces unbounded item height is caught immediately.
      expect(rect.height, lessThan(300));
      expect(rect.height, greaterThan(100));

      await _cleanUp(tester);
    });

    testWidgets('the intro card sits at the top of the scroll content',
        (tester) async {
      await _pumpOnNarrowScreen(tester);

      final introCard = find.byType(MeasurementIntroCard);
      expect(introCard, findsOneWidget);
      final item0 =
          find.byKey(const ValueKey('scrollbw_item_0'), skipOffstage: false);
      expect(item0, findsOneWidget);

      final introRect = tester.getRect(introCard);
      final item0Rect = tester.getRect(item0);
      // The intro card must be the first thing in the scroll content --
      // strictly above the first video item -- not floating somewhere
      // mid-screen because a bloated header pushed the whole feed down.
      expect(introRect.top, lessThan(item0Rect.top));

      // And it must start reasonably close to the top of the body (below
      // only the AppBar and the compact counts/knobs header), not deep
      // into the screen.
      expect(introRect.top, lessThan(250));

      await _cleanUp(tester);
    });
  });

  group('Auto fling', () {
    testWidgets(
        'drives a full programmatic sweep across all 50 items and emits '
        'start/end markers', (tester) async {
      await _pumpOnNarrowScreen(tester);

      expect(
        find.byKey(const ValueKey('scrollbw_item_0'), skipOffstage: false),
        findsOneWidget,
      );

      await tester.tap(find.text('Auto fling ↓'));
      await tester.pump();

      expect(
        find.textContaining('start:scroll-bandwidth-50', skipOffstage: false),
        findsOneWidget,
      );

      // Drive the 2500ms `animateTo` sweep to completion in small steps
      // (rather than one large jump) so the ticker actually progresses the
      // scroll animation frame by frame, matching how it runs on a device.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // The 2500ms animateTo has already completed by now (30 x 100ms above
      // == 3000ms), so a couple more bounded pumps are enough for the
      // `finally` block's `end:` marker to render -- not pumpAndSettle,
      // which would hang forever on the mounted items' BufferingService
      // timers (see `_cleanUp` above).
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.textContaining('end:scroll-bandwidth-50', skipOffstage: false),
        findsOneWidget,
      );

      // The last item must now be reachable/built -- confirming the sweep
      // actually traversed toward the end of the list rather than being a
      // no-op.
      expect(
        find.byKey(const ValueKey('scrollbw_item_49'), skipOffstage: false),
        findsOneWidget,
      );

      await _cleanUp(tester);
    });
  });
}
