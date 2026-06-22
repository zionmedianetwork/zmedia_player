import 'dart:async';
import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';
import '../data/sample_media.dart';
import '../widgets/player_scaffold.dart';

/// Demonstrates subtitle track management:
/// - [MediaController.setSubtitleTrack] to select a subtitle track
/// - [MediaController.disableSubtitles] to turn subtitles off
/// - [MediaController.subtitleTracks] / [MediaController.selectedSubtitleTrack]
/// - [MediaPlayer.subtitleTracksStream] for reactive updates
/// - [SubtitleConfig] within [MediaConfig] for styling
///
/// Subtitle tracks are reported by the native player via
/// onSubtitleTracksChanged once a stream with embedded/sideloaded tracks
/// begins buffering.  For MP4 files without sideloaded tracks, the list may
/// be empty.  The HLS bipbop stream serves as a more realistic test because
/// it can carry embedded text tracks.
///
/// NOTE: setSubtitleTrack validates that the requested track is present in the
/// native-reported list.  Attempting to set a track that the native player has
/// not reported will throw [InvalidStateException].
class SubtitlesPage extends StatefulWidget {
  const SubtitlesPage({super.key});

  @override
  State<SubtitlesPage> createState() => _SubtitlesPageState();
}

class _SubtitlesPageState extends State<SubtitlesPage> {
  late final MediaController _controller;
  StreamSubscription<List<SubtitleTrack>>? _trackSub;

  List<SubtitleTrack> _availableTracks = [];
  bool _isLoading = false;
  String? _error;

  // Subtitle styling demo
  double _fontSize = 16.0;
  int _fontColor = 0xFFFFFFFF;

  @override
  void initState() {
    super.initState();
    _controller = MediaController.create(
      playerId: 'subtitles',
      config: const MediaConfig(
        enableSubtitles: true,
        subtitleConfig: SubtitleConfig(
          fontSize: 16.0,
          fontColor: 0xFFFFFFFF,
          showOutline: true,
        ),
      ),
    );
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await _controller.initialize();

      // Subscribe to subtitle track changes from native player
      _trackSub?.cancel();
      _trackSub = _controller.player.subtitleTracksStream.listen((tracks) {
        if (mounted) setState(() => _availableTracks = tracks);
      });

      // Use the HLS stream which is more likely to carry subtitle tracks
      await _controller.load(SampleMedia.hlsStream);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectTrack(SubtitleTrack? track) async {
    try {
      await _controller.setSubtitleTrack(track);
      // Trigger a rebuild to reflect selected state
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not change subtitle track: $e'),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _trackSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PlayerScaffold(
      title: 'Subtitles',
      controller: _controller,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildBody(),
    );
  }

  Widget _buildError() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Error: $_error', style: const TextStyle(color: Colors.redAccent)),
        FilledButton(onPressed: _initAndLoad, child: const Text('Retry')),
      ],
    );
  }

  Widget _buildBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Subtitle Tracks'),
        _SubtitleTrackList(
          tracks: _availableTracks,
          selectedTrack: _controller.selectedSubtitleTrack,
          onSelectTrack: _selectTrack,
        ),
        const SectionHeader('Subtitle Styling'),
        _StyleControls(
          fontSize: _fontSize,
          fontColor: _fontColor,
          onFontSizeChanged: (v) => setState(() => _fontSize = v),
          onColorChanged: (c) => setState(() => _fontColor = c),
        ),
        const SizedBox(height: 16),
        _SubtitleApiNote(availableCount: _availableTracks.length),
      ],
    );
  }
}

class _SubtitleTrackList extends StatelessWidget {
  final List<SubtitleTrack> tracks;
  final SubtitleTrack? selectedTrack;
  final ValueChanged<SubtitleTrack?> onSelectTrack;

  const _SubtitleTrackList({
    required this.tracks,
    required this.selectedTrack,
    required this.onSelectTrack,
  });

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) {
      return const _WaitingHint();
    }
    return Column(
      children: [
        // Off option
        _TrackTile(
          label: 'Off',
          sublabel: 'Disable subtitles',
          isSelected: selectedTrack == null,
          onTap: () => onSelectTrack(null),
        ),
        ...tracks.map((t) => _TrackTile(
              label: t.title,
              sublabel: [
                if (t.language != null) t.language!,
                t.format.name.toUpperCase(),
              ].join(' • '),
              isSelected: selectedTrack?.id == t.id,
              onTap: () => onSelectTrack(t),
            )),
      ],
    );
  }
}

class _TrackTile extends StatelessWidget {
  final String label;
  final String sublabel;
  final bool isSelected;
  final VoidCallback onTap;

  const _TrackTile({
    required this.label,
    required this.sublabel,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
              : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      )),
                  Text(sublabel, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle,
                  color: theme.colorScheme.primary, size: 20),
          ],
        ),
      ),
    );
  }
}

class _StyleControls extends StatelessWidget {
  final double fontSize;
  final int fontColor;
  final ValueChanged<double> onFontSizeChanged;
  final ValueChanged<int> onColorChanged;

  const _StyleControls({
    required this.fontSize,
    required this.fontColor,
    required this.onFontSizeChanged,
    required this.onColorChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Font size slider
        Row(
          children: [
            const SizedBox(width: 4),
            const Icon(Icons.text_fields, size: 20),
            const SizedBox(width: 8),
            Text('Size: ${fontSize.round()}pt',
                style: Theme.of(context).textTheme.bodySmall),
            Expanded(
              child: Slider(
                min: 10,
                max: 32,
                value: fontSize,
                divisions: 11,
                onChanged: onFontSizeChanged,
              ),
            ),
          ],
        ),
        // Color picker chips
        Text('Color', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: const [
            _ColorOption(label: 'White', value: 0xFFFFFFFF),
            _ColorOption(label: 'Yellow', value: 0xFFFFFF00),
            _ColorOption(label: 'Cyan', value: 0xFF00FFFF),
            _ColorOption(label: 'Green', value: 0xFF00FF00),
          ]
              .map((opt) => _ColorChip(option: opt, onTap: onColorChanged))
              .toList(),
        ),
      ],
    );
  }
}

class _ColorOption {
  final String label;
  final int value;
  const _ColorOption({required this.label, required this.value});
}

class _ColorChip extends StatelessWidget {
  final _ColorOption option;
  final ValueChanged<int> onTap;
  const _ColorChip({required this.option, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(option.label),
      avatar: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: Color(option.value),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.grey.shade400, width: 0.5),
        ),
      ),
      onPressed: () => onTap(option.value),
    );
  }
}

class _WaitingHint extends StatelessWidget {
  const _WaitingHint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Waiting for subtitle tracks from native player. '
              'Press Play to start buffering.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _SubtitleApiNote extends StatelessWidget {
  final int availableCount;
  const _SubtitleApiNote({required this.availableCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .secondaryContainer
            .withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Available tracks: $availableCount (reported by native player).\n'
        'API: setSubtitleTrack(track) / disableSubtitles() / '
        'subtitleTracksStream / selectedSubtitleTrack.\n'
        'SubtitleConfig in MediaConfig controls rendering (fontSize, fontColor, '
        'showOutline, verticalPosition).',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
