import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'custom_controls_base.dart';

// Export ControlsState for use by fullscreen player implementations
export 'custom_controls_base.dart' show ControlsState;

/// Base class for fullscreen media player controls
///
/// Provides common functionality for fullscreen playback:
/// - System UI mode management (immersive mode)
/// - Orientation locking/unlocking
/// - Enter/exit fullscreen transitions
/// - Fullscreen-specific state management
///
/// Subclasses must implement [buildFullscreenControls] to define the UI.
///
/// Example usage:
/// ```dart
/// class MyFullscreenControls extends FullscreenControlsBase {
///   const MyFullscreenControls({
///     super.key,
///     required super.controller,
///     super.lockOrientation = true,
///     super.preferredOrientations = const [
///       DeviceOrientation.landscapeLeft,
///       DeviceOrientation.landscapeRight,
///     ],
///   });
///
///   @override
///   Widget buildFullscreenControls(BuildContext context, ControlsState state) {
///     return Stack(
///       children: [
///         // Your fullscreen controls UI
///       ],
///     );
///   }
/// }
/// ```
abstract class FullscreenControlsBase extends CustomControlsBase {
  /// Whether to lock device orientation when entering fullscreen
  final bool lockOrientation;

  /// Preferred orientations for fullscreen mode
  final List<DeviceOrientation> preferredOrientations;

  /// System UI mode to use in fullscreen (Android)
  final SystemUiMode systemUiMode;

  /// Whether to hide system UI completely
  final bool hideSystemUI;

  /// Callback when fullscreen is exited
  final VoidCallback? onExitFullscreen;

  const FullscreenControlsBase({
    super.key,
    required super.controller,
    this.lockOrientation = true,
    this.preferredOrientations = const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ],
    this.systemUiMode = SystemUiMode.immersiveSticky,
    this.hideSystemUI = true,
    this.onExitFullscreen,
    super.autoHideEnabled = true,
    super.autoHideDelay = const Duration(seconds: 5),
    super.animationDuration,
    super.animationCurve,
  });

  /// Build the fullscreen controls UI
  ///
  /// This method is called when fullscreen controls need to be rendered.
  /// Use [state] to access current visibility, animation value, etc.
  Widget buildFullscreenControls(BuildContext context, ControlsState state);

  @override
  Widget buildControls(BuildContext context, ControlsState state) {
    return buildFullscreenControls(context, state);
  }

  @override
  CustomControlsBaseState createState() => FullscreenControlsBaseState();
}

/// State for [FullscreenControlsBase]
///
/// Handles:
/// - System UI mode changes
/// - Orientation locking
/// - Fullscreen enter/exit transitions
class FullscreenControlsBaseState extends CustomControlsBaseState {
  SystemUiMode? _previousSystemUiMode;
  List<DeviceOrientation>? _previousOrientations;

  @override
  FullscreenControlsBase get widget => super.widget as FullscreenControlsBase;

  @override
  void initState() {
    super.initState();
    _enterFullscreen();
  }

  @override
  void dispose() {
    _exitFullscreen();
    super.dispose();
  }

  /// Enter fullscreen mode
  Future<void> _enterFullscreen() async {
    try {
      // Save current system UI mode
      _previousSystemUiMode = SystemUiMode.edgeToEdge;

      if (widget.hideSystemUI) {
        // Set immersive system UI mode
        await SystemChrome.setEnabledSystemUIMode(widget.systemUiMode);
      }

      if (widget.lockOrientation && widget.preferredOrientations.isNotEmpty) {
        // Save current orientations (all by default)
        _previousOrientations = [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ];

        // Lock to preferred orientations
        await SystemChrome.setPreferredOrientations(
          widget.preferredOrientations,
        );
      }
    } catch (e) {
      debugPrint('Error entering fullscreen: $e');
    }
  }

  /// Exit fullscreen mode
  Future<void> _exitFullscreen() async {
    try {
      // Restore system UI mode
      if (_previousSystemUiMode != null) {
        await SystemChrome.setEnabledSystemUIMode(_previousSystemUiMode!);
      } else {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }

      // Restore orientations
      if (_previousOrientations != null && _previousOrientations!.isNotEmpty) {
        await SystemChrome.setPreferredOrientations(_previousOrientations!);
      } else {
        // Restore all orientations
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }

      // Notify exit callback
      widget.onExitFullscreen?.call();
    } catch (e) {
      debugPrint('Error exiting fullscreen: $e');
    }
  }

  /// Manually exit fullscreen
  Future<void> exitFullscreen() async {
    await _exitFullscreen();
    if (mounted && context.mounted) {
      Navigator.of(context).pop();
    }
  }
}
