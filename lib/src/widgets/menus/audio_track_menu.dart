import 'package:flutter/material.dart';
import '../../models/streaming_config.dart';
import '../../core/media_controller.dart';

/// A menu widget for selecting audio tracks
///
/// Displays available audio tracks with information including:
/// - Language (English, Spanish, French, etc.)
/// - Channel configuration (Stereo, 5.1, 7.1)
/// - Codec information
/// - Current track indicator
///
/// Example usage:
/// ```dart
/// showModalBottomSheet(
///   context: context,
///   builder: (context) => AudioTrackMenu(
///     controller: mediaController,
///   ),
/// );
/// ```
class AudioTrackMenu extends StatefulWidget {
  /// The media controller to get audio tracks from
  final MediaController controller;

  /// Callback when an audio track is selected
  final ValueChanged<AudioTrack>? onAudioTrackSelected;

  /// Whether to show codec information
  final bool showCodec;

  /// Whether to show channel configuration
  final bool showChannels;

  /// Whether to show sample rate
  final bool showSampleRate;

  const AudioTrackMenu({
    super.key,
    required this.controller,
    this.onAudioTrackSelected,
    this.showCodec = false,
    this.showChannels = true,
    this.showSampleRate = false,
  });

  @override
  State<AudioTrackMenu> createState() => _AudioTrackMenuState();
}

class _AudioTrackMenuState extends State<AudioTrackMenu> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final audioTracks = widget.controller.player.audioTracks;

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
                  Icons.audiotrack,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  'Audio Track',
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

          // Audio tracks list
          if (audioTracks.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(Icons.info_outline, size: 48, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No audio tracks available',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: audioTracks.length,
                itemBuilder: (context, index) {
                  final track = audioTracks[index];
                  return _AudioTrackTile(
                    track: track,
                    isSelected: track.isSelected,
                    isDisabled: !track.isAvailable,
                    showCodec: widget.showCodec,
                    showChannels: widget.showChannels,
                    showSampleRate: widget.showSampleRate,
                    onTap: () {
                      if (track.isAvailable) {
                        widget.onAudioTrackSelected?.call(track);
                        widget.controller.player.setAudioTrack(track);
                        Navigator.of(context).pop();
                      }
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

/// Individual audio track tile
class _AudioTrackTile extends StatelessWidget {
  final AudioTrack track;
  final bool isSelected;
  final bool isDisabled;
  final bool showCodec;
  final bool showChannels;
  final bool showSampleRate;
  final VoidCallback? onTap;

  const _AudioTrackTile({
    required this.track,
    required this.isSelected,
    required this.isDisabled,
    this.showCodec = false,
    this.showChannels = true,
    this.showSampleRate = false,
    this.onTap,
  });

  String _getLanguageLabel() {
    if (track.language != null) {
      // Map language codes to display names
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
      };

      return languageMap[track.language!.toLowerCase()] ??
          track.language!.toUpperCase();
    }
    return 'Unknown';
  }

  String _getLanguageAbbreviation() {
    return track.language?.toUpperCase() ?? 'N/A';
  }

  String _getChannelLabel() {
    if (track.channels != null) {
      switch (track.channels!) {
        case 1:
          return 'Mono';
        case 2:
          return 'Stereo';
        case 6:
          return '5.1';
        case 8:
          return '7.1';
        default:
          return '${track.channels} ch';
      }
    }
    return '';
  }

  List<String> _getTrackInfo() {
    final info = <String>[];

    if (showChannels && track.channels != null) {
      info.add(_getChannelLabel());
    }

    if (showCodec && track.codec != null) {
      info.add(track.codec!);
    }

    if (showSampleRate && track.sampleRate != null) {
      final khz = track.sampleRate! / 1000;
      info.add('${khz.toStringAsFixed(1)} kHz');
    }

    return info;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trackInfo = _getTrackInfo();

    return ListTile(
      enabled: !isDisabled,
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
      subtitle: trackInfo.isNotEmpty
          ? Text(
              trackInfo.join(' • '),
              style: theme.textTheme.bodySmall,
            )
          : null,
      trailing: isSelected
          ? Icon(
              Icons.check_circle,
              color: theme.colorScheme.primary,
            )
          : null,
      onTap: isDisabled ? null : onTap,
    );
  }
}
