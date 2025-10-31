import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';

/// Demonstrates Phase 1 & Phase 2 features:
/// - Phase 1: Adaptive buffering, buffer health monitoring, network quality
/// - Phase 2: HLS/DASH streaming, quality selection, subtitle tracks, ABR
class StreamingDemoPage extends StatefulWidget {
  const StreamingDemoPage({super.key});

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
    MediaItem(
      id: 'alelouyatv',
      title: 'Alelouya TV Live',
      url: 'https://streaming-dev.zionmedianetwork.com/livegospel/index.m3u8',
      mediaType: MediaType.video,
      metadata: const {'description': 'Alelouya TV Live Stream'},
      isLive: true,
    ),
  ];

  int _selectedVideoIndex = 0;
  bool _showQualitySettings = false;
  bool _showSubtitleSettings = false;
  String _bandwidthInfo = 'Estimating...';

  // Phase 1: Buffer health monitoring
  BufferHealth? _bufferHealth;
  NetworkQuality _networkQuality = NetworkQuality.unknown;
  BufferStatistics? _bufferStatistics;
  bool _showBufferDetails = false;

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
      config: const MediaConfig(
        autoPlay: false,
        volume: 0.8,
        hlsConfig: HlsConfig(
          enableAdaptiveBitrate: true,
          enableLiveStream: true,
          enableSegmentPrefetch: true,
          maxPrefetchSegments: 3,
          enableAutoQualitySwitch: true,
        ),
        dashConfig: DashConfig(
          enableAdaptiveBitrate: true,
          enableMpdCaching: true,
        ),
        subtitleConfig: SubtitleConfig(
          fontSize: 18.0,
          fontColor: 0xFFFFFFFF,
          showOutline: true,
          outlineColor: 0xFF000000,
        ),
        cacheConfig: CacheConfig(
          enabled: true,
          maxCacheSize: 200 * 1024 * 1024,
        ),
      ),
    );

    // Setup bandwidth listener for native updates
    _setupBandwidthListener();

    // Phase 1: Setup buffer health listener
    _setupBufferHealthListener();

    // Load initial video
    _loadVideo(_selectedVideoIndex);
  }

  // Listen to bandwidth updates from native implementation
  void _setupBandwidthListener() {
    _controller.player.bandwidthStream.listen((bandwidth) {
      if (mounted) {
        // Update streaming service with native bandwidth
        _streamingService.updateBandwidth(bandwidth);
        setState(() {
          _bandwidthInfo = _streamingService.getFormattedBandwidth();
        });
      }
    });

    // Listen to quality track changes to update UI
    _controller.player.qualityTracksStream.listen((tracks) {
      if (mounted) {
        setState(() {
          // Quality tracks updated - UI will rebuild
        });
      }
    });
  }

  // Phase 1: Listen to buffer health updates
  void _setupBufferHealthListener() {
    _controller.player.bufferHealthStream.listen((health) {
      if (mounted) {
        setState(() {
          _bufferHealth = health;
          _networkQuality = _controller.player.networkQuality;
          _bufferStatistics = _controller.player.bufferStatistics;
        });
      }
    });
  }

  Future<void> _loadVideo(int index) async {
    try {
      final video = _streamingVideos[index];

      // Check for DASH on iOS (not supported by AVPlayer)
      if (Theme.of(context).platform == TargetPlatform.iOS &&
          video.url.contains('.mpd')) {
        _showError('DASH streams are not supported on iOS.\n'
            'iOS only supports HLS (.m3u8) streams.\n'
            'Please select an HLS stream instead.');
        return;
      }

      // Stop current playback first
      await _controller.stop();

      // Small delay to ensure clean state
      await Future.delayed(const Duration(milliseconds: 100));

      // Load new video
      await _controller.load(video);

      setState(() {
        _selectedVideoIndex = index;
      });

      // Auto-play the video
      await Future.delayed(const Duration(milliseconds: 300));
      await _controller.play();
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
        title: const Text('Streaming Demo (Phase 1 & 2)'),
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
                customControls: MediaControls(
                  controller: _controller,
                  title: _streamingVideos[_selectedVideoIndex].title,
                  showCastButton: true,
                  showPipButton: true,
                  showSettingsButton: true,
                  allowFullscreen: true,
                  showSubtitleControls: true,
                  showSpeedControls: true,
                  showVolumeControls: true,
                  showPlaylistControls: false,
                ),
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

          // Phase 1: Buffer Health Panel
          _buildBufferHealthPanel(),

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
                final isDash = video.url.contains('.mpd');
                final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
                final isUnsupported = isDash && isIOS;

                return Card(
                  color: isSelected
                      ? Colors.deepPurple[100]
                      : isUnsupported
                          ? Colors.grey[300]
                          : null,
                  child: ListTile(
                    leading: Icon(
                      Icons.play_circle_outline,
                      color: isUnsupported ? Colors.grey : null,
                    ),
                    title: Row(
                      children: [
                        Expanded(child: Text(video.title)),
                        if (isUnsupported)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'iOS unsupported',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                            ),
                          ),
                      ],
                    ),
                    subtitle: Text(
                      video.metadata?['description'] as String? ?? '',
                      style: TextStyle(
                        color: isUnsupported ? Colors.grey : null,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : null,
                    onTap: isUnsupported ? null : () => _loadVideo(index),
                    enabled: !isUnsupported,
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

  // Phase 1: Build buffer health monitoring panel
  Widget _buildBufferHealthPanel() {
    if (_bufferHealth == null) {
      return const SizedBox.shrink();
    }

    final health = _bufferHealth!;
    final statusColor = _getBufferStatusColor(health.status);
    final networkQualityText = _networkQuality.name.toUpperCase();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue[900],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.analytics, color: statusColor, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Buffer Health (Phase 1)',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: Icon(
                  _showBufferDetails ? Icons.expand_less : Icons.expand_more,
                  color: Colors.white70,
                ),
                onPressed: () =>
                    setState(() => _showBufferDetails = !_showBufferDetails),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Main metrics row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildBufferMetric(
                'Buffer',
                '${(health.bufferedDurationMs / 1000).toStringAsFixed(1)}s',
                statusColor,
              ),
              _buildBufferMetric(
                'Status',
                health.status.name.toUpperCase(),
                statusColor,
              ),
              _buildBufferMetric(
                'Network',
                networkQualityText,
                _getNetworkQualityColor(_networkQuality),
              ),
              _buildBufferMetric(
                'Ratio',
                '${(health.bufferRatio * 100).toStringAsFixed(0)}%',
                statusColor,
              ),
            ],
          ),

          // Detailed stats (expandable)
          if (_showBufferDetails) ...[
            const Divider(color: Colors.white24, height: 16),
            _buildDetailedStats(health),
          ],
        ],
      ),
    );
  }

  Widget _buildBufferMetric(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailedStats(BufferHealth health) {
    final stats = _bufferStatistics;
    if (stats == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Session Statistics',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _buildStatItem('Events', stats.totalBufferEvents.toString()),
            _buildStatItem('Underruns', stats.underrunCount.toString()),
            _buildStatItem(
              'Avg Buffer',
              '${(stats.averageBufferDuration.inMilliseconds / 1000).toStringAsFixed(1)}s',
            ),
            _buildStatItem(
              'Min Buffer',
              '${(stats.minBufferDuration.inMilliseconds / 1000).toStringAsFixed(1)}s',
            ),
            _buildStatItem(
              'Max Buffer',
              '${(stats.maxBufferDuration.inMilliseconds / 1000).toStringAsFixed(1)}s',
            ),
            _buildStatItem(
              'Rebuffer %',
              '${(stats.rebufferRatio * 100).toStringAsFixed(2)}%',
            ),
          ],
        ),
        if (health.shouldReduceQuality) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.orange),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning, color: Colors.orange, size: 16),
                const SizedBox(width: 4),
                Text(
                  health.warning ?? 'Consider reducing quality',
                  style: const TextStyle(
                    color: Colors.orange,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatItem(String label, String value) {
    return SizedBox(
      width: 80,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 10,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Color _getBufferStatusColor(BufferStatus status) {
    switch (status) {
      case BufferStatus.healthy:
        return Colors.green;
      case BufferStatus.warning:
        return Colors.amber;
      case BufferStatus.critical:
        return Colors.orange;
      case BufferStatus.underrun:
        return Colors.red;
    }
  }

  Color _getNetworkQualityColor(NetworkQuality quality) {
    switch (quality) {
      case NetworkQuality.excellent:
        return Colors.green;
      case NetworkQuality.good:
        return Colors.lightGreen;
      case NetworkQuality.fair:
        return Colors.amber;
      case NetworkQuality.poor:
        return Colors.orange;
      case NetworkQuality.offline:
        return Colors.red;
      case NetworkQuality.unknown:
        return Colors.grey;
    }
  }

  Widget _buildQualitySettingsSheet() {
    final qualityTracks = _controller.player.qualityTracks;

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
                Text(
                  'Video Quality (${qualityTracks.length})',
                  style: const TextStyle(
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

          // Quality Track Options or Empty State
          Expanded(
            child: qualityTracks.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.info_outline, size: 48, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'Loading quality options...',
                          style: TextStyle(color: Colors.grey),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Quality tracks will appear after\nthe stream starts playing',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: qualityTracks.length,
                    itemBuilder: (context, index) {
                      final track = qualityTracks[index];
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
        const SnackBar(
          content: Text(
              'Auto quality enabled - Player will adapt based on bandwidth'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      _showError('Auto quality: $e');
    }
  }

  void _setQuality(QualityTrack track) {
    try {
      _controller.player.setQualityTrack(track);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Quality locked to: ${track.name}'),
          backgroundColor: Colors.blue,
        ),
      );
    } catch (e) {
      _showError('Set quality: $e');
    }
  }

  Future<void> _downloadForOffline() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Download feature: Native implementation coming soon!\n\n'
            'The download API is ready on the Dart side.\n'
            'Full functionality requires proper HTTP stream URLs.'),
        duration: Duration(seconds: 4),
        backgroundColor: Colors.orange,
      ),
    );

    // NOTE: Download would work with proper progressive download URLs
    // HLS/DASH streams need special handling for offline storage
    // Current URLs are streaming manifests, not single files
    /*
    try {
      final currentVideo = _streamingVideos[_selectedVideoIndex];
      await _cacheService.downloadAndCache(currentVideo);
    } catch (e) {
      _showError('Download: $e');
    }
    */
  }
}
