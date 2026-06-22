import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/subtitle_track.dart';

/// Service for managing subtitle tracks and content
class SubtitleService {
  /// Cache for parsed subtitle data
  final Map<String, List<SubtitleCue>> _subtitleCache = {};

  /// Currently active subtitle track
  SubtitleTrack? _activeTrack;

  /// Subtitle content for active track
  List<SubtitleCue>? _activeContent;

  /// Get the currently active subtitle track
  SubtitleTrack? get activeTrack => _activeTrack;

  /// Get the currently active subtitle content
  List<SubtitleCue>? get activeContent => _activeContent;

  /// Load and parse subtitle track
  Future<List<SubtitleCue>> loadSubtitleTrack(SubtitleTrack track) async {
    // Check cache first
    if (_subtitleCache.containsKey(track.id)) {
      return _subtitleCache[track.id]!;
    }

    try {
      List<SubtitleCue> cues;

      if (track.url != null && track.url!.isNotEmpty) {
        // Load from any non-empty URL.
        cues = await _loadFromUrl(track.url!, track.format);
      } else {
        // No URL provided, return empty cues
        cues = [];
      }

      // Cache the parsed subtitles
      _subtitleCache[track.id] = cues;

      return cues;
    } catch (e) {
      // If loading fails, return empty cues instead of throwing
      // Warning: Failed to load subtitle track ${track.id}: $e
      return [];
    }
  }

  /// Set active subtitle track
  Future<void> setActiveTrack(SubtitleTrack track) async {
    if (_activeTrack?.id == track.id) return;

    try {
      final content = await loadSubtitleTrack(track);
      _activeTrack = track;
      _activeContent = content;

      // Subtitle track changed to: ${track.title} (${content.length} cues)
    } catch (e) {
      // If setting track fails, still set the track but with empty content
      // Warning: Failed to set subtitle track ${track.id}: $e
      _activeTrack = track;
      _activeContent = [];
    }
  }

  /// Get subtitle cue at specific time
  SubtitleCue? getCueAtTime(Duration position) {
    if (_activeContent == null) return null;

    // Binary search for the appropriate cue
    int left = 0;
    int right = _activeContent!.length - 1;

    while (left <= right) {
      int mid = (left + right) ~/ 2;
      final cue = _activeContent![mid];

      if (position >= cue.startTime && position <= cue.endTime) {
        return cue;
      } else if (position < cue.startTime) {
        right = mid - 1;
      } else {
        left = mid + 1;
      }
    }

    return null;
  }

  /// Get all subtitle cues
  List<SubtitleCue> getAllCues() {
    return _activeContent ?? [];
  }

  /// Clear subtitle cache
  void clearCache() {
    _subtitleCache.clear();
  }

  /// Remove specific subtitle from cache
  void removeFromCache(String trackId) {
    _subtitleCache.remove(trackId);
  }

  /// Load subtitle from URL
  Future<List<SubtitleCue>> _loadFromUrl(
      String url, SubtitleFormat format) async {
    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final content = utf8.decode(response.bodyBytes);
        return _parseSubtitleContent(content, format);
      } else {
        throw SubtitleException(
            'HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }
    } catch (e) {
      throw SubtitleException('Failed to load subtitle from URL: $e');
    }
  }

  /// Parse subtitle content based on format
  List<SubtitleCue> _parseSubtitleContent(
      String content, SubtitleFormat format) {
    // Normalise line endings once so all parsers receive Unix-style '\n'.
    // This handles Windows CRLF (\r\n) and bare CR (\r) files.
    final normalised = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    switch (format) {
      case SubtitleFormat.srt:
        return _parseSrt(normalised);
      case SubtitleFormat.webvtt:
        return _parseWebVtt(normalised);
      case SubtitleFormat.ass:
        return _parseAss(normalised);
      case SubtitleFormat.ssa:
        return _parseSsa(normalised);
      case SubtitleFormat.ttml:
        return _parseTtml(normalised);
    }
  }

  /// Parse SRT format
  List<SubtitleCue> _parseSrt(String content) {
    final cues = <SubtitleCue>[];
    final blocks = content.trim().split('\n\n');

    for (final block in blocks) {
      final lines = block.split('\n');
      if (lines.length < 3) continue;

      try {
        // Skip index number (lines[0])
        final timeLine = lines[1];
        final textLines = lines.skip(2).toList();

        final timeMatch =
            RegExp(r'(\d{2}:\d{2}:\d{2},\d{3}) --> (\d{2}:\d{2}:\d{2},\d{3})')
                .firstMatch(timeLine);
        if (timeMatch == null) continue;

        final startTime = _parseSrtTime(timeMatch.group(1)!);
        final endTime = _parseSrtTime(timeMatch.group(2)!);
        final text = textLines.join('\n');

        cues.add(SubtitleCue(
          startTime: startTime,
          endTime: endTime,
          text: text,
        ));
      } catch (e) {
        // Skip malformed blocks
        continue;
      }
    }

    return cues;
  }

  // Regex that matches a WebVTT timestamp line (optional cue settings after
  // the arrow are ignored).
  static final _webVttTimestampRegex = RegExp(
    r'^(\d{2}:\d{2}:\d{2}\.\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2}\.\d{3})',
  );

  // Block-level keywords that introduce non-cue sections to skip.
  static final _webVttBlockKeywords = RegExp(r'^(NOTE|REGION|STYLE)\b');

  /// Parse WebVTT format
  ///
  /// Handles:
  /// - Optional cue identifier lines before the timestamp.
  /// - NOTE, REGION, and STYLE blocks (skipped until next blank line).
  /// - WEBVTT header line (and optional header block separated by blank line).
  List<SubtitleCue> _parseWebVtt(String content) {
    final cues = <SubtitleCue>[];
    final lines = content.split('\n');
    final int total = lines.length;

    int i = 0;

    // Skip the mandatory WEBVTT header line and any header block that follows
    // (separated from the first cue by a blank line).
    if (i < total && lines[i].startsWith('WEBVTT')) {
      i++;
      // Skip rest of header block (until blank line).
      while (i < total && lines[i].isNotEmpty) {
        i++;
      }
    }

    while (i < total) {
      final line = lines[i];

      // Blank line: separator between blocks, advance and continue.
      if (line.isEmpty) {
        i++;
        continue;
      }

      // Block keywords (NOTE / REGION / STYLE): skip entire block.
      if (_webVttBlockKeywords.hasMatch(line)) {
        i++;
        while (i < total && lines[i].isNotEmpty) {
          i++;
        }
        continue;
      }

      // Check whether the current line is a timestamp.
      var timestampLine = line;
      var timestampMatch = _webVttTimestampRegex.firstMatch(timestampLine);

      if (timestampMatch == null) {
        // This line is a cue identifier; the timestamp must be on the next line.
        i++;
        if (i >= total) break;
        timestampLine = lines[i];
        timestampMatch = _webVttTimestampRegex.firstMatch(timestampLine);
        if (timestampMatch == null) {
          // Still no timestamp — malformed block; skip.
          i++;
          continue;
        }
      }

      // We have a valid timestamp.
      final startTime = _parseWebVttTime(timestampMatch.group(1)!);
      final endTime = _parseWebVttTime(timestampMatch.group(2)!);
      i++;

      // Collect cue payload lines (until blank line or end of file).
      final textLines = <String>[];
      while (i < total && lines[i].isNotEmpty) {
        textLines.add(lines[i]);
        i++;
      }

      if (textLines.isNotEmpty) {
        cues.add(SubtitleCue(
          startTime: startTime,
          endTime: endTime,
          text: textLines.join('\n'),
        ));
      }
    }

    return cues;
  }

  /// Parse ASS format (basic implementation)
  ///
  /// Fixes applied:
  /// - Uses sublist(9).join(',') so dialogue text containing commas is
  ///   preserved intact (ASS Dialogue has exactly 9 fixed fields before Text).
  /// - _parseAssTime correctly handles centiseconds (H:MM:SS.cc format).
  List<SubtitleCue> _parseAss(String content) {
    final cues = <SubtitleCue>[];
    final lines = content.split('\n');

    for (final line in lines) {
      if (!line.startsWith('Dialogue:')) continue;
      try {
        final parts = line.split(',');
        // ASS Dialogue: Layer, Start, End, Style, Name, MarginL, MarginR,
        //               MarginV, Effect, Text (index 0–9; Text is index 9+)
        if (parts.length < 10) continue;
        final startTime = _parseAssTime(parts[1].trim());
        final endTime = _parseAssTime(parts[2].trim());
        // Rejoin everything from index 9 onward to preserve commas in text.
        final rawText = parts.sublist(9).join(',');
        final text = rawText.replaceAll(RegExp(r'\{[^}]*\}'), '').trim();

        cues.add(SubtitleCue(
          startTime: startTime,
          endTime: endTime,
          text: text,
        ));
      } catch (e) {
        continue;
      }
    }

    return cues;
  }

  /// Parse SSA format (basic implementation — same Dialogue line structure)
  List<SubtitleCue> _parseSsa(String content) {
    return _parseAss(content);
  }

  /// Parse TTML format
  ///
  /// TTML requires XML parsing.  The `dart:xml` (or any XML) package is not
  /// currently a dependency of this package.  Rather than silently returning
  /// empty cues (which could mask integration issues), this method explicitly
  /// documents the limitation and returns an empty list.
  ///
  /// To add TTML support, add an XML parser dependency (e.g. `xml: ^6.x`) and
  /// parse `p` elements with `begin`/`end` attributes from the `body` section.
  List<SubtitleCue> _parseTtml(String content) {
    // TTML (Timed Text Markup Language) support is not yet implemented.
    // Parsing TTML requires an XML parser dependency that is not present in
    // this package.  The method intentionally returns an empty list.
    return [];
  }

  /// Parse SRT time format (HH:MM:SS,mmm)
  Duration _parseSrtTime(String timeStr) {
    final parts = timeStr.split(',');
    final timeParts = parts[0].split(':');
    final hours = int.parse(timeParts[0]);
    final minutes = int.parse(timeParts[1]);
    final seconds = int.parse(timeParts[2]);
    final milliseconds = int.parse(parts[1]);

    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: milliseconds,
    );
  }

  /// Parse WebVTT time format (HH:MM:SS.mmm)
  Duration _parseWebVttTime(String timeStr) {
    final parts = timeStr.split('.');
    final timeParts = parts[0].split(':');
    final hours = int.parse(timeParts[0]);
    final minutes = int.parse(timeParts[1]);
    final seconds = int.parse(timeParts[2]);
    final milliseconds = int.parse(parts[1]);

    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: milliseconds,
    );
  }

  /// Parse ASS/SSA time format (H:MM:SS.cc)
  ///
  /// The centiseconds component (cc) is two digits representing hundredths of
  /// a second.  Previously `int.parse("SS.cc")` would throw; now the seconds
  /// field is split on '.' to extract seconds and centiseconds separately.
  Duration _parseAssTime(String timeStr) {
    final colonParts = timeStr.split(':');
    final hours = int.parse(colonParts[0]);
    final minutes = int.parse(colonParts[1]);
    // colonParts[2] is "SS.cc"
    final secParts = colonParts[2].split('.');
    final seconds = int.parse(secParts[0]);
    // centiseconds → milliseconds (* 10)
    final centiseconds = secParts.length > 1 ? int.parse(secParts[1]) : 0;

    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: centiseconds * 10,
    );
  }

  /// Exposes [_parseSubtitleContent] for unit testing.
  ///
  /// This method is intentionally kept out of the public API.  Use it only
  /// from test files; production code should rely on [loadSubtitleTrack].
  @visibleForTesting
  List<SubtitleCue> parseSubtitleContentForTest(
          String content, SubtitleFormat format) =>
      _parseSubtitleContent(content, format);

  /// Dispose the service
  void dispose() {
    clearCache();
    _activeTrack = null;
    _activeContent = null;
  }

  /// Create sample subtitle content for demonstration
  List<SubtitleCue> createSampleSubtitles() {
    return [
      SubtitleCue(
        startTime: const Duration(seconds: 0),
        endTime: const Duration(seconds: 3),
        text: 'Welcome to Flutter Media Player',
      ),
      SubtitleCue(
        startTime: const Duration(seconds: 3),
        endTime: const Duration(seconds: 6),
        text: 'This is a sample subtitle track',
      ),
      SubtitleCue(
        startTime: const Duration(seconds: 6),
        endTime: const Duration(seconds: 9),
        text: 'Demonstrating subtitle functionality',
      ),
      SubtitleCue(
        startTime: const Duration(seconds: 9),
        endTime: const Duration(seconds: 12),
        text: 'Phase 2: Streaming & Subtitles',
      ),
    ];
  }
}

/// Represents a subtitle cue
class SubtitleCue {
  /// Start time of the subtitle
  final Duration startTime;

  /// End time of the subtitle
  final Duration endTime;

  /// Subtitle text content
  final String text;

  /// Additional styling information
  final Map<String, dynamic>? styling;

  const SubtitleCue({
    required this.startTime,
    required this.endTime,
    required this.text,
    this.styling,
  });

  /// Duration of the subtitle display
  Duration get duration => endTime - startTime;

  /// Check if a time falls within this cue
  bool containsTime(Duration time) {
    return time >= startTime && time <= endTime;
  }

  @override
  String toString() {
    return 'SubtitleCue(${startTime.inMilliseconds}ms - ${endTime.inMilliseconds}ms: $text)';
  }
}

/// Subtitle exception
class SubtitleException implements Exception {
  final String message;

  const SubtitleException(this.message);

  @override
  String toString() => 'SubtitleException: $message';
}
