/// On-device check F (#135, #138): when a load fails (HTTP 404, unresolvable host)
/// the real `MediaPlayerWidget` error overlay must not show raw native error
/// text (exception names, error domains, HTTP codes, the raw errorMessage).
/// Also (#138), on both platforms: no raw `onStateChanged` with state `ready`
/// or `playing` may arrive before the raw `onError` of a failing load (iOS used
/// to report `ready` from the player-level `AVPlayer.status`).
/// Needs a physical device and network access (the 404 case hits
/// raw.githubusercontent.com):
///
///     cd example && flutter test integration_test/check_f_test.dart -d <device-id>
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

import 'common.dart';
import 'raw_channel_spy.dart';

void main() {
  RawChannelSpy.install();

  final cases = {
    '404':
        'https://raw.githubusercontent.com/flutter/flutter/master/THIS_PATH_DOES_NOT_EXIST_404_TEST.mp4',
    'dns': 'https://this-host-does-not-exist-zmedia.invalid/video.mp4',
  };

  for (final entry in cases.entries) {
    testWidgets('F #135 error overlay ${entry.key}', (tester) async {
      final pid = 'chk_f_${entry.key}';
      final tStart = DateTime.now();
      final c = await makeController(pid);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: MediaPlayerWidget(controller: c),
          ),
        ),
      ));
      try {
        await c.load(vod('f', entry.value));
      } catch (e) {
        ev('F ${entry.key} load() threw: $e');
      }
      try {
        await c.play();
      } catch (e) {
        ev('F ${entry.key} play() threw: $e');
      }
      final ok = await waitFor(() => c.state.state == PlayerState.error,
          const Duration(seconds: 45));
      expect(ok, isTrue, reason: 'controller never reported error');
      // pump frames for the overlay's entry animation
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final raw = c.state.errorMessage;
      ev('F ${entry.key} raw controller.state.errorMessage: $raw');
      ev('F ${entry.key} controller.error: ${c.error.runtimeType} ${c.error}');
      for (final e in rawFor(pid, 'onError')) {
        ev('F ${entry.key} RAW $e');
      }
      // #138: a failing load must never look successful before its error.
      final states = rawFor(pid, 'onStateChanged', after: tStart);
      final errs = rawFor(pid, 'onError', after: tStart);
      ev('F ${entry.key} raw states: ${states.map((e) => e.map['state']).toList()}');
      expect(errs, isNotEmpty, reason: 'no raw onError received');
      final firstErr = errs.first.t;
      final early = states
          .where((e) =>
              !e.t.isAfter(firstErr) &&
              (e.map['state'] == 'ready' || e.map['state'] == 'playing'))
          .toList();
      expect(early, isEmpty,
          reason: 'ready/playing reported before onError (#138): $early');
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
          .toList();
      final rich = tester
          .widgetList<RichText>(find.byType(RichText))
          .map((t) => t.text.toPlainText())
          .toList();
      ev('F ${entry.key} Text widgets: $texts');
      ev('F ${entry.key} RichText: $rich');
      final all = [...texts, ...rich];
      final banned = <String>[
        if (raw != null && raw.isNotEmpty) raw,
        'Exception',
        'Source error',
        'ExoPlaybackException',
        'ERROR_CODE',
        'Error Code',
        'HTTP 4',
        'Unable to connect',
        'UnknownHost',
        'CoreMediaErrorDomain',
        'NSURLErrorDomain',
        "operation couldn't be completed",
        'operation couldn’t be completed',
      ];
      for (final b in banned) {
        expect(all.any((t) => t.contains(b)), isFalse,
            reason: 'found banned "$b" in $all');
      }
      expect(
          find.text(ErrorOverlay.genericMessage).evaluate().isNotEmpty ||
              all.any((t) => t.isNotEmpty),
          isTrue);
      c.dispose();
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}
