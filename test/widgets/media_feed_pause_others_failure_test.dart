// Regression tests for fire-and-forget controller failures escaping MediaFeed
// as unhandled async errors.
//
// `_pauseOthers` (and the sibling call sites listed below) drive
// MediaController from UI/activation paths that must not block, so the calls
// are deliberately never awaited. Before this fix they were bare statements —
// `other.pause();`, `unawaited(controller.play())`, `controller.toggleMute();`
// — so the discarded Future carried any failure straight to the ambient Zone's
// uncaught-error handler, with nothing naming the item or the operation that
// produced it. Since #86 made MediaController *queue* operations instead of
// throwing on contention, the common failure went away, but a genuine native
// failure (or a dispose() racing the queued pause) still escaped.
//
// Harness: mirrors media_feed_test.dart / media_list_player_pause_others_test.dart
// — mock the MethodChannel, inject native onStateChanged events to drive
// `isPlaying`, and drive genuine visibility_detector visibility through a real
// scrollable tree.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:zmedia_player/zmedia_player.dart';

const _channel = MethodChannel('zmedia_player');

String? _playerIdOf(MethodCall call) =>
    (call.arguments as Map?)?['playerId'] as String?;

MediaItem _item(int index) => MediaItem(
      id: 'feed-item-$index',
      title: 'Item $index',
      url: 'https://cdn.example.com/video-$index.mp4',
    );

void _resetHandler() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null);
}

Future<void> _injectState(String playerId, String state) async {
  const codec = StandardMethodCodec();
  final data = codec.encodeMethodCall(MethodCall('onStateChanged', {
    'playerId': playerId,
    'state': state,
    'isBuffering': false,
    'bufferPercentage': 0.0,
  }));
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage('zmedia_player', data, (_) {});
}

/// Installs a capturing handler that fails `pause` for any player id in
/// [failPauseFor], so a *specific* controller's pause can be made to blow up
/// the way a genuine native failure would.
List<MethodCall> _installCapture(Set<String> failPauseFor) {
  final calls = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (MethodCall call) async {
    calls.add(call);
    if (call.method == 'pause' && failPauseFor.contains(_playerIdOf(call))) {
      throw PlatformException(
        code: 'PAUSE_FAILED',
        message: 'native pause failed for ${_playerIdOf(call)}',
      );
    }
    return null;
  });
  return calls;
}

/// The `feed-item-N` key -> generated playerId mapping, recovered from the
/// `load` calls (each carries both the playerId and the media item's id).
Map<String, String> _keyToPlayerId(List<MethodCall> calls) {
  final result = <String, String>{};
  for (final call in calls) {
    if (call.method != 'load') continue;
    final args = call.arguments as Map;
    final item = args['mediaItem'] as Map?;
    final id = item?['id'] as String?;
    final playerId = args['playerId'] as String?;
    if (id != null && playerId != null) result[id] = playerId;
  }
  return result;
}

/// The test surface is 800x600, so a 2.0 aspect ratio makes every item
/// exactly 400 logical pixels tall — the same height as the viewport below.
/// One item therefore fills the viewport exactly, and scrolling by 400 moves
/// visibility cleanly from item N to item N+1. (`MediaFeed` wraps each item in
/// an `AspectRatio`, so the item height comes from here, *not* from whatever
/// the `itemBuilder` returns.)
const _itemExtent = 400.0;

Widget _buildFeed(MediaPlayerPool pool, ScrollController scrollController) =>
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: _itemExtent,
          child: MediaFeed(
            itemCount: 4,
            itemAt: _item,
            pool: pool,
            aspectRatio: 2.0,
            scrollController: scrollController,
            config: const MediaFeedConfig(
              // Deterministic activation: no debounce, no autoPlay (the
              // `playing` state is injected explicitly below), and no
              // auto-pause/mute so the only pause() calls in the capture are
              // the ones _pauseOthers issues.
              activationDebounce: Duration.zero,
              autoPlay: false,
              autoPause: false,
              muteWhenNotVisible: false,
              pauseOthersOnPlay: true,
              prewarmWindow: 1,
            ),
            itemBuilder: (context, state) => SizedBox(
              key: ValueKey('feed-item-${state.index}'),
              child: state.videoSurface,
            ),
          ),
        ),
      ),
    );

Future<void> _teardown(WidgetTester tester, MediaPlayerPool pool) async {
  await tester.pump(const Duration(milliseconds: 60));
  await tester.pumpAndSettle();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 260));
  await pool.releaseAll();
  await tester.pump();
  _resetHandler();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    final calls = _installCapture(const {});
    MediaController.create(playerId: 'warmup-feed-pause-failure').dispose();
    calls.clear();
    _resetHandler();
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  group('MediaFeed fire-and-forget failures do not escape', () {
    testWidgets(
        'a pause() that fails for one controller is swallowed, traced, and '
        'does not prevent the other controllers from being paused',
        (tester) async {
      final failPauseFor = <String>{};
      final calls = _installCapture(failPauseFor);
      var counter = 0;
      final pool = MediaPlayerPool(
        maxSize: 4,
        playerIdFactory: () => 'feed-pause-fail-p${counter++}',
      );
      final scrollController = ScrollController();

      final traced = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) traced.add(message);
      };

      try {
        await tester.pumpWidget(_buildFeed(pool, scrollController));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));

        // Scroll to item 1 so slots exist for items 0, 1 and 2 (item 1 plus
        // its prewarmed neighbours).
        scrollController.jumpTo(_itemExtent);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        await tester.pumpAndSettle();

        final ids = _keyToPlayerId(calls);
        final player0 = ids['feed-item-0'];
        final player1 = ids['feed-item-1'];
        expect(player0, isNotNull,
            reason: 'item 0 must have been loaded into a pool slot');
        expect(player1, isNotNull,
            reason: 'item 1 must have been loaded into a pool slot');

        // Both are "playing" as far as their controllers are concerned, so
        // _pauseOthers will try to pause both of them.
        await _injectState(player0!, 'playing');
        await _injectState(player1!, 'playing');
        await tester.pump();

        // Item 0's pause is the one that blows up.
        failPauseFor.add(player0);
        calls.clear();
        traced.clear();

        // Activating item 2 runs _pauseOthers, which must pause both 0 and 1.
        scrollController.jumpTo(_itemExtent * 2);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        await tester.pumpAndSettle();

        final pausedIds = calls
            .where((c) => c.method == 'pause')
            .map(_playerIdOf)
            .whereType<String>()
            .toSet();

        expect(pausedIds, contains(player0),
            reason: '_pauseOthers must have attempted the failing controller');
        expect(
          pausedIds,
          contains(player1),
          reason: 'one controller failing to pause must not prevent the '
              'others in the same _pauseOthers loop from being paused',
        );

        expect(
          traced.any((m) => m.startsWith('MediaFeed:') && m.contains('pause')),
          isTrue,
          reason: 'an unexpected native pause failure must leave a trace '
              'naming the operation rather than being silently dropped',
        );

        failPauseFor.clear();
        await _teardown(tester, pool);
      } finally {
        debugPrint = originalDebugPrint;
      }

      // Reaching here without the test binding reporting an uncaught
      // asynchronous error is the other half of the assertion: before the
      // fix, the rejected pause() Future was discarded entirely and surfaced
      // as an unhandled async error.
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a controller disposed out from under _pauseOthers is swallowed '
        'quietly, and the surviving controllers are still paused',
        (tester) async {
      final calls = _installCapture(const {});
      var counter = 0;
      final pool = MediaPlayerPool(
        maxSize: 4,
        playerIdFactory: () => 'feed-pause-disposed-p${counter++}',
      );
      final scrollController = ScrollController();

      final traced = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) traced.add(message);
      };

      try {
        await tester.pumpWidget(_buildFeed(pool, scrollController));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));

        scrollController.jumpTo(_itemExtent);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        await tester.pumpAndSettle();

        final ids = _keyToPlayerId(calls);
        final player0 = ids['feed-item-0'];
        final player1 = ids['feed-item-1'];
        expect(player0, isNotNull);
        expect(player1, isNotNull);

        await _injectState(player0!, 'playing');
        await _injectState(player1!, 'playing');
        await tester.pump();

        // Lose the check-then-act race deliberately: tear down item 0's
        // underlying MediaPlayer while its MediaController is still live, so
        // `!other.isDisposed && other.isPlaying` still passes but the queued
        // pause() fails with PlayerDisposedException.
        final controller0 = pool.controllerFor('feed-item-0');
        expect(controller0, isNotNull);
        controller0!.player.dispose();

        calls.clear();
        traced.clear();

        scrollController.jumpTo(_itemExtent * 2);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        await tester.pumpAndSettle();

        final pausedIds = calls
            .where((c) => c.method == 'pause')
            .map(_playerIdOf)
            .whereType<String>()
            .toSet();

        expect(
          pausedIds,
          contains(player1),
          reason: 'the disposed neighbour must not stop the still-live one '
              'from being paused',
        );

        expect(
          traced.where((m) => m.startsWith('MediaFeed:')),
          isEmpty,
          reason: 'a dispose() racing a queued pause is an expected teardown '
              'race, not a defect — MediaFeed must swallow it without adding '
              'noise of its own',
        );

        await _teardown(tester, pool);
      } finally {
        debugPrint = originalDebugPrint;
      }

      expect(tester.takeException(), isNull);
    });
  });
}
