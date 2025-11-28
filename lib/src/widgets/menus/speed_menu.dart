import 'package:flutter/material.dart';
import '../../core/media_controller.dart';

/// A menu widget for selecting playback speed
///
/// Displays speed options with descriptive labels and rounded pill selection style
/// Follows design specifications from docs/images/screenshots/controls_settings_speed_vertical.png
///
/// Features:
/// - Descriptive speed labels (Slowest, Slow, Normal, Fast, Fastest)
/// - Speed multipliers (0.5x, 0.75x, 1.0x, 1.25x, 1.5x)
/// - Rounded pill background for selected item
/// - Checkmark indicator for selection
///
/// Example usage:
/// ```dart
/// showModalBottomSheet(
///   context: context,
///   backgroundColor: Colors.transparent,
///   builder: (context) => SpeedMenu(
///     controller: mediaController,
///   ),
/// );
/// ```
class SpeedMenu extends StatelessWidget {
  /// The media controller
  final MediaController controller;

  /// Callback when a speed is selected
  final ValueChanged<double>? onSpeedSelected;

  /// Callback when pitch correction is toggled (placeholder for future)
  final ValueChanged<bool>? onPitchCorrectionToggled;

  /// Whether pitch correction is currently enabled (placeholder)
  final bool isPitchCorrectionEnabled;

  const SpeedMenu({
    super.key,
    required this.controller,
    this.onSpeedSelected,
    this.onPitchCorrectionToggled,
    this.isPitchCorrectionEnabled = true,
  });

  /// Speed options with descriptive labels
  static const List<Map<String, dynamic>> _speedOptions = [
    {'label': 'Slowest', 'speed': 0.5},
    {'label': 'Slow', 'speed': 0.75},
    {'label': 'Normal', 'speed': 1.0},
    {'label': 'Fast', 'speed': 1.25},
    {'label': 'Fastest', 'speed': 1.5},
  ];

  void _selectSpeed(BuildContext context, double speed) {
    controller.setSpeed(speed);
    onSpeedSelected?.call(speed);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentSpeed = controller.speed;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xE6282828) // rgba(40, 40, 40, 0.9)
            : const Color(0xE6FFFFFF),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
              child: Row(
                children: [
                  Text(
                    'Speed',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                  ),
                ],
              ),
            ),

            // Speed options list
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  ..._speedOptions.map((option) {
                    final label = option['label'] as String;
                    final speed = option['speed'] as double;
                    final isSelected = (speed - currentSpeed).abs() < 0.01;

                    return _SpeedOption(
                      label: label,
                      speed: speed,
                      isSelected: isSelected,
                      onTap: () => _selectSpeed(context, speed),
                      isDark: isDark,
                    );
                  }),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Individual speed option with pill selection style
class _SpeedOption extends StatelessWidget {
  final String label;
  final double speed;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isDark;

  const _SpeedOption({
    required this.label,
    required this.speed,
    required this.isSelected,
    required this.onTap,
    required this.isDark,
  });

  String _getSpeedText() {
    if (speed == speed.toInt()) {
      return '${speed.toInt()}.0x';
    }
    return '${speed}x';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(30),
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: isSelected
                  ? (isDark
                      ? const Color(0x26FFFFFF) // rgba(255, 255, 255, 0.15)
                      : const Color(0x1A000000)) // rgba(0, 0, 0, 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(
              children: [
                // Label
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),

                const SizedBox(width: 12),

                // Speed multiplier
                Text(
                  _getSpeedText(),
                  style: TextStyle(
                    fontSize: 15,
                    color: isDark
                        ? const Color(0xFFB0B0B0)
                        : const Color(0xFF808080),
                  ),
                ),

                const Spacer(),

                // Checkmark for selected item
                if (isSelected)
                  Icon(
                    Icons.check,
                    size: 24,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
