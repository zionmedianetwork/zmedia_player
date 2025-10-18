import 'dart:convert';
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
        // Check if it's a real URL (not a placeholder)
        if (track.url!.startsWith('http') &&
            !track.url!.contains('example.com')) {
          // Load from URL
          cues = await _loadFromUrl(track.url!, track.format);
        } else {
          // This is a placeholder URL, return empty cues
          cues = [];
        }
      } else {
        // No URL provided, return empty cues
        cues = [];
      }

      // Cache the parsed subtitles
      _subtitleCache[track.id] = cues;

      return cues;
    } catch (e) {
      // If loading fails, return empty cues instead of throwing
      print('Warning: Failed to load subtitle track ${track.id}: $e');
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

      // Log the track change for debugging
      print(
          'Subtitle track changed to: ${track.title} (${content.length} cues)');
    } catch (e) {
      // If setting track fails, still set the track but with empty content
      print('Warning: Failed to set subtitle track ${track.id}: $e');
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
    switch (format) {
      case SubtitleFormat.srt:
        return _parseSrt(content);
      case SubtitleFormat.webvtt:
        return _parseWebVtt(content);
      case SubtitleFormat.ass:
        return _parseAss(content);
      case SubtitleFormat.ssa:
        return _parseSsa(content);
      case SubtitleFormat.ttml:
        return _parseTtml(content);
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
        // Skip index number
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

  /// Parse WebVTT format
  List<SubtitleCue> _parseWebVtt(String content) {
    final cues = <SubtitleCue>[];
    final lines = content.split('\n');

    int i = 0;
    while (i < lines.length) {
      // Skip WebVTT header
      if (lines[i].startsWith('WEBVTT')) {
        i++;
        continue;
      }

      // Skip empty lines and notes
      if (lines[i].isEmpty || lines[i].startsWith('NOTE')) {
        i++;
        continue;
      }

      // Parse timestamp line
      if (i + 1 < lines.length) {
        final timeMatch =
            RegExp(r'(\d{2}:\d{2}:\d{2}\.\d{3}) --> (\d{2}:\d{2}:\d{2}\.\d{3})')
                .firstMatch(lines[i]);
        if (timeMatch != null) {
          final startTime = _parseWebVttTime(timeMatch.group(1)!);
          final endTime = _parseWebVttTime(timeMatch.group(2)!);

          // Collect text lines
          final textLines = <String>[];
          i++;
          while (i < lines.length && lines[i].isNotEmpty) {
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
      }
      i++;
    }

    return cues;
  }

  /// Parse ASS format (basic implementation)
  List<SubtitleCue> _parseAss(String content) {
    // ASS parsing is complex, this is a basic implementation
    final cues = <SubtitleCue>[];
    final lines = content.split('\n');

    for (final line in lines) {
      if (line.startsWith('Dialogue:')) {
        try {
          final parts = line.split(',');
          if (parts.length >= 10) {
            final startTime = _parseAssTime(parts[1]);
            final endTime = _parseAssTime(parts[2]);
            final text = parts[9]
                .replaceAll(RegExp(r'\{[^}]*\}'), ''); // Remove style tags

            cues.add(SubtitleCue(
              startTime: startTime,
              endTime: endTime,
              text: text,
            ));
          }
        } catch (e) {
          continue;
        }
      }
    }

    return cues;
  }

  /// Parse SSA format (basic implementation)
  List<SubtitleCue> _parseSsa(String content) {
    // SSA parsing is similar to ASS
    return _parseAss(content);
  }

  /// Parse TTML format (basic implementation)
  List<SubtitleCue> _parseTtml(String content) {
    // TTML parsing would require XML parsing
    // This is a placeholder implementation
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

  /// Parse ASS time format (H:MM:SS.cc)
  Duration _parseAssTime(String timeStr) {
    final parts = timeStr.split(':');
    final hours = int.parse(parts[0]);
    final minutes = int.parse(parts[1]);
    final seconds = int.parse(parts[2]);

    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
    );
  }

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
