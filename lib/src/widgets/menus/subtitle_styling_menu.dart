import 'package:flutter/material.dart';
import '../../models/subtitle_track.dart';

/// A menu widget for customizing subtitle styling
///
/// Provides controls for:
/// - Font size (8pt - 48pt)
/// - Font color with presets
/// - Background color with opacity
/// - Text outline toggle and color
/// - Vertical position (top to bottom)
/// - Horizontal alignment (left/center/right)
///
/// Example usage:
/// ```dart
/// showModalBottomSheet(
///   context: context,
///   builder: (context) => SubtitleStylingMenu(
///     initialConfig: currentSubtitleConfig,
///     onConfigChanged: (config) {
///       // Apply new configuration
///     },
///   ),
/// );
/// ```
class SubtitleStylingMenu extends StatefulWidget {
  /// Initial subtitle configuration
  final SubtitleConfig initialConfig;

  /// Callback when configuration changes
  final ValueChanged<SubtitleConfig>? onConfigChanged;

  /// Whether to show live preview
  final bool showPreview;

  const SubtitleStylingMenu({
    super.key,
    required this.initialConfig,
    this.onConfigChanged,
    this.showPreview = true,
  });

  @override
  State<SubtitleStylingMenu> createState() => _SubtitleStylingMenuState();
}

class _SubtitleStylingMenuState extends State<SubtitleStylingMenu> {
  late SubtitleConfig _config;

  // Preset colors for quick selection
  static const List<Color> _textColorPresets = [
    Colors.white,
    Colors.black,
    Colors.yellow,
    Colors.cyan,
    Colors.green,
    Colors.red,
    Colors.blue,
    Colors.orange,
  ];

  static const List<Color> _backgroundColorPresets = [
    Colors.black,
    Colors.white,
    Colors.transparent,
    Color(0x80000000), // Semi-transparent black
    Color(0x80FFFFFF), // Semi-transparent white
  ];

  @override
  void initState() {
    super.initState();
    _config = widget.initialConfig;
  }

  void _updateConfig(SubtitleConfig newConfig) {
    setState(() {
      _config = newConfig;
    });
    widget.onConfigChanged?.call(newConfig);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
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
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.text_fields,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  'Subtitle Styling',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Font size
                  _buildSectionTitle('Font Size'),
                  _buildFontSizeSlider(),
                  const SizedBox(height: 24),

                  // Text color
                  _buildSectionTitle('Text Color'),
                  _buildColorPicker(
                    currentColor: Color(_config.fontColor),
                    presets: _textColorPresets,
                    onColorSelected: (color) {
                      _updateConfig(_config.copyWith(
                        fontColor: color.toARGB32(),
                      ));
                    },
                  ),
                  const SizedBox(height: 24),

                  // Background
                  _buildSectionTitle('Background'),
                  _buildBackgroundControls(),
                  const SizedBox(height: 24),

                  // Outline
                  _buildSectionTitle('Text Outline'),
                  _buildOutlineControls(),
                  const SizedBox(height: 24),

                  // Position
                  _buildSectionTitle('Position'),
                  _buildPositionSlider(),
                  const SizedBox(height: 24),

                  // Alignment
                  _buildSectionTitle('Alignment'),
                  _buildAlignmentSelector(),
                  const SizedBox(height: 24),

                  // Preview
                  if (widget.showPreview) ...[
                    _buildSectionTitle('Preview'),
                    _buildPreview(),
                  ],
                ],
              ),
            ),
          ),

          // Bottom safe area
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  Widget _buildFontSizeSlider() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('8pt'),
            Text(
              '${_config.fontSize.round()}pt',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const Text('48pt'),
          ],
        ),
        Slider(
          value: _config.fontSize,
          min: 8.0,
          max: 48.0,
          divisions: 40,
          label: '${_config.fontSize.round()}pt',
          onChanged: (value) {
            _updateConfig(_config.copyWith(fontSize: value));
          },
        ),
      ],
    );
  }

  Widget _buildColorPicker({
    required Color currentColor,
    required List<Color> presets,
    required ValueChanged<Color> onColorSelected,
  }) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: presets.map((color) {
        final isSelected = color.toARGB32() == currentColor.toARGB32();
        return GestureDetector(
          onTap: () => onColorSelected(color),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey,
                width: isSelected ? 3 : 1,
              ),
            ),
            child: isSelected
                ? Icon(
                    Icons.check,
                    color: color.computeLuminance() > 0.5
                        ? Colors.black
                        : Colors.white,
                  )
                : null,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBackgroundControls() {
    final hasBackground = _config.backgroundColor != null;
    final backgroundColor = _config.backgroundColor != null
        ? Color(_config.backgroundColor!)
        : Colors.transparent;

    return Column(
      children: [
        SwitchListTile(
          title: const Text('Enable Background'),
          value: hasBackground,
          onChanged: (value) {
            _updateConfig(_config.copyWith(
              backgroundColor:
                  value ? const Color(0x80000000).toARGB32() : null,
            ));
          },
        ),
        if (hasBackground) ...[
          const SizedBox(height: 12),
          _buildColorPicker(
            currentColor: backgroundColor,
            presets: _backgroundColorPresets,
            onColorSelected: (color) {
              _updateConfig(_config.copyWith(
                backgroundColor: color.toARGB32(),
              ));
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Opacity:'),
              Expanded(
                child: Slider(
                  value: backgroundColor.a,
                  min: 0.0,
                  max: 1.0,
                  divisions: 20,
                  label: '${(backgroundColor.a * 100).round()}%',
                  onChanged: (value) {
                    final newColor = backgroundColor.withValues(alpha: value);
                    _updateConfig(_config.copyWith(
                      backgroundColor: newColor.toARGB32(),
                    ));
                  },
                ),
              ),
              Text('${(backgroundColor.a * 100).round()}%'),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildOutlineControls() {
    final outlineColor = _config.outlineColor != null
        ? Color(_config.outlineColor!)
        : Colors.black;

    return Column(
      children: [
        SwitchListTile(
          title: const Text('Enable Outline'),
          value: _config.showOutline,
          onChanged: (value) {
            _updateConfig(_config.copyWith(
              showOutline: value,
            ));
          },
        ),
        if (_config.showOutline) ...[
          const SizedBox(height: 12),
          _buildColorPicker(
            currentColor: outlineColor,
            presets: [Colors.black, Colors.white, Colors.grey, Colors.red],
            onColorSelected: (color) {
              _updateConfig(_config.copyWith(
                outlineColor: color.toARGB32(),
              ));
            },
          ),
        ],
      ],
    );
  }

  Widget _buildPositionSlider() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Top'),
            Text(
              '${(_config.verticalPosition * 100).round()}%',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const Text('Bottom'),
          ],
        ),
        Slider(
          value: _config.verticalPosition,
          min: 0.0,
          max: 1.0,
          divisions: 20,
          label: '${(_config.verticalPosition * 100).round()}%',
          onChanged: (value) {
            _updateConfig(_config.copyWith(verticalPosition: value));
          },
        ),
      ],
    );
  }

  Widget _buildAlignmentSelector() {
    return SegmentedButton<SubtitleAlignment>(
      segments: const [
        ButtonSegment(
          value: SubtitleAlignment.left,
          label: Text('Left'),
          icon: Icon(Icons.format_align_left),
        ),
        ButtonSegment(
          value: SubtitleAlignment.center,
          label: Text('Center'),
          icon: Icon(Icons.format_align_center),
        ),
        ButtonSegment(
          value: SubtitleAlignment.right,
          label: Text('Right'),
          icon: Icon(Icons.format_align_right),
        ),
      ],
      selected: {_config.horizontalAlignment},
      onSelectionChanged: (Set<SubtitleAlignment> newSelection) {
        _updateConfig(_config.copyWith(
          horizontalAlignment: newSelection.first,
        ));
      },
    );
  }

  Widget _buildPreview() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: _SubtitlePreviewText(config: _config),
      ),
    );
  }
}

/// Preview text widget showing subtitle with current styling
class _SubtitlePreviewText extends StatelessWidget {
  final SubtitleConfig config;

  const _SubtitlePreviewText({required this.config});

  @override
  Widget build(BuildContext context) {
    final textColor = Color(config.fontColor);
    final backgroundColor =
        config.backgroundColor != null ? Color(config.backgroundColor!) : null;
    final outlineColor =
        config.outlineColor != null ? Color(config.outlineColor!) : null;

    return Container(
      padding: backgroundColor != null
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
          : null,
      decoration: backgroundColor != null
          ? BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(4),
            )
          : null,
      child: Text(
        'Sample Subtitle Text',
        textAlign: _getTextAlign(),
        style: TextStyle(
          fontSize: config.fontSize,
          color: textColor,
          fontFamily: config.fontFamily,
          shadows: config.showOutline && outlineColor != null
              ? [
                  Shadow(
                    offset: const Offset(-1.5, -1.5),
                    color: outlineColor,
                  ),
                  Shadow(
                    offset: const Offset(1.5, -1.5),
                    color: outlineColor,
                  ),
                  Shadow(
                    offset: const Offset(1.5, 1.5),
                    color: outlineColor,
                  ),
                  Shadow(
                    offset: const Offset(-1.5, 1.5),
                    color: outlineColor,
                  ),
                ]
              : null,
        ),
      ),
    );
  }

  TextAlign _getTextAlign() {
    switch (config.horizontalAlignment) {
      case SubtitleAlignment.left:
        return TextAlign.left;
      case SubtitleAlignment.center:
        return TextAlign.center;
      case SubtitleAlignment.right:
        return TextAlign.right;
    }
  }
}
