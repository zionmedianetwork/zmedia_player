import 'package:flutter/material.dart';

/// Base feedback overlay widget for temporary visual feedback
///
/// Provides a reusable foundation for all feedback overlays with:
/// - Auto-dismiss after configurable duration
/// - Fade in/out animations
/// - Configurable positioning
/// - Semi-transparent background
///
/// This widget is designed to be extended by specific feedback overlays
/// like volume, seek, speed, and quality change indicators.
///
/// Example usage:
/// ```dart
/// FeedbackOverlay(
///   child: Icon(Icons.volume_up, size: 48),
///   duration: Duration(seconds: 1),
/// )
/// ```
class FeedbackOverlay extends StatefulWidget {
  /// Content to display in the overlay
  final Widget child;

  /// How long to show the overlay before auto-dismissing
  final Duration duration;

  /// Background color of the overlay container
  final Color? backgroundColor;

  /// Border radius of the overlay container
  final double borderRadius;

  /// Padding inside the overlay container
  final EdgeInsets padding;

  /// Size of the overlay container (if null, uses child's size)
  final Size? size;

  /// Alignment of the overlay on screen
  final Alignment alignment;

  /// Whether to show the overlay initially
  final bool show;

  /// Callback when overlay is dismissed
  final VoidCallback? onDismiss;

  /// Animation duration for fade in/out
  final Duration animationDuration;

  const FeedbackOverlay({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 1500),
    this.backgroundColor,
    this.borderRadius = 16.0,
    this.padding = const EdgeInsets.all(24),
    this.size,
    this.alignment = Alignment.center,
    this.show = true,
    this.onDismiss,
    this.animationDuration = const Duration(milliseconds: 200),
  });

  @override
  State<FeedbackOverlay> createState() => _FeedbackOverlayState();
}

class _FeedbackOverlayState extends State<FeedbackOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();

    if (widget.show) {
      _showOverlay();
    }
  }

  void _initializeAnimations() {
    _controller = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutBack,
      ),
    );
  }

  void _showOverlay() {
    _controller.forward().then((_) {
      // Auto-dismiss after duration
      Future.delayed(widget.duration, () {
        if (mounted) {
          _dismissOverlay();
        }
      });
    });
  }

  void _dismissOverlay() {
    _controller.reverse().then((_) {
      if (mounted) {
        widget.onDismiss?.call();
      }
    });
  }

  @override
  void didUpdateWidget(FeedbackOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Show overlay again if show property changes to true
    if (!oldWidget.show && widget.show) {
      _showOverlay();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.show) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final backgroundColor = widget.backgroundColor ??
        theme.colorScheme.surface.withValues(alpha: 0.95);

    return Align(
      alignment: widget.alignment,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Opacity(
            opacity: _fadeAnimation.value,
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: Container(
                width: widget.size?.width,
                height: widget.size?.height,
                padding: widget.padding,
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: widget.child,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Controller for programmatically showing/hiding feedback overlays
///
/// Allows external control of feedback overlay visibility and content.
/// Useful for integration with MediaController or custom controls.
///
/// Example usage:
/// ```dart
/// final controller = FeedbackOverlayController();
///
/// // Show volume feedback
/// controller.show(
///   child: VolumeIndicator(volume: 0.75),
///   duration: Duration(seconds: 1),
/// );
/// ```
class FeedbackOverlayController extends ChangeNotifier {
  Widget? _child;
  Duration _duration = const Duration(milliseconds: 1500);
  bool _isVisible = false;

  /// Current child widget being displayed
  Widget? get child => _child;

  /// Current display duration
  Duration get duration => _duration;

  /// Whether overlay is currently visible
  bool get isVisible => _isVisible;

  /// Show feedback overlay with given child and duration
  void show({
    required Widget child,
    Duration duration = const Duration(milliseconds: 1500),
  }) {
    _child = child;
    _duration = duration;
    _isVisible = true;
    notifyListeners();
  }

  /// Hide the feedback overlay
  void hide() {
    _isVisible = false;
    notifyListeners();
  }

  /// Clear the overlay content
  void clear() {
    _child = null;
    _isVisible = false;
    notifyListeners();
  }
}

/// Managed feedback overlay that responds to a controller
///
/// This widget automatically updates based on FeedbackOverlayController state.
/// Use this for centralized feedback overlay management.
///
/// Example usage:
/// ```dart
/// ManagedFeedbackOverlay(
///   controller: feedbackController,
/// )
/// ```
class ManagedFeedbackOverlay extends StatelessWidget {
  /// Controller that manages overlay state
  final FeedbackOverlayController controller;

  /// Background color of the overlay container
  final Color? backgroundColor;

  /// Border radius of the overlay container
  final double borderRadius;

  /// Padding inside the overlay container
  final EdgeInsets padding;

  /// Alignment of the overlay on screen
  final Alignment alignment;

  const ManagedFeedbackOverlay({
    super.key,
    required this.controller,
    this.backgroundColor,
    this.borderRadius = 16.0,
    this.padding = const EdgeInsets.all(24),
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        if (!controller.isVisible || controller.child == null) {
          return const SizedBox.shrink();
        }

        return FeedbackOverlay(
          show: controller.isVisible,
          duration: controller.duration,
          backgroundColor: backgroundColor,
          borderRadius: borderRadius,
          padding: padding,
          alignment: alignment,
          onDismiss: controller.hide,
          child: controller.child!,
        );
      },
    );
  }
}
