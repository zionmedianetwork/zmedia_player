// M-12 regression coverage: subtitle parsing must run off the UI isolate via
// `compute()` instead of blocking synchronously on the calling isolate.
//
// `compute()` requires a top-level (or static) entry point, since an
// instance method implicitly captures `this` and can't be sent across an
// isolate boundary. This test exercises the *actual* `compute()` dispatch
// path (via SubtitleService.parseSubtitleContentViaIsolateForTest), as
// opposed to SubtitleService.parseSubtitleContentForTest which deliberately
// bypasses `compute()` for synchronous test convenience elsewhere in the
// suite. A passing result here proves the top-level parser functions
// introduced for M-12 are genuinely isolate-safe (no captured instance
// state, and both the request and the returned `List<SubtitleCue>` survive
// serialization across the isolate boundary) — not just that they compile.

import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/zmedia_player.dart';

void main() {
  group('SubtitleService — compute()-based parsing (M-12)', () {
    late SubtitleService service;

    setUp(() {
      service = SubtitleService();
    });

    test('SRT content parsed via compute() matches the synchronous parser',
        () async {
      const srt = '1\n'
          '00:00:01,000 --> 00:00:04,000\n'
          'Hello from an isolate\n'
          '\n'
          '2\n'
          '00:00:05,500 --> 00:00:07,250\n'
          'Second cue\n';

      final viaIsolate = await service.parseSubtitleContentViaIsolateForTest(
        srt,
        SubtitleFormat.srt,
      );
      final viaSync =
          service.parseSubtitleContentForTest(srt, SubtitleFormat.srt);

      expect(viaIsolate, hasLength(2));
      expect(viaIsolate.length, viaSync.length,
          reason: 'the isolate-dispatched parser must produce the same cue '
              'count as the synchronous parser it wraps');

      for (var i = 0; i < viaIsolate.length; i++) {
        expect(viaIsolate[i].startTime, viaSync[i].startTime);
        expect(viaIsolate[i].endTime, viaSync[i].endTime);
        expect(viaIsolate[i].text, viaSync[i].text);
      }

      expect(viaIsolate[0].text, 'Hello from an isolate');
      expect(viaIsolate[0].startTime, const Duration(seconds: 1));
      expect(viaIsolate[0].endTime, const Duration(seconds: 4));
      expect(viaIsolate[1].text, 'Second cue');
    });

    test('WebVTT content parsed via compute() round-trips correctly', () async {
      const vtt = 'WEBVTT\n'
          '\n'
          '00:00:00.000 --> 00:00:02.000\n'
          'First\n'
          '\n'
          '00:00:02.000 --> 00:00:04.000\n'
          'Second\n';

      final cues = await service.parseSubtitleContentViaIsolateForTest(
        vtt,
        SubtitleFormat.webvtt,
      );

      expect(cues, hasLength(2));
      expect(cues[0].text, 'First');
      expect(cues[1].text, 'Second');
      expect(cues[1].startTime, const Duration(seconds: 2));
    });

    test('empty content parsed via compute() returns an empty list', () async {
      final cues = await service.parseSubtitleContentViaIsolateForTest(
        '',
        SubtitleFormat.srt,
      );
      expect(cues, isEmpty);
    });
  });
}
