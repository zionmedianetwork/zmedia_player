// Stage 7b (Phase 7) regression tests for [MediaFeed] — the package-owned
// feed widget that fixes F-02 (the package could not previously pool
// controllers by API shape: MediaListPlayer takes a host-owned
// MediaController) by owning a bounded MediaPlayerPool internally and
// handing hosts read-only MediaFeedItemState + callbacks instead of raw
// controllers.
//
// Mirrors the established pattern in test/widgets/media_list_player_*_test.dart:
// mock the MethodChannel, inject native events, and drive genuine
// visibility_detector-based visibility via a real scrollable widget tree.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:zmedia_player/zmedia_player.dart';

// ---------------------------------------------------------------------------
// Shared channel helpers (mirrors media_list_player_lifecycle_test.dart)
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

String? _playerIdOf(MethodCall call) =>
    (call.arguments as Map?)?['playerId'] as String?;

MediaItem _item(int index) => MediaItem(
      id: 'feed-item-$index',
      title: 'Item $index',
      url: 'https://cdn.example.com/video-$index.mp4',
    );

Future<void> _teardown(WidgetTester tester, {MediaPlayerPool? pool}) async {
  // See media_list_player_lifecycle_test.dart's _teardown for why this
  // sequence is needed: MediaPlayerWidget schedules several delayed
  // setState cascades that must be flushed before the test ends, or
  // flutter_test's "pending Timer" invariant trips.
  await tester.pump(const Duration(milliseconds: 60));
  await tester.pumpAndSettle();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 260));
  if (pool != null) {
    // Disposing releases every live controller, which in turn cancels its
    // BufferingService's periodic polling timer (started by play()) --
    // must happen, with a settling pump afterwards, before the test ends
    // or flutter_test's "pending Timer" invariant trips.
    await pool.releaseAll();
    await tester.pump();
  }
  _resetHandler();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    final calls = _installCapture();
    final warmup = MediaController.create(playerId: 'warmup-feed-static-timer');
    warmup.dispose();
    calls.clear();
    _resetHandler();

    // Deterministic, immediate visibility callbacks after each pump instead
    // of a real 500ms Timer — see media_list_player_lifecycle_test.dart's
    // setUpAll for the same rationale.
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  group('F-02 fix: MediaFeed owns controllers via a bounded pool', () {
    testWidgets(
        'an item that scrolls into view acquires a pool slot and its '
        'itemBuilder receives isActive=true; other items stay isActive=false',
        (tester) async {
      final calls = _installCapture();
      final pool = MediaPlayerPool(maxSize: 3);
      final states = <int, MediaFeedItemState>{};

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: MediaFeed(
                itemCount: 4,
                itemAt: _item,
                pool: pool,
                config: const MediaFeedConfig(
                  // Stage 7d / F-05: this file predates the activation debounce and
                  // asserts on synchronous (same-frame) activation timing; isolate
                  // every test here from the (now non-zero-by-default)
                  // activationDebounce so those timing assumptions still hold.
                  // Dedicated F-05 tests below set a non-zero value explicitly.
                  activationDebounce: Duration.zero,
                  autoPlay: false,
                  autoPause: false,
                  pauseOthersOnPlay: false,
                  // This test is specifically about F-02's single-active-slot
                  // behaviour, not Stage 7c's prewarm window -- isolate it
                  // from the (now non-zero-by-default) prewarmWindow so its
                  // liveCount/isActive assertions below stay exact.
                  prewarmWindow: 0,
                ),
                itemBuilder: (context, state) {
                  states[state.index] = state;
                  return SizedBox(
                    key: ValueKey('feed-item-${state.index}'),
                    height: 400,
                    child: state.videoSurface,
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(
        states[0]?.isActive,
        isTrue,
        reason: 'the initially fully-visible item must have acquired a pool '
            'slot',
      );
      expect(pool.isActive('feed-item-0'), isTrue);
      expect(pool.liveCount, 1);

      // Item 1 has not scrolled into view yet.
      expect(states[1]?.isActive ?? false, isFalse);

      await _teardown(tester, pool: pool);
      calls.clear();
      _resetHandler();
    });

    testWidgets(
        'the pool cap bounds concurrent live controllers across many '
        'scrolled-past items, mirroring F-01\'s fix at the widget level',
        (tester) async {
      final calls = _installCapture();
      final pool = MediaPlayerPool(maxSize: 2);
      final states = <int, MediaFeedItemState>{};

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: MediaFeed(
                itemCount: 8,
                itemAt: _item,
                pool: pool,
                config: const MediaFeedConfig(
                  // Stage 7d / F-05: isolate from the non-zero-by-default debounce
                  // -- see the first occurrence above for the full rationale.
                  activationDebounce: Duration.zero,
                  autoPlay: false,
                  autoPause: true,
                  pauseOthersOnPlay: false,
                ),
                itemBuilder: (context, state) {
                  states[state.index] = state;
                  return SizedBox(
                    key: ValueKey('feed-item-${state.index}'),
                    height: 400,
                    child: state.videoSurface,
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();

      // Scroll one full item-height at a time so exactly one item is fully
      // visible after each drag, exercising the pool's eviction repeatedly.
      for (var step = 0; step < 6; step++) {
        await tester.drag(find.byType(ListView), const Offset(0, -400));
        await tester.pump();
        await tester.pump();
        expect(
          pool.liveCount,
          lessThanOrEqualTo(2),
          reason: 'the live pool must never exceed maxSize regardless of '
              'how many items have been scrolled past (this is exactly '
              'what F-01 broke for MediaListPlayer, which only pauses)',
        );
      }

      expect(pool.liveCount, 2);
      // Item 0 was scrolled far past and must have lost its slot entirely
      // (not merely paused-and-retained).
      expect(pool.isActive('feed-item-0'), isFalse);

      await _teardown(tester, pool: pool);
      calls.clear();
      _resetHandler();
    });
  });

  group('pool ownership', () {
    testWidgets('MediaFeed disposes the pool it creates itself when unmounted',
        (tester) async {
      final calls = _installCapture();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: MediaFeed(
                itemCount: 2,
                itemAt: _item,
                maxPoolSize: 2,
                config: const MediaFeedConfig(
                  // Stage 7d / F-05: isolate from the non-zero-by-default debounce
                  // -- see the first occurrence above for the full rationale.
                  activationDebounce: Duration.zero,
                  autoPlay: false,
                  autoPause: false,
                  pauseOthersOnPlay: false,
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
      await tester.pump(const Duration(milliseconds: 20));

      final loadCall = calls.firstWhere((c) => c.method == 'load');
      final activePlayerId = _playerIdOf(loadCall);
      expect(activePlayerId, isNotNull);
      calls.clear();

      // Unmount the feed entirely.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        calls.any(
          (c) => c.method == 'dispose' && _playerIdOf(c) == activePlayerId,
        ),
        isTrue,
        reason: 'an internally-created pool must be fully disposed (every '
            'live controller released) when the MediaFeed that owns it is '
            'removed from the tree — otherwise the feed leaks a decoder '
            'session on every unmount',
      );

      await tester.pump(const Duration(milliseconds: 60));
      _resetHandler();
    });

    testWidgets(
        'MediaFeed does not dispose an externally-supplied pool on unmount',
        (tester) async {
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
                  // Stage 7d / F-05: isolate from the non-zero-by-default debounce
                  // -- see the first occurrence above for the full rationale.
                  activationDebounce: Duration.zero,
                  autoPlay: false,
                  autoPause: false,
                  pauseOthersOnPlay: false,
                  // Ownership, not prewarm, is under test here -- isolate
                  // from the (now non-zero-by-default) prewarmWindow so
                  // liveCount stays exactly 1.
                  prewarmWindow: 0,
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
      await tester.pump(const Duration(milliseconds: 20));

      expect(pool.liveCount, 1);
      calls.clear();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        pool.isDisposed,
        isFalse,
        reason: 'MediaFeed must not dispose a pool it did not create — '
            'ownership stays with whoever constructed it',
      );
      expect(
        calls.any((c) => c.method == 'dispose'),
        isFalse,
      );
      expect(pool.liveCount, 1);

      await pool.releaseAll();
      await tester.pump();
      _resetHandler();
    });
  });

  group('composes with B-11 input validation', () {
    testWidgets(
        'an item with an insecure DRM config never becomes active, and the '
        'pool never leaks a slot for it', (tester) async {
      final calls = _installCapture();
      final pool = MediaPlayerPool(maxSize: 2);
      final states = <int, MediaFeedItemState>{};

      final insecureDrmItem = MediaItem(
        id: 'insecure-drm-feed-item',
        title: 'insecure',
        url: 'http://cdn.example.com/video.mpd',
        drmConfig: DrmConfig.widevine(
          licenseUrl: 'https://license.example.com/widevine',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: MediaFeed(
                itemCount: 1,
                itemAt: (_) => insecureDrmItem,
                pool: pool,
                config: const MediaFeedConfig(
                  // Stage 7d / F-05: isolate from the non-zero-by-default debounce
                  // -- see the first occurrence above for the full rationale.
                  activationDebounce: Duration.zero,
                  autoPlay: false,
                  autoPause: false,
                  pauseOthersOnPlay: false,
                ),
                itemBuilder: (context, state) {
                  states[state.index] = state;
                  return SizedBox(
                    key: ValueKey('feed-item-${state.index}'),
                    height: 400,
                    child: state.videoSurface,
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(
        states[0]?.isActive ?? false,
        isFalse,
        reason: 'B-11: an insecure DRM item must never become active — the '
            'pool must reject it via the same InputValidator path any other '
            'load() goes through, not silently allow it into the feed',
      );
      expect(pool.liveCount, 0);
      expect(
        calls.any((c) => c.method == 'load'),
        isFalse,
      );

      await _teardown(tester, pool: pool);
      calls.clear();
      _resetHandler();
    });
  });

  group('autoPlay / pauseOthersOnPlay', () {
    testWidgets('autoPlay starts playback for a visible item after the delay',
        (tester) async {
      final calls = _installCapture();
      final pool = MediaPlayerPool(maxSize: 2);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: MediaFeed(
                itemCount: 1,
                itemAt: _item,
                pool: pool,
                config: const MediaFeedConfig(
                  // Stage 7d / F-05: isolate from the non-zero-by-default debounce
                  // -- see the first occurrence above for the full rationale.
                  activationDebounce: Duration.zero,
                  autoPlay: true,
                  autoPlayDelay: Duration(milliseconds: 50),
                  pauseOthersOnPlay: false,
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
      await tester.pump(const Duration(milliseconds: 20));
      calls.clear();

      await tester.pump(const Duration(milliseconds: 80));

      expect(
        calls.any((c) => c.method == 'play'),
        isTrue,
        reason: 'autoPlay must call play() once the delay elapses for a '
            'still-visible item',
      );

      await _teardown(tester, pool: pool);
      calls.clear();
      _resetHandler();
    });
  });

  group('MediaFeedItemState.isPrewarmed', () {
    MediaFeedItemState buildState(
        {required bool isActive, required bool isVisible}) {
      return MediaFeedItemState(
        index: 0,
        item: _item(0),
        isActive: isActive,
        isVisible: isVisible,
        playback: const PlaybackState(state: PlayerState.idle),
        videoSurface: const SizedBox.shrink(),
      );
    }

    test('true for a slot that is active but not the visible item', () {
      expect(
        buildState(isActive: true, isVisible: false).isPrewarmed,
        isTrue,
      );
    });

    test('false once the item is the visible/active one', () {
      expect(
        buildState(isActive: true, isVisible: true).isPrewarmed,
        isFalse,
      );
    });

    test('false when there is no live slot at all', () {
      expect(
        buildState(isActive: false, isVisible: false).isPrewarmed,
        isFalse,
      );
    });
  });

  group('Stage 7c / F-03: prewarm window', () {
    testWidgets(
        'the default window (1) prewarms the item ahead and behind the '
        'visible one, and never calls play() on either neighbour',
        (tester) async {
      final calls = _installCapture();
      // maxSize:3 = current + 1-ahead + 1-behind, matching the default
      // prewarmWindow of 1 (see MediaFeedConfig.prewarmWindow's dartdoc).
      final pool = MediaPlayerPool(maxSize: 3);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: MediaFeed(
                itemCount: 5,
                itemAt: _item,
                pool: pool,
                scrollController: ScrollController(initialScrollOffset: 800),
                config: const MediaFeedConfig(
                  // Stage 7d / F-05: isolate from the non-zero-by-default debounce
                  // -- see the first occurrence above for the full rationale.
                  activationDebounce: Duration.zero,
                  autoPlay: true,
                  autoPlayDelay: Duration.zero,
                  pauseOthersOnPlay: false,
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

      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(
        pool.isActive('feed-item-1'),
        isTrue,
        reason: 'the item behind the visible one must be prewarmed',
      );
      expect(
        pool.isActive('feed-item-2'),
        isTrue,
        reason: 'the visible item itself must be active',
      );
      expect(
        pool.isActive('feed-item-3'),
        isTrue,
        reason: 'the item ahead of the visible one must be prewarmed',
      );
      expect(pool.liveCount, 3);

      final activePlayerId = pool.controllerFor('feed-item-2')!.playerId;
      final playCalls = calls.where((c) => c.method == 'play').toList();
      expect(
        playCalls,
        hasLength(1),
        reason: 'exactly one play() must have been issued -- for the '
            'visible item only',
      );
      expect(_playerIdOf(playCalls.single), activePlayerId);

      await _teardown(tester, pool: pool);
      calls.clear();
      _resetHandler();
    });

    testWidgets(
        'prewarmWindow: 0 restores exactly the pre-Stage-7c behaviour -- '
        'neighbours never acquire a slot until they become visible '
        'themselves', (tester) async {
      final calls = _installCapture();
      final pool = MediaPlayerPool(maxSize: 3);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: MediaFeed(
                itemCount: 5,
                itemAt: _item,
                pool: pool,
                scrollController: ScrollController(initialScrollOffset: 800),
                config: const MediaFeedConfig(
                  // Stage 7d / F-05: isolate from the non-zero-by-default debounce
                  // -- see the first occurrence above for the full rationale.
                  activationDebounce: Duration.zero,
                  autoPlay: false,
                  pauseOthersOnPlay: false,
                  prewarmWindow: 0,
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

      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(pool.isActive('feed-item-2'), isTrue);
      expect(
        pool.isActive('feed-item-1'),
        isFalse,
        reason: 'prewarmWindow: 0 must disable prewarming entirely',
      );
      expect(pool.isActive('feed-item-3'), isFalse);
      expect(pool.liveCount, 1);

      await _teardown(tester, pool: pool);
      calls.clear();
      _resetHandler();
    });

    testWidgets(
        'the active item is pinned and is never evicted by its own prewarm '
        'requests, even when the pool is too small to hold every '
        'neighbour', (tester) async {
      final calls = _installCapture();
      // Deliberately tight: only room for one live slot, far below what a
      // window of 1 (which wants 3) would need. The active item must win
      // every time regardless.
      final pool = MediaPlayerPool(maxSize: 1);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: MediaFeed(
                itemCount: 5,
                itemAt: _item,
                pool: pool,
                scrollController: ScrollController(initialScrollOffset: 800),
                config: const MediaFeedConfig(
                  // Stage 7d / F-05: isolate from the non-zero-by-default debounce
                  // -- see the first occurrence above for the full rationale.
                  activationDebounce: Duration.zero,
                  autoPlay: true,
                  autoPlayDelay: Duration.zero,
                  pauseOthersOnPlay: false,
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

      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(
        pool.isActive('feed-item-2'),
        isTrue,
        reason: 'the active item must never be evicted by its own prewarm '
            'requests for its neighbours',
      );
      expect(pool.liveCount, 1);
      expect(pool.isActive('feed-item-1'), isFalse);
      expect(pool.isActive('feed-item-3'), isFalse);

      final activePlayerId = pool.controllerFor('feed-item-2')!.playerId;
      final loadCallsForActive = calls
          .where((c) => c.method == 'load' && _playerIdOf(c) == activePlayerId)
          .toList();
      expect(
        loadCallsForActive,
        hasLength(1),
        reason: 'the active item\'s own slot must have been loaded exactly '
            'once -- if a prewarm request had evicted and reclaimed it, '
            'this would be reloaded again',
      );

      await _teardown(tester, pool: pool);
      calls.clear();
      _resetHandler();
    });

    testWidgets('prewarm never goes out of bounds at the edges of the feed',
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
                  // Stage 7d / F-05: isolate from the non-zero-by-default debounce
                  // -- see the first occurrence above for the full rationale.
                  activationDebounce: Duration.zero,
                  autoPlay: false,
                  pauseOthersOnPlay: false,
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

      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(pool.isActive('feed-item-0'), isTrue);
      expect(
        pool.isActive('feed-item-1'),
        isTrue,
        reason: 'the only neighbour of item 0 (ahead) must be prewarmed; '
            'there is no "behind" neighbour and requesting index -1 must '
            'not crash',
      );
      expect(pool.liveCount, 2);

      await _teardown(tester, pool: pool);
      calls.clear();
      _resetHandler();
    });

    testWidgets(
        'a prewarmed neighbour\'s autoPlay is forced false at the native '
        'layer even when the host\'s per-item MediaConfig requests '
        'autoPlay: true', (tester) async {
      final calls = _installCapture();
      final pool = MediaPlayerPool(maxSize: 3);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: MediaFeed(
                itemCount: 5,
                itemAt: _item,
                pool: pool,
                scrollController: ScrollController(initialScrollOffset: 800),
                mediaConfigAt: (index, item) =>
                    const MediaConfig(autoPlay: true),
                config: const MediaFeedConfig(
                  // Stage 7d / F-05: isolate from the non-zero-by-default debounce
                  // -- see the first occurrence above for the full rationale.
                  activationDebounce: Duration.zero,
                  // Off, so the only source of an `initialize`
                  // `autoPlay: true` argument is the per-item MediaConfig
                  // above, isolating what this test checks.
                  autoPlay: false,
                  pauseOthersOnPlay: false,
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

      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      final activeId = pool.controllerFor('feed-item-2')!.playerId;
      final prewarmAheadId = pool.controllerFor('feed-item-3')!.playerId;
      final prewarmBehindId = pool.controllerFor('feed-item-1')!.playerId;

      bool? autoPlayArgFor(String playerId) {
        final initCall = calls.firstWhere(
          (c) => c.method == 'initialize' && _playerIdOf(c) == playerId,
        );
        final config = (initCall.arguments as Map)['config'] as Map?;
        return config?['autoPlay'] as bool?;
      }

      expect(
        autoPlayArgFor(activeId),
        isTrue,
        reason: 'the active item\'s own per-item config is untouched by '
            'prewarming',
      );
      expect(
        autoPlayArgFor(prewarmAheadId),
        isFalse,
        reason: 'a prewarmed neighbour must never be initialized with '
            'autoPlay: true, regardless of what the host\'s per-item '
            'MediaConfig requests -- it must only ever load, never play',
      );
      expect(autoPlayArgFor(prewarmBehindId), isFalse);

      await _teardown(tester, pool: pool);
      calls.clear();
      _resetHandler();
    });
  });
}
