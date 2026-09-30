/// On-device check G (#139): disposing a player while its `initialize` is in
/// flight must tear the native player down, so a recovery loop (dispose the
/// still-loading player, create a replacement) leaves exactly one native
/// player per playerId.
///
/// Before the fix `MediaPlayer.dispose()` sent no native `dispose` while
/// `initialize()` was awaiting native, and the pending `load()` went on to
/// load and play a player with no Dart owner (audio stacking on iOS). Raw
/// native events are asserted on, because the Dart-side instance is gone and
/// cannot mask or reveal anything.
///
/// Entering the race window is the hard part. `dispose()` must land AFTER the
/// native `initialize` call has been sent but BEFORE native answers. Disposing
/// synchronously after `load()` never gets there: `MediaController.load` is
/// queued (`_runQueuedOperation` awaits its predecessor, then checks
/// disposed), so the queued op drops and `initialize` is never sent; and a
/// direct `MediaPlayer.load` has not reached the channel yet either. Each test
/// therefore yields a small, varied amount of time first (0..20 ms) on distinct
/// playerIds, run concurrently, to straddle the window regardless of device
/// speed.
///
///     cd example && flutter test integration_test/check_g_test.dart -d <device-id>
///
/// Needs network access.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

import 'common.dart';
import 'raw_channel_spy.dart';

/// Yields before disposing, in milliseconds. 0 means one event-loop turn.
const _delaysMs = [0, 1, 2, 3, 5, 8, 12, 20];

const _live = MediaItem(id: 'live', title: 'live', url: liveUrl, isLive: true);

Future<void> _yield(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

/// Asserts no raw playing/position event arrived for any of [pids] after the
/// matching entry of [disposedAt].
void _expectNoOrphans(String label, Map<String, DateTime> disposedAt) {
  final orphans = <String>[];
  disposedAt.forEach((pid, t0) {
    final states = rawFor(pid, 'onStateChanged', after: t0);
    final positions = rawFor(pid, 'onPositionChanged', after: t0);
    final playing = states.any((e) => e.map['state'] == 'playing');
    ev('$label $pid: state events=${states.length} playing=$playing '
        'position events=${positions.length}');
    if (playing || positions.isNotEmpty) {
      orphans.add(pid);
      dump(pid, after: t0, methods: {'onStateChanged', 'onPositionChanged'});
    }
  });
  expect(orphans, isEmpty,
      reason: 'native player kept running after its owner was disposed '
          '(orphans: $orphans)');
}

void main() {
  RawChannelSpy.install();

  testWidgets(
      'G1 #139 MediaPlayer disposed while initialize is in flight leaves no '
      'player', (tester) async {
    final disposedAt = <String, DateTime>{};
    await Future.wait([
      for (final ms in _delaysMs)
        () async {
          final pid = 'chk_g1_${ms}ms';
          final p = MediaPlayer(
            playerId: pid,
            config: const MediaConfig(autoPlay: true),
          );
          unawaited(p
              .load(_live)
              .catchError((Object e) => ev('G1 $pid load ended with $e')));
          await _yield(ms);
          await p.dispose();
          disposedAt[pid] = DateTime.now();
        }(),
    ]);
    // An orphaned native player would now load and start playing on its own.
    await delay(const Duration(seconds: 12));
    _expectNoOrphans('G1', disposedAt);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets(
      'G1b #139 MediaController disposed while its load is in flight leaves '
      'no player', (tester) async {
    final disposedAt = <String, DateTime>{};
    await Future.wait([
      for (final ms in _delaysMs)
        () async {
          final pid = 'chk_g1b_${ms}ms';
          final c = MediaController.create(
            playerId: pid,
            config: const MediaConfig(autoPlay: true),
          );
          unawaited(c
              .load(_live)
              .catchError((Object e) => ev('G1b $pid load ended with $e')));
          await _yield(ms);
          c.dispose();
          disposedAt[pid] = DateTime.now();
        }(),
    ]);
    await delay(const Duration(seconds: 12));
    _expectNoOrphans('G1b', disposedAt);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets(
      'G2 #139 replacing a still-initializing player with the same playerId '
      'leaves one player', (tester) async {
    const pid = 'chk_g2';
    final old = MediaPlayer(
      playerId: pid,
      config: const MediaConfig(autoPlay: true),
    );
    unawaited(old
        .load(vod('old', longUrl))
        .catchError((Object e) => ev('G2 old load ended with $e')));
    // Enter the window: `initialize` sent, native not yet answered.
    await _yield(2);
    // The recovery loop: dispose the player that has not finished
    // initializing, then build its replacement on the same id.
    await old.dispose();

    final c = await makeController(pid);
    await c.load(vod('new', longUrl));
    await c.play();
    final t0 = DateTime.now();
    expect(
        await waitFor(
            () =>
                c.state.state == PlayerState.playing &&
                c.state.position > const Duration(seconds: 3),
            const Duration(seconds: 40)),
        isTrue);
    await delay(const Duration(seconds: 5));

    // Two native players behind one id would interleave their positions, so
    // the raw VOD position sequence would step backwards.
    final positions = rawFor(pid, 'onPositionChanged', after: t0)
        .map((e) => (e.map['position'] as num).toInt())
        .toList();
    ev('G2 raw position events since playing: ${positions.length}');
    var regressions = 0;
    for (var i = 1; i < positions.length; i++) {
      if (positions[i] < positions[i - 1]) regressions++;
    }
    expect(regressions, 0,
        reason: 'position went backwards: a second native player is '
            'reporting under the same playerId');
    await c.release();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
