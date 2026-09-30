import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Issue #138 drift guard: on iOS, `ready` must come only from
/// `AVPlayerItem.status == .readyToPlay`. `AVPlayer.status` is player-level and
/// turns `.readyToPlay` for a load that then fails (404, unresolvable host), so
/// emitting `ready` from it reported a failing load as ready before `onError`.
/// Parses the Swift source as text (see ready_after_start_paused_test.dart).
void main() {
  late String src;
  setUpAll(() {
    final f = File(
        'ios/zmedia_player/Sources/zmedia_player/MediaPlayerManager.swift');
    expect(f.existsSync(), isTrue);
    src = f.readAsStringSync().split('\n').map((l) {
      final i = l.indexOf('//');
      return i == -1 ? l : l.substring(0, i);
    }).join('\n');
  });

  String bodyOf(String signature) {
    final start = src.indexOf(signature);
    expect(start, greaterThanOrEqualTo(0), reason: '$signature not found');
    final open = src.indexOf('{', src.indexOf(')', start));
    var depth = 0;
    for (var i = open; i < src.length; i++) {
      if (src[i] == '{') depth++;
      if (src[i] == '}' && --depth == 0) return src.substring(open, i + 1);
    }
    fail('unbalanced braces after $signature');
  }

  test('AVPlayer.status handler emits no ready/playing state', () {
    final body = bodyOf('func handleStatusChange(status: AVPlayer.Status)');
    expect(body.contains('"ready"'), isFalse);
    expect(body.contains('"playing"'), isFalse);
    expect(body.contains('notifyDurationChanged'), isFalse,
        reason: 'duration is reported by the item-level handler');
  });

  test('AVPlayer.status handler still reports .failed', () {
    final body = bodyOf('func handleStatusChange(status: AVPlayer.Status)');
    expect(body.contains('case .failed'), isTrue);
    expect(body.contains('notifyError'), isTrue);
  });

  test('AVPlayerItem.status handler emits ready and reports duration', () {
    final body = bodyOf('func handlePlayerItemStatusChange(');
    expect(body.contains('"ready"'), isTrue);
    expect(body.contains('notifyDurationChanged()'), isTrue);
    expect(body.contains('checkLiveDvrWindowDuration()'), isTrue);
    expect(body.contains('activateTopmostView()'), isTrue);
  });

  test('"ready" is emitted only from the item-level handler', () {
    expect('notifyStateChanged(state: "ready"'.allMatches(src).length, 1);
  });
}
