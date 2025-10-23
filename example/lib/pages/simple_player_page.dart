import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';
import '../data/sample_videos.dart';

class SimplePlayerPage extends StatefulWidget {
  const SimplePlayerPage({super.key});

  @override
  State<SimplePlayerPage> createState() => _SimplePlayerPageState();
}

class _SimplePlayerPageState extends State<SimplePlayerPage> {
  late MediaController _controller;
  bool _isInitializing = true;
  String? _error;

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
          autoPlay: true,
          volume: 1.0,
          showControls: true,
          boxFit: BoxFit.contain,
        ),
      );

      await _controller.initialize();
      await _controller.load(SampleVideos.defaultVideo);

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

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;
    final isLandscape = orientation == Orientation.landscape;

    // Build player once
    final player = _buildPlayer();

    return Scaffold(
      appBar: isLandscape ? null : AppBar(title: const Text('Simple Player')),
      backgroundColor: isLandscape ? Colors.black : null,
      body: Column(
        children: [
          // Video Player - wrapped differently based on orientation
          isLandscape
              ? Expanded(child: player)
              : AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Container(
                    color: Colors.black,
                    child: player,
                  ),
                ),

          // Info Section - only show in portrait
          if (!isLandscape)
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Video Info
                    if (_controller.currentItem != null) ...[
                      Text(
                        _controller.currentItem!.title,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      if (_controller.currentItem!.artist != null)
                        Text(
                          _controller.currentItem!.artist!,
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: const Color(0xFF6366F1),
                                  ),
                        ),
                      const SizedBox(height: 16),
                      if (_controller.currentItem!.metadata?['description'] !=
                          null)
                        Text(
                          _controller.currentItem!.metadata!['description'],
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      const SizedBox(height: 24),
                    ],

                    // Player State Info
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Player State',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          ListenableBuilder(
                            listenable: _controller,
                            builder: (context, _) {
                              return Column(
                                children: [
                                  _InfoRow(
                                    label: 'Status',
                                    value: _controller.state.state.name
                                        .toUpperCase(),
                                  ),
                                  _InfoRow(
                                    label: 'Position',
                                    value: _controller.formattedPosition,
                                  ),
                                  _InfoRow(
                                    label: 'Duration',
                                    value: _controller.formattedDuration,
                                  ),
                                  _InfoRow(
                                    label: 'Volume',
                                    value:
                                        '${(_controller.volume * 100).toInt()}%',
                                  ),
                                  _InfoRow(
                                    label: 'Speed',
                                    value: '${_controller.speed}x',
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Features
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF6366F1).withOpacity(0.1),
                            const Color(0xFF8B5CF6).withOpacity(0.1),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF6366F1).withOpacity(0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: const Color(0xFF6366F1),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'About This Demo',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'This simple player demonstrates basic video playback with default controls. '
                            'Tap the video to show/hide controls.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            '✓ Auto-play enabled\n'
                            '✓ Default controls\n'
                            '✓ Volume control\n'
                            '✓ Seek functionality\n'
                            '✓ Fullscreen support',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white60,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
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
            CircularProgressIndicator(
              color: Color(0xFF6366F1),
            ),
            SizedBox(height: 16),
            Text(
              'Initializing player...',
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
            const Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              'Error loading video',
              style: const TextStyle(
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

    return MediaPlayerWidget(
      key: _playerKey,
      controller: _controller,
      showControls: true,
      customControls: MediaControls(
        controller: _controller,
        title: _controller.currentItem?.title ?? 'Simple Player',
        showCastButton: true,
        showPipButton: true,
        showSettingsButton: true,
        allowFullscreen: true,
        showSubtitleControls: true,
        showSpeedControls: true,
        showVolumeControls: true,
        showPlaylistControls: false,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 13,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
