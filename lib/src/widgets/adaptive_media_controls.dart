import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../core/media_controller.dart';
import 'material_media_controls.dart';
import 'cupertino_media_controls.dart';

/// Platform-adaptive media controls widget
///
/// Automatically selects the appropriate control style based on the platform:
/// - **iOS**: Uses [CupertinoMediaControls] with translucent blur effects
/// - **Android/Other**: Uses [MaterialMediaControls] with Material Design 3
///
/// Provides an override option for testing or forcing a specific style.
///
/// Example usage:
/// ```dart
/// AdaptiveMediaControls(
///   controller: mediaController,
///   title: 'Video Title',
/// )
/// ```
///
/// Example with style override:
/// ```dart
/// AdaptiveMediaControls(
///   controller: mediaController,
///   title: 'Video Title',
///   forceStyle: AdaptiveControlStyle.cupertino, // Force iOS style on Android
/// )
/// ```
class AdaptiveMediaControls extends StatelessWidget {
  /// Media controller for this controls widget
  final MediaController controller;

  /// Whether to show the fullscreen button
  final bool showFullscreen;

  /// Whether to show settings button
  final bool showSettings;

  /// Whether to show PiP button
  final bool showPip;

  /// Custom title to display
  final String? title;

  /// Force a specific control style (overrides platform detection)
  ///
  /// Useful for testing or when you want consistent UI across platforms.
  /// If null, automatically detects platform and selects appropriate style.
  final AdaptiveControlStyle? forceStyle;

  /// Custom color scheme for Material controls
  ///
  /// Only applies when using Material controls. Ignored for Cupertino.
  final ColorScheme? materialColorScheme;

  /// Custom brightness for Cupertino controls
  ///
  /// Only applies when using Cupertino controls. Ignored for Material.
  final Brightness? cupertinoBrightness;

  const AdaptiveMediaControls({
    super.key,
    required this.controller,
    this.showFullscreen = true,
    this.showSettings = true,
    this.showPip = true,
    this.title,
    this.forceStyle,
    this.materialColorScheme,
    this.cupertinoBrightness,
  });

  @override
  Widget build(BuildContext context) {
    final style = forceStyle ?? _detectPlatformStyle();

    switch (style) {
      case AdaptiveControlStyle.material:
        return MaterialMediaControls(
          controller: controller,
          showFullscreen: showFullscreen,
          showSettings: showSettings,
          showPip: showPip,
          title: title,
          colorScheme: materialColorScheme,
        );

      case AdaptiveControlStyle.cupertino:
        return CupertinoMediaControls(
          controller: controller,
          showFullscreen: showFullscreen,
          showSettings: showSettings,
          showPip: showPip,
          title: title,
          brightness: cupertinoBrightness,
        );
    }
  }

  /// Detects the platform and returns the appropriate control style
  AdaptiveControlStyle _detectPlatformStyle() {
    // On web, default to Material Design
    if (kIsWeb) {
      return AdaptiveControlStyle.material;
    }

    // On native platforms, use platform-specific styles
    if (Platform.isIOS) {
      return AdaptiveControlStyle.cupertino;
    }

    // Default to Material for Android and other platforms
    return AdaptiveControlStyle.material;
  }
}

/// Control style options for adaptive media controls
enum AdaptiveControlStyle {
  /// Material Design 3 controls (Android, Web, default)
  material,

  /// Cupertino (iOS) controls with blur effects
  cupertino,
}
