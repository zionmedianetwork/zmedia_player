// Regression tests for the Stage 7a measurement #5 harness layout review
// requested alongside the measurement #4 fix (same conventions, same
// harness). Unlike measurement #4, this page's scrollable body was already
// a plain, fully-scrollable `ListView` with no `Wrap`-squeeze defect --
// but "Start hold" sat close enough to the bottom edge of the initial
// viewport (on a Note 9P-class 360x800 logical screen) that real-device
// safe-area insets or font scale could plausibly push it out of reach.
// The hold/force-play controls now live in a pinned `bottomNavigationBar`,
// matching the convention applied to measurement #4, so they are reachable
// regardless of scroll position or those device-specific variables.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:zmedia_player/zmedia_player.dart';
import 'package:zmedia_player_example/pages/measurement/live_offscreen_bandwidth_page.dart';

const _channel = MethodChannel('zmedia_player');

void _setUpMockChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async => null);
}

void _tearDownMockChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null);
}

Future<void> _pumpOnNarrowScreen(WidgetTester tester) async {
  tester.view.physicalSize = const Size(720, 1600);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(const MaterialApp(home: LiveOffscreenBandwidthPage()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _cleanUp(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    _setUpMockChannel();
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    final warmup = MediaController.create(
      playerId: 'warmup-live-offscreen-static-timer',
    );
    warmup.dispose();
    _tearDownMockChannel();
  });

  setUp(_setUpMockChannel);
  tearDown(_tearDownMockChannel);

  group('hold controls reachability', () {
    testWidgets(
        'Start hold / End hold / Force pause / Force play all exist and '
        'are on-screen without scrolling', (tester) async {
      await _pumpOnNarrowScreen(tester);

      final screenSize =
          tester.view.physicalSize / tester.view.devicePixelRatio;

      for (final label in [
        'Start hold',
        'End hold',
        'Force pause',
        'Force play',
      ]) {
        final finder = find.text(label, skipOffstage: false);
        expect(finder, findsOneWidget, reason: '"$label" must exist');
        final rect = tester.getRect(finder);
        expect(
          rect.bottom,
          lessThanOrEqualTo(screenSize.height),
          reason: '"$label" must be on-screen without any scrolling, since '
              'it lives in the pinned bottomNavigationBar',
        );
      }

      await _cleanUp(tester);
    });

    testWidgets(
        'hold controls stay reachable after scrolling the body ListView '
        'to the bottom', (tester) async {
      await _pumpOnNarrowScreen(tester);

      final listFinder = find.byType(ListView).first;
      await tester.drag(listFinder, const Offset(0, -5000));
      await tester.pump();
      await tester.drag(listFinder, const Offset(0, -5000));
      await tester.pump();

      final screenSize =
          tester.view.physicalSize / tester.view.devicePixelRatio;
      final startHold = find.text('Start hold');
      expect(startHold, findsOneWidget);
      final rect = tester.getRect(startHold);
      expect(rect.bottom, lessThanOrEqualTo(screenSize.height));

      await _cleanUp(tester);
    });
  });

  group('body scroll', () {
    testWidgets('the body ListView is actually scrollable', (tester) async {
      await _pumpOnNarrowScreen(tester);

      final listFinder = find.byType(ListView).first;
      final scrollableState = tester.state<ScrollableState>(
        find.descendant(
          of: listFinder,
          matching: find.byType(Scrollable),
        ),
      );
      final before = scrollableState.position.pixels;

      await tester.drag(listFinder, const Offset(0, -600));
      await tester.pump();

      final after = scrollableState.position.pixels;
      expect(
        after,
        greaterThan(before),
        reason: 'dragging the body ListView must actually move its scroll '
            'position',
      );

      await _cleanUp(tester);
    });
  });
}
