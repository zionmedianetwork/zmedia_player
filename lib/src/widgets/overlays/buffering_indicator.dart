import 'package:flutter/material.dart';
import '../../models/buffer_health.dart';

/// Advanced buffering indicator with buffer health visualization
///
/// Displays:
/// - Circular progress with buffer percentage
/// - Buffer health color coding (green/yellow/orange/red)
/// - Buffering reason display ("Slow network", "Rebuffering")
/// - Estimated time to ready
/// - Animated loading states
///
/// Example usage:
/// ```dart
/// BufferingIndicator(
///   bufferHealth: bufferHealth,
///   showDetails: true,
/// )
/// ```
class BufferingIndicator extends StatefulWidget {
  /// Current buffer health status
  final BufferHealth bufferHealth;

  /// Whether to show detailed information
  final bool showDetails;

  /// Size of the indicator
  final double size;

  /// Whether to show background
  final bool showBackground;

  /// Custom background color
  final Color? backgroundColor;

  const BufferingIndicator({
    super.key,
    required this.bufferHealth,
    this.showDetails = true,
    this.size = 64.0,
    this.showBackground = true,
    this.backgroundColor,
  });

  @override
  State<BufferingIndicator> createState() => _BufferingIndicatorState();
}

class _BufferingIndicatorState extends State<BufferingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _spinController;
  late Animation<double> _spinAnimation;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _spinAnimation = CurvedAnimation(
      parent: _spinController,
      curve: Curves.linear,
    );
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  Color _getHealthColor() {
    switch (widget.bufferHealth.status) {
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

  String _getBufferingReason() {
    final warning = widget.bufferHealth.warning;
    if (warning != null && warning.isNotEmpty) {
      return warning;
    }

    // Default buffering messages based on status
    switch (widget.bufferHealth.status) {
      case BufferStatus.healthy:
        return 'Buffering...';
      case BufferStatus.warning:
        return 'Slow network';
      case BufferStatus.critical:
        return 'Poor connection';
      case BufferStatus.underrun:
        return 'Rebuffering...';
    }
  }

  String _getEstimatedTimeText() {
    final timeToUnderrun = widget.bufferHealth.estimatedTimeToUnderrun;
    if (timeToUnderrun == null) {
      return '';
    }

    final seconds = timeToUnderrun.inSeconds;
    if (seconds < 1) {
      return 'Almost ready';
    } else if (seconds < 60) {
      return '~${seconds}s';
    } else {
      final minutes = timeToUnderrun.inMinutes;
      return '~${minutes}m';
    }
  }

  double _getBufferPercentage() {
    return (widget.bufferHealth.bufferRatio * 100).clamp(0.0, 100.0);
  }

  @override
  Widget build(BuildContext context) {
    final healthColor = _getHealthColor();
    final percentage = _getBufferPercentage();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: widget.showBackground
          ? BoxDecoration(
              color:
                  widget.backgroundColor ?? Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(16),
            )
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Circular progress indicator
          SizedBox(
            width: widget.size,
            height: widget.size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Background circle
                SizedBox(
                  width: widget.size,
                  height: widget.size,
                  child: CircularProgressIndicator(
                    value: 1.0,
                    strokeWidth: 4.0,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      healthColor.withValues(alpha: 0.2),
                    ),
                  ),
                ),
                // Progress circle
                RotationTransition(
                  turns: _spinAnimation,
                  child: SizedBox(
                    width: widget.size,
                    height: widget.size,
                    child: CircularProgressIndicator(
                      value: widget.bufferHealth.status == BufferStatus.underrun
                          ? null // Indeterminate for underrun
                          : percentage / 100,
                      strokeWidth: 4.0,
                      valueColor: AlwaysStoppedAnimation<Color>(healthColor),
                    ),
                  ),
                ),
                // Percentage text
                if (widget.bufferHealth.status != BufferStatus.underrun)
                  Text(
                    '${percentage.toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: widget.size * 0.25,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),

          // Details section
          if (widget.showDetails) ...[
            const SizedBox(height: 16),

            // Buffering reason
            Text(
              _getBufferingReason(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),

            // Estimated time to ready
            if (widget.bufferHealth.estimatedTimeToUnderrun != null) ...[
              const SizedBox(height: 8),
              Text(
                _getEstimatedTimeText(),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],

            // Download speed indicator
            if (widget.bufferHealth.currentDownloadSpeed != null) ...[
              const SizedBox(height: 8),
              Text(
                _formatSpeed(widget.bufferHealth.currentDownloadSpeed!),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ],
      ),
    );
  }

  String _formatSpeed(int bytesPerSecond) {
    final mbps = (bytesPerSecond * 8) / 1000000;
    if (mbps >= 1) {
      return '${mbps.toStringAsFixed(1)} Mbps';
    }
    final kbps = (bytesPerSecond * 8) / 1000;
    return '${kbps.toStringAsFixed(0)} Kbps';
  }
}

/// Compact buffering indicator for minimal UI
class CompactBufferingIndicator extends StatelessWidget {
  /// Current buffer health status
  final BufferHealth bufferHealth;

  /// Size of the indicator
  final double size;

  const CompactBufferingIndicator({
    super.key,
    required this.bufferHealth,
    this.size = 32.0,
  });

  Color _getHealthColor() {
    switch (bufferHealth.status) {
      case BufferStatus.healthy:
        return const Color(0xFF4CAF50);
      case BufferStatus.warning:
        return const Color(0xFFFFC107);
      case BufferStatus.critical:
        return const Color(0xFFFF9800);
      case BufferStatus.underrun:
        return const Color(0xFFF44336);
    }
  }

  @override
  Widget build(BuildContext context) {
    final healthColor = _getHealthColor();
    final percentage = (bufferHealth.bufferRatio * 100).clamp(0.0, 100.0);

    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        value: bufferHealth.status == BufferStatus.underrun
            ? null
            : percentage / 100,
        strokeWidth: 3.0,
        valueColor: AlwaysStoppedAnimation<Color>(healthColor),
      ),
    );
  }
}
