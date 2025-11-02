import 'package:flutter/material.dart';
import '../../models/subtitle_track.dart';
import '../../core/media_controller.dart';

/// A menu widget for selecting subtitle tracks
///
/// Displays available subtitle tracks with information including:
/// - Language (English, Spanish, French, etc.)
/// - Format (SRT, WebVTT, ASS, SSA, TTML)
/// - "Off" option to disable subtitles
/// - Current track indicator
///
/// Example usage:
/// ```dart
/// showModalBottomSheet(
///   context: context,
///   builder: (context) => SubtitleSelectionMenu(
///     controller: mediaController,
///   ),
/// );
/// ```
class SubtitleSelectionMenu extends StatefulWidget {
  /// The media controller to get subtitle tracks from
  final MediaController controller;

  /// Callback when a subtitle track is selected
  final ValueChanged<SubtitleTrack?>? onSubtitleSelected;

  /// Whether to show format information
  final bool showFormat;

  const SubtitleSelectionMenu({
    super.key,
    required this.controller,
    this.onSubtitleSelected,
    this.showFormat = true,
  });

  @override
  State<SubtitleSelectionMenu> createState() => _SubtitleSelectionMenuState();
}

class _SubtitleSelectionMenuState extends State<SubtitleSelectionMenu> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleTracks = widget.controller.player.subtitleTracks;
    final selectedTrack = widget.controller.player.selectedSubtitleTrack;

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
                  Icons.closed_caption,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  'Subtitles',
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

          // Off option
          ListTile(
            leading: Container(
              width: 56,
              height: 32,
              decoration: BoxDecoration(
                color: selectedTrack == null
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: selectedTrack == null
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.subtitles_off,
                  size: 20,
                  color: selectedTrack == null
                      ? theme.colorScheme.primary
                      : theme.textTheme.bodyMedium?.color,
                ),
              ),
            ),
            title: Text(
              'Off',
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight:
                    selectedTrack == null ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            trailing: selectedTrack == null
                ? Icon(
                    Icons.check_circle,
                    color: theme.colorScheme.primary,
                  )
                : null,
            onTap: () {
              widget.onSubtitleSelected?.call(null);
              widget.controller.player.setSubtitleTrack(null);
              Navigator.of(context).pop();
            },
          ),

          const Divider(height: 1),

          // Subtitle tracks list
          if (subtitleTracks.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(Icons.info_outline, size: 48, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No subtitle tracks available',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: subtitleTracks.length,
                itemBuilder: (context, index) {
                  final track = subtitleTracks[index];
                  return _SubtitleTrackTile(
                    track: track,
                    isSelected: track.isSelected,
                    showFormat: widget.showFormat,
                    onTap: () {
                      widget.onSubtitleSelected?.call(track);
                      widget.controller.player.setSubtitleTrack(track);
                      Navigator.of(context).pop();
                    },
                  );
                },
              ),
            ),

          // Bottom safe area
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

/// Individual subtitle track tile
class _SubtitleTrackTile extends StatelessWidget {
  final SubtitleTrack track;
  final bool isSelected;
  final bool showFormat;
  final VoidCallback? onTap;

  const _SubtitleTrackTile({
    required this.track,
    required this.isSelected,
    this.showFormat = true,
    this.onTap,
  });

  String _getLanguageLabel() {
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

  String _getLanguageAbbreviation() {
    if (track.language != null) {
      return track.language!.toUpperCase();
    }
    // If no language code, try to extract from title
    final titleLower = track.title.toLowerCase();
    if (titleLower.contains('english')) return 'EN';
    if (titleLower.contains('spanish')) return 'ES';
    if (titleLower.contains('french')) return 'FR';
    return 'CC';
  }

  String _getFormatLabel() {
    switch (track.format) {
      case SubtitleFormat.srt:
        return 'SRT';
      case SubtitleFormat.webvtt:
        return 'WebVTT';
      case SubtitleFormat.ass:
        return 'ASS';
      case SubtitleFormat.ssa:
        return 'SSA';
      case SubtitleFormat.ttml:
        return 'TTML';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: Container(
        width: 56,
        height: 32,
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? theme.colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Center(
          child: Text(
            _getLanguageAbbreviation(),
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.textTheme.bodyMedium?.color,
            ),
          ),
        ),
      ),
      title: Text(
        _getLanguageLabel(),
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: showFormat
          ? Text(
              _getFormatLabel(),
              style: theme.textTheme.bodySmall,
            )
          : null,
      trailing: isSelected
          ? Icon(
              Icons.check_circle,
              color: theme.colorScheme.primary,
            )
          : null,
      onTap: onTap,
    );
  }
}
