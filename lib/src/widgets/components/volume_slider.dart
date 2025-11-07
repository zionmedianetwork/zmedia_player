import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Orientation for volume slider
enum VolumeSliderOrientation {
  /// Vertical slider (bottom to top)
  vertical,

  /// Horizontal slider (left to right)
  horizontal,
}

/// A customizable volume slider component for media players
///
/// Provides:
/// - Vertical or horizontal orientation
/// - Volume percentage display
/// - Mute toggle integration
/// - Smooth dragging with haptic feedback
/// - Customizable colors and sizes
/// - Accessibility support
///
/// Example usage:
/// ```dart
/// VolumeSlider(
///   value: 0.7,
///   isMuted: false,
///   onChanged: (value) => controller.setVolume(value),
///   onMuteToggle: () => controller.toggleMute(),
/// )
/// ```
class VolumeSlider extends StatefulWidget {
  /// Current volume level (0.0 - 1.0)
  final double value;

  /// Whether audio is muted
  final bool isMuted;

  /// Callback when volume changes
  final ValueChanged<double>? onChanged;

  /// Callback when mute is toggled
  final VoidCallback? onMuteToggle;

  /// Slider orientation
  final VolumeSliderOrientation orientation;

  /// Track color for active portion
  final Color? activeColor;

  /// Track color for inactive portion
  final Color? inactiveColor;

  /// Thumb color
  final Color? thumbColor;

  /// Icon color
  final Color? iconColor;

  /// Track height (or width for horizontal)
  final double trackSize;

  /// Thumb radius
  final double thumbRadius;

  /// Slider length (height for vertical, width for horizontal)
  final double? sliderLength;

  /// Whether to show volume percentage
  final bool showPercentage;

  /// Whether to show mute icon button
  final bool showMuteButton;

  /// Whether to enable haptic feedback
  final bool enableHapticFeedback;

  const VolumeSlider({
    super.key,
    required this.value,
    this.isMuted = false,
    this.onChanged,
    this.onMuteToggle,
    this.orientation = VolumeSliderOrientation.vertical,
    this.activeColor,
    this.inactiveColor,
    this.thumbColor,
    this.iconColor,
    this.trackSize = 3.0,
    this.thumbRadius = 6.0,
    this.sliderLength,
    this.showPercentage = false,
    this.showMuteButton = true,
    this.enableHapticFeedback = true,
  });

  @override
  State<VolumeSlider> createState() => _VolumeSliderState();
}

class _VolumeSliderState extends State<VolumeSlider> {
  double? _dragValue;
  bool _isDragging = false;

  double get currentValue => _dragValue ?? widget.value;

  void _handleChange(double value) {
    setState(() {
      _dragValue = value;
    });
    widget.onChanged?.call(value);

    if (widget.enableHapticFeedback) {
      HapticFeedback.selectionClick();
    }
  }

  void _handleChangeEnd(double value) {
    setState(() {
      _isDragging = false;
      _dragValue = null;
    });

    if (widget.enableHapticFeedback) {
      HapticFeedback.lightImpact();
    }
  }

  IconData _getVolumeIcon() {
    if (widget.isMuted || currentValue == 0.0) {
      return Icons.volume_off;
    } else if (currentValue < 0.3) {
      return Icons.volume_mute;
    } else if (currentValue < 0.7) {
      return Icons.volume_down;
    } else {
      return Icons.volume_up;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeColor = widget.activeColor ?? theme.colorScheme.primary;
    final inactiveColor =
        widget.inactiveColor ?? Colors.white.withValues(alpha: 0.3);
    final thumbColor = widget.thumbColor ?? activeColor;
    final iconColor = widget.iconColor ?? Colors.white;

    if (widget.orientation == VolumeSliderOrientation.vertical) {
      return _buildVerticalSlider(
        activeColor,
        inactiveColor,
        thumbColor,
        iconColor,
      );
    } else {
      return _buildHorizontalSlider(
        activeColor,
        inactiveColor,
        thumbColor,
        iconColor,
      );
    }
  }

  Widget _buildVerticalSlider(
    Color activeColor,
    Color inactiveColor,
    Color thumbColor,
    Color iconColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mute button
          if (widget.showMuteButton)
            IconButton(
              icon: Icon(
                _getVolumeIcon(),
                color: iconColor,
                size: 20,
              ),
              onPressed: widget.onMuteToggle,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),

          if (widget.showMuteButton) const SizedBox(height: 8),

          // Volume slider
          SizedBox(
            height: widget.sliderLength ?? 120,
            child: RotatedBox(
              quarterTurns: 3,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: widget.trackSize,
                  thumbShape: RoundSliderThumbShape(
                    enabledThumbRadius: widget.thumbRadius,
                  ),
                  overlayShape: RoundSliderOverlayShape(
                    overlayRadius: widget.thumbRadius * 2,
                  ),
                  activeTrackColor: activeColor,
                  inactiveTrackColor: inactiveColor,
                  thumbColor: thumbColor,
                  overlayColor: activeColor.withValues(alpha: 0.2),
                ),
                child: Slider(
                  value: widget.isMuted ? 0.0 : currentValue,
                  onChanged: widget.onChanged != null
                      ? (value) {
                          // Auto-unmute if user increases volume while muted
                          if (widget.isMuted && value > 0) {
                            widget.onMuteToggle?.call();
                          }
                          _handleChange(value);
                        }
                      : null,
                  onChangeEnd:
                      widget.onChanged != null ? _handleChangeEnd : null,
                ),
              ),
            ),
          ),

          // Volume percentage
          if (widget.showPercentage) ...[
            const SizedBox(height: 8),
            Text(
              '${(currentValue * 100).round()}%',
              style: TextStyle(
                color: iconColor,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHorizontalSlider(
    Color activeColor,
    Color inactiveColor,
    Color thumbColor,
    Color iconColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mute button
          if (widget.showMuteButton)
            IconButton(
              icon: Icon(
                _getVolumeIcon(),
                color: iconColor,
                size: 20,
              ),
              onPressed: widget.onMuteToggle,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),

          if (widget.showMuteButton) const SizedBox(width: 12),

          // Volume slider
          SizedBox(
            width: widget.sliderLength ?? 120,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: widget.trackSize,
                thumbShape: RoundSliderThumbShape(
                  enabledThumbRadius: widget.thumbRadius,
                ),
                overlayShape: RoundSliderOverlayShape(
                  overlayRadius: widget.thumbRadius * 2,
                ),
                activeTrackColor: activeColor,
                inactiveTrackColor: inactiveColor,
                thumbColor: thumbColor,
                overlayColor: activeColor.withValues(alpha: 0.2),
              ),
              child: Slider(
                value: widget.isMuted ? 0.0 : currentValue,
                onChanged: widget.onChanged != null
                    ? (value) {
                        // Auto-unmute if user increases volume while muted
                        if (widget.isMuted && value > 0) {
                          widget.onMuteToggle?.call();
                        }
                        _handleChange(value);
                      }
                    : null,
                onChangeEnd: widget.onChanged != null ? _handleChangeEnd : null,
              ),
            ),
          ),

          // Volume percentage
          if (widget.showPercentage) ...[
            const SizedBox(width: 12),
            SizedBox(
              width: 40,
              child: Text(
                '${(currentValue * 100).round()}%',
                style: TextStyle(
                  color: iconColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
