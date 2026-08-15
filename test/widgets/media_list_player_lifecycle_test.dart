// Regression tests for B-09 / M-11 (Phase 4 widget-layer remediation, see
// docs/implementation/production-gate-assessment.md).
//
// B-09: A feed accumulated one live decoder per item ever scrolled past, not
// per item currently visible, because of two compounding defects:
//
//   1. `MediaListPlayer`'s hand-rolled `VisibilityDetector` used
//      `NotificationListener<ScrollNotification>` as a *descendant* of the
//      enclosing `Scrollable`. Flutter dispatches scroll notifications
//      *upward* from the dispatching context, so a listener below the
//      `Scrollable` in the tree structurally can never receive them --
//      `_onBecameInvisible()` (which calls `pause()`) never ran on scroll.
//   2. `MediaPlayerWidget` hardcoded `wantKeepAlive => true`, so every
//      item's State (and its native decoder/platform view) was kept alive
//      by `AutomaticKeepAliveClientMixin` forever once mounted, regardless
//      of how far it scrolled out of view.
//
// This file exercises the fix for both, plus the new `maxConcurrentPlayers`
// policy cap, entirely through the public `MediaListPlayer` +
// `MediaController` surface -- mirroring
// test/widgets/media_list_player_pause_others_test.dart's approach of
// injecting native onStateChanged events and capturing outgoing
// MethodChannel calls rather than reaching into the private
// `_MediaListPlaybackCoordinator`.
//
// The scroll test (`scrolling a MediaListPlayer item out of view pauses
// it...`) is the key deliverable: it is written so that it FAILS against the
// pre-fix `NotificationListener<ScrollNotification>` implementation and
// PASSES against the `visibility_detector`-package-backed implementation.
// This was verified manually by temporarily reverting
// lib/src/widgets/media_list_player.dart's `build()`/VisibilityDetector to
// the pre-fix implementation, confirming this test fails with a clear
// assertion failure (not a compile error), then restoring the fix and
// confirming it passes again -- see the Phase 4 handoff report for the
// verbatim before/after `flutter test` output.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:zmedia_player/zmedia_player.dart';

// ---------------------------------------------------------------------------
// Shared channel helpers (mirrors media_list_player_pause_others_test.dart)
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

List<MethodCall> _pauseCallsFor(List<MethodCall> calls, String playerId) =>
    calls
        .where((c) =>
            c.method == 'pause' && (c.arguments as Map)['playerId'] == playerId)
        .toList();

Future<void> _teardown(
  WidgetTester tester,
  List<MediaController> controllers,
) async {
  // Flush pending timers while the widget tree is still mounted. Every
  // MediaPlayerWidget mount schedules a didChangeDependencies -> 50ms ->
  // refreshVideoSurface -> 100ms delayed setState cascade (pre-existing
  // behavior, unrelated to this file's changes); this test file mounts and
  // remounts several MediaPlayerWidgets (ListView.builder rebuilding items,
  // MediaListPlayer's wantKeepAlive: false disposing/recreating State as
  // items scroll in and out, the two-stage cap harness), each starting its
  // own cascade. `pumpAndSettle()` alone was not always sufficient to drain
  // all of them here, so explicitly elapse real time both before and after
  // unmounting to guarantee every pending Timer actually fires (as a no-op,
  // once `mounted` is false) before the test ends -- flutter_test asserts
  // no Timer is left pending when a test completes.
  await tester.pump(const Duration(milliseconds: 60));
  await tester.pumpAndSettle();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 260));
  for (final c in controllers) {
    c.dispose();
  }
  await tester.pump();
  _resetHandler();
}

// ---------------------------------------------------------------------------
// Two-stage harness for the concurrency-cap test: item B is not in the tree
// until `revealB()` is called, so item A can be established as visible +
// playing strictly before B becomes visible.
// ---------------------------------------------------------------------------

class _CapHarness extends StatefulWidget {
  final MediaController a;
  final MediaController b;

  const _CapHarness({super.key, required this.a, required this.b});

  @override
  State<_CapHarness> createState() => _CapHarnessState();
}

class _CapHarnessState extends State<_CapHarness> {
  bool showB = false;

  void revealB() => setState(() => showB = true);

  static const _config = MediaListPlayerConfig(
    autoPlay: false,
    autoPause: false,
    pauseOthersOnPlay: false, // isolate the maxConcurrentPlayers path
    maxConcurrentPlayers: 1,
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            SizedBox(
              width: 320,
              height: 200,
              child: MediaListPlayer(
                controller: widget.a,
                showControls: false,
                config: _config,
              ),
            ),
            if (showB)
              SizedBox(
                width: 320,
                height: 200,
                child: MediaListPlayer(
                  controller: widget.b,
                  showControls: false,
                  config: _config,
                ),
              ),
          ],
        ),
      ),
    );
  }
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
        MediaController.create(playerId: 'warmup-list-lifecycle-static-timer');
    warmup.dispose();
    calls.clear();
    _resetHandler();

    // MediaListPlayer's VisibilityDetector defaults to a real 500ms Timer
    // between visibility checks. flutter_test fakes Timers via FakeAsync, so
    // that Timer would still be pending (never fired) after a test tears its
    // widget tree down with only a couple of `tester.pump()` calls, tripping
    // flutter_test's "Timer is still pending" invariant. Duration.zero makes
    // the package fire via addPostFrameCallback instead of a Timer -- the
    // setting the package's own docs recommend for automated tests, and
    // also gives deterministic, immediate visibility callbacks after each
    // pump instead of a real 500ms wait.
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  group('B-09: scroll-driven visibility pauses off-screen players', () {
    testWidgets(
        'scrolling a MediaListPlayer item out of view pauses it via '
        'genuine, scroll-driven visibility detection', (tester) async {
      final calls = _installCapture();

      final controllers = List<MediaController>.generate(
        6,
        (i) => MediaController.create(playerId: 'scroll-item-$i'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 600,
              child: ListView.builder(
                itemCount: controllers.length,
                itemBuilder: (context, index) => SizedBox(
                  key: ValueKey('scroll-item-box-$index'),
                  height: 400,
                  child: MediaListPlayer(
                    controller: controllers[index],
                    showControls: false,
                    config: const MediaListPlayerConfig(
                      autoPlay: false,
                      autoPause: true,
                      // Isolate the visibility-driven pause path from the
                      // separate maxConcurrentPlayers policy (covered by
                      // its own test below).
                      pauseOthersOnPlay: false,
                      maxConcurrentPlayers: 10,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();

      // Item 0 (400px tall) is fully on-screen at the top of the 600px
      // viewport; mark it playing.
      await _injectState('scroll-item-0', 'playing');
      await tester.pump();
      expect(controllers[0].isPlaying, isTrue);

      calls.clear();

      // Scroll far enough (list is only 6 * 400 = 2400px tall, viewport is
      // 600px, so the max scroll offset is 1800px) that item 0 is fully
      // outside the viewport.
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pump();
      await tester.pump();

      expect(
        _pauseCallsFor(calls, 'scroll-item-0'),
        isNotEmpty,
        reason:
            'scrolling item 0 off-screen must pause it via genuine visibility '
            'detection. A NotificationListener<ScrollNotification> placed as '
            'a *descendant* of the ListView\'s Scrollable can never observe '
            'this scroll (notifications only bubble upward), which is '
            'exactly the pre-fix defect this test is written to catch.',
      );

      await _teardown(tester, controllers);
    });

    testWidgets(
        'scrolling a MediaListPlayer item back into view resumes autoPlay',
        (tester) async {
      final calls = _installCapture();

      final controllers = List<MediaController>.generate(
        6,
        (i) => MediaController.create(playerId: 'scroll-back-item-$i'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 600,
              child: ListView.builder(
                itemCount: controllers.length,
                itemBuilder: (context, index) => SizedBox(
                  key: ValueKey('scroll-back-item-box-$index'),
                  height: 400,
                  child: MediaListPlayer(
                    controller: controllers[index],
                    showControls: false,
                    config: const MediaListPlayerConfig(
                      autoPlay: true,
                      autoPause: true,
                      pauseOthersOnPlay: false,
                      maxConcurrentPlayers: 10,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      // autoPlay's own 300ms delay (see MediaListPlayer._onBecameVisible)
      // before it calls controller.play() for the initially-visible item 0.
      await tester.pump(const Duration(milliseconds: 350));

      expect(
        calls.where((c) =>
            c.method == 'play' &&
            (c.arguments as Map)['playerId'] == 'scroll-back-item-0'),
        isNotEmpty,
        reason: 'item 0 autoPlays on initial mount (sanity check)',
      );

      await _injectState('scroll-back-item-0', 'playing');
      await tester.pump();

      calls.clear();

      // Scroll item 0 (400px tall) fully out of the 600px viewport.
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pump();
      await tester.pump();
      expect(
        _pauseCallsFor(calls, 'scroll-back-item-0'),
        isNotEmpty,
        reason: 'scrolling item 0 off-screen pauses it',
      );

      calls.clear();

      // Scroll item 0 back into view. Because wantKeepAlive is now false
      // (see MediaPlayerWidget.wantKeepAlive), the far-scrolled-away item's
      // State was disposed while off-screen, so scrolling back creates a
      // *fresh* MediaListPlayer State (`_hasPlayedOnce` reset to false) that
      // autoPlays again via the same 300ms-delayed path as the initial
      // mount -- not the alternate "resume if paused" branch.
      await tester.drag(find.byType(ListView), const Offset(0, 2000));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      final resumePlayCalls = calls
          .where((c) =>
              c.method == 'play' &&
              (c.arguments as Map)['playerId'] == 'scroll-back-item-0')
          .toList();
      expect(
        resumePlayCalls,
        isNotEmpty,
        reason: 'scrolling item 0 back into view must autoPlay it again',
      );

      await _teardown(tester, controllers);
    });
  });

  group('wantKeepAlive default', () {
    testWidgets(
        'MediaListPlayer disables wantKeepAlive on its inner '
        'MediaPlayerWidget; a standalone MediaPlayerWidget still defaults '
        'to true', (tester) async {
      final calls = _installCapture();
      final controller =
          MediaController.create(playerId: 'keep-alive-list-check');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaListPlayer(
              controller: controller,
              showControls: false,
              config: const MediaListPlayerConfig(
                autoPlay: false,
                autoPause: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final innerWidget =
          tester.widget<MediaPlayerWidget>(find.byType(MediaPlayerWidget));
      expect(
        innerWidget.wantKeepAlive,
        isFalse,
        reason:
            'MediaListPlayer must not keep every scrolled-past item\'s State '
            '(and its native decoder/platform view) alive forever -- that is '
            'exactly what caused the live decoder count to track every item '
            'ever scrolled past instead of only the currently-visible ones.',
      );

      // A standalone MediaPlayerWidget (not hosted by MediaListPlayer)
      // still defaults to keeping its State alive, preserving prior
      // behavior for single-player usage (e.g. a video embedded in a
      // scrollable article).
      final standaloneController =
          MediaController.create(playerId: 'keep-alive-standalone-check');
      addTearDown(standaloneController.dispose);
      final standalone = MediaPlayerWidget(controller: standaloneController);
      expect(standalone.wantKeepAlive, isTrue);

      await _teardown(tester, [controller]);
      calls.clear();
    });
  });

  group('maxConcurrentPlayers policy cap', () {
    testWidgets(
        'exceeding the live cap pauses the least-recently-visible player, '
        'independent of pauseOthersOnPlay', (tester) async {
      final calls = _installCapture();

      final controllerA = MediaController.create(playerId: 'cap-item-a');
      final controllerB = MediaController.create(playerId: 'cap-item-b');

      final harnessKey = GlobalKey<_CapHarnessState>();

      await tester.pumpWidget(
        _CapHarness(key: harnessKey, a: controllerA, b: controllerB),
      );
      await tester.pump();
      await tester.pump();

      // A is visible (live set: [A]) and playing. B is not mounted yet.
      await _injectState('cap-item-a', 'playing');
      await tester.pump();
      expect(controllerA.isPlaying, isTrue);

      calls.clear();

      // Reveal B. Both are visible together, but maxConcurrentPlayers: 1
      // means B's arrival must evict (pause) the least-recently-visible
      // player, A -- even though pauseOthersOnPlay is false and B itself
      // never plays.
      harnessKey.currentState!.revealB();
      await tester.pump();
      await tester.pump();

      expect(
        _pauseCallsFor(calls, 'cap-item-a'),
        isNotEmpty,
        reason:
            'maxConcurrentPlayers: 1 must pause A once B pushes the live set '
            'over the cap, independent of pauseOthersOnPlay (disabled here) '
            'and regardless of whether B itself is playing.',
      );

      await _teardown(tester, [controllerA, controllerB]);
    });

    testWidgets('maxConcurrentPlayers <= 0 disables the cap', (tester) async {
      final calls = _installCapture();

      final controllerA =
          MediaController.create(playerId: 'cap-disabled-item-a');
      final controllerB =
          MediaController.create(playerId: 'cap-disabled-item-b');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(
                  width: 320,
                  height: 200,
                  child: MediaListPlayer(
                    controller: controllerA,
                    showControls: false,
                    config: const MediaListPlayerConfig(
                      autoPlay: false,
                      autoPause: false,
                      pauseOthersOnPlay: false,
                      maxConcurrentPlayers: 0,
                    ),
                  ),
                ),
                SizedBox(
                  width: 320,
                  height: 200,
                  child: MediaListPlayer(
                    controller: controllerB,
                    showControls: false,
                    config: const MediaListPlayerConfig(
                      autoPlay: false,
                      autoPause: false,
                      pauseOthersOnPlay: false,
                      maxConcurrentPlayers: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      await _injectState('cap-disabled-item-a', 'playing');
      await tester.pump();
      calls.clear();

      await _injectState('cap-disabled-item-b', 'playing');
      await tester.pump();

      expect(
        _pauseCallsFor(calls, 'cap-disabled-item-a'),
        isEmpty,
        reason: 'maxConcurrentPlayers: 0 must disable the cap entirely',
      );

      await _teardown(tester, [controllerA, controllerB]);
    });
  });
}
