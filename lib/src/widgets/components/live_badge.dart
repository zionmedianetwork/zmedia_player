import 'package:flutter/material.dart';

/// A badge widget that displays a LIVE indicator for live streaming content
///
/// Shows a pulsing red dot with "LIVE" text when content is being streamed live.
/// Optionally displays DVR availability and current latency information.
///
/// Features:
/// - Pulsing red dot animation
/// - LIVE text label
/// - Optional DVR available indicator
/// - Optional latency display
/// - Customizable styling and colors
///
/// Example usage:
/// ```dart
/// LiveBadge(
///   isLive: true,
///   dvrAvailable: true,
///   latency: Duration(seconds: 3),
/// )
/// ```
class LiveBadge extends StatefulWidget {
  /// Whether the content is currently live
  final bool isLive;

  /// Whether DVR (Digital Video Recording/seeking in live content) is available
  final bool dvrAvailable;

  /// Current latency behind live edge (optional)
  final Duration? latency;

  /// Whether to show DVR indicator
  final bool showDvrIndicator;

  /// Whether to show latency information
  final bool showLatency;

  /// Background color of the badge
  final Color? backgroundColor;

  /// Text color of the badge
  final Color? textColor;

  /// Color of the pulsing live indicator dot
  final Color liveIndicatorColor;

  /// Border radius of the badge
  final double borderRadius;

  /// Padding inside the badge
  final EdgeInsets padding;

  /// Text style for the LIVE label
  final TextStyle? textStyle;

  /// Duration of the pulsing animation
  final Duration pulseDuration;

  const LiveBadge({
    super.key,
    required this.isLive,
    this.dvrAvailable = false,
    this.latency,
    this.showDvrIndicator = true,
    this.showLatency = false,
    this.backgroundColor,
    this.textColor,
    this.liveIndicatorColor = Colors.red,
    this.borderRadius = 4.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    this.textStyle,
    this.pulseDuration = const Duration(milliseconds: 1000),
  });

  @override
  State<LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<LiveBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(
      vsync: this,
      duration: widget.pulseDuration,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _formatLatency() {
    if (widget.latency == null) return '';

    final seconds = widget.latency!.inSeconds;
    if (seconds < 60) {
      return '${seconds}s';
    } else {
      final minutes = seconds ~/ 60;
      final remainingSeconds = seconds % 60;
      return '${minutes}m ${remainingSeconds}s';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isLive) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final backgroundColor = widget.backgroundColor ??
        theme.colorScheme.surface.withValues(alpha: 0.95);
    final textColor = widget.textColor ?? theme.colorScheme.onSurface;

    return Container(
      padding: widget.padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pulsing live indicator dot
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: widget.liveIndicatorColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: widget.liveIndicatorColor.withValues(
                        alpha: _pulseAnimation.value * 0.8,
                      ),
                      blurRadius: 4 * _pulseAnimation.value,
                      spreadRadius: 2 * _pulseAnimation.value,
                    ),
                  ],
                ),
              );
            },
          ),

          const SizedBox(width: 6),

          // LIVE text
          Text(
            'LIVE',
            style: widget.textStyle ??
                theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: textColor,
                  fontSize: 11,
                  letterSpacing: 0.5,
                ),
          ),

          // DVR indicator
          if (widget.dvrAvailable && widget.showDvrIndicator) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color:
                    theme.colorScheme.primaryContainer.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.access_time,
                    size: 10,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    'DVR',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Latency display
          if (widget.latency != null && widget.showLatency) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color:
                    theme.colorScheme.secondaryContainer.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                _formatLatency(),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A compact live indicator dot only (no text)
///
/// Shows just a pulsing red dot for minimal UI footprint
class LiveIndicatorDot extends StatefulWidget {
  /// Whether the content is currently live
  final bool isLive;

  /// Color of the pulsing live indicator dot
  final Color color;

  /// Size of the indicator dot
  final double size;

  /// Duration of the pulsing animation
  final Duration pulseDuration;

  const LiveIndicatorDot({
    super.key,
    required this.isLive,
    this.color = Colors.red,
    this.size = 8.0,
    this.pulseDuration = const Duration(milliseconds: 1000),
  });

  @override
  State<LiveIndicatorDot> createState() => _LiveIndicatorDotState();
}

class _LiveIndicatorDotState extends State<LiveIndicatorDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(
      vsync: this,
      duration: widget.pulseDuration,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isLive) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(
                  alpha: _pulseAnimation.value * 0.8,
                ),
                blurRadius: 4 * _pulseAnimation.value,
                spreadRadius: 2 * _pulseAnimation.value,
              ),
            ],
          ),
        );
      },
    );
  }
}
