// Regression tests for two related fixes in MediaPlayer:
//
//  Fix A — Playlist auto-advance on completion (_handlePlaybackCompleted):
//    When state transitions to PlayerState.completed, the player should:
//    • Call skipToIndex(nextIndex) then play() for a multi-item playlist.
//    • Do nothing (no advance) at the last item with RepeatMode.none.
//    • With no playlist and config.looping == true: call seekTo(0) then play().
//    • Guard: a second consecutive 'completed' event must not re-advance.
//
//  Fix B — play()-after-completion restart:
//    When _currentState is completed, play() should first send seekTo(pos=0)
//    then send play. When state is playing/paused, play() sends only play.
//
// Harness: same pattern as media_player_channel_test.dart and
// media_player_events_test.dart (TestWidgetsFlutterBinding +
// TestDefaultBinaryMessengerBinding.setMockMethodCallHandler to capture
// outgoing calls, handlePlatformMessage with StandardMethodCodec to inject
// native events).

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

// ---------------------------------------------------------------------------
// Helpers — reuse the same style as the existing harness files
// ---------------------------------------------------------------------------

const _channel = MethodChannel('zmedia_player');

/// Installs a mock handler that captures all outgoing MethodCalls.
/// The optional [reply] function can provide return values per method.
List<MethodCall> _installCapture(
    [Future<dynamic> Function(MethodCall)? reply]) {
  final calls = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (MethodCall call) async {
    calls.add(call);
    return reply != null ? await reply(call) : null;
  });
  return calls;
}

void _resetHandler() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null);
}

/// Injects a native→Dart event through the test binary messenger.
Future<void> _injectEvent(String method, Map<String, dynamic> arguments) async {
  final codec = const StandardMethodCodec();
  final data = codec.encodeMethodCall(MethodCall(method, arguments));
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage('zmedia_player', data, (_) {});
}

/// Injects an onStateChanged 'completed' event for [playerId].
Future<void> _injectCompleted(String playerId) => _injectEvent(
      'onStateChanged',
      {
        'playerId': playerId,
        'state': 'completed',
        'isBuffering': false,
        'bufferPercentage': 100.0,
      },
    );

/// Injects an onStateChanged event with the given [state] string.
Future<void> _injectState(String playerId, String state) => _injectEvent(
      'onStateChanged',
      {
        'playerId': playerId,
        'state': state,
        'isBuffering': false,
        'bufferPercentage': 0.0,
      },
    );

const _items = [
  MediaItem(
    id: 'item-0',
    title: 'Track 0',
    url: 'https://example.com/track0.mp4',
  ),
  MediaItem(
    id: 'item-1',
    title: 'Track 1',
    url: 'https://example.com/track1.mp4',
  ),
  MediaItem(
    id: 'item-2',
    title: 'Track 2',
    url: 'https://example.com/track2.mp4',
  ),
];

// ---------------------------------------------------------------------------
// Tests — Fix A: playlist auto-advance on completion
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    _resetHandler();
  });

  // =========================================================================
  group('Fix A — Playlist auto-advance on completion', () {
    // -----------------------------------------------------------------------
    test(
        'completed at non-last item: issues skipToIndex(nextIndex) then play()',
        () async {
      // Arrange: 3-item playlist, sequential, RepeatMode.none, at index 0.
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'cmp-advance-1');
      await player.initialize();

      final playlist = Playlist(
        id: 'pl-advance-1',
        title: 'Auto Advance',
        items: _items,
        currentIndex: 0,
        mode: PlaybackMode.sequential,
        repeatMode: RepeatMode.none,
      );
      await player.setPlaylist(playlist);
      calls.clear(); // ignore setup calls

      // Act: inject a 'completed' state event.
      await _injectCompleted('cmp-advance-1');

      // The auto-advance is async (then chain); give the microtask queue a tick.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // Assert: should see a skipToIndex to index 1, then play.
      final methodNames = calls.map((c) => c.method).toList();
      expect(
        methodNames,
        containsAllInOrder(['skipToIndex', 'play']),
        reason: 'On completion with a next item available, '
            'skipToIndex must be called before play()',
      );

      final skipCall = calls.firstWhere((c) => c.method == 'skipToIndex');
      expect(
        skipCall.arguments['index'],
        1,
        reason:
            'skipToIndex must advance to index 1 (the next sequential item)',
      );
      expect(
        skipCall.arguments['playerId'],
        'cmp-advance-1',
      );

      final playAfterSkip = calls.lastWhere((c) => c.method == 'play');
      expect(playAfterSkip.arguments['playerId'], 'cmp-advance-1');

      await player.dispose();
    });

    // -----------------------------------------------------------------------
    test(
        'completed at last item with RepeatMode.none: does NOT issue skipToIndex or play',
        () async {
      // Arrange: at the last item (index 2), no repeat.
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'cmp-last-none');
      await player.initialize();

      final playlist = Playlist(
        id: 'pl-last-none',
        title: 'Last Item',
        items: _items,
        currentIndex: 2, // last
        mode: PlaybackMode.sequential,
        repeatMode: RepeatMode.none,
      );
      await player.setPlaylist(playlist);
      calls.clear();

      await _injectCompleted('cmp-last-none');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final methodNames = calls.map((c) => c.method).toList();
      expect(
        methodNames.contains('skipToIndex'),
        isFalse,
        reason:
            'No skipToIndex must be sent when at the last item with RepeatMode.none',
      );
      // play() is also not expected to be called by the auto-advance logic.
      // (A standalone play() call from the test itself would be a different story.)
      expect(
        methodNames.contains('play'),
        isFalse,
        reason:
            'No play must be sent when at the last item with RepeatMode.none',
      );

      await player.dispose();
    });

    // -----------------------------------------------------------------------
    test(
        'no playlist + config.looping == true: completed issues seekTo(0) then play()',
        () async {
      // Arrange: no playlist, looping config.
      final calls = _installCapture();
      final player = MediaPlayer(
        playerId: 'cmp-loop',
        config: const MediaConfig(looping: true),
      );
      await player.initialize();
      calls.clear();

      await _injectCompleted('cmp-loop');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final methodNames = calls.map((c) => c.method).toList();
      expect(
        methodNames,
        containsAllInOrder(['seekTo', 'play']),
        reason:
            'looping == true with no playlist must issue seekTo(0) then play()',
      );

      final seekCall = calls.firstWhere((c) => c.method == 'seekTo');
      expect(
        seekCall.arguments['position'],
        0,
        reason: 'seekTo position must be 0 (restart) for loop',
      );
      expect(seekCall.arguments['playerId'], 'cmp-loop');

      await player.dispose();
    });

    // -----------------------------------------------------------------------
    test('guard: two consecutive completed events advance only once', () async {
      // Arrange: 3-item playlist at index 0.
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'cmp-double');
      await player.initialize();

      final playlist = Playlist(
        id: 'pl-double',
        title: 'Double Completed',
        items: _items,
        currentIndex: 0,
        mode: PlaybackMode.sequential,
        repeatMode: RepeatMode.none,
      );
      await player.setPlaylist(playlist);
      calls.clear();

      // Inject first 'completed'.
      await _injectCompleted('cmp-double');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final countAfterFirst =
          calls.where((c) => c.method == 'skipToIndex').length;

      // Inject second 'completed' while already in completed state.
      await _injectCompleted('cmp-double');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final countAfterSecond =
          calls.where((c) => c.method == 'skipToIndex').length;

      expect(
        countAfterFirst,
        1,
        reason: 'First completed must produce exactly one skipToIndex',
      );
      expect(
        countAfterSecond,
        countAfterFirst,
        reason:
            'Second completed while already completed must NOT produce another skipToIndex '
            '(wasCompleted guard must prevent duplicate advances)',
      );

      await player.dispose();
    });

    // -----------------------------------------------------------------------
    test(
        'completed at last item with RepeatMode.all: wraps to index 0 and plays',
        () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'cmp-all-wrap');
      await player.initialize();

      final playlist = Playlist(
        id: 'pl-all-wrap',
        title: 'All Repeat',
        items: _items,
        currentIndex: 2, // last
        mode: PlaybackMode.sequential,
        repeatMode: RepeatMode.all,
      );
      await player.setPlaylist(playlist);
      calls.clear();

      await _injectCompleted('cmp-all-wrap');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final methodNames = calls.map((c) => c.method).toList();
      expect(
        methodNames,
        containsAllInOrder(['skipToIndex', 'play']),
        reason: 'RepeatMode.all at last item must wrap to first and play',
      );

      final skipCall = calls.firstWhere((c) => c.method == 'skipToIndex');
      expect(
        skipCall.arguments['index'],
        0,
        reason: 'RepeatMode.all must wrap to index 0',
      );

      await player.dispose();
    });

    // -----------------------------------------------------------------------
    test('no playlist + looping == false: completed is a no-op', () async {
      final calls = _installCapture();
      final player = MediaPlayer(
        playerId: 'cmp-no-loop',
        config: const MediaConfig(looping: false),
      );
      await player.initialize();
      calls.clear();

      await _injectCompleted('cmp-no-loop');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final methodNames = calls.map((c) => c.method).toList();
      expect(
        methodNames.contains('seekTo'),
        isFalse,
        reason: 'No seekTo expected without looping',
      );
      expect(
        methodNames.contains('play'),
        isFalse,
        reason: 'No play expected without looping or playlist next',
      );

      await player.dispose();
    });
  });

  // =========================================================================
  group('Fix B — play()-after-completion restart', () {
    // Helper: inject a state event and wait for it to be reflected in
    // currentState. Because stateStream is a broadcast stream, we must
    // subscribe BEFORE injecting so we don't miss the emission.
    Future<void> driveToState(
        MediaPlayer player, String playerId, String stateStr) async {
      final completer = Completer<void>();
      final sub = player.stateStream.listen((s) {
        if (s.state.name == stateStr && !completer.isCompleted) {
          completer.complete();
        }
      });
      await _injectState(playerId, stateStr);
      await completer.future.timeout(const Duration(seconds: 2));
      await sub.cancel();
    }

    // -----------------------------------------------------------------------
    test(
        'play() when state == completed: sends seekTo(pos=0) BEFORE play on channel',
        () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'cmp-play-restart');
      await player.initialize();
      calls.clear();

      // Drive _currentState to completed via an injected event.
      // No playlist set, so _handlePlaybackCompleted does nothing (no looping).
      await driveToState(player, 'cmp-play-restart', 'completed');
      // Flush any microtasks from _handlePlaybackCompleted.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      calls.clear(); // only care about the explicit play() call below

      // Act: call play() while in completed state.
      await player.play();

      final methodNames = calls.map((c) => c.method).toList();

      // seekTo must appear before play in the captured call list.
      final seekIndex = methodNames.indexOf('seekTo');
      final playIndex = methodNames.indexOf('play');

      expect(
        seekIndex,
        isNot(equals(-1)),
        reason: 'play() from completed state must issue a seekTo(0) first',
      );
      expect(
        playIndex,
        isNot(equals(-1)),
        reason: 'play() must still send a play call after seekTo',
      );
      expect(
        seekIndex < playIndex,
        isTrue,
        reason: 'seekTo must come before play in the channel call sequence',
      );

      final seekCall = calls.firstWhere((c) => c.method == 'seekTo');
      expect(
        seekCall.arguments['position'],
        0,
        reason: 'seekTo position must be 0 (beginning of media)',
      );
      expect(seekCall.arguments['playerId'], 'cmp-play-restart');

      await player.dispose();
    });

    // -----------------------------------------------------------------------
    test('play() when state == playing: sends only play (no seekTo)', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'cmp-play-playing');
      await player.initialize();
      calls.clear();

      // Drive to playing state.
      await driveToState(player, 'cmp-play-playing', 'playing');

      calls.clear();

      await player.play();

      final methodNames = calls.map((c) => c.method).toList();

      expect(
        methodNames.contains('play'),
        isTrue,
        reason: 'play() must send a play call',
      );
      expect(
        methodNames.contains('seekTo'),
        isFalse,
        reason: 'play() from playing state must NOT send seekTo',
      );

      await player.dispose();
    });

    // -----------------------------------------------------------------------
    test('play() when state == paused: sends only play (no seekTo)', () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'cmp-play-paused');
      await player.initialize();
      calls.clear();

      // Drive to paused state.
      await driveToState(player, 'cmp-play-paused', 'paused');

      calls.clear();

      await player.play();

      final methodNames = calls.map((c) => c.method).toList();

      expect(
        methodNames.contains('play'),
        isTrue,
        reason: 'play() must send a play call when paused',
      );
      expect(
        methodNames.contains('seekTo'),
        isFalse,
        reason: 'play() from paused state must NOT send seekTo',
      );

      await player.dispose();
    });

    // -----------------------------------------------------------------------
    test(
        'play() when state == idle (never played): sends only play (no seekTo)',
        () async {
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'cmp-play-idle');
      await player.initialize();
      calls.clear();

      // State is idle by default — never injected any event.
      await player.play();

      final methodNames = calls.map((c) => c.method).toList();

      expect(
        methodNames.contains('play'),
        isTrue,
        reason: 'play() from idle must send play',
      );
      expect(
        methodNames.contains('seekTo'),
        isFalse,
        reason: 'play() from idle must NOT send seekTo',
      );

      await player.dispose();
    });

    // -----------------------------------------------------------------------
    test(
        'play()-after-completion seekTo uses position=0, not a non-zero position',
        () async {
      // Verify the specific value 0 is sent (not milliseconds of some previous
      // position that was tracked), confirming the restart-from-beginning fix.
      final calls = _installCapture();
      final player = MediaPlayer(playerId: 'cmp-play-zero');
      await player.initialize();

      // Simulate a position update to something non-zero.
      final posFuture = player.positionStream.first;
      await _injectEvent('onPositionChanged', {
        'playerId': 'cmp-play-zero',
        'position': 45000, // 45 seconds
      });
      await posFuture.timeout(const Duration(seconds: 2));

      // Now drive to completed — no playlist, no looping.
      await driveToState(player, 'cmp-play-zero', 'completed');
      // Flush microtasks from _handlePlaybackCompleted.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      calls.clear();

      await player.play();

      final seekCall = calls.firstWhere(
        (c) => c.method == 'seekTo',
        orElse: () => fail('No seekTo call found'),
      );
      expect(
        seekCall.arguments['position'],
        0,
        reason:
            'play() after completion must seek to position 0, not the last known position',
      );

      await player.dispose();
    });
  });
}
