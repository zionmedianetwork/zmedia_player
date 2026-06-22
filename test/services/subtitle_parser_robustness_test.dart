import 'package:flutter_test/flutter_test.dart';
import 'package:zmedia_player/src/services/subtitle_service.dart';
import 'package:zmedia_player/src/models/subtitle_track.dart';

/// Real-world corpus tests for subtitle parser robustness (Fix 1).
///
/// Covers:
///   - Windows CRLF (\r\n) in SRT, WebVTT, and ASS files.
///   - WebVTT cue identifiers (text IDs before the timestamp line).
///   - WebVTT STYLE and NOTE block skipping.
///   - ASS Dialogue lines whose text field contains commas.
///   - ASS centisecond timing (H:MM:SS.cc format).
void main() {
  // ---------------------------------------------------------------------------
  // Helpers — expose private parsers via _parseSubtitleContent through the
  // public loadSubtitleTrack + in-memory cache injection trick, OR call the
  // service indirectly via a helper that bypasses the HTTP layer.
  //
  // The simplest approach for unit-testing the parsers in isolation is to
  // sub-class SubtitleService and expose the parse method, OR use the
  // createSampleSubtitles pattern.  Because SubtitleService is not abstract
  // and _parseSubtitleContent is private, we test through the public API by
  // pre-populating the cache with parsed results via a thin test subclass.
  // ---------------------------------------------------------------------------

  late _TestableSubtitleService service;

  setUp(() {
    service = _TestableSubtitleService();
  });

  // ============================================================
  // SRT — Windows CRLF
  // ============================================================
  group('SRT parser', () {
    test('parses Unix-style SRT correctly (sanity check)', () {
      const srt = '1\n'
          '00:00:01,000 --> 00:00:03,500\n'
          'Hello world\n'
          '\n'
          '2\n'
          '00:00:04,000 --> 00:00:06,000\n'
          'Second line\n';

      final cues = service.parseSrt(srt);
      expect(cues, hasLength(2));
      expect(cues[0].text, 'Hello world');
      expect(cues[0].startTime, const Duration(seconds: 1));
      expect(cues[0].endTime, const Duration(seconds: 3, milliseconds: 500));
      expect(cues[1].text, 'Second line');
    });

    test('parses Windows CRLF SRT — cue count correct', () {
      // Real Windows SRT: every line ending is \r\n.
      const srt = '1\r\n'
          '00:00:01,000 --> 00:00:03,500\r\n'
          'Hello world\r\n'
          '\r\n'
          '2\r\n'
          '00:00:04,000 --> 00:00:06,000\r\n'
          'Second cue\r\n'
          '\r\n'
          '3\r\n'
          '00:00:07,100 --> 00:00:09,200\r\n'
          'Third cue\r\n';

      final cues = service.parseSrt(srt);
      expect(cues, hasLength(3),
          reason: 'CRLF must not collapse all blocks into one');
    });

    test('parses Windows CRLF SRT — timing is correct', () {
      const srt = '1\r\n'
          '00:00:05,250 --> 00:00:08,750\r\n'
          'Timing test\r\n';

      final cues = service.parseSrt(srt);
      expect(cues, hasLength(1));
      expect(cues[0].startTime, const Duration(seconds: 5, milliseconds: 250));
      expect(cues[0].endTime, const Duration(seconds: 8, milliseconds: 750));
    });

    test('parses Windows CRLF SRT — text is intact (no trailing \\r)', () {
      const srt = '1\r\n'
          '00:00:01,000 --> 00:00:03,000\r\n'
          'No trailing CR here\r\n';

      final cues = service.parseSrt(srt);
      expect(cues, hasLength(1));
      // Text must not end with \r.
      expect(cues[0].text, isNot(contains('\r')));
      expect(cues[0].text, 'No trailing CR here');
    });

    test('multi-line cue text is preserved', () {
      const srt = '1\n'
          '00:00:01,000 --> 00:00:04,000\n'
          'Line one\n'
          'Line two\n';

      final cues = service.parseSrt(srt);
      expect(cues, hasLength(1));
      expect(cues[0].text, 'Line one\nLine two');
    });
  });

  // ============================================================
  // WebVTT
  // ============================================================
  group('WebVTT parser', () {
    test('parses simple WebVTT without cue IDs', () {
      const vtt = 'WEBVTT\n'
          '\n'
          '00:00:01.000 --> 00:00:03.000\n'
          'Hello\n'
          '\n'
          '00:00:04.000 --> 00:00:06.000\n'
          'World\n';

      final cues = service.parseWebVtt(vtt);
      expect(cues, hasLength(2));
      expect(cues[0].text, 'Hello');
      expect(cues[1].text, 'World');
    });

    test('parses WebVTT with numeric cue identifiers', () {
      const vtt = 'WEBVTT\n'
          '\n'
          '1\n'
          '00:00:01.000 --> 00:00:03.000\n'
          'Cue with ID 1\n'
          '\n'
          '2\n'
          '00:00:04.000 --> 00:00:06.000\n'
          'Cue with ID 2\n';

      final cues = service.parseWebVtt(vtt);
      expect(cues, hasLength(2),
          reason: 'Cue identifiers must not swallow the cue');
      expect(cues[0].text, 'Cue with ID 1');
      expect(cues[1].text, 'Cue with ID 2');
    });

    test('parses WebVTT with text (non-numeric) cue identifiers', () {
      const vtt = 'WEBVTT\n'
          '\n'
          'intro\n'
          '00:00:00.000 --> 00:00:02.000\n'
          'Opening line\n'
          '\n'
          'title-card\n'
          '00:00:03.000 --> 00:00:05.000\n'
          'Title card text\n';

      final cues = service.parseWebVtt(vtt);
      expect(cues, hasLength(2));
      expect(cues[0].text, 'Opening line');
      expect(cues[1].text, 'Title card text');
    });

    test('skips STYLE blocks', () {
      const vtt = 'WEBVTT\n'
          '\n'
          'STYLE\n'
          '::cue { color: yellow; }\n'
          '\n'
          '00:00:01.000 --> 00:00:03.000\n'
          'After style block\n';

      final cues = service.parseWebVtt(vtt);
      expect(cues, hasLength(1));
      expect(cues[0].text, 'After style block');
    });

    test('skips NOTE blocks', () {
      const vtt = 'WEBVTT\n'
          '\n'
          'NOTE This is a comment\n'
          '\n'
          '00:00:01.000 --> 00:00:03.000\n'
          'After note block\n'
          '\n'
          'NOTE\n'
          'Multi-line note\n'
          'still a note\n'
          '\n'
          '00:00:04.000 --> 00:00:06.000\n'
          'Second cue\n';

      final cues = service.parseWebVtt(vtt);
      expect(cues, hasLength(2));
      expect(cues[0].text, 'After note block');
      expect(cues[1].text, 'Second cue');
    });

    test('skips REGION blocks', () {
      const vtt = 'WEBVTT\n'
          '\n'
          'REGION\n'
          'id:myregion\n'
          '\n'
          '00:00:01.000 --> 00:00:03.000\n'
          'After region block\n';

      final cues = service.parseWebVtt(vtt);
      expect(cues, hasLength(1));
      expect(cues[0].text, 'After region block');
    });

    test('handles mix of cue IDs, STYLE, NOTE in production-like file', () {
      // Resembles a YouTube-exported VTT file structure.
      const vtt = 'WEBVTT\n'
          'Kind: captions\n'
          'Language: en\n'
          '\n'
          'STYLE\n'
          '::cue(b) { color: peachpuff; }\n'
          '\n'
          'NOTE\n'
          'Generated automatically.\n'
          '\n'
          '00:00:00.499 --> 00:00:02.000\n'
          'We the people\n'
          '\n'
          '1\n'
          '00:00:02.000 --> 00:00:04.000\n'
          'of the United States\n'
          '\n'
          '2\n'
          '00:00:04.000 --> 00:00:06.000\n'
          'in order to form\n';

      final cues = service.parseWebVtt(vtt);
      expect(cues, hasLength(3),
          reason:
              'Mix of bare cues and ID-prefixed cues must all parse correctly');
      expect(cues[0].text, 'We the people');
      expect(cues[1].text, 'of the United States');
      expect(cues[2].text, 'in order to form');
    });

    test('parses Windows CRLF WebVTT with cue IDs', () {
      const vtt = 'WEBVTT\r\n'
          '\r\n'
          '1\r\n'
          '00:00:01.000 --> 00:00:03.000\r\n'
          'CRLF with ID\r\n'
          '\r\n'
          '2\r\n'
          '00:00:04.000 --> 00:00:06.000\r\n'
          'Second CRLF cue\r\n';

      final cues = service.parseWebVtt(vtt);
      expect(cues, hasLength(2));
      expect(cues[0].text, isNot(contains('\r')));
      expect(cues[0].text, 'CRLF with ID');
    });

    test('timing is parsed correctly', () {
      const vtt = 'WEBVTT\n'
          '\n'
          '00:01:23.456 --> 00:01:25.789\n'
          'Timing check\n';

      final cues = service.parseWebVtt(vtt);
      expect(cues, hasLength(1));
      expect(cues[0].startTime,
          const Duration(minutes: 1, seconds: 23, milliseconds: 456));
      expect(cues[0].endTime,
          const Duration(minutes: 1, seconds: 25, milliseconds: 789));
    });
  });

  // ============================================================
  // ASS parser
  // ============================================================
  group('ASS parser', () {
    // Minimal ASS file preamble + Dialogue lines.
    const assHeader = '[Script Info]\n'
        'Title: Test\n'
        '\n'
        '[V4+ Styles]\n'
        'Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, '
        'OutlineColour, BackColour, Bold, Italic, Underline, '
        'StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, '
        'Shadow, Alignment, MarginL, MarginR, MarginV, Encoding\n'
        'Style: Default,Arial,20,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,'
        '0,0,0,0,100,100,0,0,1,2,2,2,10,10,10,1\n'
        '\n'
        '[Events]\n'
        'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, '
        'Effect, Text\n';

    test('parses basic Dialogue line', () {
      final content =
          '${assHeader}Dialogue: 0,0:00:01.00,0:00:03.00,Default,,0,0,0,,Hello ASS\n';

      final cues = service.parseAss(content);
      expect(cues, hasLength(1));
      expect(cues[0].text, 'Hello ASS');
      expect(cues[0].startTime, const Duration(seconds: 1));
      expect(cues[0].endTime, const Duration(seconds: 3));
    });

    test('dialogue text containing commas is preserved intact', () {
      final content =
          '${assHeader}Dialogue: 0,0:00:01.00,0:00:03.00,Default,,0,0,0,,'
          'Hello, world, how are you?\n';

      final cues = service.parseAss(content);
      expect(cues, hasLength(1));
      expect(cues[0].text, 'Hello, world, how are you?',
          reason: 'Commas in dialogue text must not truncate the string');
    });

    test('dialogue text with multiple commas and style tags', () {
      // ignore: prefer_interpolation_to_compose_strings
      final content =
          '${assHeader}Dialogue: 0,0:00:05.00,0:00:08.00,Default,,0,0,0,,'
          r'{\b1}Bold, italic, and {\i1}styled{\i0} text{\b0}'
          '\n';

      final cues = service.parseAss(content);
      expect(cues, hasLength(1));
      // Style tags removed, commas preserved in text.
      expect(cues[0].text, isNot(contains('{')));
      expect(cues[0].text, contains(','));
    });

    test('centiseconds: 0 cs parses to 0 ms', () {
      final content =
          '${assHeader}Dialogue: 0,0:00:01.00,0:00:03.00,Default,,0,0,0,,Zero cs\n';

      final cues = service.parseAss(content);
      expect(cues, hasLength(1));
      expect(cues[0].startTime.inMilliseconds, 1000);
      expect(cues[0].endTime.inMilliseconds, 3000);
    });

    test('centiseconds: non-zero cs are converted to milliseconds correctly',
        () {
      // 0:00:02.50 = 2 seconds + 50 cs = 2000 + 500 = 2500 ms
      // 0:00:04.25 = 4 seconds + 25 cs = 4000 + 250 = 4250 ms
      final content =
          '${assHeader}Dialogue: 0,0:00:02.50,0:00:04.25,Default,,0,0,0,,Centisecs\n';

      final cues = service.parseAss(content);
      expect(cues, hasLength(1));
      expect(cues[0].startTime.inMilliseconds, 2500,
          reason: '50 centiseconds = 500 ms');
      expect(cues[0].endTime.inMilliseconds, 4250,
          reason: '25 centiseconds = 250 ms');
    });

    test('centiseconds: 99 cs = 990 ms', () {
      // 0:00:01.99 = 1990 ms
      final content =
          '${assHeader}Dialogue: 0,0:00:01.99,0:00:03.99,Default,,0,0,0,,Max cs\n';

      final cues = service.parseAss(content);
      expect(cues, hasLength(1));
      expect(cues[0].startTime.inMilliseconds, 1990);
      expect(cues[0].endTime.inMilliseconds, 3990);
    });

    test('ignores non-Dialogue lines', () {
      final content = '$assHeader'
          'Comment: 0,0:00:01.00,0:00:03.00,Default,,0,0,0,,Not parsed\n'
          'Dialogue: 0,0:00:01.00,0:00:03.00,Default,,0,0,0,,Parsed\n';

      final cues = service.parseAss(content);
      expect(cues, hasLength(1));
      expect(cues[0].text, 'Parsed');
    });

    test('parses multiple Dialogue lines', () {
      final content = '$assHeader'
          'Dialogue: 0,0:00:01.00,0:00:03.00,Default,,0,0,0,,First\n'
          'Dialogue: 0,0:00:03.50,0:00:05.00,Default,,0,0,0,,Second\n'
          'Dialogue: 0,0:00:05.50,0:00:07.00,Default,,0,0,0,,Third\n';

      final cues = service.parseAss(content);
      expect(cues, hasLength(3));
    });

    test('parses Windows CRLF ASS file', () {
      final content =
          ('${assHeader}Dialogue: 0,0:00:01.00,0:00:03.00,Default,,0,0,0,,'
                  'CRLF ASS\r\n')
              .replaceAll('\n', '\r\n');

      final cues = service.parseAss(content);
      expect(cues, hasLength(1));
      expect(cues[0].text, isNot(contains('\r')));
      expect(cues[0].text, 'CRLF ASS');
    });
  });

  // ============================================================
  // TTML — explicit stub behaviour
  // ============================================================
  group('TTML parser (stub)', () {
    test('returns empty list for TTML content — documented stub', () {
      const ttml = '''<?xml version="1.0" encoding="UTF-8"?>
<tt xml:lang="en" xmlns="http://www.w3.org/ns/ttml">
  <body>
    <div>
      <p begin="00:00:01.000" end="00:00:03.000">Hello TTML</p>
    </div>
  </body>
</tt>''';

      final cues = service.parseTtml(ttml);
      // TTML is an unsupported stub — must return empty without throwing.
      expect(cues, isEmpty,
          reason: 'TTML is not yet implemented; empty list is the contract');
    });
  });
}

/// Thin subclass that exposes the private parser methods for unit testing
/// without requiring HTTP mocking.
class _TestableSubtitleService extends SubtitleService {
  List<SubtitleCue> parseSrt(String content) =>
      parseSubtitleContentForTest(content, SubtitleFormat.srt);

  List<SubtitleCue> parseWebVtt(String content) =>
      parseSubtitleContentForTest(content, SubtitleFormat.webvtt);

  List<SubtitleCue> parseAss(String content) =>
      parseSubtitleContentForTest(content, SubtitleFormat.ass);

  List<SubtitleCue> parseTtml(String content) =>
      parseSubtitleContentForTest(content, SubtitleFormat.ttml);
}
