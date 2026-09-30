import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Issue #134 drift guard.
///
/// A `seekTo` while paused moved the native player but produced no
/// `onPositionChanged`, because Android's periodic tick is deliberately silent
/// unless playing/stalled-and-intending-to-play. Both natives must now emit one
/// position event after a seek regardless of play state. The channel is mocked
/// in every Dart test and `flutter analyze` cannot see native code, so parse
/// the sources as text (same technique as pause_reason_vocabulary_test.dart).
void main() {
  String read(String path) {
    final f = File(path);
    expect(f.existsSync(), isTrue, reason: 'missing $path');
    return f.readAsStringSync();
  }

  String stripComments(String source) => source
          .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
          .split('\n')
          .map((l) {
        final i = l.indexOf('//');
        return i == -1 ? l : l.substring(0, i);
      }).join('\n');

  String bodyAfter(String source, String signature) {
    final start = source.indexOf(signature);
    expect(start, greaterThanOrEqualTo(0), reason: 'missing $signature');
    final open = source.indexOf('{', start);
    var depth = 0;
    var i = open;
    for (; i < source.length; i++) {
      if (source[i] == '{') depth++;
      if (source[i] == '}' && --depth == 0) break;
    }
    return source.substring(open, i + 1);
  }

  test('Android emits onPositionChanged from a SEEK discontinuity', () {
    final src = stripComments(read(
        'android/src/main/kotlin/com/zionmedianetwork/zmedia_player/MediaPlayerManager.kt'));
    final body = bodyAfter(src, 'override fun onPositionDiscontinuity(');
    expect(body, contains('DISCONTINUITY_REASON_SEEK'));
    expect(body, contains('notifyPositionChanged('));

    // The periodic tick must stay silent while paused.
    final tick = bodyAfter(src, 'private fun startPositionUpdates()');
    expect(tick, contains('player.isPlaying || stalledButIntendingToPlay'));
  });

  test('iOS emits a position snapshot from the seek completion', () {
    final src = stripComments(read(
        'ios/zmedia_player/Sources/zmedia_player/MediaPlayerManager.swift'));
    final seek = bodyAfter(src, 'private func performSeek(');
    expect(seek, contains('seek(to: time)'));
    expect(seek, contains('emitPositionSnapshot('));

    // Both public seek paths (window-relative live and plain) go through it,
    // and nothing calls avPlayer.seek(to:) bare from seekTo(position:).
    final seekTo = bodyAfter(src, 'func seekTo(position: Int64)');
    expect(RegExp(r'performSeek\(to:').allMatches(seekTo).length, 2);
    expect(seekTo, isNot(contains('avPlayer?.seek(to:')));

    // The snapshot builder must be the one that ends in onPositionChanged.
    final snap = bodyAfter(src, 'private func emitPositionSnapshot(');
    expect(snap, contains('notifyPositionChanged('));
  });
}
