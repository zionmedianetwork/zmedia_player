import 'package:flutter/material.dart';
import '../../core/media_controller.dart';

/// A menu widget for selecting playback speed
///
/// Provides:
/// - Quick presets (0.5x, 0.75x, 1.0x, 1.25x, 1.5x, 2.0x)
/// - Custom speed slider (0.1x - 4.0x)
/// - Current speed indicator
/// - Pitch correction toggle (placeholder for future implementation)
///
/// Example usage:
/// ```dart
/// showModalBottomSheet(
///   context: context,
///   builder: (context) => SpeedMenu(
///     controller: mediaController,
///     onSpeedSelected: (speed) {
///       // Handle speed change
///     },
///   ),
/// );
/// ```
class SpeedMenu extends StatefulWidget {
  /// The media controller
  final MediaController controller;

  /// Callback when a speed is selected
  final ValueChanged<double>? onSpeedSelected;

  /// Callback when pitch correction is toggled
  final ValueChanged<bool>? onPitchCorrectionToggled;

  /// Whether pitch correction is currently enabled
  /// Note: Pitch correction is not yet implemented in native layer
  final bool isPitchCorrectionEnabled;

  const SpeedMenu({
    super.key,
    required this.controller,
    this.onSpeedSelected,
    this.onPitchCorrectionToggled,
    this.isPitchCorrectionEnabled = true,
  });

  @override
  State<SpeedMenu> createState() => _SpeedMenuState();
}

class _SpeedMenuState extends State<SpeedMenu> {
  late double _customSpeed;
  late bool _isPitchCorrectionEnabled;

  // Speed presets
  static const List<double> _speedPresets = [
    0.25,
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    1.75,
    2.0,
  ];

  @override
  void initState() {
    super.initState();
    _customSpeed = widget.controller.speed;
    _isPitchCorrectionEnabled = widget.isPitchCorrectionEnabled;
  }

  bool _isPresetSpeed(double speed) {
    return _speedPresets.any((preset) => (preset - speed).abs() < 0.01);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      constraints: BoxConstraints(
        maxHeight: screenHeight * 0.7,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.dividerColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Icon(
                  Icons.speed,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  'Playback Speed',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                // Current speed indicator
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${_customSpeed.toStringAsFixed(2)}x',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                // Speed presets section
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quick Presets',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.textTheme.bodySmall?.color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _speedPresets.map((speed) {
                          final isSelected =
                              (speed - _customSpeed).abs() < 0.01;
                          return _buildSpeedChip(
                            theme: theme,
                            speed: speed,
                            isSelected: isSelected,
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // Custom speed slider
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Custom Speed',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.textTheme.bodySmall?.color,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (!_isPresetSpeed(_customSpeed))
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Custom',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSecondaryContainer,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            '0.1x',
                            style: theme.textTheme.bodySmall,
                          ),
                          Expanded(
                            child: Slider(
                              value: _customSpeed.clamp(0.1, 4.0),
                              min: 0.1,
                              max: 4.0,
                              divisions: 39, // 0.1 increments
                              label: '${_customSpeed.toStringAsFixed(1)}x',
                              onChanged: (value) {
                                setState(() {
                                  _customSpeed = value;
                                });
                              },
                              onChangeEnd: (value) {
                                _applySpeed(value);
                              },
                            ),
                          ),
                          Text(
                            '4.0x',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // Pitch correction toggle (placeholder)
                ListTile(
                  leading: Icon(
                    Icons.graphic_eq,
                    color: theme.colorScheme.onSurface,
                  ),
                  title: const Text('Preserve Pitch'),
                  subtitle: Text(
                    'Maintain audio pitch when changing speed',
                    style: theme.textTheme.bodySmall,
                  ),
                  trailing: Switch(
                    value: _isPitchCorrectionEnabled,
                    onChanged: (value) {
                      setState(() {
                        _isPitchCorrectionEnabled = value;
                      });
                      widget.onPitchCorrectionToggled?.call(value);
                      // Show info that this is not yet implemented
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text(
                              'Pitch correction will be implemented in a future update',
                            ),
                            duration: const Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                  ),
                ),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedChip({
    required ThemeData theme,
    required double speed,
    required bool isSelected,
  }) {
    return FilterChip(
      label: Text(
        speed == 1.0 ? 'Normal' : '${speed}x',
        style: TextStyle(
          color: isSelected
              ? theme.colorScheme.onPrimary
              : theme.colorScheme.onSurface,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          _applySpeed(speed);
        }
      },
      selectedColor: theme.colorScheme.primary,
      checkmarkColor: theme.colorScheme.onPrimary,
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
  }

  void _applySpeed(double speed) {
    setState(() {
      _customSpeed = speed;
    });
    widget.controller.setSpeed(speed);
    widget.onSpeedSelected?.call(speed);
  }
}
