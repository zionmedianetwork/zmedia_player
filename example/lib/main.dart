import 'package:flutter/material.dart';
import 'package:flutter_media_player/flutter_media_player.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Media Player Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MediaPlayerExamplePage(),
    );
  }
}

class MediaPlayerExamplePage extends StatefulWidget {
  const MediaPlayerExamplePage({super.key});

  @override
  State<MediaPlayerExamplePage> createState() => _MediaPlayerExamplePageState();
}

class _MediaPlayerExamplePageState extends State<MediaPlayerExamplePage> {
  late MediaController _controller;
  int _currentTabIndex = 0;

  // Sample media items
  final List<MediaItem> _sampleVideos = [
    const MediaItem(
      id: '1',
      title: 'Big Buck Bunny',
      artist: 'Blender Foundation',
      url:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
      artworkUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/BigBuckBunny.jpg',
      mediaType: MediaType.video,
    ),
    MediaItem(
      id: '2',
      title: 'Elephant Dream',
      artist: 'Blender Foundation',
      url:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
      artworkUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ElephantsDream.jpg',
      mediaType: MediaType.video,
    ),
    MediaItem(
      id: '3',
      title: 'For Bigger Blazes',
      artist: 'Google',
      url:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
      artworkUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerBlazes.jpg',
      mediaType: MediaType.video,
    ),
    MediaItem(
      id: '4',
      title: 'Sintel',
      artist: 'Blender Foundation',
      url:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4',
      artworkUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/Sintel.jpg',
      mediaType: MediaType.video,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _initializeController();
  }

  void _initializeController() {
    _controller = MediaController.create(
      config: const MediaConfig(
        autoPlay: false,
        showControls: false,
        volume: 1.0,
        speed: 1.0,
        boxFit: BoxFit.contain,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Flutter Media Player Example'),
      ),
      body: Column(
        children: [
          // Video Player Section
          Container(
            height: 250,
            color: Colors.black,
            child: MediaPlayerWidget(
              controller: _controller,
              showControls:
                  false, // Disable built-in controls to avoid double overlay
              placeholder: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.video_library, size: 64, color: Colors.white54),
                    SizedBox(height: 16),
                    Text(
                      'Select a video to start playing',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Video Selection Buttons (not duplicate controls)
          Container(
            padding: const EdgeInsets.all(16),
            child: _buildVideoSelectionButtons(),
          ),

          // Bottom Navigation
          Expanded(
            child: Column(
              children: [
                _buildTabBar(),
                Expanded(
                  child: _buildTabContent(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoSelectionButtons() {
    return Column(
      children: [
        // Video Selection Buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ElevatedButton(
                  onPressed: () => _playVideo(_sampleVideos[0]),
                  child: const Text('Video 1'),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ElevatedButton(
                  onPressed: () => _playVideo(_sampleVideos[1]),
                  child: const Text('Video 2'),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ElevatedButton(
                  onPressed: _createPlaylist,
                  child: const Text('Playlist'),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Configuration Controls (not duplicate playback controls)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Volume Control
            Column(
              children: [
                IconButton(
                  onPressed: _controller.toggleMute,
                  icon: Icon(
                    _controller.isMuted ? Icons.volume_off : Icons.volume_up,
                  ),
                ),
                const Text('Volume', style: TextStyle(fontSize: 12)),
              ],
            ),

            // Speed Control
            Column(
              children: [
                IconButton(
                  onPressed: _controller.cycleSpeed,
                  icon: const Icon(Icons.speed),
                ),
                Text('${_controller.speed}x',
                    style: const TextStyle(fontSize: 12)),
              ],
            ),

            // BoxFit Control
            Column(
              children: [
                IconButton(
                  onPressed: _cycleBoxFit,
                  icon: const Icon(Icons.aspect_ratio),
                ),
                Text(_getBoxFitName(), style: const TextStyle(fontSize: 12)),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: const Border(top: BorderSide(color: Colors.grey)),
      ),
      child: Row(
        children: [
          _buildTabButton('Videos', 0),
          _buildTabButton('Playlist', 1),
          _buildTabButton('Settings', 2),
        ],
      ),
    );
  }

  Widget _buildTabButton(String title, int index) {
    final isSelected = _currentTabIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _currentTabIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue : Colors.transparent,
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.black,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_currentTabIndex) {
      case 0:
        return _buildVideoList();
      case 1:
        return _buildPlaylistView();
      case 2:
        return _buildSettingsView();
      default:
        return _buildVideoList();
    }
  }

  Widget _buildVideoList() {
    return ListView.builder(
      itemCount: _sampleVideos.length,
      itemBuilder: (context, index) {
        final video = _sampleVideos[index];
        final isCurrentVideo = _controller.currentItem?.id == video.id;

        return ListTile(
          leading: Container(
            width: 60,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(4),
            ),
            child: video.artworkUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.network(
                      video.artworkUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(Icons.video_library);
                      },
                    ),
                  )
                : const Icon(Icons.video_library),
          ),
          title: Text(
            video.title,
            style: TextStyle(
              fontWeight: isCurrentVideo ? FontWeight.bold : FontWeight.normal,
              color: isCurrentVideo ? Colors.blue : null,
            ),
          ),
          subtitle: Text(video.artist ?? 'Unknown Artist'),
          trailing: isCurrentVideo
              ? const Icon(Icons.play_arrow, color: Colors.blue)
              : null,
          onTap: () => _playVideo(video),
        );
      },
    );
  }

  Widget _buildPlaylistView() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _createPlaylist,
                  child: const Text('Create Playlist'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: _clearPlaylist,
                  child: const Text('Clear Playlist'),
                ),
              ),
            ],
          ),
        ),
        if (_controller.currentPlaylist != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Current Playlist: ${_controller.currentPlaylist!.title}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: _controller.currentPlaylist!.items.length,
              itemBuilder: (context, index) {
                final item = _controller.currentPlaylist!.items[index];
                final isCurrent =
                    _controller.currentPlaylist!.currentIndex == index;

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isCurrent ? Colors.blue : Colors.grey,
                    child: Text('${index + 1}'),
                  ),
                  title: Text(
                    item.title,
                    style: TextStyle(
                      fontWeight:
                          isCurrent ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(item.artist ?? 'Unknown Artist'),
                  onTap: () => _controller.skipToIndex(index),
                );
              },
            ),
          ),
        ] else ...[
          const Expanded(
            child: Center(
              child: Text('No playlist created'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSettingsView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Player Settings',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),

        // Volume Slider
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Volume: ${(_controller.volume * 100).toInt()}%'),
                Slider(
                  value: _controller.volume,
                  onChanged: _controller.setVolume,
                  min: 0.0,
                  max: 1.0,
                ),
              ],
            );
          },
        ),

        const SizedBox(height: 16),

        // Speed Slider
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Speed: ${_controller.speed}x'),
                Slider(
                  value: _controller.speed,
                  onChanged: _controller.setSpeed,
                  min: 0.25,
                  max: 4.0,
                  divisions: 15,
                ),
              ],
            );
          },
        ),

        const SizedBox(height: 16),

        // BoxFit Selection
        const Text('Video Fit:'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: BoxFit.values.map((fit) {
            return ChoiceChip(
              label: Text(_getBoxFitDisplayName(fit)),
              selected: _controller.config.boxFit == fit,
              onSelected: (selected) {
                if (selected) {
                  _setBoxFit(fit);
                }
              },
            );
          }).toList(),
        ),

        const SizedBox(height: 16),

        // Player Info
        const Text(
          'Player Information',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('State: ${_controller.state.state.name}'),
                Text('Is Playing: ${_controller.isPlaying}'),
                Text('Is Buffering: ${_controller.isBuffering}'),
                Text('Has Error: ${_controller.hasError}'),
                if (_controller.hasError)
                  Text('Error: ${_controller.state.errorMessage}'),
              ],
            );
          },
        ),
      ],
    );
  }

  void _playVideo(MediaItem video) async {
    print('Loading video: ${video.title}');
    try {
      await _controller.load(video);
      print('Video loaded successfully');

      // Auto-play the video after loading
      await _controller.play();
      print('Video started playing');
    } catch (e) {
      print('Error loading video: $e');
    }
  }

  void _createPlaylist() async {
    final playlist = Playlist(
      id: 'sample_playlist',
      title: 'Sample Videos',
      items: _sampleVideos,
      currentIndex: 0,
      mode: PlaybackMode.sequential,
      repeatMode: RepeatMode.none,
    );

    await _controller.setPlaylist(playlist);
  }

  void _clearPlaylist() async {
    await _controller.stop();
    // Note: In a real implementation, you might want to add a method to clear the playlist
    setState(() {});
  }

  void _cycleBoxFit() {
    final currentFit = _controller.config.boxFit;
    final fits = BoxFit.values;
    final currentIndex = fits.indexOf(currentFit);
    final nextIndex = (currentIndex + 1) % fits.length;
    _setBoxFit(fits[nextIndex]);
  }

  void _setBoxFit(BoxFit boxFit) async {
    final newConfig = _controller.config.copyWith(boxFit: boxFit);
    await _controller.updateConfig(newConfig);
    setState(() {});
  }

  String _getBoxFitName() {
    return _getBoxFitDisplayName(_controller.config.boxFit);
  }

  String _getBoxFitDisplayName(BoxFit boxFit) {
    switch (boxFit) {
      case BoxFit.contain:
        return 'Contain';
      case BoxFit.cover:
        return 'Cover';
      case BoxFit.fill:
        return 'Fill';
      case BoxFit.fitWidth:
        return 'Fit Width';
      case BoxFit.fitHeight:
        return 'Fit Height';
      case BoxFit.none:
        return 'None';
      case BoxFit.scaleDown:
        return 'Scale Down';
    }
  }
}
