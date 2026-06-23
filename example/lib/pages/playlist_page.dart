import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';
import '../data/sample_media.dart';
import '../widgets/player_scaffold.dart';

/// Demonstrates playlist management with ZMedia Player:
/// - [MediaController.setPlaylist] to load a [Playlist]
/// - [MediaController.skipToNext] / [MediaController.skipToPrevious]
/// - [MediaController.skipToIndex] for direct track selection
/// - [MediaRepeatMode] cycling (none → single → all)
/// - [PlaybackMode] toggling (sequential ↔ shuffle)
/// - Auto-advance on completion (handled natively)
///
/// NOTE: Automatic playback in shuffle mode uses a simplified shuffled-index
/// implementation in the Playlist model — not a proper shuffled queue.
class PlaylistPage extends StatefulWidget {
  const PlaylistPage({super.key});

  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  late final MediaController _controller;

  PlaybackMode _mode = PlaybackMode.sequential;
  MediaRepeatMode _repeatMode = MediaRepeatMode.none;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = MediaController.create(
      playerId: 'playlist',
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
      await _controller.setPlaylist(
        SampleMedia.samplePlaylist(mode: _mode, repeatMode: _repeatMode),
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _applyNewPlaylistOptions() async {
    final current = _controller.currentPlaylist;
    if (current == null) return;
    // Rebuild playlist with new options while preserving current index
    final updated = current.copyWith(mode: _mode, repeatMode: _repeatMode);
    try {
      await _controller.setPlaylist(updated, startIndex: current.currentIndex);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
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
      title: 'Playlist',
      controller: _controller,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorCard(message: _error!, onRetry: _initAndLoad)
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Playback Mode'),
        _ModeControls(
          mode: _mode,
          repeatMode: _repeatMode,
          onModeChanged: (m) {
            setState(() => _mode = m);
            _applyNewPlaylistOptions();
          },
          onRepeatChanged: (r) {
            setState(() => _repeatMode = r);
            _applyNewPlaylistOptions();
          },
        ),
        const SectionHeader('Navigation'),
        _NavigationControls(controller: _controller),
        const SectionHeader('Playlist'),
        _PlaylistView(controller: _controller),
      ],
    );
  }
}

class _ModeControls extends StatelessWidget {
  final PlaybackMode mode;
  final MediaRepeatMode repeatMode;
  final ValueChanged<PlaybackMode> onModeChanged;
  final ValueChanged<MediaRepeatMode> onRepeatChanged;

  const _ModeControls({
    required this.mode,
    required this.repeatMode,
    required this.onModeChanged,
    required this.onRepeatChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // Sequential vs shuffle toggle
        ChoiceChip(
          label: const Text('Sequential'),
          selected: mode == PlaybackMode.sequential,
          onSelected: (_) => onModeChanged(PlaybackMode.sequential),
          avatar: const Icon(Icons.view_list, size: 16),
        ),
        ChoiceChip(
          label: const Text('Shuffle'),
          selected: mode == PlaybackMode.shuffle,
          onSelected: (_) => onModeChanged(PlaybackMode.shuffle),
          avatar: const Icon(Icons.shuffle, size: 16),
        ),
        const SizedBox(width: 8),
        // Repeat modes
        ChoiceChip(
          label: const Text('No Repeat'),
          selected: repeatMode == MediaRepeatMode.none,
          onSelected: (_) => onRepeatChanged(MediaRepeatMode.none),
        ),
        ChoiceChip(
          label: const Text('Repeat One'),
          selected: repeatMode == MediaRepeatMode.single,
          onSelected: (_) => onRepeatChanged(MediaRepeatMode.single),
          avatar: const Icon(Icons.repeat_one, size: 16),
        ),
        ChoiceChip(
          label: const Text('Repeat All'),
          selected: repeatMode == MediaRepeatMode.all,
          onSelected: (_) => onRepeatChanged(MediaRepeatMode.all),
          avatar: const Icon(Icons.repeat, size: 16),
        ),
      ],
    );
  }
}

class _NavigationControls extends StatelessWidget {
  final MediaController controller;
  const _NavigationControls({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.outlined(
              icon: const Icon(Icons.skip_previous),
              onPressed: controller.hasPrevious
                  ? () => controller.skipToPrevious()
                  : null,
              tooltip: 'Previous',
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              icon: Icon(
                controller.isPlaying ? Icons.pause : Icons.play_arrow,
              ),
              label: Text(controller.isPlaying ? 'Pause' : 'Play'),
              onPressed: () => controller.togglePlayPause(),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              icon: const Icon(Icons.skip_next),
              onPressed:
                  controller.hasNext ? () => controller.skipToNext() : null,
              tooltip: 'Next',
            ),
          ],
        );
      },
    );
  }
}

class _PlaylistView extends StatelessWidget {
  final MediaController controller;
  const _PlaylistView({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final playlist = controller.currentPlaylist;
        if (playlist == null || playlist.items.isEmpty) {
          return const Text('No playlist loaded');
        }
        return Column(
          children: List.generate(playlist.items.length, (index) {
            final item = playlist.items[index];
            final isCurrent = index == playlist.currentIndex;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isCurrent
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isCurrent ? Icons.play_circle : Icons.play_circle_outline,
                  color: isCurrent
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 22,
                ),
              ),
              title: Text(
                item.title,
                style: TextStyle(
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                  color:
                      isCurrent ? Theme.of(context).colorScheme.primary : null,
                ),
              ),
              subtitle: item.artist != null ? Text(item.artist!) : null,
              trailing: item.duration != null
                  ? Text(
                      '${item.duration!.inMinutes}:${(item.duration!.inSeconds % 60).toString().padLeft(2, '0')}',
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  : null,
              onTap: () => controller.skipToIndex(index),
            );
          }),
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
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Error: $message',
              style: const TextStyle(color: Colors.redAccent)),
          const SizedBox(height: 8),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
