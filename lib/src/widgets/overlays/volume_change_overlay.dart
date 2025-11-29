import 'package:flutter/material.dart';
import 'feedback_overlay.dart';

/// Volume change feedback overlay
///
/// Displays visual feedback when volume changes with:
/// - Volume icon (muted/low/medium/high)
/// - Volume percentage or bars
/// - Auto-dismiss after duration
///
/// Example usage:
/// ```dart
/// VolumeChangeOverlay(
///   volume: 0.75, // 75%
///   show: true,
/// )
/// ```
class VolumeChangeOverlay extends StatelessWidget {
  /// Current volume level (0.0 to 1.0)
  final double volume;

  /// Whether to show the overlay
  final bool show;

  /// How long to display the overlay
  final Duration duration;

  /// Display style (percentage or bars)
  final VolumeDisplayStyle displayStyle;

  /// Icon color
  final Color? iconColor;

  /// Text color for percentage
  final Color? textColor;

  /// Background color of overlay
  final Color? backgroundColor;

  /// Callback when overlay is dismissed
  final VoidCallback? onDismiss;

  const VolumeChangeOverlay({
    super.key,
    required this.volume,
    this.show = true,
    this.duration = const Duration(milliseconds: 1500),
    this.displayStyle = VolumeDisplayStyle.percentage,
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
          // Volume icon
          Icon(
            _getVolumeIcon(),
            size: 48,
            color: iconColor,
          ),

          const SizedBox(height: 16),

          // Volume display (percentage or bars)
          if (displayStyle == VolumeDisplayStyle.percentage)
            Text(
              '${(volume * 100).round()}%',
              style: theme.textTheme.headlineMedium?.copyWith(
                color: textColor,
                fontWeight: FontWeight.bold,
              ),
            )
          else
            _VolumeBars(
              volume: volume,
              color: iconColor,
            ),
        ],
      ),
    );
  }

  IconData _getVolumeIcon() {
    if (volume == 0.0) {
      return Icons.volume_off;
    } else if (volume < 0.33) {
      return Icons.volume_mute;
    } else if (volume < 0.66) {
      return Icons.volume_down;
    } else {
      return Icons.volume_up;
    }
  }
}

/// Display style for volume overlay
enum VolumeDisplayStyle {
  /// Show volume as percentage (e.g., "75%")
  percentage,

  /// Show volume as bars
  bars,
}

/// Volume bars widget for visual volume indication
class _VolumeBars extends StatelessWidget {
  final double volume;
  final Color color;

  const _VolumeBars({
    required this.volume,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    const barCount = 10;
    final filledBars = (volume * barCount).round();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(barCount, (index) {
        final isFilled = index < filledBars;
        final barHeight = 8.0 + (index * 3.0); // Progressive height

        return Container(
          width: 6,
          height: barHeight,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: isFilled ? color : color.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}

/// Brightness change feedback overlay (similar to volume)
///
/// Displays visual feedback when screen brightness changes with:
/// - Brightness icon (low/medium/high)
/// - Brightness percentage
/// - Auto-dismiss after duration
///
/// Example usage:
/// ```dart
/// BrightnessChangeOverlay(
///   brightness: 0.5, // 50%
///   show: true,
/// )
/// ```
class BrightnessChangeOverlay extends StatelessWidget {
  /// Current brightness level (0.0 to 1.0)
  final double brightness;

  /// Whether to show the overlay
  final bool show;

  /// How long to display the overlay
  final Duration duration;

  /// Icon color
  final Color? iconColor;

  /// Text color for percentage
  final Color? textColor;

  /// Background color of overlay
  final Color? backgroundColor;

  /// Callback when overlay is dismissed
  final VoidCallback? onDismiss;

  const BrightnessChangeOverlay({
    super.key,
    required this.brightness,
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
          // Brightness icon
          Icon(
            _getBrightnessIcon(),
            size: 48,
            color: iconColor,
          ),

          const SizedBox(height: 16),

          // Brightness percentage
          Text(
            '${(brightness * 100).round()}%',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: textColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getBrightnessIcon() {
    if (brightness < 0.33) {
      return Icons.brightness_low;
    } else if (brightness < 0.66) {
      return Icons.brightness_medium;
    } else {
      return Icons.brightness_high;
    }
  }
}
