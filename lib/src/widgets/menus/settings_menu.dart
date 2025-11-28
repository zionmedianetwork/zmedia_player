import 'package:flutter/material.dart';
import '../../core/media_controller.dart';
import 'quality_menu.dart';
import 'subtitle_menu.dart';
import 'speed_menu.dart';

/// A unified settings menu with navigation-based interface
///
/// Provides access to:
/// - Subtitle selection
/// - Video quality/resolution selection
/// - Playback speed selection
/// - Audio track selection (if available)
///
/// Follows design specifications from docs/images/screenshots/controls_settings.png
///
/// Example usage:
/// ```dart
/// showModalBottomSheet(
///   context: context,
///   backgroundColor: Colors.transparent,
///   builder: (context) => SettingsMenu(
///     controller: mediaController,
///   ),
/// );
/// ```
class SettingsMenu extends StatelessWidget {
  /// The media controller
  final MediaController controller;

  /// Callback when a setting is changed
  final VoidCallback? onSettingChanged;

  const SettingsMenu({
    super.key,
    required this.controller,
    this.onSettingChanged,
  });

  String _getCurrentSubtitleValue() {
    final selectedTrack = controller.player.selectedSubtitleTrack;
    if (selectedTrack == null) {
      return 'Off';
    }

    // Return language name or title
    if (selectedTrack.language != null) {
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
      };
      return languageMap[selectedTrack.language!.toLowerCase()] ??
          selectedTrack.language!.toUpperCase();
    }

    return selectedTrack.title;
  }

  String _getCurrentQualityValue() {
    final qualityTracks = controller.player.qualityTracks;
    final selectedTrack = qualityTracks.where((t) => t.isSelected).firstOrNull;

    // Check if auto quality is enabled
    // For now, we'll check if there's no manually selected track
    if (selectedTrack == null || qualityTracks.isEmpty) {
      return 'Auto';
    }

    // Return quality label
    if (selectedTrack.height != null) {
      final height = selectedTrack.height!;
      if (height >= 2160) return '4K';
      if (height >= 1440) return '2K';
      if (height >= 1080) return 'Full HD';
      if (height >= 720) return 'HD';
      if (height >= 480) return 'SD';
      return '${height}p';
    }

    return 'Auto';
  }

  String _getCurrentSpeedValue() {
    final speed = controller.speed;
    if ((speed - 1.0).abs() < 0.01) {
      return 'Normal';
    }
    return '${speed.toStringAsFixed(2)}x';
  }

  void _showSubtitleMenu(BuildContext context) {
    Navigator.of(context).pop(); // Close settings menu
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => SubtitleSelectionMenu(
        controller: controller,
        onSubtitleSelected: (track) {
          onSettingChanged?.call();
        },
      ),
    );
  }

  void _showQualityMenu(BuildContext context) {
    Navigator.of(context).pop(); // Close settings menu
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => QualitySelectionMenu(
        controller: controller,
        onQualitySelected: (track) {
          onSettingChanged?.call();
        },
      ),
    );
  }

  void _showSpeedMenu(BuildContext context) {
    Navigator.of(context).pop(); // Close settings menu
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => SpeedMenu(
        controller: controller,
        onSpeedSelected: (speed) {
          onSettingChanged?.call();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                    'Settings',
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

            // Menu items
            _SettingsMenuItem(
              icon: Icons.closed_caption_outlined,
              label: 'Subtitles',
              currentValue: _getCurrentSubtitleValue(),
              onTap: () => _showSubtitleMenu(context),
              isDark: isDark,
            ),

            _SettingsMenuItem(
              icon: Icons.play_circle_outline,
              label: 'video',
              currentValue: _getCurrentQualityValue(),
              onTap: () => _showQualityMenu(context),
              isDark: isDark,
            ),

            _SettingsMenuItem(
              icon: Icons.speed,
              label: 'Playback speed',
              currentValue: _getCurrentSpeedValue(),
              onTap: () => _showSpeedMenu(context),
              isDark: isDark,
              showDivider: false,
            ),

            // Bottom spacing
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// Individual settings menu item
class _SettingsMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String currentValue;
  final VoidCallback onTap;
  final bool isDark;
  final bool showDivider;

  const _SettingsMenuItem({
    required this.icon,
    required this.label,
    required this.currentValue,
    required this.onTap,
    required this.isDark,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Container(
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  // Icon
                  Icon(
                    icon,
                    size: 24,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  const SizedBox(width: 16),

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

                  // Current value
                  Text(
                    currentValue,
                    style: TextStyle(
                      fontSize: 15,
                      color: isDark
                          ? const Color(0xFFB0B0B0)
                          : const Color(0xFF808080),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Chevron
                  Icon(
                    Icons.chevron_right,
                    size: 24,
                    color: isDark
                        ? const Color(0xFFB0B0B0)
                        : const Color(0xFF808080),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            thickness: 0.5,
            indent: 60,
            color: isDark ? const Color(0x33FFFFFF) : const Color(0x1F000000),
          ),
      ],
    );
  }
}
