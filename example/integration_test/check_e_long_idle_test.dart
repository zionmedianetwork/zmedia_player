/// On-device check E (#133): a paused player must survive 21 minutes idle (past
/// the 15-minute stale-instance reaper) and resume playing. Opt-in because it
/// takes over 21 minutes; skipped unless ZMP_LONG_IDLE=true:
///
///     cd example && flutter test integration_test/check_e_long_idle_test.dart \
///       -d <device-id> --dart-define=ZMP_LONG_IDLE=true
///
/// Keep the device awake and the app foregrounded for the duration. Needs
/// network access.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

import 'common.dart';
import 'raw_channel_spy.dart';

const _longIdle = bool.fromEnvironment('ZMP_LONG_IDLE');

void main() {
  RawChannelSpy.install();

  testWidgets('E #133 paused player survives 21 min idle', (tester) async {
    const pid = 'chk_e';
    final lifecycle = AppLifecycleListener(
        onStateChange: (s) => ev(
            'E LIFECYCLE ${DateTime.now().toIso8601String().substring(11, 23)} $s'));
    addTearDown(lifecycle.dispose);
    final c = await makeController(pid);
    await c.load(vod('bbb', longUrl));
    await c.play();
    expect(
        await waitFor(
            () =>
                c.state.state == PlayerState.playing &&
                c.state.position > const Duration(seconds: 3),
            const Duration(seconds: 40)),
        isTrue);
    await delay(const Duration(seconds: 2));
    await c.pause();
    expect(
        await waitFor(() => c.state.state == PlayerState.paused,
            const Duration(seconds: 5)),
        isTrue);
    ev('E paused at ${c.state.position} ${DateTime.now()}');
    for (var m = 1; m <= 21; m++) {
      await delay(const Duration(minutes: 1));
      ev('E idle minute $m dart state=${c.state.state} pos=${c.state.position}');
    }
    final t0 = DateTime.now();
    final posBefore = c.state.position;
    ev('E calling play() at $t0 posBefore=$posBefore');
    await c.play();
    final sawPlaying = await waitFor(
        () => rawFor(pid, 'onStateChanged', after: t0)
            .any((e) => e.map['state'] == 'playing'),
        const Duration(seconds: 10));
    await delay(const Duration(seconds: 5));
    final posAfter = c.state.position;
    final raws = rawFor(pid, 'onPositionChanged', after: t0);
    ev('E raw playing seen=$sawPlaying posAfter=$posAfter (advance=${posAfter - posBefore}) raw position events since play: ${raws.length}');
    dump(pid, after: t0, methods: {'onStateChanged', 'onError'});
    for (final e in raws.take(3)) {
      ev('   $e');
    }
    for (final e in raws.skip(raws.length > 3 ? raws.length - 2 : 0)) {
      ev('   $e');
    }
    expect(sawPlaying, isTrue);
    expect((posAfter - posBefore) > const Duration(seconds: 2), isTrue);
    c.dispose();
  }, skip: !_longIdle, timeout: const Timeout(Duration(minutes: 35)));
}
