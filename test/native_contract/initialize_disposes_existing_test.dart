import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Issue #139 drift guard.
///
/// `initializePlayer` used to overwrite `players[playerId]` without disposing
/// the instance already there. With a reused playerId (a recovery loop that
/// replaces a controller) the old ExoPlayer/AVPlayer kept loading and playing
/// with nothing referencing it -- unreachable by `dispose` and `shutdown()`.
/// Native has no automated tests, so the sources are parsed as text, like
/// `no_stale_reaper_test.dart`.
void main() {
  const androidPath =
      'android/src/main/kotlin/com/zionmedianetwork/zmedia_player/MediaPlayerManager.kt';
  const iosPath =
      'ios/zmedia_player/Sources/zmedia_player/MediaPlayerManager.swift';

  String read(String path) {
    final f = File(path);
    expect(f.existsSync(), isTrue,
        reason: 'missing $path (cwd ${Directory.current.path})');
    return f
        .readAsStringSync()
        .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
        .replaceAll(RegExp(r'//.*'), '');
  }

  /// Body of the first function whose signature starts at [signature],
  /// found by brace matching.
  String body(String src, String signature) {
    final start = src.indexOf(signature);
    expect(start, isNonNegative, reason: 'missing `$signature`');
    final open = src.indexOf('{', start);
    var depth = 0;
    for (var i = open; i < src.length; i++) {
      if (src[i] == '{') depth++;
      if (src[i] == '}') {
        depth--;
        if (depth == 0) return src.substring(open, i + 1);
      }
    }
    fail('unbalanced braces after `$signature`');
  }

  test('iOS initializePlayer disposes an existing instance before replacing',
      () {
    final b = body(read(iosPath), 'func initializePlayer(');
    final dispose = b.indexOf('existing.dispose()');
    final assign = b.indexOf('players[playerId] = playerInstance');
    expect(dispose, isNonNegative, reason: 'no dispose of the old instance');
    expect(assign, isNonNegative);
    expect(dispose, lessThan(assign),
        reason: 'the old instance must be disposed before it is replaced');
  });

  test('Android disposeExistingPlayer removes and disposes the old instance',
      () {
    final b = body(read(androidPath), 'private fun disposeExistingPlayer(');
    expect(b.contains('players.remove(playerId)?.dispose()'), isTrue);
  });

  test(
      'Android initializePlayer disposes first in BOTH the main and posted '
      'branches', () {
    final src = read(androidPath);
    final b = body(src, 'fun initializePlayer(');
    final calls = 'disposeExistingPlayer(playerId)'.allMatches(b).length;
    expect(calls, 2, reason: 'synchronous branch and mainHandler.post branch');
    // Each branch must dispose before it constructs.
    final segments = b.split('MediaPlayerInstance(');
    expect(segments.length, 3);
    for (var i = 0; i < 2; i++) {
      expect(segments[i].contains('disposeExistingPlayer(playerId)'), isTrue,
          reason: 'branch ${i + 1} constructs before disposing');
    }
  });

  test(
      'Android disposePlayer runs synchronously on the main looper and its '
      'posted path only disposes the captured instance', () {
    final b = body(read(androidPath), 'fun disposePlayer(');
    expect(b.contains('Looper.myLooper() == Looper.getMainLooper()'), isTrue,
        reason: 'must not always post: a posted dispose runs after a '
            'synchronous initialize for the same id and kills the replacement');
    final sync = b.substring(0, b.indexOf('mainHandler.post'));
    expect(sync.contains('players.remove(playerId)?.dispose()'), isTrue);
    final posted = b.substring(b.indexOf('mainHandler.post'));
    expect(
        posted.contains('val captured') || b.contains('val captured'), isTrue);
    expect(posted.contains('players[playerId] === captured'), isTrue,
        reason: 'the posted path needs an identity check');
  });

  test('Android dispose() (shutdown) is synchronous on the main looper', () {
    final b = body(read(androidPath), 'fun dispose()');
    expect(b.contains('Looper.myLooper() == Looper.getMainLooper()'), isTrue);
  });
}
