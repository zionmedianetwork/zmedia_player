import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';
import '../data/sample_media.dart';
import '../widgets/player_scaffold.dart';

/// Demonstrates the simplest possible usage of ZMedia Player:
/// load a single [MediaItem] into a [MediaController] and display it
/// with [MediaPlayerWidget] and [AdaptiveMediaControls].
///
/// Features shown:
/// - [MediaController.create] factory
/// - [MediaController.initialize] + [MediaController.load]
/// - [MediaController.play] / [MediaController.pause] / [MediaController.stop]
/// - [MediaController.seekForward] / [MediaController.seekBackward]
/// - Volume and mute controls via [MediaController.setVolume] /
///   [MediaController.toggleMute]
/// - [PlaybackState] via [MediaController.state]
class SimplePlaybackPage extends StatefulWidget {
  const SimplePlaybackPage({super.key});

  @override
  State<SimplePlaybackPage> createState() => _SimplePlaybackPageState();
}

class _SimplePlaybackPageState extends State<SimplePlaybackPage> {
  late final MediaController _controller;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = MediaController.create(
      playerId: 'simple_playback',
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
    });
    try {
      await _controller.initialize();
      await _controller.load(SampleMedia.bigBuckBunny);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PlayerScaffold(
      title: 'Simple Playback',
      controller: _controller,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _ErrorCard(
        message: _error!,
        onRetry: _initAndLoad,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Now Playing'),
        _NowPlayingCard(controller: _controller),
        const SectionHeader('Playback Controls'),
        _PlaybackControls(controller: _controller),
        const SectionHeader('Volume'),
        _VolumeControls(controller: _controller),
        const SizedBox(height: 16),
        const _ApiNote(),
      ],
    );
  }
}

class _NowPlayingCard extends StatelessWidget {
  final MediaController controller;
  const _NowPlayingCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final item = controller.currentItem;
        final state = controller.state;
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item?.title ?? 'No media loaded',
                    style: Theme.of(context).textTheme.titleMedium),
                if (item?.artist != null)
                  Text(item!.artist!,
                      style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                InfoRow(label: 'State', value: state.state.name),
                InfoRow(
                  label: 'Position',
                  value:
                      '${controller.formattedPosition} / ${controller.formattedDuration}',
                ),
                InfoRow(
                  label: 'Speed',
                  value: '${state.speed}x',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PlaybackControls extends StatelessWidget {
  final MediaController controller;
  const _PlaybackControls({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              icon: Icon(
                controller.isPlaying ? Icons.pause : Icons.play_arrow,
              ),
              label: Text(controller.isPlaying ? 'Pause' : 'Play'),
              onPressed: () => controller.togglePlayPause(),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.stop),
              label: const Text('Stop'),
              onPressed: controller.isPlaying || controller.isPaused
                  ? () => controller.stop()
                  : null,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.replay_10),
              label: const Text('-10s'),
              onPressed: () => controller.seekBackward(),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.forward_10),
              label: const Text('+10s'),
              onPressed: () => controller.seekForward(),
            ),
          ],
        );
      },
    );
  }
}

class _VolumeControls extends StatelessWidget {
  final MediaController controller;
  const _VolumeControls({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Row(
          children: [
            IconButton(
              icon: Icon(
                controller.isMuted ? Icons.volume_off : Icons.volume_up,
              ),
              onPressed: () => controller.toggleMute(),
              tooltip: controller.isMuted ? 'Unmute' : 'Mute',
            ),
            Expanded(
              child: Slider(
                value: controller.isMuted ? 0.0 : controller.volume,
                onChanged: (v) => controller.setVolume(v),
                label: '${(controller.volume * 100).round()}%',
                divisions: 10,
              ),
            ),
            SizedBox(
              width: 40,
              child: Text(
                controller.isMuted
                    ? '0%'
                    : '${(controller.volume * 100).round()}%',
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Load Error',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                  fontWeight: FontWeight.bold,
                )),
            const SizedBox(height: 8),
            Text(message,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                  fontSize: 12,
                )),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _ApiNote extends StatelessWidget {
  const _ApiNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .secondaryContainer
            .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'API Used',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'MediaController.create() -> initialize() -> load(MediaItem) -> '
            'play() / pause() / stop() / seekForward() / seekBackward() / '
            'setVolume() / toggleMute()',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
