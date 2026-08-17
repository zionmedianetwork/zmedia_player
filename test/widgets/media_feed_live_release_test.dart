// Stage 7d (Phase 7) regression tests for [MediaFeed] — F-04: an off-screen
// LIVE item must be stopped and released (its pool slot fully torn down),
// not merely paused. On-device measurement found a paused, off-screen live
// stream still pulled ~13% of its playing bandwidth (~727 KB/min) and never
// actually stopped -- pausing throttles a live session, it does not end it.
// VOD keeps the original pause-and-retain behaviour unchanged.
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

String? _playerIdOf(MethodCall call) =>
    (call.arguments as Map?)?['playerId'] as String?;

MediaItem _liveItem(int index) => MediaItem(
      id: 'feed-live-item-$index',
      title: 'Live Item $index',
      url: 'https://cdn.example.com/live-$index.m3u8',
      isLive: true,
    );

MediaItem _vodItem(int index) => MediaItem(
      id: 'feed-vod-item-$index',
      title: 'VOD Item $index',
      url: 'https://cdn.example.com/vod-$index.mp4',
    );

Future<void> _teardown(WidgetTester tester, {MediaPlayerPool? pool}) async {
  await tester.pump(const Duration(milliseconds: 60));
  await tester.pumpAndSettle();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 260));
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
        MediaController.create(playerId: 'warmup-feed-live-release-timer');
    warmup.dispose();
    calls.clear();
    _resetHandler();

    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  group('F-04: live items are released, not paused, when off-screen', () {
    testWidgets(
        'an off-screen LIVE item loses its pool slot entirely (release), '
        'and its unpin happens cleanly alongside it', (tester) async {
      final calls = _installCapture();
      final pool = MediaPlayerPool(maxSize: 2);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: MediaFeed(
                itemCount: 3,
                itemAt: _liveItem,
                pool: pool,
                config: const MediaFeedConfig(
                  autoPlay: false,
                  autoPause: true,
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
      await tester.pump(const Duration(milliseconds: 20));

      expect(pool.isActive('feed-live-item-0'), isTrue);

      // Simulate the slot being pinned (as Stage 7c's prewarm window would
      // do for the active item -- deliberately set directly here, with
      // prewarmWindow: 0 above, so this test isolates F-04's release path
      // from any cross-item prewarm interaction between item 0 and its
      // neighbour once item 1 becomes active below).
      pool.pin('feed-live-item-0');
      expect(pool.isPinned('feed-live-item-0'), isTrue);

      final loadCall = calls.firstWhere(
        (c) => c.method == 'load' && _playerIdOf(c) != null,
      );
      final playerId = _playerIdOf(loadCall);
      calls.clear();

      // Scroll item 0 fully out of view.
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(
        pool.isActive('feed-live-item-0'),
        isFalse,
        reason: 'F-04: a live item must lose its pool slot entirely when it '
            'goes off-screen -- pausing (and retaining the decoder session) '
            'is not enough for live, unlike VOD',
      );
      expect(
        pool.isPinned('feed-live-item-0'),
        isFalse,
        reason: 'releasing a live item must also drop its pin cleanly',
      );
      expect(
        calls.any(
          (c) => c.method == 'dispose' && _playerIdOf(c) == playerId,
        ),
        isTrue,
        reason: 'release() disposes the underlying controller, unlike a '
            'plain pause',
      );
      expect(
        calls.any((c) => c.method == 'pause'),
        isFalse,
        reason: 'a live item must be released, never merely paused',
      );

      await _teardown(tester, pool: pool);
      calls.clear();
      _resetHandler();
    });

    testWidgets(
        'an off-screen VOD item is still only paused and retains its slot '
        '(regression guard: F-04 must not affect non-live items)',
        (tester) async {
      final calls = _installCapture();
      final pool = MediaPlayerPool(maxSize: 2);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: MediaFeed(
                itemCount: 3,
                itemAt: _vodItem,
                pool: pool,
                config: const MediaFeedConfig(
                  autoPlay: false,
                  autoPause: true,
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
      await tester.pump(const Duration(milliseconds: 20));

      expect(pool.isActive('feed-vod-item-0'), isTrue);
      calls.clear();

      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(
        pool.isActive('feed-vod-item-0'),
        isTrue,
        reason: 'a VOD item must keep its pool slot on invisibility -- only '
            'live items release',
      );
      expect(
        calls.any((c) => c.method == 'dispose'),
        isFalse,
        reason: 'VOD must never be disposed just for going off-screen',
      );

      await _teardown(tester, pool: pool);
      calls.clear();
      _resetHandler();
    });

    testWidgets(
        'scrolling a released live item back into view re-acquires a fresh '
        'slot and calls load() again -- the rejoin, with no seekToLive call',
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
                itemAt: _liveItem,
                pool: pool,
                config: const MediaFeedConfig(
                  autoPlay: false,
                  autoPause: true,
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
      await tester.pump(const Duration(milliseconds: 20));

      expect(pool.isActive('feed-live-item-0'), isTrue);

      // Scroll away (releases item 0) then all the way back.
      await tester.drag(find.byType(ListView), const Offset(0, -800));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(pool.isActive('feed-live-item-0'), isFalse);

      calls.clear();
      await tester.drag(find.byType(ListView), const Offset(0, 800));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(
        pool.isActive('feed-live-item-0'),
        isTrue,
        reason: 'scrolling back must re-acquire a slot for the released '
            'live item',
      );
      expect(
        calls.any((c) => c.method == 'load'),
        isTrue,
        reason: 'rejoining a released live item costs a fresh load() -- '
            'there is no seekToLive path, a freshly loaded live stream '
            'always joins at the live edge on its own',
      );
      expect(
        calls.any((c) => c.method == 'seekTo'),
        isFalse,
        reason: 'no seek-to-live call exists or is used for the rejoin',
      );

      await _teardown(tester, pool: pool);
      calls.clear();
      _resetHandler();
    });
  });
}
