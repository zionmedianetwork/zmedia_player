import 'package:flutter/material.dart';
import 'feedback_overlay.dart';

/// Seek feedback overlay
///
/// Displays visual feedback when seeking forward/backward with:
/// - Direction arrows (forward/backward)
/// - Seek amount (±10s, ±30s, etc.)
/// - Optional timestamp display
/// - Auto-dismiss after duration
///
/// Example usage:
/// ```dart
/// SeekFeedbackOverlay(
///   seekAmount: Duration(seconds: 10),
///   direction: SeekDirection.forward,
///   show: true,
/// )
/// ```
class SeekFeedbackOverlay extends StatelessWidget {
  /// Amount of time being seeked
  final Duration seekAmount;

  /// Direction of seek
  final SeekDirection direction;

  /// Whether to show the overlay
  final bool show;

  /// How long to display the overlay
  final Duration duration;

  /// Optional current position after seek
  final Duration? currentPosition;

  /// Icon color
  final Color? iconColor;

  /// Text color
  final Color? textColor;

  /// Background color of overlay
  final Color? backgroundColor;

  /// Callback when overlay is dismissed
  final VoidCallback? onDismiss;

  const SeekFeedbackOverlay({
    super.key,
    required this.seekAmount,
    required this.direction,
    this.show = true,
    this.duration = const Duration(milliseconds: 1200),
    this.currentPosition,
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
          // Direction icon with seek amount
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                direction == SeekDirection.forward
                    ? Icons.fast_forward
                    : Icons.fast_rewind,
                size: 40,
                color: iconColor,
              ),
              const SizedBox(width: 12),
              Text(
                _formatSeekAmount(),
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: textColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          // Current position (if provided)
          if (currentPosition != null) ...[
            const SizedBox(height: 8),
            Text(
              _formatDuration(currentPosition!),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: textColor.withValues(alpha: 0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatSeekAmount() {
    final prefix = direction == SeekDirection.forward ? '+' : '-';
    final seconds = seekAmount.inSeconds;

    if (seconds < 60) {
      return '$prefix${seconds}s';
    } else {
      final minutes = seconds ~/ 60;
      final remainingSeconds = seconds % 60;
      if (remainingSeconds == 0) {
        return '$prefix${minutes}m';
      }
      return '$prefix${minutes}m ${remainingSeconds}s';
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '$minutes:${seconds.toString().padLeft(2, '0')}';
    }
  }
}

/// Direction of seek operation
enum SeekDirection {
  /// Seeking forward in time
  forward,

  /// Seeking backward in time
  backward,
}

/// Double-tap seek feedback overlay
///
/// Specialized overlay for double-tap to seek interactions,
/// showing animated ripples in the direction of seek.
///
/// Example usage:
/// ```dart
/// DoubleTapSeekOverlay(
///   seekAmount: Duration(seconds: 10),
///   direction: SeekDirection.forward,
///   side: SeekSide.right, // Double-tapped on right side
///   show: true,
/// )
/// ```
class DoubleTapSeekOverlay extends StatelessWidget {
  /// Amount of time being seeked
  final Duration seekAmount;

  /// Direction of seek
  final SeekDirection direction;

  /// Side of screen that was double-tapped
  final SeekSide side;

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

  const DoubleTapSeekOverlay({
    super.key,
    required this.seekAmount,
    required this.direction,
    required this.side,
    this.show = true,
    this.duration = const Duration(milliseconds: 1200),
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

    // Position overlay on the side that was tapped
    final alignment =
        side == SeekSide.left ? Alignment.centerLeft : Alignment.centerRight;

    return FeedbackOverlay(
      show: show,
      duration: duration,
      backgroundColor: backgroundColor ?? Colors.transparent,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      onDismiss: onDismiss,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Animated ripples
          _AnimatedRipples(
            direction: direction,
            color: iconColor,
          ),

          const SizedBox(height: 12),

          // Seek amount
          Text(
            _formatSeekAmount(),
            style: theme.textTheme.titleLarge?.copyWith(
              color: textColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  String _formatSeekAmount() {
    final seconds = seekAmount.inSeconds;
    return '$seconds seconds';
  }
}

/// Side of screen for double-tap seek
enum SeekSide {
  /// Left side of screen
  left,

  /// Right side of screen
  right,
}

/// Animated ripples for double-tap seek feedback
class _AnimatedRipples extends StatefulWidget {
  final SeekDirection direction;
  final Color color;

  const _AnimatedRipples({
    required this.direction,
    required this.color,
  });

  @override
  State<_AnimatedRipples> createState() => _AnimatedRipplesState();
}

class _AnimatedRipplesState extends State<_AnimatedRipples>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Multiple animated triangles/arrows
          for (var i = 0; i < 3; i++)
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final delay = i * 0.15;
                final progress = (_controller.value - delay).clamp(0.0, 1.0);
                final opacity = (1.0 - progress).clamp(0.0, 1.0);

                return Opacity(
                  opacity: opacity * 0.8,
                  child: Transform.translate(
                    offset: Offset(
                      (widget.direction == SeekDirection.forward ? 1 : -1) *
                          progress *
                          20,
                      0,
                    ),
                    child: Icon(
                      widget.direction == SeekDirection.forward
                          ? Icons.play_arrow
                          : Icons.keyboard_arrow_left,
                      size: 40,
                      color: widget.color,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
