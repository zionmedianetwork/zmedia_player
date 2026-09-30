import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Issue #137 drift guard: Android must not report `ready` for a
/// STATE_READY with playWhenReady == false once the item has started
/// playback (a paused seek/rebuffer) - it must report `paused`.
/// Parses the Kotlin source as text (see pause_reason_vocabulary_test.dart).
void main() {
  late String src;
  setUpAll(() {
    final f = File(
        'android/src/main/kotlin/com/zionmedianetwork/zmedia_player/MediaPlayerManager.kt');
    expect(f.existsSync(), isTrue);
    src = f.readAsStringSync().split('\n').map((l) {
      final i = l.indexOf('//');
      return i == -1 ? l : l.substring(0, i);
    }).join('\n');
  });

  test('readyStateName maps started+!playWhenReady to paused', () {
    final start = src.indexOf('fun readyStateName');
    expect(start, greaterThanOrEqualTo(0));
    final body =
        src.substring(start, src.indexOf('}', src.indexOf('else ->', start)));
    final playing = body.indexOf('playWhenReady -> "playing"');
    final paused = body.indexOf('hasStartedPlayback -> "paused"');
    final ready = body.indexOf('else -> "ready"');
    expect(playing, greaterThanOrEqualTo(0));
    expect(paused, greaterThan(playing));
    expect(ready, greaterThan(paused));
  });

  test('no STATE_READY mapping bypasses the guard', () {
    expect(
        RegExp(r'STATE_READY\s*->\s*if\s*\([^)]*\)\s*"playing"\s*else\s*"ready"')
            .hasMatch(src),
        isFalse,
        reason: 'use readyStateName(...) for every STATE_READY mapping');
    expect('readyStateName('.allMatches(src).length, greaterThanOrEqualTo(3),
        reason: 'declaration + onPlaybackStateChanged + skipped-load re-emit');
  });

  test('hasStartedPlayback is set on play/ended and reset on load and stop',
      () {
    expect('hasStartedPlayback = true'.allMatches(src).length,
        greaterThanOrEqualTo(2));
    expect('hasStartedPlayback = false'.allMatches(src).length,
        greaterThanOrEqualTo(2),
        reason: 'loadMediaItem + stop');
    final stop = src.indexOf('fun stop()');
    expect(src.substring(stop, stop + 300),
        contains('hasStartedPlayback = false'));
  });
}
