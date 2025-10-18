import 'package:flutter/material.dart';
import 'package:flutter_media_player/flutter_media_player.dart';

/// Demonstrates Phase 2 features: HLS/DASH streaming, quality selection,
/// subtitle tracks, and adaptive bitrate streaming
class StreamingDemoPage extends StatefulWidget {
  const StreamingDemoPage({Key? key}) : super(key: key);

  @override
  State<StreamingDemoPage> createState() => _StreamingDemoPageState();
}

class _StreamingDemoPageState extends State<StreamingDemoPage> {
  late MediaController _controller;
  late StreamingService _streamingService;
  late CacheService _cacheService;

  // Sample HLS/DASH URLs (using common test streams)
  final List<MediaItem> _streamingVideos = [
    MediaItem(
      id: 'hls_sample_1',
      title: 'Big Buck Bunny (HLS)',
      url: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
      mediaType: MediaType.video,
      artworkUrl: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.jpg',
      metadata: const {'description': 'HLS adaptive streaming demo'},
    ),
    MediaItem(
      id: 'dash_sample_1',
      title: 'Sintel (DASH)',
      url: 'https://dash.akamaized.net/akamai/bbb_30fps/bbb_30fps.mpd',
      mediaType: MediaType.video,
      metadata: const {'description': 'DASH adaptive streaming demo'},
    ),
  ];

  int _selectedVideoIndex = 0;
  bool _showQualitySettings = false;
  bool _showSubtitleSettings = false;
  String _bandwidthInfo = 'Estimating...';

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  void _initializePlayer() {
    // Initialize streaming service with configuration
    _streamingService = StreamingService(
      const StreamingConfig(
        enableAdaptiveBitrate: true,
        bitrateStrategy: BitrateSelectionStrategy.auto,
        enableAutoQualitySwitch: true,
        qualitySwitchThreshold: 0.8,
        enableBandwidthEstimation: true,
      ),
    );

    // Initialize cache service
    _cacheService = CacheService(
      const CacheConfig(
        maxCacheSize: 200 * 1024 * 1024, // 200MB
        cacheExpiration: Duration(days: 7),
        enabled: true,
      ),
    );

    // Initialize media controller with streaming configuration
    _controller = MediaController.create(
      config: MediaConfig(
        autoPlay: false,
        volume: 0.8,
        hlsConfig: const HlsConfig(
          enableAdaptiveBitrate: true,
          enableLiveStream: false,
          enableSegmentPrefetch: true,
          maxPrefetchSegments: 3,
        ),
        dashConfig: const DashConfig(
          enableAdaptiveBitrate: true,
          enableMpdCaching: true,
        ),
        subtitleConfig: const SubtitleConfig(
          fontSize: 18.0,
          fontColor: 0xFFFFFFFF,
          showOutline: true,
          outlineColor: 0xFF000000,
        ),
        cacheConfig: const CacheConfig(
          enabled: true,
          maxCacheSize: 200 * 1024 * 1024,
        ),
      ),
    );

    // Listen to bandwidth updates
    _streamingService.bandwidthStream.listen((bandwidth) {
      if (mounted) {
        setState(() {
          _bandwidthInfo = _streamingService.getFormattedBandwidth();
        });
      }
    });

    // Listen to quality changes
    _streamingService.qualityStream.listen((quality) {
      if (mounted && quality != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Quality changed to: ${quality.name}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });

    // Load initial video
    _loadVideo(_selectedVideoIndex);
  }

  Future<void> _loadVideo(int index) async {
    try {
      await _controller.load(_streamingVideos[index]);
      setState(() {
        _selectedVideoIndex = index;
      });
    } catch (e) {
      _showError('Failed to load video: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _streamingService.dispose();
    _cacheService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Streaming Demo (Phase 2)'),
        backgroundColor: Colors.deepPurple,
      ),
      body: Column(
        children: [
          // Video Player
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              color: Colors.black,
              child: MediaPlayerWidget(
                controller: _controller,
                showControls: true,
              ),
            ),
          ),

          // Streaming Info Panel
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[900],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildInfoItem(
                  Icons.speed,
                  'Bandwidth',
                  _bandwidthInfo,
                ),
                _buildInfoItem(
                  Icons.high_quality,
                  'Quality',
                  _controller.player.selectedQualityTrack?.name ?? 'Auto',
                ),
                _buildInfoItem(
                  Icons.subtitles,
                  'Subtitles',
                  _controller.player.selectedSubtitleTrack?.title ?? 'Off',
                ),
              ],
            ),
          ),

          // Control Buttons
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: () => setState(() => _showQualitySettings = true),
                  icon: const Icon(Icons.settings),
                  label: const Text('Quality'),
                ),
                ElevatedButton.icon(
                  onPressed: () => setState(() => _showSubtitleSettings = true),
                  icon: const Icon(Icons.closed_caption),
                  label: const Text('Subtitles'),
                ),
                ElevatedButton.icon(
                  onPressed: _toggleAutoQuality,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Auto Quality'),
                ),
                ElevatedButton.icon(
                  onPressed: _downloadForOffline,
                  icon: const Icon(Icons.download),
                  label: const Text('Download'),
                ),
              ],
            ),
          ),

          // Video Selection
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _streamingVideos.length,
              itemBuilder: (context, index) {
                final video = _streamingVideos[index];
                final isSelected = index == _selectedVideoIndex;

                return Card(
                  color: isSelected ? Colors.deepPurple[100] : null,
                  child: ListTile(
                    leading: const Icon(Icons.play_circle_outline),
                    title: Text(video.title),
                    subtitle:
                        Text(video.metadata?['description'] as String? ?? ''),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : null,
                    onTap: () => _loadVideo(index),
                  ),
                );
              },
            ),
          ),
        ],
      ),

      // Quality Settings Bottom Sheet
      bottomSheet: _showQualitySettings
          ? _buildQualitySettingsSheet()
          : _showSubtitleSettings
              ? _buildSubtitleSettingsSheet()
              : null,
    );
  }

  Widget _buildInfoItem(IconData icon, String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildQualitySettingsSheet() {
    return Container(
      height: 300,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Video Quality',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _showQualitySettings = false),
                ),
              ],
            ),
          ),
          const Divider(),

          // Auto Quality Option
          ListTile(
            leading: const Icon(Icons.auto_awesome),
            title: const Text('Auto (Recommended)'),
            subtitle: const Text('Adapts to network conditions'),
            trailing: _controller.player.selectedQualityTrack == null
                ? const Icon(Icons.check, color: Colors.green)
                : null,
            onTap: () {
              _toggleAutoQuality();
              setState(() => _showQualitySettings = false);
            },
          ),

          // Quality Track Options
          Expanded(
            child: ListView.builder(
              itemCount: _controller.player.qualityTracks.length,
              itemBuilder: (context, index) {
                final track = _controller.player.qualityTracks[index];
                return ListTile(
                  leading: const Icon(Icons.high_quality),
                  title: Text(track.name),
                  subtitle: Text(
                    '${track.width}x${track.height} • ${(track.bitrate / 1000).toStringAsFixed(0)} Kbps',
                  ),
                  trailing: track.isSelected
                      ? const Icon(Icons.check, color: Colors.green)
                      : null,
                  onTap: () {
                    _setQuality(track);
                    setState(() => _showQualitySettings = false);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubtitleSettingsSheet() {
    return Container(
      height: 300,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Subtitles',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () =>
                      setState(() => _showSubtitleSettings = false),
                ),
              ],
            ),
          ),
          const Divider(),

          // Off Option
          ListTile(
            leading: const Icon(Icons.subtitles_off),
            title: const Text('Off'),
            trailing: _controller.player.selectedSubtitleTrack == null
                ? const Icon(Icons.check, color: Colors.green)
                : null,
            onTap: () {
              _controller.disableSubtitles();
              setState(() => _showSubtitleSettings = false);
            },
          ),

          // Subtitle Track Options
          Expanded(
            child: ListView.builder(
              itemCount: _controller.player.subtitleTracks.length,
              itemBuilder: (context, index) {
                final track = _controller.player.subtitleTracks[index];
                return ListTile(
                  leading: const Icon(Icons.closed_caption),
                  title: Text(track.title),
                  subtitle:
                      track.language != null ? Text(track.language!) : null,
                  trailing: track.isSelected
                      ? const Icon(Icons.check, color: Colors.green)
                      : null,
                  onTap: () {
                    _controller.setSubtitleTrack(track);
                    setState(() => _showSubtitleSettings = false);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _toggleAutoQuality() {
    try {
      _controller.player.enableAutoQuality();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Auto quality enabled')),
      );
    } catch (e) {
      _showError('Failed to enable auto quality: $e');
    }
  }

  void _setQuality(QualityTrack track) {
    try {
      _controller.player.setQualityTrack(track);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Quality set to: ${track.name}')),
      );
    } catch (e) {
      _showError('Failed to set quality: $e');
    }
  }

  Future<void> _downloadForOffline() async {
    try {
      final currentVideo = _streamingVideos[_selectedVideoIndex];

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Download started...'),
          duration: Duration(seconds: 2),
        ),
      );

      // Start download with progress tracking
      _cacheService.downloadProgressStream.listen((progress) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Downloading: ${progress.formattedProgress} '
                '(${progress.formattedDownloadedSize} / ${progress.formattedTotalSize})',
              ),
              duration: const Duration(milliseconds: 500),
            ),
          );
        }
      });

      await _cacheService.downloadAndCache(currentVideo);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Download completed! Video is now available offline.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _showError('Download failed: $e');
    }
  }
}
