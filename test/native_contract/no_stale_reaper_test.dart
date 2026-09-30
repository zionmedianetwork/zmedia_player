import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Issue #133 drift guard.
///
/// Both natives used to run a periodic "stale instance" reaper that disposed
/// any non-playing player idle for 15 minutes -- including a paused player
/// still on screen -- and told Dart nothing. Afterwards Android's commands were
/// silent `?.` no-ops and iOS threw `playerNotFound` with no event. Nothing
/// compiled is shared across Dart/Kotlin/Swift and native has no automated
/// tests, so parsing the sources as text is the only thing that stops the
/// reaper (or the silent no-op) from coming back. Same technique as
/// `pause_reason_vocabulary_test.dart`.
void main() {
  const androidPath =
      'android/src/main/kotlin/com/zionmedianetwork/zmedia_player/MediaPlayerManager.kt';
  const iosPath =
      'ios/zmedia_player/Sources/zmedia_player/MediaPlayerManager.swift';

  String read(String path) {
    final f = File(path);
    expect(f.existsSync(), isTrue,
        reason: 'missing $path (cwd ${Directory.current.path})');
    return f.readAsStringSync();
  }

  // Strip comments so the explanatory notes about the removed reaper don't
  // trip the identifier checks.
  String code(String s) => s
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .replaceAll(RegExp(r'//.*'), '');

  final forbidden = <String>[
    'cleanupStaleInstances',
    'STALE_THRESHOLD',
    'staleThreshold',
    'CLEANUP_INTERVAL',
    'cleanupInterval',
    'cleanupTimer',
    'cleanupRunnable',
    'lastActivity',
    'markActivity',
  ];

  test('Android has no time-based stale-instance reaper', () {
    final src = code(read(androidPath));
    for (final id in forbidden) {
      expect(src.contains(id), isFalse, reason: 'Android reintroduced `$id`');
    }
  });

  test('iOS has no time-based stale-instance reaper', () {
    final src = code(read(iosPath));
    for (final id in forbidden) {
      expect(src.contains(id), isFalse, reason: 'iOS reintroduced `$id`');
    }
  });

  test('Android commands fail loudly on a missing player (no silent no-op)',
      () {
    final src = code(read(androidPath));
    expect(src.contains('fun requirePlayer'), isTrue);
    expect(src, contains('throw IllegalStateException'));

    // Every command that goes through the main-thread post must validate the
    // id synchronously first, so the plugin handler can return an error.
    const commands = [
      'loadMediaItem',
      'setPlaylist',
      'play',
      'pause',
      'stop',
      'seekTo',
      'setVolume',
      'setPlaybackSpeed',
      'setMuted',
      'setBoxFit',
      'setSubtitleTrack',
      'setQualityTrack',
      'setAudioTrack',
      'enableAutoQuality',
      'skipToIndex',
      'updateConfig',
    ];
    for (final c in commands) {
      final m = RegExp(r'    fun ' + c + r'\([^{]*\{\n((?:.*\n){0,2})')
          .firstMatch(src);
      expect(m, isNotNull, reason: 'could not find Android fun $c');
      expect(m!.group(1), contains('requirePlayer(playerId)'),
          reason: 'Android `$c` must call requirePlayer(playerId) first');
    }
  });
}
