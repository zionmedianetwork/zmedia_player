import 'package:flutter/material.dart';
import '../../models/subtitle_track.dart';
import '../../core/media_controller.dart';

/// A menu widget for selecting subtitle tracks
///
/// Displays available subtitle tracks with rounded pill selection style
/// Follows design specifications from docs/images/screenshots/controls_settings_subtitle.png
///
/// Features:
/// - "Off" option to disable subtitles
/// - Language options (English, Spanish, French, etc.)
/// - Rounded pill background for selected item
/// - Checkmark indicator for selection
///
/// Example usage:
/// ```dart
/// showModalBottomSheet(
///   context: context,
///   backgroundColor: Colors.transparent,
///   builder: (context) => SubtitleSelectionMenu(
///     controller: mediaController,
///   ),
/// );
/// ```
class SubtitleSelectionMenu extends StatelessWidget {
  /// The media controller to get subtitle tracks from
  final MediaController controller;

  /// Callback when a subtitle track is selected
  final ValueChanged<SubtitleTrack?>? onSubtitleSelected;

  const SubtitleSelectionMenu({
    super.key,
    required this.controller,
    this.onSubtitleSelected,
  });

  String _getLanguageLabel(SubtitleTrack track) {
    if (track.language != null) {
      final languageMap = {
        'en': 'English',
        'es': 'Spanish',
        'fr': 'French',
        'de': 'German',
        'it': 'Italian',
        'pt': 'Portuguese',
        'ru': 'Russian',
        'ja': 'Japanese',
        'ko': 'Korean',
        'zh': 'Chinese',
        'ar': 'Arabic',
        'hi': 'Hindi',
        'tr': 'Turkish',
        'nl': 'Dutch',
        'pl': 'Polish',
        'sv': 'Swedish',
        'da': 'Danish',
        'fi': 'Finnish',
        'no': 'Norwegian',
        'cs': 'Czech',
        'el': 'Greek',
        'he': 'Hebrew',
        'th': 'Thai',
        'vi': 'Vietnamese',
        'id': 'Indonesian',
      };

      return languageMap[track.language!.toLowerCase()] ??
          track.language!.toUpperCase();
    }
    return track.title;
  }

  void _selectOff(BuildContext context) {
    onSubtitleSelected?.call(null);
    controller.player.setSubtitleTrack(null);
    Navigator.of(context).pop();
  }

  void _selectTrack(BuildContext context, SubtitleTrack track) {
    onSubtitleSelected?.call(track);
    controller.player.setSubtitleTrack(track);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subtitleTracks = controller.player.subtitleTracks;
    final selectedTrack = controller.player.selectedSubtitleTrack;

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
                    'Subtitles',
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

            // Subtitle options list
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  // Off option
                  _SubtitleOption(
                    label: 'Off',
                    isSelected: selectedTrack == null,
                    onTap: () => _selectOff(context),
                    isDark: isDark,
                  ),

                  // Subtitle tracks
                  ...subtitleTracks.map((track) {
                    return _SubtitleOption(
                      label: _getLanguageLabel(track),
                      isSelected: track.isSelected,
                      onTap: () => _selectTrack(context, track),
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

/// Individual subtitle option with pill selection style
class _SubtitleOption extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isDark;

  const _SubtitleOption({
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.isDark,
  });

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
