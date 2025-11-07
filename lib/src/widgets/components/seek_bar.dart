import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'time_display.dart';

/// Chapter marker for seek bar
class ChapterMarker {
  /// Position in the video (0.0 - 1.0)
  final double position;

  /// Chapter title
  final String title;

  /// Optional thumbnail URL
  final String? thumbnailUrl;

  const ChapterMarker({
    required this.position,
    required this.title,
    this.thumbnailUrl,
  });
}

/// A customizable seek bar component for media players
///
/// Provides:
/// - Smooth dragging with haptic feedback
/// - Time tooltip on hover/drag
/// - Buffer progress visualization
/// - Chapter markers support
/// - Customizable theme colors
/// - Accessibility support
///
/// Example usage:
/// ```dart
/// SeekBar(
///   value: 0.3,
///   buffered: 0.5,
///   duration: Duration(minutes: 5),
///   onChanged: (value) => controller.seekTo(duration * value),
/// )
/// ```
class SeekBar extends StatefulWidget {
  /// Current playback position (0.0 - 1.0)
  final double value;

  /// Buffered position (0.0 - 1.0)
  final double? buffered;

  /// Total duration for tooltip display
  final Duration? duration;

  /// Callback when seeking
  final ValueChanged<double>? onChanged;

  /// Callback when seek starts
  final ValueChanged<double>? onChangeStart;

  /// Callback when seek ends
  final ValueChanged<double>? onChangeEnd;

  /// Track color for played portion
  final Color? activeColor;

  /// Track color for unplayed portion
  final Color? inactiveColor;

  /// Track color for buffered portion
  final Color? bufferedColor;

  /// Thumb color
  final Color? thumbColor;

  /// Track height
  final double trackHeight;

  /// Thumb radius
  final double thumbRadius;

  /// Whether to show time tooltip on drag
  final bool showTooltip;

  /// Chapter markers (optional)
  final List<ChapterMarker>? chapters;

  /// Whether to enable haptic feedback
  final bool enableHapticFeedback;

  const SeekBar({
    super.key,
    required this.value,
    this.buffered,
    this.duration,
    this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.activeColor,
    this.inactiveColor,
    this.bufferedColor,
    this.thumbColor,
    this.trackHeight = 3.0,
    this.thumbRadius = 6.0,
    this.showTooltip = true,
    this.chapters,
    this.enableHapticFeedback = true,
  });

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _dragValue;
  bool _isDragging = false;
  Offset? _dragPosition;

  bool get isDragging => _isDragging;
  double get currentValue => _dragValue ?? widget.value;

  void _handleChangeStart(double value) {
    setState(() {
      _isDragging = true;
      _dragValue = value;
    });
    widget.onChangeStart?.call(value);
    if (widget.enableHapticFeedback) {
      HapticFeedback.selectionClick();
    }
  }

  void _handleChange(double value) {
    setState(() {
      _dragValue = value;
    });
    widget.onChanged?.call(value);
  }

  void _handleChangeEnd(double value) {
    setState(() {
      _isDragging = false;
      _dragValue = null;
      _dragPosition = null;
    });
    widget.onChangeEnd?.call(value);
    if (widget.enableHapticFeedback) {
      HapticFeedback.lightImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeColor = widget.activeColor ?? theme.colorScheme.primary;
    final inactiveColor =
        widget.inactiveColor ?? Colors.white.withValues(alpha: 0.3);
    final bufferedColor =
        widget.bufferedColor ?? Colors.white.withValues(alpha: 0.5);
    final thumbColor = widget.thumbColor ?? activeColor;

    return GestureDetector(
      onHorizontalDragStart: (details) {
        if (widget.onChanged != null) {
          final box = context.findRenderObject() as RenderBox;
          final localPosition = box.globalToLocal(details.globalPosition);
          final value = (localPosition.dx / box.size.width).clamp(0.0, 1.0);
          setState(() {
            _dragPosition = localPosition;
          });
          _handleChangeStart(value);
        }
      },
      onHorizontalDragUpdate: (details) {
        if (widget.onChanged != null) {
          final box = context.findRenderObject() as RenderBox;
          final localPosition = box.globalToLocal(details.globalPosition);
          final value = (localPosition.dx / box.size.width).clamp(0.0, 1.0);
          setState(() {
            _dragPosition = localPosition;
          });
          _handleChange(value);
        }
      },
      onHorizontalDragEnd: (details) {
        if (widget.onChanged != null && _dragValue != null) {
          _handleChangeEnd(_dragValue!);
        }
      },
      onTapDown: (details) {
        if (widget.onChanged != null) {
          final box = context.findRenderObject() as RenderBox;
          final localPosition = box.globalToLocal(details.globalPosition);
          final value = (localPosition.dx / box.size.width).clamp(0.0, 1.0);
          _handleChangeStart(value);
          _handleChangeEnd(value);
        }
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Main seek bar
          Container(
            height: widget.trackHeight + (widget.thumbRadius * 2),
            child: CustomPaint(
              painter: _SeekBarPainter(
                value: currentValue,
                buffered: widget.buffered,
                activeColor: activeColor,
                inactiveColor: inactiveColor,
                bufferedColor: bufferedColor,
                thumbColor: thumbColor,
                trackHeight: widget.trackHeight,
                thumbRadius: widget.thumbRadius,
                isDragging: isDragging,
                chapters: widget.chapters,
              ),
              child: Container(),
            ),
          ),

          // Time tooltip
          if (widget.showTooltip &&
              isDragging &&
              _dragPosition != null &&
              widget.duration != null)
            _buildTooltip(context, _dragPosition!),
        ],
      ),
    );
  }

  Widget _buildTooltip(BuildContext context, Offset position) {
    final duration = widget.duration!;
    final seekTime = duration * currentValue;

    return Positioned(
      left: position.dx - 30,
      top: -40,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          TimeDisplay.formatDuration(seekTime),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _SeekBarPainter extends CustomPainter {
  final double value;
  final double? buffered;
  final Color activeColor;
  final Color inactiveColor;
  final Color bufferedColor;
  final Color thumbColor;
  final double trackHeight;
  final double thumbRadius;
  final bool isDragging;
  final List<ChapterMarker>? chapters;

  _SeekBarPainter({
    required this.value,
    this.buffered,
    required this.activeColor,
    required this.inactiveColor,
    required this.bufferedColor,
    required this.thumbColor,
    required this.trackHeight,
    required this.thumbRadius,
    required this.isDragging,
    this.chapters,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final trackRect = Rect.fromLTWH(
      thumbRadius,
      centerY - (trackHeight / 2),
      size.width - (thumbRadius * 2),
      trackHeight,
    );

    // Draw track background (inactive)
    final inactivePaint = Paint()
      ..color = inactiveColor
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        trackRect,
        Radius.circular(trackHeight / 2),
      ),
      inactivePaint,
    );

    // Draw buffered progress
    if (buffered != null && buffered! > 0) {
      final bufferedWidth = trackRect.width * buffered!;
      final bufferedRect = Rect.fromLTWH(
        trackRect.left,
        trackRect.top,
        bufferedWidth,
        trackRect.height,
      );

      final bufferedPaint = Paint()
        ..color = bufferedColor
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          bufferedRect,
          Radius.circular(trackHeight / 2),
        ),
        bufferedPaint,
      );
    }

    // Draw active progress (played)
    final activeWidth = trackRect.width * value;
    final activeRect = Rect.fromLTWH(
      trackRect.left,
      trackRect.top,
      activeWidth,
      trackRect.height,
    );

    final activePaint = Paint()
      ..shader = LinearGradient(
        colors: [
          activeColor,
          activeColor.withValues(alpha: 0.8),
        ],
      ).createShader(activeRect)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        activeRect,
        Radius.circular(trackHeight / 2),
      ),
      activePaint,
    );

    // Draw chapter markers
    if (chapters != null && chapters!.isNotEmpty) {
      for (final chapter in chapters!) {
        final markerX = trackRect.left + (trackRect.width * chapter.position);
        final markerPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.6)
          ..style = PaintingStyle.fill;

        canvas.drawCircle(
          Offset(markerX, centerY),
          2,
          markerPaint,
        );
      }
    }

    // Draw thumb
    final thumbX = trackRect.left + activeWidth;
    final thumbCenter = Offset(thumbX, centerY);

    // Thumb shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    canvas.drawCircle(
      thumbCenter.translate(0, 1),
      thumbRadius,
      shadowPaint,
    );

    // Thumb outer circle
    final thumbPaint = Paint()
      ..color = thumbColor
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      thumbCenter,
      isDragging ? thumbRadius * 1.2 : thumbRadius,
      thumbPaint,
    );

    // Thumb inner circle (for depth)
    final innerThumbPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      thumbCenter,
      (isDragging ? thumbRadius * 1.2 : thumbRadius) * 0.4,
      innerThumbPaint,
    );
  }

  @override
  bool shouldRepaint(_SeekBarPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.buffered != buffered ||
        oldDelegate.isDragging != isDragging ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.bufferedColor != bufferedColor ||
        oldDelegate.thumbColor != thumbColor;
  }
}
