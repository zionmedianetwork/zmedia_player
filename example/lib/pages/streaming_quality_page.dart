import 'dart:async';
import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';
import '../data/sample_media.dart';
import '../widgets/player_scaffold.dart';

/// Demonstrates adaptive streaming (HLS/DASH) and manual quality selection:
/// - Loading an HLS and a DASH stream via [MediaController.load]
/// - Listening to [MediaPlayer.qualityTracksStream] for available tracks
/// - Manual track selection via [MediaController.setQualityTrack]
/// - Returning to ABR via [MediaController.enableAutoQuality]
/// - Bandwidth monitoring via [MediaPlayer.bandwidthStream]
///
/// NOTE: Quality tracks and bandwidth data arrive from the native player
/// after buffering begins.  On first run you may need to wait a few seconds
/// for the native player to report tracks.  Requires a real device / simulator
/// with network access.
class StreamingQualityPage extends StatefulWidget {
  const StreamingQualityPage({super.key});

  @override
  State<StreamingQualityPage> createState() => _StreamingQualityPageState();
}

class _StreamingQualityPageState extends State<StreamingQualityPage> {
  late final MediaController _controller;
  StreamSubscription<int>? _bandwidthSub;
  StreamSubscription<List<QualityTrack>>? _qualitySub;

  int _bandwidthBps = 0;
  List<QualityTrack> _qualityTracks = [];
  bool _isAuto = true;
  bool _isLoading = false;
  String? _error;

  /// Currently active source
  _Source _source = _Source.hls;

  @override
  void initState() {
    super.initState();
    _controller = MediaController.create(
      playerId: 'streaming_quality',
      // respectSafeArea keeps the video below the status bar / notch in
      // landscape so content is never obscured. Set immersiveLandscape: true
      // instead if you want the status bar hidden in landscape.
      config: const MediaConfig(respectSafeArea: true),
    );
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _qualityTracks = [];
      _bandwidthBps = 0;
      _isAuto = true;
    });

    try {
      await _controller.initialize();

      // Subscribe to bandwidth updates from the underlying player
      _bandwidthSub?.cancel();
      _bandwidthSub = _controller.player.bandwidthStream.listen((bps) {
        if (mounted) setState(() => _bandwidthBps = bps);
      });

      // Subscribe to quality track changes
      _qualitySub?.cancel();
      _qualitySub = _controller.player.qualityTracksStream.listen((tracks) {
        if (mounted) setState(() => _qualityTracks = tracks);
      });

      final item = _source == _Source.hls
          ? SampleMedia.hlsStream
          : SampleMedia.dashStream;
      await _controller.load(item);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectQuality(QualityTrack track) async {
    try {
      await _controller.setQualityTrack(track);
      if (mounted) setState(() => _isAuto = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Quality change failed: $e')),
        );
      }
    }
  }

  Future<void> _enableAuto() async {
    try {
      await _controller.enableAutoQuality();
      if (mounted) setState(() => _isAuto = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Auto quality failed: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _bandwidthSub?.cancel();
    _qualitySub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PlayerScaffold(
      title: 'Streaming Quality',
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
        const SizedBox(height: 8),
        FilledButton(onPressed: _initAndLoad, child: const Text('Retry')),
      ],
    );
  }

  Widget _buildBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Source'),
        _SourceSelector(
          source: _source,
          onChanged: (s) {
            setState(() => _source = s);
            _initAndLoad();
          },
        ),
        const SectionHeader('Network'),
        _BandwidthDisplay(bandwidthBps: _bandwidthBps),
        const SectionHeader('Quality Tracks'),
        if (_qualityTracks.isEmpty)
          const _WaitingForTracksHint()
        else
          _QualityTrackList(
            tracks: _qualityTracks,
            isAuto: _isAuto,
            onSelectAuto: _enableAuto,
            onSelectTrack: _selectQuality,
          ),
        const SizedBox(height: 8),
        const _StreamingNote(),
      ],
    );
  }
}

enum _Source { hls, dash }

class _SourceSelector extends StatelessWidget {
  final _Source source;
  final ValueChanged<_Source> onChanged;

  const _SourceSelector({required this.source, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_Source>(
      segments: const [
        ButtonSegment(
          value: _Source.hls,
          label: Text('HLS'),
          icon: Icon(Icons.stream),
        ),
        ButtonSegment(
          value: _Source.dash,
          label: Text('DASH'),
          icon: Icon(Icons.bar_chart),
        ),
      ],
      selected: {source},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

class _BandwidthDisplay extends StatelessWidget {
  final int bandwidthBps;
  const _BandwidthDisplay({required this.bandwidthBps});

  String get _formatted {
    if (bandwidthBps == 0) return 'Measuring...';
    if (bandwidthBps < 1000) return '$bandwidthBps bps';
    if (bandwidthBps < 1000000) {
      return '${(bandwidthBps / 1000).toStringAsFixed(1)} Kbps';
    }
    return '${(bandwidthBps / 1000000).toStringAsFixed(2)} Mbps';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.network_check, size: 20),
        const SizedBox(width: 8),
        Text('Estimated bandwidth: $_formatted'),
      ],
    );
  }
}

class _QualityTrackList extends StatelessWidget {
  final List<QualityTrack> tracks;
  final bool isAuto;
  final VoidCallback onSelectAuto;
  final ValueChanged<QualityTrack> onSelectTrack;

  const _QualityTrackList({
    required this.tracks,
    required this.isAuto,
    required this.onSelectAuto,
    required this.onSelectTrack,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Auto option
        _QualityTile(
          label: 'Auto (ABR)',
          sublabel: 'Adaptive bitrate selection',
          isSelected: isAuto,
          onTap: onSelectAuto,
        ),
        // Manual quality options
        ...tracks.map((track) {
          final res = (track.width != null && track.height != null)
              ? '${track.width}x${track.height}'
              : null;
          final kbps = '${(track.bitrate / 1000).round()} Kbps';
          return _QualityTile(
            label: track.name,
            sublabel: [if (res != null) res, kbps].join(' — '),
            isSelected: !isAuto && track.isSelected,
            onTap: () => onSelectTrack(track),
          );
        }),
      ],
    );
  }
}

class _QualityTile extends StatelessWidget {
  final String label;
  final String sublabel;
  final bool isSelected;
  final VoidCallback onTap;

  const _QualityTile({
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
          border: isSelected
              ? Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.4))
              : null,
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

class _WaitingForTracksHint extends StatelessWidget {
  const _WaitingForTracksHint();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Waiting for native player to report quality tracks '
              '(press Play first).',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _StreamingNote extends StatelessWidget {
  const _StreamingNote();

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
        'Quality tracks are reported by the native player after it begins '
        'buffering. Tap Play, then wait for tracks to appear. '
        'Bandwidth estimation runs in real-time from the native layer.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
