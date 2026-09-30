import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart' show addTearDown;
import 'package:zmedia_player/zmedia_player.dart';

import 'raw_channel_spy.dart';

// External dependencies: these are public sample URLs the suite does not
// control. A check that cannot reach its stream should say so rather than fail
// silently (check C skips gracefully when the live demo is unreachable).

/// Short (~14s) clip; used to reach a natural end quickly.
const shortUrl =
    'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4';

/// Long VOD, for seeking and idling.
const longUrl =
    'https://storage.googleapis.com/exoplayer-test-media-0/BigBuckBunny_320x180.mp4';

/// Unified Streaming live demo (HLS).
const liveUrl =
    'https://demo.unified-streaming.com/k8s/live/stable/live.isml/.m3u8';

/// Emits an evidence line. `EVID:` lines are the suite's human-readable
/// output; grep a run log for them to review what each check observed.
void ev(String s) => debugPrint('EVID: $s');

String _now() => DateTime.now().toIso8601String().substring(11, 23);

/// Polls [cond] every [step] until true or [timeout]; returns the final value.
Future<bool> waitFor(
  bool Function() cond,
  Duration timeout, {
  Duration step = const Duration(milliseconds: 50),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (cond()) return true;
    await Future<void>.delayed(step);
  }
  return cond();
}

Future<void> delay(Duration d) => Future<void>.delayed(d);

/// Raw native events named [method] for player [pid], optionally only those at
/// or after [after].
List<RawEvent> rawFor(String pid, String method, {DateTime? after}) => rawEvents
    .where(
      (e) =>
          e.method == method &&
          e.map['playerId'] == pid &&
          (after == null || !e.t.isBefore(after)),
    )
    .toList();

/// Logs raw events for [pid] as evidence, optionally filtered.
void dump(String pid, {DateTime? after, Set<String>? methods}) {
  for (final e in rawEvents) {
    if (e.map['playerId'] != pid) continue;
    if (after != null && e.t.isBefore(after)) continue;
    if (methods != null && !methods.contains(e.method)) continue;
    ev('  RAW $e');
  }
}

/// Creates and initializes a controller with evidence logging of Dart-side
/// state and error streams; on teardown logs the raw native timeline.
Future<MediaController> makeController(
  String pid, {
  MediaConfig? config,
}) async {
  final c = MediaController.create(
    playerId: pid,
    config: config ?? const MediaConfig(),
  );
  await c.initialize();
  PlayerState? lastState;
  c.player.stateStream.listen((st) {
    if (st.state != lastState) {
      lastState = st.state;
      ev(
        'DART ${_now()} state=${st.state} pos=${st.position} '
        'err=${st.errorMessage}',
      );
    }
  });
  c.errorStream.listen(
    (e) => ev('DART ${_now()} errorStream: ${e.runtimeType} $e'),
  );
  addTearDown(() {
    ev('--- $pid raw timeline (state/error/duration) ---');
    dump(pid, methods: {'onStateChanged', 'onError', 'onDurationChanged'});
    final p = rawFor(pid, 'onPositionChanged');
    ev(
      '--- $pid position events: ${p.length}; '
      'first=${p.isEmpty ? null : p.first} last=${p.isEmpty ? null : p.last}',
    );
  });
  return c;
}

MediaItem vod(String id, String url) => MediaItem(id: id, title: id, url: url);
