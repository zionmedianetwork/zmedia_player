import 'package:flutter/material.dart';
import '../../models/streaming_config.dart';
import '../../core/media_controller.dart';

/// A menu widget for selecting video quality/resolution
///
/// Displays available quality tracks with information including:
/// - Resolution (360p, 720p, 1080p, 4K, etc.)
/// - Bitrate and codec information
/// - Auto quality toggle
/// - Current quality indicator
///
/// Example usage:
/// ```dart
/// showModalBottomSheet(
///   context: context,
///   builder: (context) => QualitySelectionMenu(
///     controller: mediaController,
///   ),
/// );
/// ```
class QualitySelectionMenu extends StatefulWidget {
  /// The media controller to get quality tracks from
  final MediaController controller;

  /// Whether auto quality is currently enabled
  final bool isAutoQualityEnabled;

  /// Callback when a quality track is selected
  final ValueChanged<QualityTrack>? onQualitySelected;

  /// Callback when auto quality is toggled
  final ValueChanged<bool>? onAutoQualityToggled;

  /// Whether to show bitrate information
  final bool showBitrate;

  /// Whether to show codec information
  final bool showCodec;

  /// Whether to show frame rate information
  final bool showFrameRate;

  const QualitySelectionMenu({
    super.key,
    required this.controller,
    this.isAutoQualityEnabled = false,
    this.onQualitySelected,
    this.onAutoQualityToggled,
    this.showBitrate = true,
    this.showCodec = true,
    this.showFrameRate = false,
  });

  @override
  State<QualitySelectionMenu> createState() => _QualitySelectionMenuState();
}

class _QualitySelectionMenuState extends State<QualitySelectionMenu> {
  late bool _isAutoQualityEnabled;

  @override
  void initState() {
    super.initState();
    _isAutoQualityEnabled = widget.isAutoQualityEnabled;
  }

  /// Deduplicate quality tracks by height to avoid showing duplicates
  List<QualityTrack> _deduplicateQualityTracks(List<QualityTrack> tracks) {
    final seen = <int>{};
    final deduplicated = <QualityTrack>[];

    for (final track in tracks) {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allQualityTracks = widget.controller.player.qualityTracks;
    final qualityTracks = _deduplicateQualityTracks(allQualityTracks);

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
                  Icons.high_quality,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  'Quality',
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
                // Note: Disabling auto quality happens automatically when user selects a manual quality
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
              // Note: Disabling auto quality happens automatically when user selects a manual quality
            },
          ),

          const Divider(height: 1),

          // Quality tracks list
          if (qualityTracks.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(Icons.info_outline, size: 48, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No quality tracks available',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: qualityTracks.length,
                itemBuilder: (context, index) {
                  final track = qualityTracks[index];
                  return _QualityTrackTile(
                    track: track,
                    isSelected: track.isSelected,
                    isDisabled: !track.isAvailable || _isAutoQualityEnabled,
                    showBitrate: widget.showBitrate,
                    showCodec: widget.showCodec,
                    showFrameRate: widget.showFrameRate,
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

          // Bottom safe area
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

/// Individual quality track tile
class _QualityTrackTile extends StatelessWidget {
  final QualityTrack track;
  final bool isSelected;
  final bool isDisabled;
  final bool showBitrate;
  final bool showCodec;
  final bool showFrameRate;
  final VoidCallback? onTap;

  const _QualityTrackTile({
    required this.track,
    required this.isSelected,
    required this.isDisabled,
    this.showBitrate = true,
    this.showCodec = true,
    this.showFrameRate = false,
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
    // Remove bitrate in parentheses (e.g., "720p (2119Kbs)" -> "720p")
    return track.name.replaceAll(RegExp(r'\s*\(.*?\)'), '').trim();
  }

  String _getBitrateLabel() {
    final kbps = track.bitrate ~/ 1000;
    if (kbps >= 1000) {
      return '${(kbps / 1000).toStringAsFixed(1)} Mbps';
    }
    return '$kbps Kbps';
  }

  List<String> _getTrackInfo() {
    final info = <String>[];

    if (track.width != null && track.height != null) {
      info.add('${track.width}×${track.height}');
    }

    if (showBitrate) {
      info.add(_getBitrateLabel());
    }

    if (showCodec && track.codec != null) {
      info.add(track.codec!);
    }

    if (showFrameRate && track.frameRate != null) {
      info.add('${track.frameRate!.toStringAsFixed(0)} fps');
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
