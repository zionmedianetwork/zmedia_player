import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// A native AirPlay button for iOS that shows the system route picker
///
/// This widget displays the native AVRoutePickerView on iOS, which allows
/// users to select AirPlay devices. On Android, this widget is not displayed.
///
/// Example usage:
/// ```dart
/// if (Platform.isIOS)
///   AirPlayButton(
///     size: 32.0,
///     tintColor: Colors.white,
///   )
/// ```
class AirPlayButton extends StatelessWidget {
  /// Size of the AirPlay button (width and height)
  final double size;

  /// Tint color for the button
  final Color? tintColor;

  /// Active tint color when AirPlay is connected
  final Color? activeTintColor;

  /// Whether to prioritize video devices over audio
  final bool prioritizesVideoDevices;

  const AirPlayButton({
    super.key,
    this.size = 32.0,
    this.tintColor,
    this.activeTintColor,
    this.prioritizesVideoDevices = true,
  });

  @override
  Widget build(BuildContext context) {
    // Only show on iOS
    if (!Platform.isIOS) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: size,
      height: size,
      child: UiKitView(
        viewType: 'zmedia_player/airplay_button',
        creationParams: {
          'tintColor': _colorToHex(tintColor),
          'activeTintColor': _colorToHex(activeTintColor),
          'prioritizesVideoDevices': prioritizesVideoDevices,
        },
        creationParamsCodec: const StandardMessageCodec(),
      ),
    );
  }

  /// Convert Color to hex string for native side
  String? _colorToHex(Color? color) {
    if (color == null) return null;
    final value = (color.a * 255).round() |
        ((color.r * 255).round() << 24) |
        ((color.g * 255).round() << 16) |
        ((color.b * 255).round() << 8);
    return '#${value.toRadixString(16).padLeft(8, '0')}';
  }
}
