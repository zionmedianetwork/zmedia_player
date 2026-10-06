import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Issue #132 drift guard: both natives must not report a plain "paused"
/// once the item has ended, or `PlayerState.completed` is overwritten.
/// Parses the native sources as text (see pause_reason_vocabulary_test.dart
/// for why this is the only mechanism that can see it).
void main() {
  String read(String path) {
    final f = File(path);
    expect(f.existsSync(), isTrue, reason: 'missing $path');
    return f.readAsStringSync().split('\n').map((l) {
      final i = l.indexOf('//');
      return i == -1 ? l : l.substring(0, i);
    }).join('\n');
  }

  test('Android onIsPlayingChanged guards "paused" on STATE_ENDED', () {
    final src = read(
        'android/src/main/kotlin/com/zionmedianetwork/zmedia_player/MediaPlayerManager.kt');
    final start = src.indexOf('override fun onIsPlayingChanged');
    expect(start, greaterThanOrEqualTo(0));
    final pausedAt =
        src.indexOf('if (isPlaying) "playing" else "paused"', start);
    expect(pausedAt, greaterThan(start));
    final guard = RegExp(
        r'!isPlaying\s*&&\s*exoPlayer\?\.playbackState\s*==\s*Player\.STATE_ENDED');
    expect(guard.firstMatch(src.substring(start, pausedAt)), isNotNull,
        reason: 'onIsPlayingChanged must return early on !isPlaying while '
            'STATE_ENDED, before emitting "paused".');
  });

  test('iOS .paused branch is guarded by currentItemPlayedToEnd', () {
    final src = read(
        'ios/zmedia_player/Sources/zmedia_player/MediaPlayerManager.swift');
    final fn = src.indexOf('func handleTimeControlStatusChange');
    expect(fn, greaterThanOrEqualTo(0));
    final paused = src.indexOf('case .paused:', fn);
    final emit = src.indexOf('state: "paused"', paused);
    expect(paused, greaterThan(fn));
    expect(emit, greaterThan(paused));
    expect(src.substring(paused, emit), contains('if currentItemPlayedToEnd'));

    final finish = src.indexOf('func playerDidFinishPlaying');
    expect(finish, greaterThanOrEqualTo(0));
    expect(src.substring(finish, src.indexOf('func playerDidFailWithError')),
        contains('currentItemPlayedToEnd = true'));
    expect('currentItemPlayedToEnd = false'.allMatches(src).length,
        greaterThanOrEqualTo(5),
        reason: 'declaration + load, play, seekTo, stop must all reset it');
  });

  test('iOS seekTo away from an ended item reports paused (issue #143)', () {
    final src = read(
        'ios/zmedia_player/Sources/zmedia_player/MediaPlayerManager.swift');
    final seek = src.indexOf('func seekTo(position: Int64)');
    final perform = src.indexOf('private func performSeek');
    expect(seek, greaterThanOrEqualTo(0));
    expect(src.substring(seek, perform),
        contains('let seekingAwayFromEnd = currentItemPlayedToEnd'));
    final end = src.indexOf('func setVolume', perform);
    final body = src.substring(perform, end);
    expect(body, contains('leavingEnded'));
    expect(body, contains('state: "paused"'));
  });
}
