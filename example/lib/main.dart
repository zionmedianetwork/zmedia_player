import 'package:flutter/material.dart';
import 'package:flutter_media_player/flutter_media_player.dart';
import 'package:flutter_media_player/src/models/streaming_config.dart';
import 'package:flutter_media_player/src/models/subtitle_track.dart';
import 'package:flutter_media_player/src/core/media_config.dart';

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
    // Phase 2: HLS and subtitle examples
    MediaItem(
      id: '5',
      title: 'HLS Sample (Big Buck Bunny)',
      artist: 'Blender Foundation',
      url: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
      artworkUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/BigBuckBunny.jpg',
      mediaType: MediaType.video,
      httpHeaders: {
        'User-Agent': 'Flutter Media Player Example',
      },
    ),
    MediaItem(
      id: '6',
      title: 'DASH Sample (Sintel)',
      artist: 'Blender Foundation',
      url: 'https://dash.akamaized.net/akamai/bbb_30fps/bbb_30fps.mpd',
      artworkUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/Sintel.jpg',
      mediaType: MediaType.video,
      httpHeaders: {
        'User-Agent': 'Flutter Media Player Example',
      },
    ),
    // Additional streaming content for testing
    MediaItem(
      id: '7',
      title: 'HLS Multi-Quality (Tears of Steel)',
      artist: 'Blender Foundation',
      url:
          'https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.m3u8',
      artworkUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/TearsOfSteel.jpg',
      mediaType: MediaType.video,
      httpHeaders: {
        'User-Agent': 'Flutter Media Player Example',
      },
    ),
    MediaItem(
      id: '8',
      title: 'DASH Multi-Quality (Big Buck Bunny)',
      artist: 'Blender Foundation',
      url: 'https://dash.akamaized.net/akamai/bbb_30fps/bbb_30fps.mpd',
      artworkUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/BigBuckBunny.jpg',
      mediaType: MediaType.video,
      httpHeaders: {
        'User-Agent': 'Flutter Media Player Example',
      },
    ),
    MediaItem(
      id: '9',
      title: 'HLS Live Stream Test',
      artist: 'Live Stream',
      url: 'https://cph-p2p-msl.akamaized.net/hls/live/2000341/test01.m3u8',
      artworkUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/BigBuckBunny.jpg',
      mediaType: MediaType.video,
      httpHeaders: {
        'User-Agent': 'Flutter Media Player Example',
      },
    ),
    MediaItem(
      id: '10',
      title: 'HLS with Subtitles (Big Buck Bunny)',
      artist: 'Blender Foundation',
      url: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
      artworkUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/BigBuckBunny.jpg',
      mediaType: MediaType.video,
      httpHeaders: {
        'User-Agent': 'Flutter Media Player Example',
      },
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
        enableSubtitles: true,
        subtitleConfig: SubtitleConfig(
          fontSize: 18.0,
          fontColor: 0xFFFFFFFF,
          backgroundColor: 0x80000000,
          showOutline: true,
          outlineColor: 0xFF000000,
          verticalPosition: 0.85,
          horizontalAlignment: SubtitleAlignment.center,
        ),
        cacheConfig: CacheConfig(
          enabled: true,
          maxCacheSize: 200 * 1024 * 1024, // 200MB
          cacheExpiration: Duration(days: 30),
        ),
        hlsConfig: HlsConfig(
          enableAdaptiveBitrate: true,
          enableLiveStream: false,
          enableDvr: false,
          enableSegmentPrefetch: true,
          maxPrefetchSegments: 5,
        ),
        dashConfig: DashConfig(
          enableAdaptiveBitrate: true,
          enableLiveStream: false,
          enableDvr: false,
          enableSegmentPrefetch: true,
          maxPrefetchSegments: 5,
          enableMpdCaching: true,
          mpdCacheExpiration: Duration(minutes: 10),
        ),
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
      body: SafeArea(
        child: Column(
          children: [
            // Video Player Section - make height flexible
            Flexible(
              flex: 2,
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: 200,
                  maxHeight: 300,
                ),
                color: Colors.black,
                child: MediaPlayerWidget(
                  controller: _controller,
                  showControls:
                      true, // Disable built-in controls to avoid double overlay
                  placeholder: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.video_library,
                            size: 64, color: Colors.white54),
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
            ),

            // Video Selection Buttons - make more compact
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

        const SizedBox(height: 8),

        // Streaming Content Buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ElevatedButton(
                  onPressed: () => _playVideo(_sampleVideos[5]),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[100],
                    foregroundColor: Colors.blue[800],
                  ),
                  child: const Text('HLS', style: TextStyle(fontSize: 12)),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ElevatedButton(
                  onPressed: () => _playVideo(_sampleVideos[6]),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[100],
                    foregroundColor: Colors.green[800],
                  ),
                  child: const Text('DASH', style: TextStyle(fontSize: 12)),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ElevatedButton(
                  onPressed: () => _playVideo(_sampleVideos[7]),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple[100],
                    foregroundColor: Colors.purple[800],
                  ),
                  child: const Text('Multi-Q', style: TextStyle(fontSize: 12)),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

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
                    size: 20,
                  ),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                const Text('Volume', style: TextStyle(fontSize: 10)),
              ],
            ),

            // Speed Control
            Column(
              children: [
                IconButton(
                  onPressed: _controller.cycleSpeed,
                  icon: const Icon(Icons.speed, size: 20),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                Text('${_controller.speed}x',
                    style: const TextStyle(fontSize: 10)),
              ],
            ),

            // BoxFit Control
            Column(
              children: [
                IconButton(
                  onPressed: _cycleBoxFit,
                  icon: const Icon(Icons.aspect_ratio, size: 20),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                Text(_getBoxFitName(), style: const TextStyle(fontSize: 10)),
              ],
            ),

            // Streaming Quality Info
            Column(
              children: [
                IconButton(
                  onPressed: _showQualityInfo,
                  icon: const Icon(Icons.high_quality, size: 20),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                const Text('Quality', style: TextStyle(fontSize: 10)),
              ],
            ),
          ],
        ),

        // Streaming Status Indicator
        if (_controller.currentItem != null) ...[
          const SizedBox(height: 8),
          _buildStreamingStatus(),
        ],
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
          padding: const EdgeInsets.symmetric(vertical: 8),
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

        const SizedBox(height: 16),

        // Streaming Performance Info
        if (_controller.currentItem != null) ...[
          const Text(
            'Streaming Performance',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _buildStreamingPerformanceInfo(),
        ],
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

  /// Show streaming quality information
  void _showQualityInfo() {
    final currentItem = _controller.currentItem;
    if (currentItem == null) {
      _showSnackBar('No media loaded');
      return;
    }

    final url = currentItem.url.toLowerCase();
    String streamType = 'Unknown';
    String qualityInfo = 'No quality info available';

    if (url.contains('.m3u8')) {
      streamType = 'HLS (HTTP Live Streaming)';
      qualityInfo =
          'Adaptive bitrate streaming with automatic quality switching';
    } else if (url.contains('.mpd')) {
      streamType = 'DASH (Dynamic Adaptive Streaming over HTTP)';
      qualityInfo = 'MPEG-DASH with multiple quality tracks';
    } else if (url.contains('.mp4') || url.contains('.mov')) {
      streamType = 'Progressive Download';
      qualityInfo = 'Single quality, progressive download';
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Streaming Quality Info'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Media: ${currentItem.title}'),
            const SizedBox(height: 8),
            Text('Stream Type: $streamType'),
            const SizedBox(height: 8),
            Text('Quality: $qualityInfo'),
            const SizedBox(height: 8),
            Text('URL: ${currentItem.url}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Show a snackbar message
  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  /// Build streaming status indicator
  Widget _buildStreamingStatus() {
    final currentItem = _controller.currentItem;
    if (currentItem == null) return const SizedBox.shrink();

    final url = currentItem.url.toLowerCase();
    String streamType = 'Unknown';
    Color statusColor = Colors.grey;
    IconData statusIcon = Icons.help_outline;

    if (url.contains('.m3u8')) {
      streamType = 'HLS Streaming';
      statusColor = Colors.blue;
      statusIcon = Icons.stream;
    } else if (url.contains('.mpd')) {
      streamType = 'DASH Streaming';
      statusColor = Colors.green;
      statusIcon = Icons.high_quality;
    } else if (url.contains('.mp4') || url.contains('.mov')) {
      streamType = 'Progressive Download';
      statusColor = Colors.orange;
      statusIcon = Icons.download;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon, size: 16, color: statusColor),
          const SizedBox(width: 6),
          Text(
            streamType,
            style: TextStyle(
              fontSize: 12,
              color: statusColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Build streaming performance information
  Widget _buildStreamingPerformanceInfo() {
    final currentItem = _controller.currentItem;
    if (currentItem == null) return const SizedBox.shrink();

    final url = currentItem.url.toLowerCase();
    final isStreaming = url.contains('.m3u8') || url.contains('.mpd');

    if (!isStreaming) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text('Not a streaming source'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  url.contains('.m3u8') ? Icons.stream : Icons.high_quality,
                  color: url.contains('.m3u8') ? Colors.blue : Colors.green,
                ),
                const SizedBox(width: 8),
                Text(
                  url.contains('.m3u8') ? 'HLS Stream' : 'DASH Stream',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
                'Protocol: ${url.contains('.m3u8') ? 'HTTP Live Streaming' : 'MPEG-DASH'}'),
            Text('Adaptive Bitrate: Enabled'),
            Text('Quality Switching: Automatic'),
            if (url.contains('.m3u8')) ...[
              Text('Segment Prefetching: Enabled'),
              Text('Live Stream Support: Available'),
            ],
            if (url.contains('.mpd')) ...[
              Text('MPD Caching: Enabled'),
              Text('Multiple Quality Tracks: Available'),
            ],
          ],
        ),
      ),
    );
  }
}
