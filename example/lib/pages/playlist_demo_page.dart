import 'package:flutter/material.dart';
import 'package:flutter_media_player/flutter_media_player.dart';
import '../data/sample_videos.dart';

class PlaylistDemoPage extends StatefulWidget {
  const PlaylistDemoPage({super.key});

  @override
  State<PlaylistDemoPage> createState() => _PlaylistDemoPageState();
}

class _PlaylistDemoPageState extends State<PlaylistDemoPage> {
  late MediaController _controller;
  bool _isInitializing = true;
  String? _error;
  PlaybackMode _playbackMode = PlaybackMode.sequential;
  RepeatMode _repeatMode = RepeatMode.none;

  // Use GlobalKey to preserve MediaPlayerWidget state across orientation changes
  final GlobalKey _playerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      setState(() {
        _isInitializing = true;
        _error = null;
      });

      _controller = MediaController.create(
        config: const MediaConfig(
          autoPlay: false,
          volume: 0.8,
          showControls: false,
          boxFit: BoxFit.contain,
        ),
      );

      await _controller.initialize();

      // Load the playlist
      final playlist = SampleVideos.fullPlaylist.copyWith(
        mode: _playbackMode,
        repeatMode: _repeatMode,
      );
      await _controller.setPlaylist(playlist);

      setState(() {
        _isInitializing = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isInitializing = false;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _changePlaybackMode(PlaybackMode mode) async {
    setState(() {
      _playbackMode = mode;
    });

    // Update playlist with new mode
    final currentPlaylist = _controller.currentPlaylist;
    if (currentPlaylist != null) {
      await _controller.setPlaylist(
        currentPlaylist.copyWith(mode: mode),
      );
    }
  }

  void _changeRepeatMode(RepeatMode mode) async {
    setState(() {
      _repeatMode = mode;
    });

    // Update playlist with new repeat mode
    final currentPlaylist = _controller.currentPlaylist;
    if (currentPlaylist != null) {
      await _controller.setPlaylist(
        currentPlaylist.copyWith(repeatMode: mode),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;
    final isLandscape = orientation == Orientation.landscape;

    // In landscape, show fullscreen video without app bar
    if (isLandscape) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Fullscreen video
            SizedBox.expand(
              child: _buildPlayer(),
            ),
            // Back button
            Positioned(
              top: 8,
              left: 8,
              child: SafeArea(
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Portrait mode - normal layout
    return Scaffold(
      appBar: AppBar(
        title: const Text('Playlist Demo'),
        actions: [
          PopupMenuButton<PlaybackMode>(
            icon: const Icon(Icons.shuffle),
            tooltip: 'Playback Mode',
            onSelected: _changePlaybackMode,
            itemBuilder: (context) => [
              CheckedPopupMenuItem(
                value: PlaybackMode.sequential,
                checked: _playbackMode == PlaybackMode.sequential,
                child: const Text('Sequential'),
              ),
              CheckedPopupMenuItem(
                value: PlaybackMode.shuffle,
                checked: _playbackMode == PlaybackMode.shuffle,
                child: const Text('Shuffle'),
              ),
            ],
          ),
          PopupMenuButton<RepeatMode>(
            icon: Icon(
              _repeatMode == RepeatMode.none
                  ? Icons.repeat
                  : _repeatMode == RepeatMode.single
                      ? Icons.repeat_one
                      : Icons.repeat_on,
            ),
            tooltip: 'Repeat Mode',
            onSelected: _changeRepeatMode,
            itemBuilder: (context) => [
              CheckedPopupMenuItem(
                value: RepeatMode.none,
                checked: _repeatMode == RepeatMode.none,
                child: const Text('No Repeat'),
              ),
              CheckedPopupMenuItem(
                value: RepeatMode.single,
                checked: _repeatMode == RepeatMode.single,
                child: const Text('Repeat One'),
              ),
              CheckedPopupMenuItem(
                value: RepeatMode.all,
                checked: _repeatMode == RepeatMode.all,
                child: const Text('Repeat All'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Video Player
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              color: Colors.black,
              child: _buildPlayer(),
            ),
          ),

          // Player Controls
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF1E293B),
            child: ListenableBuilder(
              listenable: _controller,
              builder: (context, _) {
                return Column(
                  children: [
                    // Progress Bar
                    Row(
                      children: [
                        Text(
                          _controller.formattedPosition,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                        Expanded(
                          child: Slider(
                            value:
                                _controller.position.inMilliseconds.toDouble(),
                            max: _controller.duration.inMilliseconds
                                .toDouble()
                                .clamp(1.0, double.infinity),
                            onChanged: (value) {
                              _controller.seekTo(
                                  Duration(milliseconds: value.toInt()));
                            },
                          ),
                        ),
                        Text(
                          _controller.formattedDuration,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),

                    // Playback Controls
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Previous
                        IconButton(
                          icon: Icon(
                            Icons.skip_previous,
                            color: _controller.hasPrevious
                                ? Colors.white
                                : Colors.white38,
                          ),
                          onPressed: _controller.hasPrevious
                              ? _controller.skipToPrevious
                              : null,
                          iconSize: 32,
                        ),

                        const SizedBox(width: 16),

                        // Play/Pause
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF6366F1),
                                const Color(0xFF8B5CF6),
                              ],
                            ),
                          ),
                          child: IconButton(
                            icon: Icon(
                              _controller.isPlaying
                                  ? Icons.pause
                                  : Icons.play_arrow,
                              color: Colors.white,
                            ),
                            onPressed: _controller.togglePlayPause,
                            iconSize: 32,
                          ),
                        ),

                        const SizedBox(width: 16),

                        // Next
                        IconButton(
                          icon: Icon(
                            Icons.skip_next,
                            color: _controller.hasNext
                                ? Colors.white
                                : Colors.white38,
                          ),
                          onPressed: _controller.hasNext
                              ? _controller.skipToNext
                              : null,
                          iconSize: 32,
                        ),
                      ],
                    ),

                    // Current Video Info
                    if (_controller.currentItem != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _controller.currentItem!.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (_controller.currentItem!.artist != null)
                        Text(
                          _controller.currentItem!.artist!,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                    ],
                  ],
                );
              },
            ),
          ),

          // Playlist Settings
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF0F172A),
            child: Row(
              children: [
                const Icon(Icons.settings, color: Colors.white70, size: 20),
                const SizedBox(width: 12),
                Text(
                  'Mode: ${_playbackMode.name}',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(width: 16),
                const Text('•', style: TextStyle(color: Colors.white30)),
                const SizedBox(width: 16),
                Text(
                  'Repeat: ${_repeatMode.name}',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),

          // Playlist Items
          Expanded(
            child: _buildPlaylist(),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayer() {
    if (_isInitializing) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF6366F1)),
            SizedBox(height: 16),
            Text(
              'Loading playlist...',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Error loading playlist',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _initializePlayer,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        MediaPlayerWidget(
          key: _playerKey,
          controller: _controller,
          showControls: false,
        ),
        // Tap to play/pause overlay
        GestureDetector(
          onTap: _controller.togglePlayPause,
          child: Container(
            color: Colors.transparent,
            child: Center(
              child: ListenableBuilder(
                listenable: _controller,
                builder: (context, _) {
                  if (_controller.isBuffering) {
                    return const CircularProgressIndicator(
                      color: Colors.white,
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlaylist() {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final playlist = _controller.currentPlaylist;
        if (playlist == null) {
          return const Center(
            child: Text(
              'No playlist loaded',
              style: TextStyle(color: Colors.white60),
            ),
          );
        }

        return ListView.builder(
          itemCount: playlist.items.length,
          itemBuilder: (context, index) {
            final item = playlist.items[index];
            final isCurrentItem = index == playlist.currentIndex;

            return Container(
              color: isCurrentItem
                  ? const Color(0xFF6366F1).withOpacity(0.1)
                  : null,
              child: ListTile(
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: isCurrentItem
                        ? const Color(0xFF6366F1)
                        : const Color(0xFF1E293B),
                  ),
                  child: Center(
                    child: isCurrentItem && _controller.isPlaying
                        ? const Icon(
                            Icons.equalizer,
                            color: Colors.white,
                          )
                        : Text(
                            '${index + 1}',
                            style: TextStyle(
                              color:
                                  isCurrentItem ? Colors.white : Colors.white70,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                title: Text(
                  item.title,
                  style: TextStyle(
                    color:
                        isCurrentItem ? const Color(0xFF6366F1) : Colors.white,
                    fontWeight:
                        isCurrentItem ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                subtitle: item.artist != null
                    ? Text(
                        item.artist!,
                        style: const TextStyle(color: Colors.white60),
                      )
                    : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (item.duration != null)
                      Text(
                        _formatDuration(item.duration!),
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                    const SizedBox(width: 8),
                    Icon(
                      isCurrentItem
                          ? Icons.play_circle_filled
                          : Icons.play_circle_outline,
                      color: isCurrentItem
                          ? const Color(0xFF6366F1)
                          : Colors.white54,
                    ),
                  ],
                ),
                onTap: () {
                  if (!isCurrentItem) {
                    _controller.skipToIndex(index);
                  }
                },
              ),
            );
          },
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
