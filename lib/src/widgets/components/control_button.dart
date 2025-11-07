import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Button style for media controls
enum ControlButtonStyle {
  /// Simple icon with press animation
  simple,

  /// Icon with background circle
  filled,

  /// Icon with glow effect when active
  glowing,
}

/// A customizable control button component for media players
///
/// Provides:
/// - Animated press states with scale transition
/// - Icon glow effects for active states
/// - Loading state support
/// - Disabled state styling
/// - Badge support (for notifications/counts)
/// - Haptic feedback
/// - Accessibility support
///
/// Example usage:
/// ```dart
/// ControlButton(
///   icon: Icons.play_arrow,
///   onPressed: () => controller.play(),
///   tooltip: 'Play',
///   style: ControlButtonStyle.filled,
/// )
/// ```
class ControlButton extends StatefulWidget {
  /// Icon to display
  final IconData icon;

  /// Callback when button is pressed
  final VoidCallback? onPressed;

  /// Tooltip text for accessibility
  final String? tooltip;

  /// Icon color
  final Color? color;

  /// Background color (for filled/glowing styles)
  final Color? backgroundColor;

  /// Icon size
  final double size;

  /// Button style
  final ControlButtonStyle style;

  /// Whether the button is in an active state
  final bool isActive;

  /// Badge text to display (e.g., count)
  final String? badge;

  /// Badge color
  final Color? badgeColor;

  /// Whether the button is in a loading state
  final bool isLoading;

  /// Loading indicator color
  final Color? loadingColor;

  /// Whether to show haptic feedback on press
  final bool enableHapticFeedback;

  const ControlButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
    this.backgroundColor,
    this.size = 24,
    this.style = ControlButtonStyle.simple,
    this.isActive = false,
    this.badge,
    this.badgeColor,
    this.isLoading = false,
    this.loadingColor,
    this.enableHapticFeedback = true,
  });

  @override
  State<ControlButton> createState() => _ControlButtonState();
}

class _ControlButtonState extends State<ControlButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _glowAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _controller.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    _controller.reverse();
    if (widget.enableHapticFeedback) {
      HapticFeedback.selectionClick();
    }
  }

  void _handleTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = widget.color ?? theme.iconTheme.color ?? Colors.white;
    final bgColor =
        widget.backgroundColor ?? Colors.black.withValues(alpha: 0.3);

    // Show loading indicator if loading
    if (widget.isLoading) {
      return _buildLoadingState(iconColor);
    }

    Widget button;

    switch (widget.style) {
      case ControlButtonStyle.simple:
        button = _buildSimpleButton(iconColor);
        break;
      case ControlButtonStyle.filled:
        button = _buildFilledButton(iconColor, bgColor);
        break;
      case ControlButtonStyle.glowing:
        button = _buildGlowingButton(iconColor, bgColor);
        break;
    }

    // Add badge if provided
    if (widget.badge != null) {
      button = Stack(
        clipBehavior: Clip.none,
        children: [
          button,
          Positioned(
            right: -4,
            top: -4,
            child: _buildBadge(),
          ),
        ],
      );
    }

    return GestureDetector(
      onTapDown: widget.onPressed != null ? _handleTapDown : null,
      onTapUp: widget.onPressed != null ? _handleTapUp : null,
      onTapCancel: _handleTapCancel,
      onTap: widget.onPressed,
      child: Semantics(
        button: true,
        label: widget.tooltip,
        enabled: widget.onPressed != null,
        child: button,
      ),
    );
  }

  Widget _buildSimpleButton(Color iconColor) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Icon(
        widget.icon,
        color: widget.onPressed != null
            ? iconColor
            : iconColor.withValues(alpha: 0.5),
        size: widget.size,
      ),
    );
  }

  Widget _buildFilledButton(Color iconColor, Color bgColor) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.onPressed != null
              ? bgColor
              : bgColor.withValues(alpha: 0.5),
          border: widget.isActive
              ? Border.all(color: iconColor.withValues(alpha: 0.5), width: 2)
              : null,
        ),
        child: Icon(
          widget.icon,
          color: widget.onPressed != null
              ? iconColor
              : iconColor.withValues(alpha: 0.5),
          size: widget.size,
        ),
      ),
    );
  }

  Widget _buildGlowingButton(Color iconColor, Color bgColor) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: AnimatedBuilder(
        animation: _glowAnimation,
        builder: (context, child) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.onPressed != null
                  ? bgColor
                  : bgColor.withValues(alpha: 0.5),
              border: widget.isActive
                  ? Border.all(
                      color: iconColor.withValues(alpha: 0.5), width: 2)
                  : null,
              boxShadow: widget.isActive
                  ? [
                      BoxShadow(
                        color: iconColor.withValues(alpha: 0.3),
                        blurRadius: 8 + (_glowAnimation.value * 4),
                        spreadRadius: 2 + (_glowAnimation.value * 2),
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              widget.icon,
              color: widget.onPressed != null
                  ? iconColor
                  : iconColor.withValues(alpha: 0.5),
              size: widget.size,
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoadingState(Color iconColor) {
    final loadColor = widget.loadingColor ?? iconColor;

    return SizedBox(
      width: widget.size + 24,
      height: widget.size + 24,
      child: Center(
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(loadColor),
          ),
        ),
      ),
    );
  }

  Widget _buildBadge() {
    final badgeColor = widget.badgeColor ?? Colors.red;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: badgeColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      constraints: const BoxConstraints(
        minWidth: 16,
        minHeight: 16,
      ),
      child: Text(
        widget.badge!,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
