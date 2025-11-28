import 'package:flutter/material.dart';
import '../../models/streaming_config.dart';
import '../../core/media_controller.dart';

/// A menu widget for selecting video quality/resolution
///
/// Displays available quality tracks with rounded pill selection style
/// Follows design specifications from docs/images/screenshots/controls_settings_video_quality.png
///
/// Features:
/// - Auto quality option with "Recommended" subtitle
/// - Quality presets: Full HD (1080p), High (720p), Medium (480p), etc.
/// - Rounded pill background for selected item
/// - Checkmark indicator for selection
///
/// Example usage:
/// ```dart
/// showModalBottomSheet(
///   context: context,
///   backgroundColor: Colors.transparent,
///   builder: (context) => QualitySelectionMenu(
///     controller: mediaController,
///   ),
/// );
/// ```
class QualitySelectionMenu extends StatefulWidget {
  /// The media controller to get quality tracks from
  final MediaController controller;

  /// Callback when a quality track is selected
  final ValueChanged<QualityTrack>? onQualitySelected;

  /// Callback when auto quality is toggled
  final ValueChanged<bool>? onAutoQualityToggled;

  const QualitySelectionMenu({
    super.key,
    required this.controller,
    this.onQualitySelected,
    this.onAutoQualityToggled,
  });

  @override
  State<QualitySelectionMenu> createState() => _QualitySelectionMenuState();
}

class _QualitySelectionMenuState extends State<QualitySelectionMenu> {
  bool _isAutoQualityEnabled = false;

  @override
  void initState() {
    super.initState();
    // Check if auto quality is enabled by checking if no track is manually selected
    final qualityTracks = widget.controller.player.qualityTracks;
    _isAutoQualityEnabled = qualityTracks.every((t) => !t.isSelected);
  }

  /// Get quality label and resolution for display
  Map<String, String> _getQualityInfo(QualityTrack track) {
    if (track.height != null) {
      final height = track.height!;
      if (height >= 2160) {
        return {'label': '4K Ultra HD', 'resolution': '2160p'};
      }
      if (height >= 1440) {
        return {'label': '2K', 'resolution': '1440p'};
      }
      if (height >= 1080) {
        return {'label': 'Full HD', 'resolution': '1080p'};
      }
      if (height >= 720) {
        return {'label': 'High', 'resolution': '720p'};
      }
      if (height >= 480) {
        return {'label': 'Medium', 'resolution': '480p'};
      }
      if (height >= 360) {
        return {'label': 'Low', 'resolution': '360p'};
      }
      return {'label': 'SD', 'resolution': '${height}p'};
    }
    return {'label': track.name, 'resolution': ''};
  }

  /// Deduplicate quality tracks by height to avoid showing duplicates
  List<QualityTrack> _deduplicateQualityTracks(List<QualityTrack> tracks) {
    final seen = <int>{};
    final deduplicated = <QualityTrack>[];

    // Sort by height descending
    final sortedTracks = List<QualityTrack>.from(tracks)
      ..sort((a, b) {
        if (a.height == null) return 1;
        if (b.height == null) return -1;
        return b.height!.compareTo(a.height!);
      });

    for (final track in sortedTracks) {
      if (track.height != null) {
        if (!seen.contains(track.height)) {
          seen.add(track.height!);
          deduplicated.add(track);
        }
      } else {
        // Keep tracks without height info
        deduplicated.add(track);
      }
    }

    return deduplicated;
  }

  void _selectAutoQuality() {
    setState(() {
      _isAutoQualityEnabled = true;
    });
    widget.onAutoQualityToggled?.call(true);
    widget.controller.player.enableAutoQuality();
    Navigator.of(context).pop();
  }

  void _selectQuality(QualityTrack track) {
    setState(() {
      _isAutoQualityEnabled = false;
    });
    widget.onQualitySelected?.call(track);
    widget.onAutoQualityToggled?.call(false);
    widget.controller.player.setQualityTrack(track);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allQualityTracks = widget.controller.player.qualityTracks;
    final qualityTracks = _deduplicateQualityTracks(allQualityTracks);

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
                    'Video Quality',
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

            // Quality options list
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  // Auto quality option
                  _QualityOption(
                    label: 'Auto',
                    subtitle: 'Recommended',
                    isSelected: _isAutoQualityEnabled,
                    onTap: _selectAutoQuality,
                    isDark: isDark,
                  ),

                  // Quality tracks
                  ...qualityTracks.map((track) {
                    final info = _getQualityInfo(track);
                    return _QualityOption(
                      label: info['label']!,
                      subtitle: info['resolution']!,
                      isSelected: !_isAutoQualityEnabled && track.isSelected,
                      onTap: () => _selectQuality(track),
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

/// Individual quality option with pill selection style
class _QualityOption extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isDark;

  const _QualityOption({
    required this.label,
    required this.subtitle,
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
                // Label and subtitle
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark
                              ? const Color(0xFFB0B0B0)
                              : const Color(0xFF808080),
                        ),
                      ),
                  ],
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
