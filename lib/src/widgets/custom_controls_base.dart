import 'dart:async';
import 'package:flutter/widgets.dart';
import '../core/media_controller.dart';

/// Base class for custom media player controls
///
/// Provides common functionality for implementing custom controls:
/// - Auto-hide controls logic with configurable timeout
/// - Fade animations for showing/hiding controls
/// - Gesture handling (tap to toggle controls)
/// - State management helpers
/// - Lifecycle management
///
/// Subclasses must implement [buildControls] to define the actual control UI.
///
/// Example usage:
/// ```dart
/// class MyCustomControls extends CustomControlsBase {
///   const MyCustomControls({
///     super.key,
///     required super.controller,
///     super.autoHideEnabled = true,
///     super.autoHideDelay = const Duration(seconds: 3),
///   });
///
///   @override
///   Widget buildControls(BuildContext context, ControlsState state) {
///     return Stack(
///       children: [
///         // Your custom controls UI
///         Positioned(
///           bottom: 0,
///           left: 0,
///           right: 0,
///           child: YourControlsWidget(
///             controller: controller,
///             isVisible: state.isVisible,
///           ),
///         ),
///       ],
///     );
///   }
/// }
/// ```
abstract class CustomControlsBase extends StatefulWidget {
  /// Media controller for the player
  final MediaController controller;

  /// Whether to automatically hide controls after inactivity
  final bool autoHideEnabled;

  /// Duration before auto-hiding controls
  final Duration autoHideDelay;

  /// Animation duration for showing/hiding controls
  final Duration animationDuration;

  /// Animation curve for showing/hiding controls
  final Curve animationCurve;

  const CustomControlsBase({
    super.key,
    required this.controller,
    this.autoHideEnabled = true,
    this.autoHideDelay = const Duration(seconds: 3),
    this.animationDuration = const Duration(milliseconds: 300),
    this.animationCurve = Curves.easeInOut,
  });

  /// Build the custom controls UI
  ///
  /// This method is called when controls need to be rendered.
  /// Use [state] to access current visibility, animation value, etc.
  Widget buildControls(BuildContext context, ControlsState state);

  @override
  State<CustomControlsBase> createState() => CustomControlsBaseState();
}

/// State for [CustomControlsBase]
///
/// Handles:
/// - Control visibility toggling
/// - Auto-hide timer management
/// - Fade animations
/// - Gesture detection
class CustomControlsBaseState extends State<CustomControlsBase>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  Timer? _autoHideTimer;
  bool _isVisible = true;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _startAutoHideTimer();
  }

  @override
  void didUpdateWidget(CustomControlsBase oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Update animation if duration or curve changed
    if (oldWidget.animationDuration != widget.animationDuration ||
        oldWidget.animationCurve != widget.animationCurve) {
      _fadeController.dispose();
      _initializeAnimations();
    }

    // Restart timer if auto-hide settings changed
    if (oldWidget.autoHideEnabled != widget.autoHideEnabled ||
        oldWidget.autoHideDelay != widget.autoHideDelay) {
      _cancelAutoHideTimer();
      if (widget.autoHideEnabled && _isVisible) {
        _startAutoHideTimer();
      }
    }
  }

  @override
  void dispose() {
    _cancelAutoHideTimer();
    _fadeController.dispose();
    super.dispose();
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: widget.animationCurve,
    );
    _fadeController.forward();
  }

  /// Toggle controls visibility
  void toggleControls() {
    setState(() {
      _isVisible = !_isVisible;
      if (_isVisible) {
        _fadeController.forward();
        _startAutoHideTimer();
      } else {
        _fadeController.reverse();
        _cancelAutoHideTimer();
      }
    });
  }

  /// Show controls (with optional auto-hide)
  void showControls({bool startAutoHide = true}) {
    if (!_isVisible) {
      setState(() {
        _isVisible = true;
        _fadeController.forward();
      });
    }

    if (startAutoHide && widget.autoHideEnabled) {
      _startAutoHideTimer();
    }
  }

  /// Hide controls
  void hideControls() {
    if (_isVisible) {
      setState(() {
        _isVisible = false;
        _fadeController.reverse();
      });
    }
    _cancelAutoHideTimer();
  }

  /// Reset the auto-hide timer
  ///
  /// Call this when user interacts with controls to prevent auto-hiding
  void resetAutoHideTimer() {
    if (widget.autoHideEnabled && _isVisible) {
      _cancelAutoHideTimer();
      _startAutoHideTimer();
    }
  }

  void _startAutoHideTimer() {
    if (!widget.autoHideEnabled) return;

    _cancelAutoHideTimer();
    _autoHideTimer = Timer(widget.autoHideDelay, () {
      if (mounted && _isVisible) {
        hideControls();
      }
    });
  }

  void _cancelAutoHideTimer() {
    _autoHideTimer?.cancel();
    _autoHideTimer = null;
  }

  /// Handle tap gesture on the player
  void _handleTap() {
    toggleControls();
  }

  @override
  Widget build(BuildContext context) {
    final state = ControlsState(
      isVisible: _isVisible,
      animation: _fadeAnimation,
      animationValue: _fadeAnimation.value,
      controller: widget.controller,
    );

    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _fadeAnimation,
        builder: (context, child) {
          return widget.buildControls(context, state);
        },
      ),
    );
  }
}

/// State information passed to [CustomControlsBase.buildControls]
class ControlsState {
  /// Whether controls are currently visible
  final bool isVisible;

  /// Fade animation for smooth transitions
  final Animation<double> animation;

  /// Current animation value (0.0 to 1.0)
  final double animationValue;

  /// Media controller
  final MediaController controller;

  const ControlsState({
    required this.isVisible,
    required this.animation,
    required this.animationValue,
    required this.controller,
  });
}

/// Builder typedef for custom controls
typedef ControlsBuilder = Widget Function(
  BuildContext context,
  ControlsState state,
);

/// Convenient builder-based custom controls
///
/// Allows creating custom controls without extending [CustomControlsBase].
/// Perfect for quick prototyping or simple customizations.
///
/// Example usage:
/// ```dart
/// CustomControlsBuilder(
///   controller: mediaController,
///   builder: (context, state) {
///     return Opacity(
///       opacity: state.animationValue,
///       child: state.isVisible
///           ? YourControlsWidget(controller: state.controller)
///           : const SizedBox.shrink(),
///     );
///   },
/// )
/// ```
class CustomControlsBuilder extends CustomControlsBase {
  /// Builder function for controls UI
  final ControlsBuilder builder;

  const CustomControlsBuilder({
    super.key,
    required super.controller,
    required this.builder,
    super.autoHideEnabled,
    super.autoHideDelay,
    super.animationDuration,
    super.animationCurve,
  });

  @override
  Widget buildControls(BuildContext context, ControlsState state) {
    return builder(context, state);
  }
}
