import 'package:flutter/material.dart';
import '../../models/buffer_health.dart';

/// A badge widget that displays buffer health status
///
/// Shows visual buffer health indicators with color-coded status,
/// buffer percentage, and optional tooltip with detailed statistics.
///
/// Features:
/// - Color-coded status (green/amber/orange/red)
/// - Buffer percentage display
/// - Optional tooltip with detailed buffer stats
/// - Animated transitions between states
/// - Compact and detailed display modes
///
/// Example usage:
/// ```dart
/// BufferHealthBadge(
///   bufferHealth: currentBufferHealth,
///   showPercentage: true,
///   showTooltip: true,
/// )
/// ```
class BufferHealthBadge extends StatefulWidget {
  /// Current buffer health status
  final BufferHealth? bufferHealth;

  /// Whether to show buffer percentage
  final bool showPercentage;

  /// Whether to show tooltip with detailed stats
  final bool showTooltip;

  /// Background color of the badge (defaults to status color)
  final Color? backgroundColor;

  /// Text color of the badge
  final Color? textColor;

  /// Border radius of the badge
  final double borderRadius;

  /// Padding inside the badge
  final EdgeInsets padding;

  /// Text style for the percentage label
  final TextStyle? textStyle;

  /// Size of the status indicator dot
  final double indicatorSize;

  /// Duration of status change animation
  final Duration animationDuration;

  const BufferHealthBadge({
    super.key,
    required this.bufferHealth,
    this.showPercentage = true,
    this.showTooltip = false,
    this.backgroundColor,
    this.textColor,
    this.borderRadius = 4.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    this.textStyle,
    this.indicatorSize = 8.0,
    this.animationDuration = const Duration(milliseconds: 300),
  });

  @override
  State<BufferHealthBadge> createState() => _BufferHealthBadgeState();
}

class _BufferHealthBadgeState extends State<BufferHealthBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  BufferStatus? _previousStatus;

  @override
  void initState() {
    super.initState();
    _previousStatus = widget.bufferHealth?.status;
    _animationController = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOut,
      ),
    );
  }

  @override
  void didUpdateWidget(BufferHealthBadge oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Trigger animation when status changes
    if (widget.bufferHealth?.status != _previousStatus) {
      _previousStatus = widget.bufferHealth?.status;
      _animationController.forward(from: 0.0).then((_) {
        if (mounted) {
          _animationController.reverse();
        }
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Color _getStatusColor() {
    final status = widget.bufferHealth?.status ?? BufferStatus.healthy;
    switch (status) {
      case BufferStatus.healthy:
        return const Color(0xFF4CAF50); // Green
      case BufferStatus.warning:
        return const Color(0xFFFFC107); // Amber
      case BufferStatus.critical:
        return const Color(0xFFFF9800); // Orange
      case BufferStatus.underrun:
        return const Color(0xFFF44336); // Red
    }
  }

  String _getStatusLabel() {
    final status = widget.bufferHealth?.status ?? BufferStatus.healthy;
    switch (status) {
      case BufferStatus.healthy:
        return 'Healthy';
      case BufferStatus.warning:
        return 'Low';
      case BufferStatus.critical:
        return 'Critical';
      case BufferStatus.underrun:
        return 'Empty';
    }
  }

  String _getPercentageDisplay() {
    if (widget.bufferHealth == null) return '--';

    final ratio = widget.bufferHealth!.bufferRatio;
    final percentage = (ratio * 100).clamp(0, 999);
    return '${percentage.toInt()}%';
  }

  String _getTooltipMessage() {
    if (widget.bufferHealth == null) {
      return 'Buffer status unavailable';
    }

    final health = widget.bufferHealth!;
    final bufferedSec = (health.bufferedDurationMs / 1000).toStringAsFixed(1);
    final ratio = (health.bufferRatio * 100).toStringAsFixed(0);

    final lines = [
      'Buffer Health: ${_getStatusLabel()}',
      'Buffered: ${bufferedSec}s',
      'Ratio: $ratio%',
    ];

    if (health.currentDownloadSpeed != null) {
      final speedMbps =
          (health.currentDownloadSpeed! * 8 / 1000000).toStringAsFixed(2);
      lines.add('Speed: $speedMbps Mbps');
    }

    if (health.warning != null) {
      lines.add('Warning: ${health.warning}');
    }

    if (health.estimatedTimeToUnderrun != null) {
      final timeToUnderrun =
          health.estimatedTimeToUnderrun!.inSeconds.toStringAsFixed(0);
      lines.add('Time to underrun: ${timeToUnderrun}s');
    }

    return lines.join('\n');
  }

  Widget _buildBadge(BuildContext context) {
    if (widget.bufferHealth == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final statusColor = _getStatusColor();
    final backgroundColor =
        widget.backgroundColor ?? statusColor.withValues(alpha: 0.15);
    final textColor = widget.textColor ?? statusColor;

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
                color: statusColor.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Status indicator dot
                Container(
                  width: widget.indicatorSize,
                  height: widget.indicatorSize,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: statusColor.withValues(alpha: 0.4),
                        blurRadius: 3,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),

                // Buffer percentage (if enabled)
                if (widget.showPercentage) ...[
                  const SizedBox(width: 4),
                  Text(
                    _getPercentageDisplay(),
                    style: widget.textStyle ??
                        theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: textColor,
                          fontSize: 11,
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

  @override
  Widget build(BuildContext context) {
    if (widget.bufferHealth == null) {
      return const SizedBox.shrink();
    }

    final badge = _buildBadge(context);

    if (!widget.showTooltip) {
      return badge;
    }

    return Tooltip(
      message: _getTooltipMessage(),
      preferBelow: false,
      verticalOffset: 8,
      padding: const EdgeInsets.all(12),
      textStyle: const TextStyle(
        fontSize: 12,
        color: Colors.white,
        height: 1.4,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: badge,
    );
  }
}

/// A compact buffer health indicator (dot only, no text)
///
/// Shows just a color-coded dot for minimal UI footprint
class BufferHealthIndicator extends StatelessWidget {
  /// Current buffer health status
  final BufferHealth? bufferHealth;

  /// Size of the indicator dot
  final double size;

  /// Whether to show pulsing animation for problematic statuses
  final bool showPulse;

  const BufferHealthIndicator({
    super.key,
    required this.bufferHealth,
    this.size = 8.0,
    this.showPulse = true,
  });

  Color _getStatusColor() {
    final status = bufferHealth?.status ?? BufferStatus.healthy;
    switch (status) {
      case BufferStatus.healthy:
        return const Color(0xFF4CAF50); // Green
      case BufferStatus.warning:
        return const Color(0xFFFFC107); // Amber
      case BufferStatus.critical:
        return const Color(0xFFFF9800); // Orange
      case BufferStatus.underrun:
        return const Color(0xFFF44336); // Red
    }
  }

  bool _shouldPulse() {
    if (!showPulse || bufferHealth == null) return false;
    return bufferHealth!.status.isProblematic;
  }

  @override
  Widget build(BuildContext context) {
    if (bufferHealth == null) {
      return const SizedBox.shrink();
    }

    final color = _getStatusColor();

    if (_shouldPulse()) {
      return _PulsingDot(color: color, size: size);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 3,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

/// Internal widget for pulsing dot animation
class _PulsingDot extends StatefulWidget {
  final Color color;
  final double size;

  const _PulsingDot({
    required this.color,
    required this.size,
  });

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
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
                  alpha: _animation.value * 0.6,
                ),
                blurRadius: 4 * _animation.value,
                spreadRadius: 2 * _animation.value,
              ),
            ],
          ),
        );
      },
    );
  }
}
