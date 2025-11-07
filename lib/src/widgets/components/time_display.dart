import 'package:flutter/material.dart';

/// Display format for time
enum TimeDisplayFormat {
  /// Shows current/total time (e.g., "1:23 / 5:00")
  currentAndTotal,

  /// Shows remaining time (e.g., "-3:37")
  remaining,

  /// Shows only current time (e.g., "1:23")
  currentOnly,

  /// Shows only total duration (e.g., "5:00")
  totalOnly,
}

/// A customizable time display component for media players
///
/// Displays playback time in various formats with support for:
/// - Current position and total duration
/// - Remaining time display
/// - Live stream indicator
/// - Customizable separators and styling
/// - Accessibility support
///
/// Example usage:
/// ```dart
/// TimeDisplay(
///   position: Duration(seconds: 83),
///   duration: Duration(seconds: 300),
///   format: TimeDisplayFormat.currentAndTotal,
/// )
/// ```
class TimeDisplay extends StatelessWidget {
  /// Current playback position
  final Duration position;

  /// Total media duration
  final Duration? duration;

  /// Display format
  final TimeDisplayFormat format;

  /// Whether this is a live stream
  final bool isLive;

  /// Text style for the time display
  final TextStyle? style;

  /// Separator between current and total time (default: " / ")
  final String separator;

  /// Color for the live indicator
  final Color? liveColor;

  /// Text to display for live streams (default: "LIVE")
  final String liveText;

  const TimeDisplay({
    super.key,
    required this.position,
    this.duration,
    this.format = TimeDisplayFormat.currentAndTotal,
    this.isLive = false,
    this.style,
    this.separator = ' / ',
    this.liveColor,
    this.liveText = 'LIVE',
  });

  @override
  Widget build(BuildContext context) {
    if (isLive) {
      return _buildLiveIndicator(context);
    }

    final textStyle = style ??
        const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        );

    String displayText;
    switch (format) {
      case TimeDisplayFormat.currentAndTotal:
        displayText =
            '${formatDuration(position)}$separator${formatDuration(duration ?? Duration.zero)}';
        break;
      case TimeDisplayFormat.remaining:
        final remaining = (duration ?? Duration.zero) - position;
        displayText = '-${formatDuration(remaining)}';
        break;
      case TimeDisplayFormat.currentOnly:
        displayText = formatDuration(position);
        break;
      case TimeDisplayFormat.totalOnly:
        displayText = formatDuration(duration ?? Duration.zero);
        break;
    }

    return Text(
      displayText,
      style: textStyle,
      semanticsLabel: _getAccessibilityLabel(),
    );
  }

  Widget _buildLiveIndicator(BuildContext context) {
    final color = liveColor ?? Colors.red;
    final textStyle = style ??
        const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          liveText,
          style: textStyle.copyWith(color: color),
          semanticsLabel: 'Live broadcast',
        ),
      ],
    );
  }

  String _getAccessibilityLabel() {
    if (isLive) {
      return 'Live broadcast';
    }

    switch (format) {
      case TimeDisplayFormat.currentAndTotal:
        return 'Playback time: ${formatDurationForAccessibility(position)} of ${formatDurationForAccessibility(duration ?? Duration.zero)}';
      case TimeDisplayFormat.remaining:
        final remaining = (duration ?? Duration.zero) - position;
        return '${formatDurationForAccessibility(remaining)} remaining';
      case TimeDisplayFormat.currentOnly:
        return 'Current time: ${formatDurationForAccessibility(position)}';
      case TimeDisplayFormat.totalOnly:
        return 'Total duration: ${formatDurationForAccessibility(duration ?? Duration.zero)}';
    }
  }

  /// Format duration for visual display (e.g., "1:23:45" or "12:34")
  static String formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return "$hours:${twoDigits(minutes)}:${twoDigits(seconds)}";
    }
    return "${twoDigits(minutes)}:${twoDigits(seconds)}";
  }

  /// Format duration for accessibility (e.g., "1 hour 23 minutes 45 seconds")
  static String formatDurationForAccessibility(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    final parts = <String>[];

    if (hours > 0) {
      parts.add('$hours ${hours == 1 ? "hour" : "hours"}');
    }
    if (minutes > 0) {
      parts.add('$minutes ${minutes == 1 ? "minute" : "minutes"}');
    }
    if (seconds > 0 || parts.isEmpty) {
      parts.add('$seconds ${seconds == 1 ? "second" : "seconds"}');
    }

    return parts.join(' ');
  }
}
