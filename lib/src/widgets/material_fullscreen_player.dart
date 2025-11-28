import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'fullscreen_controls_base.dart';
import 'material_media_controls.dart';

/// Material Design 3 fullscreen media player
///
/// Optimized for fullscreen playback with:
/// - Landscape orientation lock
/// - Immersive system UI mode (Android)
/// - Material Design 3 controls
/// - Exit fullscreen button
///
/// This widget wraps MaterialMediaControls with fullscreen-specific
/// functionality like orientation locking and system UI hiding.
///
/// Example usage:
/// ```dart
/// Navigator.of(context).push(
///   MaterialPageRoute(
///     builder: (context) => Scaffold(
///       body: MediaPlayerWidget(
///         controller: mediaController,
///         customControls: MaterialFullscreenPlayer(
///           controller: mediaController,
///           title: 'Video Title',
///         ),
///       ),
///     ),
///   ),
/// );
/// ```
class MaterialFullscreenPlayer extends FullscreenControlsBase {
  /// Custom title to display
  final String? title;

  /// Whether to show settings button
  final bool showSettings;

  /// Whether to show PiP button
  final bool showPip;

  /// Custom color scheme (defaults to Theme.of(context).colorScheme)
  final ColorScheme? colorScheme;

  const MaterialFullscreenPlayer({
    super.key,
    required super.controller,
    this.title,
    this.showSettings = true,
    this.showPip = true,
    this.colorScheme,
    super.lockOrientation = true,
    super.preferredOrientations = const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ],
    super.systemUiMode = SystemUiMode.immersiveSticky,
    super.hideSystemUI = true,
    super.onExitFullscreen,
  });

  @override
  Widget buildFullscreenControls(BuildContext context, ControlsState state) {
    // Use MaterialMediaControls with fullscreen mode disabled
    // (we're already in fullscreen, don't show fullscreen button)
    return MaterialMediaControls(
      controller: controller,
      title: title,
      showFullscreen: false,
      showSettings: showSettings,
      showPip: showPip,
      colorScheme: colorScheme,
    );
  }
}
