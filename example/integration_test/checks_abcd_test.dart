/// On-device checks A-D for the #132-#137 fixes. Needs a physical device (or
/// emulator) and network access; run with:
///
///     cd example && flutter test integration_test/checks_abcd_test.dart -d <device-id>
///
/// Each check asserts on RAW native events (see raw_channel_spy.dart), because
/// the Dart layer latches errors and updates state optimistically and could
/// hide a native regression.
///
/// - A (#132): after a natural end, native emits `completed` and no
///   trailing `paused`/`idle`; Dart stays `completed`; `play()` restarts.
/// - B (#134/#137): a seek while paused reports the new position within 3s
///   and no runaway events; state returns to `paused` (Android: last raw
///   state is `paused` with no `pauseReason`; iOS: no `ready`). A load that
///   was never played reports `ready`, not `paused`.
/// - C (#134): the same paused seek on a live DVR stream (external live demo;
///   skipped, not failed, if the stream cannot be loaded or never plays).
/// - D (#133): play/pause/seekTo for an unknown playerId throw
///   `PlatformException` instead of silently succeeding.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

import 'common.dart';
import 'raw_channel_spy.dart';

void main() {
  RawChannelSpy.install();

  testWidgets('A #132 completed persists', (tester) async {
    const pid = 'chk_a';
    final c = await makeController(pid);
    await c.load(vod('bee', shortUrl));
    await c.play();
    final ok = await waitFor(() => c.state.state == PlayerState.completed,
        const Duration(seconds: 60));
    ev('A reached completed=$ok state=${c.state.state}');
    expect(ok, isTrue);
    final rawCompleted = rawFor(pid, 'onStateChanged')
        .where((e) => e.map['state'] == 'completed')
        .toList();
    expect(rawCompleted, isNotEmpty, reason: 'no raw completed');
    final tc = rawCompleted.first.t;
    await delay(const Duration(seconds: 5));
    final after = rawFor(pid, 'onStateChanged', after: tc);
    ev('A raw onStateChanged from first completed onward:');
    for (final e in after) {
      ev('   $e');
    }
    final bad = after
        .where((e) => e.map['state'] == 'paused' || e.map['state'] == 'idle')
        .toList();
    ev('A native paused/idle after completed: ${bad.length}');
    ev('A dart state after 5s: ${c.state.state}');
    expect(bad, isEmpty);
    expect(c.state.state, PlayerState.completed);

    final tp = DateTime.now();
    await c.play();
    final playing = await waitFor(() => c.state.state == PlayerState.playing,
        const Duration(seconds: 10));
    await delay(const Duration(seconds: 1));
    ev('A replay playing=$playing position=${c.state.position}');
    final rawPos = rawFor(pid, 'onPositionChanged', after: tp);
    for (final e in rawPos.take(4)) {
      ev('   $e');
    }
    dump(pid, after: tp, methods: {'onStateChanged'});
    expect(playing, isTrue);
    expect(c.state.position < const Duration(seconds: 3), isTrue);
    c.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('B #134 VOD paused seek', (tester) async {
    const pid = 'chk_b';
    final c = await makeController(pid);
    final tl = DateTime.now();
    await c.load(vod('bbb', longUrl));
    // #137: right after load, never played -> ready (not paused).
    final gotReady = await waitFor(
        () => c.state.state == PlayerState.ready, const Duration(seconds: 20));
    ev('B #137 raw states after load: ${rawFor(pid, 'onStateChanged', after: tl).map((e) => e.map['state']).toList()}');
    expect(gotReady, isTrue, reason: 'first ready after load must stay ready');
    await c.play();
    expect(
        await waitFor(
            () =>
                c.state.state == PlayerState.playing &&
                c.state.position > const Duration(seconds: 1),
            const Duration(seconds: 30)),
        isTrue);
    await c.pause();
    expect(
        await waitFor(() => c.state.state == PlayerState.paused,
            const Duration(seconds: 5)),
        isTrue);
    await delay(const Duration(seconds: 1));

    for (final target in [30, 10]) {
      final t0 = DateTime.now();
      await c.seekTo(Duration(seconds: target));
      // raw event within 3s
      final got = await waitFor(() {
        return rawFor(pid, 'onPositionChanged', after: t0).any(
            (e) => ((e.map['position'] as int) - target * 1000).abs() <= 1500);
      }, const Duration(seconds: 3));
      final t1 = DateTime.now();
      await delay(const Duration(seconds: 4));
      final all = rawFor(pid, 'onPositionChanged', after: t0);
      ev('B target=${target}s raw position events after seek (${all.length}):');
      for (final e in all) {
        ev('   $e');
      }
      final matching = all.firstWhere(
          (e) => ((e.map['position'] as int) - target * 1000).abs() <= 1500,
          orElse: () => RawEvent(t0, 'none', {}));
      ev('B target=${target}s raw match latency: ${matching.t.difference(t0).inMilliseconds}ms; dart position=${c.state.position} state=${c.state.state}');
      final later = rawFor(pid, 'onPositionChanged', after: t1);
      ev('B target=${target}s raw events in 4s window after first match window: ${later.length}');
      expect(got, isTrue, reason: 'raw native position ~${target}s not seen');
      expect((c.state.position.inMilliseconds - target * 1000).abs() <= 1500,
          isTrue);
      expect(later.length, lessThanOrEqualTo(2));
      final st = rawFor(pid, 'onStateChanged', after: t0);
      ev('B #137 raw states after paused seek to ${target}s: ${st.map((e) => "${e.map['state']}(reason=${e.map['pauseReason']})").toList()}');
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        expect(st.any((e) => e.map['state'] == 'ready'), isFalse);
      } else {
        expect(st.isNotEmpty, isTrue);
        expect(st.last.map['state'], 'paused');
        expect(st.last.map['pauseReason'], isNull);
        expect(st.any((e) => e.map['state'] == 'ready'), isFalse);
      }
      expect(c.state.state, PlayerState.paused);
    }
    c.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('C #134 live DVR paused seek', (tester) async {
    const pid = 'chk_c';
    final c = await makeController(pid,
        config: const MediaConfig(hlsConfig: HlsConfig(enableDvr: true)));
    try {
      await c.load(const MediaItem(
          id: 'live', title: 'live', url: liveUrl, isLive: true));
      await c.play();
    } catch (e) {
      ev('C SKIP load failed: $e');
      return;
    }
    final flowing = await waitFor(
        () =>
            rawFor(pid, 'onPositionChanged').length >= 3 &&
            c.state.state == PlayerState.playing,
        const Duration(seconds: 40));
    if (!flowing) {
      ev('C SKIP stream not playing: state=${c.state.state} err=${c.state.errorMessage}');
      dump(pid);
      return;
    }
    await delay(const Duration(seconds: 25));
    await c.pause();
    await waitFor(
        () => c.state.state == PlayerState.paused, const Duration(seconds: 5));
    await delay(const Duration(seconds: 1));
    final before = c.state.position;
    final dur = c.state.duration;
    ev('C before seek position=$before duration=$dur basis=${c.state.positionBasis} liveEdgeOffset=${c.state.liveEdgeOffset} seekable=${c.player.isSeekable}');
    final target = before - const Duration(seconds: 18);
    final tgt = target < Duration.zero ? Duration.zero : target;
    final t0 = DateTime.now();
    await c.seekTo(tgt);
    await delay(const Duration(seconds: 3));
    final raw = rawFor(pid, 'onPositionChanged', after: t0);
    ev('C target=$tgt raw events after seek (${raw.length}):');
    for (final e in raw) {
      ev('   $e');
    }
    ev('C after seek dart position=${c.state.position}');
    expect(raw, isNotEmpty);
    expect(c.state.position, isNot(before));
    expect((c.state.position - tgt).inMilliseconds.abs() < 3000, isTrue);
    c.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('D #133 unknown player fails loudly', (tester) async {
    const ch = MethodChannel('zmedia_player');
    final args = <String, Map<String, dynamic>>{
      'play': {'playerId': 'no-such-player'},
      'pause': {'playerId': 'no-such-player'},
      'seekTo': {'playerId': 'no-such-player', 'position': 1000},
    };
    for (final m in args.keys) {
      try {
        final r = await ch.invokeMethod(m, args[m]);
        ev('D $m returned success: $r');
        fail('$m did not throw');
      } on PlatformException catch (e) {
        ev('D $m threw PlatformException code=${e.code} message=${e.message}');
      }
    }
  });
}
