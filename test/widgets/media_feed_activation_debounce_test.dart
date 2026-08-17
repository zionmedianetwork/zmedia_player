// Stage 7d (Phase 7) regression tests for [MediaFeed] — F-05: the fling
// debounce that keeps a fast scroll from instantiating a pool slot for every
// item it flies past must be an owned, feed-local timer
// ([MediaFeedConfig.activationDebounce]) rather than an accidental side
// effect of `visibility_detector`'s own global
// `VisibilityDetectorController.instance.updateInterval`. This file proves
// two things: (1) the debounce genuinely holds off `MediaPlayerPool.acquire`
// for an item that never stays visible long enough, and (2) it does so even
// though this package's own test setup zeroes the *global* interval for
// deterministic visibility delivery -- i.e. the protection is MediaFeed's
// own, not inherited.
//
// Mirrors the shared channel/teardown helpers established in
// media_feed_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:zmedia_player/zmedia_player.dart';

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

MediaItem _item(int index) => MediaItem(
      id: 'feed-debounce-item-$index',
      title: 'Item $index',
      url: 'https://cdn.example.com/video-$index.mp4',
    );

Future<void> _teardown(WidgetTester tester, {MediaPlayerPool? pool}) async {
  await tester.pump(const Duration(milliseconds: 60));
  await tester.pumpAndSettle();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 700));
  if (pool != null) {
    await pool.releaseAll();
    await tester.pump();
  }
  _resetHandler();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    final calls = _installCapture();
    final warmup =
        MediaController.create(playerId: 'warmup-feed-debounce-timer');
    warmup.dispose();
    calls.clear();
    _resetHandler();

    // See media_feed_test.dart's setUpAll: this makes visibility_detector
    // deliver onVisibilityChanged callbacks immediately after each pump
    // rather than on its own real ~500ms timer. MediaFeedConfig
    // .activationDebounce is a *separate*, feed-local timer layered on top
    // -- these tests exist specifically to prove that separation holds.
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  group(
      'F-05: activation is debounced independently of the global '
      'visibility_detector interval', () {
    testWidgets(
        'activationDebounce holds off a pool acquire even though the '
        'test-global visibility_detector interval is zero', (tester) async {
      final calls = _installCapture();
      final pool = MediaPlayerPool(maxSize: 2);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: MediaFeed(
                itemCount: 2,
                itemAt: _item,
                pool: pool,
                config: const MediaFeedConfig(
                  autoPlay: false,
                  pauseOthersOnPlay: false,
                  prewarmWindow: 0,
                  activationDebounce: Duration(milliseconds: 200),
                ),
                itemBuilder: (context, state) => SizedBox(
                  key: ValueKey('feed-item-${state.index}'),
                  height: 400,
                  child: state.videoSurface,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();

      expect(
        pool.liveCount,
        0,
        reason: 'even with the global visibility_detector interval at '
            'zero, MediaFeed\'s own activationDebounce must still hold off '
            'the acquire() -- this proves the debounce is genuinely owned '
            'by MediaFeed, not merely inherited from the (test-only, '
            'zeroed) global',
      );

      await tester.pump(const Duration(milliseconds: 210));
      await tester.pump();

      expect(
        pool.liveCount,
        1,
        reason: 'once activationDebounce genuinely elapses while the item '
            'is still visible, the slot must be acquired',
      );

      await _teardown(tester, pool: pool);
      calls.clear();
      _resetHandler();
    });

    testWidgets(
        'a fast fling (each item visible for less than activationDebounce) '
        'never acquires a pool slot for any item it flies past',
        (tester) async {
      final calls = _installCapture();
      final pool = MediaPlayerPool(maxSize: 6);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: MediaFeed(
                itemCount: 10,
                itemAt: _item,
                pool: pool,
                config: const MediaFeedConfig(
                  autoPlay: false,
                  pauseOthersOnPlay: false,
                  prewarmWindow: 0,
                  activationDebounce: Duration(milliseconds: 300),
                ),
                itemBuilder: (context, state) => SizedBox(
                  key: ValueKey('feed-item-${state.index}'),
                  height: 400,
                  child: state.videoSurface,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();

      // Fling: scroll one item-height at a time using only zero-duration
      // pumps between drags -- never enough real (fake-clock) time for any
      // single item's debounce timer to fire before the next crossing
      // cancels it. Mirrors the drag pattern already established in
      // media_feed_test.dart's pool-cap eviction test.
      for (var step = 0; step < 8; step++) {
        await tester.drag(find.byType(ListView), const Offset(0, -400));
        await tester.pump();
        await tester.pump();
      }

      expect(
        pool.liveCount,
        0,
        reason: 'a fling through many items, none of which stayed visible '
            'for activationDebounce, must never acquire a pool slot for '
            'any of them -- this is exactly Measurement 4\'s finding '
            '(only 5 of 50 items instantiated a player during a fast '
            'fling) made an owned, deliberate guarantee instead of an '
            'accidental one',
      );
      expect(
        calls.any((c) => c.method == 'load'),
        isFalse,
      );

      // Let the scroll settle on wherever it landed and wait out the
      // debounce -- the currently-visible item must now activate.
      await tester.pump(const Duration(milliseconds: 320));
      await tester.pump();

      expect(
        pool.liveCount,
        1,
        reason: 'once the scroll genuinely settles for activationDebounce, '
            'the now-visible item must acquire a slot',
      );

      await _teardown(tester, pool: pool);
      calls.clear();
      _resetHandler();
    });

    testWidgets(
        'activationDebounce: Duration.zero restores immediate '
        'activation on every visibility crossing (opt-out, matches every '
        'release before Stage 7d)', (tester) async {
      final calls = _installCapture();
      final pool = MediaPlayerPool(maxSize: 2);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: MediaFeed(
                itemCount: 2,
                itemAt: _item,
                pool: pool,
                config: const MediaFeedConfig(
                  autoPlay: false,
                  pauseOthersOnPlay: false,
                  prewarmWindow: 0,
                  activationDebounce: Duration.zero,
                ),
                itemBuilder: (context, state) => SizedBox(
                  key: ValueKey('feed-item-${state.index}'),
                  height: 400,
                  child: state.videoSurface,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 5));

      expect(
        pool.liveCount,
        1,
        reason: 'Duration.zero must acquire immediately on the very first '
            'crossing, with no settle delay at all',
      );

      await _teardown(tester, pool: pool);
      calls.clear();
      _resetHandler();
    });

    testWidgets(
        'a pending activation timer is cancelled if the item leaves view '
        'again before the debounce elapses, and never acquires a slot',
        (tester) async {
      final calls = _installCapture();
      final pool = MediaPlayerPool(maxSize: 3);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: MediaFeed(
                itemCount: 3,
                itemAt: _item,
                pool: pool,
                config: const MediaFeedConfig(
                  autoPlay: false,
                  pauseOthersOnPlay: false,
                  prewarmWindow: 0,
                  activationDebounce: Duration(milliseconds: 250),
                ),
                itemBuilder: (context, state) => SizedBox(
                  key: ValueKey('feed-item-${state.index}'),
                  height: 400,
                  child: state.videoSurface,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();
      expect(pool.liveCount, 0);

      // Scroll away well before the 250ms debounce for item 0 elapses.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();
      await tester.pump();

      // Wait out well beyond the original debounce window -- if the first
      // timer had NOT been cancelled, it would fire around the 250ms mark
      // and wrongly acquire a slot for the now off-screen item 0.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(
        pool.isActive('feed-debounce-item-0'),
        isFalse,
        reason: 'item 0\'s activation timer must have been cancelled the '
            'moment it left view, not merely outraced -- it must never '
            'acquire a slot after scrolling away',
      );

      await _teardown(tester, pool: pool);
      calls.clear();
      _resetHandler();
    });
  });
}
