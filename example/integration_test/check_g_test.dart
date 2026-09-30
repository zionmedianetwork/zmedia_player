/// On-device check G (#139): disposing a controller while its load is still in
/// flight must tear the native player down, so a recovery loop (dispose the
/// still-loading controller, create a replacement) leaves exactly one native
/// player per playerId.
///
/// Before the fix `MediaPlayer.dispose()` sent no native `dispose` while
/// `initialize()` was awaiting native, and the queued `load()` went on to
/// load and play a player with no Dart owner (audio stacking on iOS). Raw
/// native events are asserted on, because the Dart-side instance is gone and
/// cannot mask or reveal anything.
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

void main() {
  RawChannelSpy.install();

  testWidgets('G1 #139 dispose during an in-flight live load leaves no player',
      (tester) async {
    const pid = 'chk_g1';
    final c = MediaController.create(
      playerId: pid,
      config: const MediaConfig(autoPlay: true),
    );
    // No await on initialize/load: dispose lands while native is still
    // answering `initialize` / the load is still queued behind it.
    unawaited(c
        .load(const MediaItem(
          id: 'live',
          title: 'live',
          url: liveUrl,
          isLive: true,
        ))
        .catchError((Object e) => ev('G1 load ended with $e')));
    c.dispose();
    final t0 = DateTime.now();

    // An orphaned native player would now load and start playing on its own.
    await delay(const Duration(seconds: 12));
    final events = rawFor(pid, 'onStateChanged', after: t0);
    dump(pid, after: t0);
    ev('G1 raw state events after dispose: ${events.length}');
    expect(events.any((e) => e.map['state'] == 'playing'), isFalse,
        reason: 'native player kept running after its controller was disposed');
    expect(rawFor(pid, 'onPositionChanged', after: t0), isEmpty,
        reason: 'orphaned native player is still reporting position');
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets(
      'G2 #139 replacing a still-loading controller with the same playerId '
      'leaves one player', (tester) async {
    const pid = 'chk_g2';
    final old = MediaController.create(
      playerId: pid,
      config: const MediaConfig(autoPlay: true),
    );
    unawaited(old
        .load(vod('old', longUrl))
        .catchError((Object e) => ev('G2 old load ended with $e')));
    // The recovery loop: release the controller that has not finished
    // loading, then build its replacement on the same id.
    await old.release();

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
