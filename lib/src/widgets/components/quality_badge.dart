import 'package:flutter/material.dart';
import '../../models/streaming_config.dart';

/// A badge widget that displays the current video quality
///
/// Shows the resolution (e.g., "720p", "1080p", "4K") with an optional
/// "AUTO" indicator when automatic quality selection is enabled.
///
/// Features:
/// - Resolution display with customizable format
/// - Auto quality indicator
/// - Animated quality changes
/// - Customizable styling
///
/// Example usage:
/// ```dart
/// QualityBadge(
///   qualityTrack: currentQuality,
///   isAuto: true,
/// )
/// ```
class QualityBadge extends StatefulWidget {
  /// The current quality track to display
  final QualityTrack? qualityTrack;

  /// Whether auto quality is enabled
  final bool isAuto;

  /// Background color of the badge
  final Color? backgroundColor;

  /// Text color of the badge
  final Color? textColor;

  /// Border color of the badge
  final Color? borderColor;

  /// Border radius of the badge
  final double borderRadius;

  /// Padding inside the badge
  final EdgeInsets padding;

  /// Text style for the quality label
  final TextStyle? textStyle;

  /// Whether to show the "AUTO" indicator
  final bool showAutoIndicator;

  /// Duration of the quality change animation
  final Duration animationDuration;

  const QualityBadge({
    super.key,
    this.qualityTrack,
    this.isAuto = false,
    this.backgroundColor,
    this.textColor,
    this.borderColor,
    this.borderRadius = 4.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    this.textStyle,
    this.showAutoIndicator = true,
    this.animationDuration = const Duration(milliseconds: 300),
  });

  @override
  State<QualityBadge> createState() => _QualityBadgeState();
}

class _QualityBadgeState extends State<QualityBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  QualityTrack? _previousTrack;

  @override
  void initState() {
    super.initState();
    _previousTrack = widget.qualityTrack;
    _animationController = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOut,
      ),
    );
  }

  @override
  void didUpdateWidget(QualityBadge oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Trigger animation when quality changes
    if (widget.qualityTrack?.id != _previousTrack?.id) {
      _previousTrack = widget.qualityTrack;
      _animationController.forward(from: 0.0).then((_) {
        _animationController.reverse();
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  String _getQualityLabel() {
    if (widget.qualityTrack == null) {
      return '--';
    }

    final track = widget.qualityTrack!;

    // Get quality abbreviation
    if (track.height != null) {
      final height = track.height!;
      if (height >= 2160) return '4K';
      if (height >= 1440) return '2K';
      if (height >= 1080) return 'FHD';
      if (height >= 720) return 'HD';
      if (height >= 360) return 'SD';
      return '${height}p';
    }

    // Fallback to track name
    return track.name;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = widget.backgroundColor ??
        theme.colorScheme.surface.withValues(alpha: 0.9);
    final textColor = widget.textColor ?? theme.colorScheme.onSurface;
    final borderColor = widget.borderColor ?? theme.colorScheme.outline;

    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            padding: widget.padding,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(widget.borderRadius),
              border: Border.all(
                color: borderColor,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Quality label
                Text(
                  _getQualityLabel(),
                  style: widget.textStyle ??
                      theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: textColor,
                        fontSize: 11,
                      ),
                ),

                // Auto indicator
                if (widget.isAuto && widget.showAutoIndicator) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      'AUTO',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A simple quality indicator dot
///
/// Shows a colored dot that changes based on quality level
class QualityIndicatorDot extends StatelessWidget {
  /// The current quality track
  final QualityTrack? qualityTrack;

  /// Size of the indicator dot
  final double size;

  const QualityIndicatorDot({
    super.key,
    this.qualityTrack,
    this.size = 8.0,
  });

  Color _getQualityColor(BuildContext context) {
    if (qualityTrack == null) return Colors.grey;

    final height = qualityTrack!.height ?? 0;

    if (height >= 1080) {
      return Colors.green; // HD/4K
    } else if (height >= 720) {
      return Colors.lightGreen; // HD
    } else if (height >= 480) {
      return Colors.orange; // SD
    } else {
      return Colors.red; // Low quality
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _getQualityColor(context),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: _getQualityColor(context).withValues(alpha: 0.5),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}
