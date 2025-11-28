import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'fullscreen_controls_base.dart';
import 'cupertino_media_controls.dart';

/// Cupertino (iOS) fullscreen media player
///
/// Optimized for fullscreen playback with:
/// - Landscape orientation lock
/// - Immersive system UI mode (iOS)
/// - Cupertino design language
/// - Exit fullscreen button
/// - Translucent blur effects
///
/// This widget wraps CupertinoMediaControls with fullscreen-specific
/// functionality like orientation locking and system UI hiding.
///
/// Example usage:
/// ```dart
/// Navigator.of(context).push(
///   CupertinoPageRoute(
///     builder: (context) => CupertinoFullscreenPlayer(
///       controller: mediaController,
///       title: 'Video Title',
///     ),
///   ),
/// );
/// ```
class CupertinoFullscreenPlayer extends FullscreenControlsBase {
  /// Custom title to display
  final String? title;

  /// Whether to show settings button
  final bool showSettings;

  /// Whether to show PiP button
  final bool showPip;

  /// Custom iOS brightness (light/dark)
  final Brightness? brightness;

  const CupertinoFullscreenPlayer({
    super.key,
    required super.controller,
    this.title,
    this.showSettings = true,
    this.showPip = true,
    this.brightness,
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
    // Use CupertinoMediaControls with fullscreen mode disabled
    // (we're already in fullscreen, don't show fullscreen button)
    return CupertinoMediaControls(
      controller: controller,
      title: title,
      showFullscreen: false,
      showSettings: showSettings,
      showPip: showPip,
      brightness: brightness,
    );
  }
}
