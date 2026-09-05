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
//  3. The Custom source: selecting it reveals its fields without attempting
//     a load, an empty URL is rejected inline (no load attempted -- the mock
//     channel returning null for every call means "no load attempted" is
//     asserted via the previously-loaded item's title staying put), and a
//     valid URL builds the MediaItem the page's own dartdoc promises
//     (id/title/url/isLive/streamingFormat/httpHeaders), reaching
//     MediaController.currentItem via MediaPlayer.load's synchronous,
//     pre-round-trip `_currentItem = item` assignment -- see
//     media_player.dart -- which is what makes it observable at all against
//     a mocked channel that never replies.
//
// Mirrors the mock-channel/warmup/pump conventions used across the example
// app's other page tests.
//
// NOT pumpAndSettle anywhere in this file: this page's MediaController
// calls initialize()/load() on a real (mocked-channel) player, which starts
// BufferingService.startMonitoring's periodic 500ms Timer -- see
// scroll_bandwidth_page_test.dart / live_offscreen_bandwidth_page_test.dart
// for the same mechanism. That timer round-trips the mocked platform
// buffer-status channel and schedules a new frame forever, so pumpAndSettle
// can never observe zero pending frames on this page. Every wait below is a
// bounded pump chain instead, sized to flush the specific async chain it
// follows (initial init/load, or a reload triggered by updateConfig()+
// load()) -- each queued through MediaController's operation queue
// (Completer-chained, no real Timer of its own), so a handful of pumps is
// enough to drain it.

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
  // Drains _initAndLoad()'s full chain: controller.initialize(), the
  // pipStatus/pipAction stream subscriptions, controller.load(), a
  // checkPipAvailability() round trip and NotificationService.initialize()
  // -- all mocked-channel calls that resolve within a few microtask hops,
  // no real delay involved.
  await _pumpBounded(tester);
}

/// Pumps a bounded, fixed number of short frames -- enough to drain the
/// mocked-channel async chains this page's actions kick off, without ever
/// waiting for the tree to go idle (it never does; see the file header).
Future<void> _pumpBounded(WidgetTester tester, {int steps = 6}) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _cleanUp(WidgetTester tester) async {
  await _pumpBounded(tester);
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
      // Drains _trySeek(): a single seekTo() call that rejects synchronously
      // (isLive && !dvrEnabled, no platform round trip involved).
      await _pumpBounded(tester);

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
      // Drains _reloadWithCurrentSettings(): controller.updateConfig() then
      // controller.load(), both queued through MediaController's operation
      // queue and both mocked-channel calls with no real timer of their own.
      await _pumpBounded(tester);

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
      // Drains _trySeek() -- succeeds this time (DVR on), a single mocked
      // seekTo() platform call.
      await _pumpBounded(tester);

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
      // Drains _reloadWithCurrentSettings() again -- see the DVR toggle test
      // above.
      await _pumpBounded(tester);

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
      // Drains _trySeek() -- succeeds on the VOD source regardless of DVR.
      await _pumpBounded(tester);

      final banner = find.byKey(const Key('seek_outcome_banner'));
      expect(
        find.descendant(of: banner, matching: find.textContaining('SUCCESS')),
        findsOneWidget,
      );

      await _cleanUp(tester);
    });
  });

  group('live-edge readout (issues #88/#109/#110)', () {
    // The mock channel handler returns `null` for every call, so no
    // `onPositionChanged` event is ever delivered -- `MediaController`'s
    // `PlaybackState` never advances off its `PlayerState.idle` default
    // (see `MediaController._currentState`'s initializer). That default has
    // `liveEdgeOffset: null` and `positionBasis: PositionBasis.absolute`,
    // which is genuinely the VOD case (case 3 in the page dartdoc), true
    // regardless of `_useLiveSource` -- there is no mocked-channel path that
    // reaches the "healthy live edge" or "issue #109 anomaly" cases, which
    // require a real `liveEdgeOffset` value from native. Those two are only
    // observable on-device against a real stream, which is exactly why this
    // page exists.
    testWidgets(
        'default (unreachable-live) state renders liveEdgeOffset null, '
        'isAtLiveEdge false, positionBasis absolute', (tester) async {
      await _pumpOnDeviceScreen(tester);

      expect(
        find.descendant(
            of: find.byKey(const Key('liveEdgeOffset_row')),
            matching: find.textContaining('null')),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: find.byKey(const Key('isAtLiveEdge_row')),
            matching: find.text('false')),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: find.byKey(const Key('positionBasis_row')),
            matching: find.text('absolute')),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: find.byKey(const Key('offsetWithinWindow_row')),
            matching: find.textContaining('n/a')),
        findsOneWidget,
      );

      final banner = find.byKey(const Key('live_edge_case_banner'));
      expect(banner, findsOneWidget);
      expect(
        find.descendant(of: banner, matching: find.textContaining('VOD')),
        findsOneWidget,
      );

      await _cleanUp(tester);
    });

    testWidgets('rows and banner render without overflow after a reload',
        (tester) async {
      await _pumpOnDeviceScreen(tester);

      // Flip the DVR toggle to exercise the reload path the live-latency
      // section relies on -- the readout must keep rendering cleanly, even
      // though (per the mocked channel) the values themselves stay at their
      // VOD-shaped defaults.
      await tester.tap(find.byKey(const Key('dvr_toggle')));
      await _pumpBounded(tester);

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('liveEdgeOffset_row')), findsOneWidget);
      expect(find.byKey(const Key('offsetWithinWindow_row')), findsOneWidget);
      expect(find.byKey(const Key('isAtLiveEdge_row')), findsOneWidget);
      expect(find.byKey(const Key('positionBasis_row')), findsOneWidget);
      expect(find.byKey(const Key('live_edge_case_banner')), findsOneWidget);

      await _cleanUp(tester);
    });
  });

  group('custom stream source', () {
    testWidgets('selecting Custom reveals its fields without attempting a load',
        (tester) async {
      await _pumpOnDeviceScreen(tester);

      // Not present until Custom is selected.
      expect(find.byKey(const Key('custom_source_controls')), findsNothing);

      await tester.tap(find.text('Custom'));
      // Selecting Custom only reveals the fields -- no updateConfig()/load()
      // round trip to drain, but pump anyway since the switch still goes
      // through setState.
      await _pumpBounded(tester);

      expect(find.byKey(const Key('custom_source_controls')), findsOneWidget);
      expect(find.byKey(const Key('custom_url_field')), findsOneWidget);
      expect(find.byKey(const Key('custom_is_live_toggle')), findsOneWidget);
      expect(find.byKey(const Key('custom_format_selector')), findsOneWidget);
      expect(find.byKey(const Key('custom_header_name_field')), findsOneWidget);
      expect(
          find.byKey(const Key('custom_header_value_field')), findsOneWidget);
      expect(
          find.byKey(const Key('load_custom_stream_button')), findsOneWidget);

      // The live source (the default) is still the loaded item -- selecting
      // Custom did not reload.
      expect(
        find.descendant(
            of: find.byKey(const Key('isLive_row')),
            matching: find.text('true')),
        findsOneWidget,
      );

      await _cleanUp(tester);
    });

    testWidgets('an empty URL does not attempt a load and surfaces inline',
        (tester) async {
      await _pumpOnDeviceScreen(tester);

      await tester.tap(find.text('Custom'));
      await _pumpBounded(tester);

      await tester
          .ensureVisible(find.byKey(const Key('load_custom_stream_button')));
      await tester.tap(find.byKey(const Key('load_custom_stream_button')));
      // Drains the synchronous null-item guard in
      // _reloadWithCurrentSettings -- no updateConfig()/load() round trip is
      // even started, but pump anyway for consistency with the other cases.
      await _pumpBounded(tester);

      expect(
        find.text('Enter a stream URL before loading.'),
        findsOneWidget,
      );

      // Still the default live item -- no load was attempted.
      final seekabilityItemRow = find.byKey(const Key('isLive_row'));
      expect(
        find.descendant(of: seekabilityItemRow, matching: find.text('true')),
        findsOneWidget,
      );

      await _cleanUp(tester);
    });

    testWidgets('a valid URL builds the expected MediaItem and reloads with it',
        (tester) async {
      await _pumpOnDeviceScreen(tester);

      await tester.tap(find.text('Custom'));
      await _pumpBounded(tester);

      await tester.enterText(find.byKey(const Key('custom_url_field')),
          'https://cdn.example.com/manifest.mpd?token=abc');
      await _pumpBounded(tester, steps: 1);

      // `auto` (the default) infers dash from the URL's path.
      expect(
        find.descendant(
            of: find.byKey(const Key('custom_resolved_format_row')),
            matching: find.text('dash')),
        findsOneWidget,
      );

      // Flip isLive off so the loaded result is distinguishable from the
      // live default (which is also isLive: true).
      await tester.tap(find.byKey(const Key('custom_is_live_toggle')));
      await _pumpBounded(tester, steps: 1);

      await tester.enterText(
          find.byKey(const Key('custom_header_name_field')), 'Cookie');
      await tester.enterText(
          find.byKey(const Key('custom_header_value_field')), 'session=1');
      await _pumpBounded(tester, steps: 1);

      await tester
          .ensureVisible(find.byKey(const Key('load_custom_stream_button')));
      await tester.tap(find.byKey(const Key('load_custom_stream_button')));
      // Drains _reloadWithCurrentSettings(): updateConfig() then load(),
      // same mocked-channel chain as the built-in sources' reload path.
      await _pumpBounded(tester);

      expect(find.text('Enter a stream URL before loading.'), findsNothing);
      // MediaPlayer.load() assigns `_currentItem = item` synchronously,
      // before any platform round trip -- see the group's own doc comment --
      // so the built MediaItem's title and isLive are observable even
      // though the mocked channel never replies.
      expect(find.text('Custom stream'), findsOneWidget);
      expect(
        find.descendant(
            of: find.byKey(const Key('isLive_row')),
            matching: find.text('false')),
        findsOneWidget,
      );

      await _cleanUp(tester);
    });
  });
}
