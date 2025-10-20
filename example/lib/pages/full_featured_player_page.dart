import 'package:flutter/material.dart';
import 'package:flutter_media_player/flutter_media_player.dart';
import '../data/sample_videos.dart';
import '../widgets/custom_controls.dart';

class FullFeaturedPlayerPage extends StatefulWidget {
  const FullFeaturedPlayerPage({super.key});

  @override
  State<FullFeaturedPlayerPage> createState() => _FullFeaturedPlayerPageState();
}

class _FullFeaturedPlayerPageState extends State<FullFeaturedPlayerPage> {
  late MediaController _controller;
  bool _isInitializing = true;
  String? _error;
  BoxFit _currentBoxFit = BoxFit.contain;
  bool _showDebugInfo = false;

  final List<MapEntry<BoxFit, String>> _boxFitOptions = [
    const MapEntry(BoxFit.contain, 'Contain'),
    const MapEntry(BoxFit.cover, 'Cover'),
    const MapEntry(BoxFit.fill, 'Fill'),
    const MapEntry(BoxFit.fitWidth, 'Fit Width'),
    const MapEntry(BoxFit.fitHeight, 'Fit Height'),
    const MapEntry(BoxFit.none, 'None'),
    const MapEntry(BoxFit.scaleDown, 'Scale Down'),
  ];

  final List<double> _speedOptions = [
    0.25,
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    2.0,
    4.0
  ];

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
        config: MediaConfig(
          autoPlay: false,
          volume: 0.8,
          showControls: false, // We'll use custom controls
          boxFit: _currentBoxFit,
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

  void _changeBoxFit(BoxFit boxFit) {
    setState(() {
      _currentBoxFit = boxFit;
    });
    _controller.player.setBoxFit(boxFit);
  }

  void _showBoxFitPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Video BoxFit',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              ..._boxFitOptions.map((option) {
                final isSelected = option.key == _currentBoxFit;
                return ListTile(
                  leading: Icon(
                    isSelected ? Icons.check_circle : Icons.circle_outlined,
                    color:
                        isSelected ? const Color(0xFF6366F1) : Colors.white54,
                  ),
                  title: Text(
                    option.value,
                    style: TextStyle(
                      color:
                          isSelected ? const Color(0xFF6366F1) : Colors.white,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  onTap: () {
                    _changeBoxFit(option.key);
                    Navigator.pop(context);
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showSpeedPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Playback Speed',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              ..._speedOptions.map((speed) {
                final isSelected = speed == _controller.speed;
                return ListTile(
                  leading: Icon(
                    isSelected ? Icons.check_circle : Icons.circle_outlined,
                    color:
                        isSelected ? const Color(0xFF6366F1) : Colors.white54,
                  ),
                  title: Text(
                    '${speed}x',
                    style: TextStyle(
                      color:
                          isSelected ? const Color(0xFF6366F1) : Colors.white,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  onTap: () {
                    _controller.setSpeed(speed);
                    Navigator.pop(context);
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showVideoSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          maxChildSize: 0.9,
          minChildSize: 0.5,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Select Video',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: SampleVideos.videos.length,
                    itemBuilder: (context, index) {
                      final video = SampleVideos.videos[index];
                      final isCurrentVideo =
                          _controller.currentItem?.id == video.id;

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isCurrentVideo
                              ? const Color(0xFF6366F1)
                              : Colors.white12,
                          child: isCurrentVideo
                              ? const Icon(Icons.play_arrow,
                                  color: Colors.white)
                              : Text(
                                  '${index + 1}',
                                  style: const TextStyle(color: Colors.white),
                                ),
                        ),
                        title: Text(
                          video.title,
                          style: TextStyle(
                            color: isCurrentVideo
                                ? const Color(0xFF6366F1)
                                : Colors.white,
                            fontWeight: isCurrentVideo
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        subtitle: video.artist != null
                            ? Text(
                                video.artist!,
                                style: const TextStyle(color: Colors.white60),
                              )
                            : null,
                        trailing: video.duration != null
                            ? Text(
                                _formatDuration(video.duration!),
                                style: const TextStyle(color: Colors.white60),
                              )
                            : null,
                        onTap: () async {
                          Navigator.pop(context);
                          await _controller.load(video);
                        },
                      );
                    },
                  ),
                ),
              ],
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
        title: const Text('Full Featured Player'),
        actions: [
          IconButton(
            icon: Icon(
                _showDebugInfo ? Icons.bug_report : Icons.bug_report_outlined),
            onPressed: () {
              setState(() {
                _showDebugInfo = !_showDebugInfo;
              });
            },
            tooltip: 'Toggle Debug Info',
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

          // Controls Section
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Video Info
                  ListenableBuilder(
                    listenable: _controller,
                    builder: (context, _) {
                      final item = _controller.currentItem;
                      if (item == null) return const SizedBox.shrink();

                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        color: const Color(0xFF1E293B),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            if (item.artist != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                item.artist!,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: const Color(0xFF6366F1),
                                    ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),

                  // Control Buttons
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // Primary Controls
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _ControlButton(
                              icon: Icons.video_library,
                              label: 'Videos',
                              onPressed: _showVideoSelector,
                            ),
                            _ControlButton(
                              icon: Icons.aspect_ratio,
                              label: 'BoxFit',
                              onPressed: _showBoxFitPicker,
                            ),
                            _ControlButton(
                              icon: Icons.speed,
                              label: 'Speed',
                              onPressed: _showSpeedPicker,
                            ),
                            ListenableBuilder(
                              listenable: _controller,
                              builder: (context, _) {
                                return _ControlButton(
                                  icon: _controller.isMuted
                                      ? Icons.volume_off
                                      : Icons.volume_up,
                                  label: 'Mute',
                                  onPressed: _controller.toggleMute,
                                );
                              },
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Volume Control
                        ListenableBuilder(
                          listenable: _controller,
                          builder: (context, _) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.volume_up,
                                        size: 20, color: Colors.white70),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Slider(
                                        value: _controller.volume,
                                        onChanged: (value) =>
                                            _controller.setVolume(value),
                                        min: 0.0,
                                        max: 1.0,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    SizedBox(
                                      width: 40,
                                      child: Text(
                                        '${(_controller.volume * 100).toInt()}%',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                        textAlign: TextAlign.right,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),

                        const SizedBox(height: 16),

                        // Current Settings Display
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              ListenableBuilder(
                                listenable: _controller,
                                builder: (context, _) {
                                  return Column(
                                    children: [
                                      _SettingRow(
                                        icon: Icons.aspect_ratio,
                                        label: 'BoxFit',
                                        value: _boxFitOptions
                                            .firstWhere(
                                                (e) => e.key == _currentBoxFit)
                                            .value,
                                      ),
                                      _SettingRow(
                                        icon: Icons.speed,
                                        label: 'Speed',
                                        value: '${_controller.speed}x',
                                      ),
                                      _SettingRow(
                                        icon: Icons.play_arrow,
                                        label: 'State',
                                        value: _controller.state.state.name
                                            .toUpperCase(),
                                      ),
                                      _SettingRow(
                                        icon: Icons.schedule,
                                        label: 'Position',
                                        value:
                                            '${_controller.formattedPosition} / ${_controller.formattedDuration}',
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ),

                        // Debug Info
                        if (_showDebugInfo) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.orange.withOpacity(0.3),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.bug_report,
                                        color: Colors.orange, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      'Debug Information',
                                      style: TextStyle(
                                        color: Colors.orange,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                ListenableBuilder(
                                  listenable: _controller,
                                  builder: (context, _) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _DebugRow('State',
                                            _controller.state.state.name),
                                        _DebugRow('Is Playing',
                                            _controller.isPlaying.toString()),
                                        _DebugRow('Is Paused',
                                            _controller.isPaused.toString()),
                                        _DebugRow('Is Buffering',
                                            _controller.isBuffering.toString()),
                                        _DebugRow('Is Muted',
                                            _controller.isMuted.toString()),
                                        _DebugRow('Progress',
                                            '${(_controller.progress * 100).toStringAsFixed(1)}%'),
                                        _DebugRow(
                                            'Volume',
                                            _controller.volume
                                                .toStringAsFixed(2)),
                                        _DebugRow('Speed',
                                            _controller.speed.toString()),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
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
            CircularProgressIndicator(color: Color(0xFF6366F1)),
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
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Error loading video',
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
          controller: _controller,
          showControls: false,
        ),
        CustomControls(controller: _controller),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 70,
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: const Color(0xFF6366F1)),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white70,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _SettingRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF6366F1)),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 13),
          ),
          const Spacer(),
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

class _DebugRow extends StatelessWidget {
  final String label;
  final String value;

  const _DebugRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
