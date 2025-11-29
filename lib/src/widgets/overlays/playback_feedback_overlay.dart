import 'package:flutter/material.dart';
import 'feedback_overlay.dart';

/// Speed change feedback overlay
///
/// Displays visual feedback when playback speed changes with:
/// - Speed icon
/// - Speed value (0.5x, 1.0x, 1.25x, etc.)
/// - Optional descriptive label
/// - Auto-dismiss after duration
///
/// Example usage:
/// ```dart
/// SpeedChangeOverlay(
///   speed: 1.5,
///   show: true,
/// )
/// ```
class SpeedChangeOverlay extends StatelessWidget {
  /// Current playback speed
  final double speed;

  /// Whether to show the overlay
  final bool show;

  /// How long to display the overlay
  final Duration duration;

  /// Whether to show descriptive label (e.g., "Fast", "Normal")
  final bool showLabel;

  /// Icon color
  final Color? iconColor;

  /// Text color
  final Color? textColor;

  /// Background color of overlay
  final Color? backgroundColor;

  /// Callback when overlay is dismissed
  final VoidCallback? onDismiss;

  const SpeedChangeOverlay({
    super.key,
    required this.speed,
    this.show = true,
    this.duration = const Duration(milliseconds: 1500),
    this.showLabel = true,
    this.iconColor,
    this.textColor,
    this.backgroundColor,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = this.iconColor ?? theme.colorScheme.onSurface;
    final textColor = this.textColor ?? theme.colorScheme.onSurface;

    return FeedbackOverlay(
      show: show,
      duration: duration,
      backgroundColor: backgroundColor,
      onDismiss: onDismiss,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Speed icon
          Icon(
            Icons.speed,
            size: 48,
            color: iconColor,
          ),

          const SizedBox(height: 16),

          // Speed value
          Text(
            '${speed.toStringAsFixed(2)}x',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: textColor,
              fontWeight: FontWeight.bold,
            ),
          ),

          // Descriptive label
          if (showLabel) ...[
            const SizedBox(height: 8),
            Text(
              _getSpeedLabel(),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: textColor.withValues(alpha: 0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _getSpeedLabel() {
    if (speed <= 0.5) {
      return 'Slowest';
    } else if (speed < 0.75) {
      return 'Slower';
    } else if (speed < 1.0) {
      return 'Slow';
    } else if (speed == 1.0) {
      return 'Normal';
    } else if (speed <= 1.25) {
      return 'Fast';
    } else if (speed <= 1.5) {
      return 'Faster';
    } else {
      return 'Fastest';
    }
  }
}

/// Quality change feedback overlay
///
/// Displays visual feedback when video quality changes with:
/// - Quality icon (HD, 4K, etc.)
/// - Quality label (720p, 1080p, 4K, etc.)
/// - Optional transition indicator (upgrading/downgrading)
/// - Auto-dismiss after duration
///
/// Example usage:
/// ```dart
/// QualityChangeOverlay(
///   quality: '1080p',
///   previousQuality: '720p',
///   show: true,
/// )
/// ```
class QualityChangeOverlay extends StatelessWidget {
  /// Current quality label
  final String quality;

  /// Previous quality (optional, for transition display)
  final String? previousQuality;

  /// Whether to show the overlay
  final bool show;

  /// How long to display the overlay
  final Duration duration;

  /// Icon color
  final Color? iconColor;

  /// Text color
  final Color? textColor;

  /// Background color of overlay
  final Color? backgroundColor;

  /// Callback when overlay is dismissed
  final VoidCallback? onDismiss;

  const QualityChangeOverlay({
    super.key,
    required this.quality,
    this.previousQuality,
    this.show = true,
    this.duration = const Duration(milliseconds: 1500),
    this.iconColor,
    this.textColor,
    this.backgroundColor,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = this.iconColor ?? theme.colorScheme.onSurface;
    final textColor = this.textColor ?? theme.colorScheme.onSurface;

    return FeedbackOverlay(
      show: show,
      duration: duration,
      backgroundColor: backgroundColor,
      onDismiss: onDismiss,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Quality icon
          Icon(
            _getQualityIcon(),
            size: 48,
            color: iconColor,
          ),

          const SizedBox(height: 16),

          // Quality transition or single value
          if (previousQuality != null && previousQuality != quality)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  previousQuality!,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: textColor.withValues(alpha: 0.5),
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.arrow_forward,
                  size: 24,
                  color: textColor.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 12),
                Text(
                  quality,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            )
          else
            Text(
              quality,
              style: theme.textTheme.headlineMedium?.copyWith(
                color: textColor,
                fontWeight: FontWeight.bold,
              ),
            ),

          // Quality descriptor
          const SizedBox(height: 8),
          Text(
            _getQualityDescriptor(),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: textColor.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getQualityIcon() {
    // Determine icon based on quality
    if (quality.contains('4K') || quality.contains('2160')) {
      return Icons.four_k;
    } else if (quality.contains('HD') ||
        quality.contains('1080') ||
        quality.contains('720')) {
      return Icons.hd;
    } else if (quality.contains('SD') || quality.contains('480')) {
      return Icons.sd;
    } else {
      return Icons.high_quality;
    }
  }

  String _getQualityDescriptor() {
    if (quality.contains('4K') || quality.contains('2160')) {
      return 'Ultra HD';
    } else if (quality.contains('1080')) {
      return 'Full HD';
    } else if (quality.contains('720')) {
      return 'HD';
    } else if (quality.contains('480')) {
      return 'Standard Definition';
    } else if (quality.contains('360')) {
      return 'Low Quality';
    } else {
      return quality;
    }
  }
}

/// Auto quality change notification
///
/// Displays a subtle notification when auto quality selection changes
/// the video quality based on network conditions.
///
/// Example usage:
/// ```dart
/// AutoQualityNotification(
///   quality: '720p',
///   reason: 'Network conditions',
///   show: true,
/// )
/// ```
class AutoQualityNotification extends StatelessWidget {
  /// New quality selected by auto mode
  final String quality;

  /// Reason for quality change
  final String reason;

  /// Whether to show the notification
  final bool show;

  /// How long to display the notification
  final Duration duration;

  /// Text color
  final Color? textColor;

  /// Background color of notification
  final Color? backgroundColor;

  /// Callback when notification is dismissed
  final VoidCallback? onDismiss;

  const AutoQualityNotification({
    super.key,
    required this.quality,
    required this.reason,
    this.show = true,
    this.duration = const Duration(milliseconds: 2000),
    this.textColor,
    this.backgroundColor,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = this.textColor ?? theme.colorScheme.onSurface;

    return FeedbackOverlay(
      show: show,
      duration: duration,
      backgroundColor: backgroundColor,
      alignment: Alignment.topCenter,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      onDismiss: onDismiss,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_awesome,
            size: 20,
            color: textColor,
          ),
          const SizedBox(width: 8),
          Text(
            'Auto: $quality',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '($reason)',
            style: theme.textTheme.bodySmall?.copyWith(
              color: textColor.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}
