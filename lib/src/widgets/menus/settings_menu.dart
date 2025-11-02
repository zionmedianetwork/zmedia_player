import 'package:flutter/material.dart';
import '../../models/streaming_config.dart';
import '../../core/media_controller.dart';

/// A unified settings menu with tabs for all player configurations
///
/// Provides access to:
/// - Quality/Resolution selection
/// - Audio track selection
/// - Subtitle settings (future)
/// - Playback speed (future)
/// - Other player settings (future)
///
/// Example usage:
/// ```dart
/// showModalBottomSheet(
///   context: context,
///   builder: (context) => SettingsMenu(
///     controller: mediaController,
///   ),
/// );
/// ```
class SettingsMenu extends StatefulWidget {
  /// The media controller
  final MediaController controller;

  /// Whether auto quality is currently enabled
  final bool isAutoQualityEnabled;

  /// Callback when a quality track is selected
  final ValueChanged<QualityTrack>? onQualitySelected;

  /// Callback when auto quality is toggled
  final ValueChanged<bool>? onAutoQualityToggled;

  /// Callback when an audio track is selected
  final ValueChanged<AudioTrack>? onAudioTrackSelected;

  const SettingsMenu({
    super.key,
    required this.controller,
    this.isAutoQualityEnabled = false,
    this.onQualitySelected,
    this.onAutoQualityToggled,
    this.onAudioTrackSelected,
  });

  @override
  State<SettingsMenu> createState() => _SettingsMenuState();
}

class _SettingsMenuState extends State<SettingsMenu>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late bool _isAutoQualityEnabled;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _isAutoQualityEnabled = widget.isAutoQualityEnabled;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      constraints: BoxConstraints(
        maxHeight: screenHeight * 0.6, // Max 60% of screen height
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
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.settings,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  'Settings',
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

          // Tabs
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Quality', icon: Icon(Icons.high_quality, size: 20)),
              Tab(text: 'Audio', icon: Icon(Icons.audiotrack, size: 20)),
            ],
          ),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildQualityTab(theme),
                _buildAudioTab(theme),
              ],
            ),
          ),

          // Bottom safe area
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  Widget _buildQualityTab(ThemeData theme) {
    final qualityTracks = widget.controller.player.qualityTracks;

    return Column(
      children: [
        const Divider(height: 1),

        // Auto quality toggle
        ListTile(
          leading: Icon(
            _isAutoQualityEnabled ? Icons.auto_awesome : Icons.auto_fix_off,
            color: _isAutoQualityEnabled
                ? theme.colorScheme.primary
                : theme.iconTheme.color,
          ),
          title: const Text('Auto Quality'),
          subtitle: Text(
            _isAutoQualityEnabled
                ? 'Automatically adjust quality based on network'
                : 'Manually select quality',
            style: theme.textTheme.bodySmall,
          ),
          trailing: Switch(
            value: _isAutoQualityEnabled,
            onChanged: (value) {
              setState(() {
                _isAutoQualityEnabled = value;
              });
              widget.onAutoQualityToggled?.call(value);
              if (value) {
                widget.controller.player.enableAutoQuality();
              }
            },
          ),
          onTap: () {
            final newValue = !_isAutoQualityEnabled;
            setState(() {
              _isAutoQualityEnabled = newValue;
            });
            widget.onAutoQualityToggled?.call(newValue);
            if (newValue) {
              widget.controller.player.enableAutoQuality();
            }
          },
        ),

        const Divider(height: 1),

        // Quality tracks list
        if (qualityTracks.isEmpty)
          const Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.info_outline, size: 48, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No quality tracks available',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: qualityTracks.length,
              itemBuilder: (context, index) {
                final track = qualityTracks[index];
                return _QualityTrackTile(
                  track: track,
                  isSelected: track.isSelected,
                  isDisabled: !track.isAvailable || _isAutoQualityEnabled,
                  onTap: () {
                    if (!_isAutoQualityEnabled && track.isAvailable) {
                      widget.onQualitySelected?.call(track);
                      widget.controller.player.setQualityTrack(track);
                      Navigator.of(context).pop();
                    }
                  },
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildAudioTab(ThemeData theme) {
    final audioTracks = widget.controller.player.audioTracks;

    return Column(
      children: [
        const Divider(height: 1),

        // Audio tracks list
        if (audioTracks.isEmpty)
          const Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.info_outline, size: 48, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No audio tracks available',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: audioTracks.length,
              itemBuilder: (context, index) {
                final track = audioTracks[index];
                return _AudioTrackTile(
                  track: track,
                  isSelected: track.isSelected,
                  isDisabled: !track.isAvailable,
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
      ],
    );
  }
}

/// Quality track tile
class _QualityTrackTile extends StatelessWidget {
  final QualityTrack track;
  final bool isSelected;
  final bool isDisabled;
  final VoidCallback? onTap;

  const _QualityTrackTile({
    required this.track,
    required this.isSelected,
    required this.isDisabled,
    this.onTap,
  });

  String _getQualityAbbreviation() {
    if (track.height != null) {
      final height = track.height!;
      if (height >= 2160) return '4K';
      if (height >= 1440) return '2K';
      if (height >= 1080) return 'FHD';
      if (height >= 720) return 'HD';
      if (height >= 360) return 'SD';
      return '${height}p';
    }
    return 'N/A';
  }

  String _getCleanTrackName() {
    return track.name.replaceAll(RegExp(r'\s*\(.*?\)'), '').trim();
  }

  String _getTrackInfo() {
    if (track.width != null && track.height != null) {
      return '${track.width}×${track.height}';
    }
    return '';
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
            _getQualityAbbreviation(),
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
        _getCleanTrackName(),
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: trackInfo.isNotEmpty
          ? Text(
              trackInfo,
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

/// Audio track tile
class _AudioTrackTile extends StatelessWidget {
  final AudioTrack track;
  final bool isSelected;
  final bool isDisabled;
  final VoidCallback? onTap;

  const _AudioTrackTile({
    required this.track,
    required this.isSelected,
    required this.isDisabled,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final channelLabel = _getChannelLabel();

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
      subtitle: channelLabel.isNotEmpty
          ? Text(
              channelLabel,
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
