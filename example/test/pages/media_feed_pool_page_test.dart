// Regression tests for the Stage 7d layout defect on `MediaFeedPoolPage`:
// on a narrow phone (Note 9P-class, 720x1600 @2.0 -> 360x800 logical), the
// segmented-control rows and explanatory paragraphs Stage 7d added directly
// to the page's fixed header grew it tall enough to push the entire feed
// below the fold -- no item was ever visible, so none of Stage 7b-7d's
// behaviour (pool bounding, prewarm, live release, activation debounce,
// network-aware autoplay) could ever be exercised on a device. See
// `media_feed_pool_page.dart`'s class doc comment for the fix (compact
// status bar + settings bottom sheet) and
// `scroll_bandwidth_page_test.dart`, which guards the same failure mode on
// a different page, for the pumped-at-device-size pattern this file
// follows.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:zmedia_player/zmedia_player.dart';
import 'package:zmedia_player_example/pages/media_feed_pool_page.dart';

const _channel = MethodChannel('zmedia_player');

void _setUpMockChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async => null);
}

void _tearDownMockChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null);
}

/// Note 9P-class screen: 720x1600 physical @2.0 -> 360x800 logical -- the
/// exact device configuration the bug report measured this regression on.
Future<void> _pumpOnDeviceScreen(WidgetTester tester) async {
  tester.view.physicalSize = const Size(720, 1600);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(const MaterialApp(home: MediaFeedPoolPage()));
  // Deliberately just enough pumps to let the first frame's layout and
  // VisibilityDetector's post-frame callback settle -- NOT pumpAndSettle,
  // which would run well past MediaFeedConfig's 500ms activationDebounce
  // and start pulling pool-acquire/log-panel machinery into the tree,
  // which is irrelevant to (and would complicate) a first-frame layout
  // assertion.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

Future<void> _cleanUp(WidgetTester tester) async {
  // Mirrors media_feed_test.dart's _teardown sequence: flush the delayed
  // setState cascades MediaFeed/MediaPlayerWidget schedule (activation
  // debounce timers, buffering polling, etc.) before the test ends, or
  // flutter_test's "pending Timer" invariant trips.
  await tester.pump(const Duration(milliseconds: 60));
  await tester.pumpAndSettle();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 260));
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
        MediaController.create(playerId: 'warmup-feed-pool-static-timer');
    warmup.dispose();
    _tearDownMockChannel();
  });

  setUp(_setUpMockChannel);
  tearDown(_tearDownMockChannel);

  group('feed viewport share', () {
    testWidgets(
        'the feed list gets the majority of the viewport height, not a '
        'sliver squeezed out by the header', (tester) async {
      await _pumpOnDeviceScreen(tester);

      final screenSize =
          tester.view.physicalSize / tester.view.devicePixelRatio;

      final listFinder = find.descendant(
        of: find.byType(MediaFeedPoolPage),
        matching: find.byType(ListView),
      );
      // Only the feed's own ListView should exist at first frame -- the
      // event log panel renders a "No events yet." Text instead of a
      // ListView until the pool actually changes (which happens well after
      // the 500ms activationDebounce this page configures by default), and
      // the settings sheet is not open.
      expect(listFinder, findsOneWidget);

      final listRect = tester.getRect(listFinder);
      expect(
        listRect.height,
        greaterThan(screenSize.height / 2),
        reason: 'the feed is the point of this page and must get the '
            'majority of the viewport, not be squeezed below the fold by '
            'header content',
      );

      await _cleanUp(tester);
    });

    testWidgets('at least one feed item is laid out on screen at first '
        'frame', (tester) async {
      await _pumpOnDeviceScreen(tester);

      final screenSize =
          tester.view.physicalSize / tester.view.devicePixelRatio;

      // MediaFeed keys each item's VisibilityDetector as
      // 'media_feed_item_$key', where key defaults to MediaItem.id --
      // 'feed_pool_item_0' for the first item this page's `_itemAt` builds.
      final item0 = find.byKey(
        const ValueKey('media_feed_item_feed_pool_item_0'),
        skipOffstage: false,
      );
      expect(
        item0,
        findsOneWidget,
        reason: 'the first feed item must exist in the tree at first frame',
      );

      final rect = tester.getRect(item0);
      expect(
        rect.top,
        lessThan(screenSize.height),
        reason: 'the first feed item must actually be on screen at first '
            'frame -- this is the specific claim the bug report disputed '
            '("no item is ever visible")',
      );
      expect(rect.bottom, greaterThan(0));

      await _cleanUp(tester);
    });
  });

  group('status bar', () {
    testWidgets(
        'pool count and Auto fling stay visible without opening settings',
        (tester) async {
      await _pumpOnDeviceScreen(tester);

      final screenSize =
          tester.view.physicalSize / tester.view.devicePixelRatio;

      expect(find.textContaining('pool:'), findsOneWidget);
      expect(find.text('Auto fling'), findsOneWidget);

      final autoFling = find.text('Auto fling');
      final rect = tester.getRect(autoFling);
      expect(rect.bottom, lessThanOrEqualTo(screenSize.height));
      expect(rect.right, lessThanOrEqualTo(screenSize.width));

      await _cleanUp(tester);
    });
  });

  group('settings sheet', () {
    testWidgets(
        'the tune icon opens a sheet exposing every Stage 7b-7d control',
        (tester) async {
      await _pumpOnDeviceScreen(tester);

      expect(find.byIcon(Icons.tune), findsOneWidget);
      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();

      expect(find.text('Feed settings'), findsOneWidget);
      expect(find.text('maxPoolSize'), findsOneWidget);
      expect(find.text('prewarm window (±)'), findsOneWidget);
      expect(find.text('activation debounce (F-05)'), findsOneWidget);
      expect(find.text('autoplay policy (F-06)'), findsOneWidget);

      // All four F-05/F-06/pool/prewarm segmented controls are reachable
      // from here -- Stage 7d's behaviours stay exercisable, just relocated.
      expect(find.text('500ms'), findsOneWidget); // activationDebounce
      expect(find.text('Always hold'), findsOneWidget); // autoPlayPolicy

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('Feed settings'), findsNothing);

      await _cleanUp(tester);
    });

    testWidgets('changing activation debounce in the sheet updates the '
        'running feed config', (tester) async {
      await _pumpOnDeviceScreen(tester);

      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();

      await tester.tap(find.text('1000ms'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // The page's own event log records every CONFIG change -- confirms
      // the sheet's control actually reached the page's state, not just its
      // own local mirror.
      expect(
        find.textContaining('CONFIG activationDebounce=1000ms'),
        findsOneWidget,
      );

      await _cleanUp(tester);
    });
  });
}
