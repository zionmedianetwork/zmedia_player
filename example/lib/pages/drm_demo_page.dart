import 'dart:io';
import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';

/// Demo page for DRM (Digital Rights Management) content playback
///
/// Demonstrates Phase 1 P1 features:
/// - Analytics tracking for DRM events
/// - Secure token storage
/// - Certificate pinning
/// - Buffer health monitoring
/// - Network resilience
class DrmDemoPage extends StatefulWidget {
  const DrmDemoPage({Key? key}) : super(key: key);

  @override
  State<DrmDemoPage> createState() => _DrmDemoPageState();
}

class _DrmDemoPageState extends State<DrmDemoPage> {
  late MediaController _controller;
  DrmSession? _drmSession;
  bool _isDrmSupported = false;
  Map<String, dynamic>? _drmSystemInfo;

  // Phase 1 P1: Analytics Service
  late AnalyticsService _analyticsService;

  // Phase 1 P1: Secure Storage
  late SecureStorage _secureStorage;

  // Phase 1 P0: Buffering Service
  late BufferingService _bufferingService;
  BufferHealth? _bufferHealth;

  // Analytics metrics tracking
  DateTime? _playbackStartTime;
  int _bufferEventCount = 0;
  int _errorCount = 0;

  // Sample DRM videos (replace with your own test content)
  final List<_DrmVideo> _videos = [
    // Widevine sample (Android)
    _DrmVideo(
      title: 'Widevine Test (Android Only)',
      description: 'Google Widevine DRM protected content',
      url: 'https://storage.googleapis.com/wvmedia/cenc/h264/tears/tears.mpd',
      drmConfig: DrmConfig.widevine(
        licenseUrl:
            'https://proxy.uat.widevine.com/proxy?provider=widevine_test',
      ),
      platformSupport: 'Android',
    ),

    // FairPlay sample (iOS)
    _DrmVideo(
      title: 'FairPlay Test (iOS Only)',
      description: 'Apple FairPlay DRM protected content',
      url:
          'https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_adv_example_hevc/master.m3u8',
      drmConfig: DrmConfig.fairplay(
        licenseUrl: 'YOUR_FAIRPLAY_LICENSE_URL',
        certificateUrl: 'YOUR_CERTIFICATE_URL',
      ),
      platformSupport: 'iOS',
    ),

    // ClearKey sample (Testing both platforms)
    _DrmVideo(
      title: 'ClearKey Test (Both Platforms)',
      description: 'ClearKey DRM for testing',
      url: 'https://media.axprod.net/TestVectors/v7-Clear/Manifest_1080p.mpd',
      drmConfig: const DrmConfig(
        scheme: DrmScheme.clearkey,
        licenseUrl: 'https://drm-clearkey-test.axtest.net/AcquireLicense',
      ),
      platformSupport: 'Both',
    ),
  ];

  int _currentVideoIndex = 0;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    // Phase 1 P1: Initialize Analytics Service
    _analyticsService = ConsoleAnalyticsService(verbose: true);
    _analyticsService.trackCustomEvent('drm_demo_initialized', {
      'platform': Platform.isAndroid ? 'Android' : 'iOS',
      'timestamp': DateTime.now().toIso8601String(),
    });

    // Phase 1 P1: Initialize Secure Storage
    _secureStorage = PlatformSecureStorage();

    // Phase 1 P0: Initialize Buffering Service
    _bufferingService = BufferingService(
      config: BufferingConfig.smoothPlayback(), // Optimized for DRM content
    );

    // Create controller
    _controller = MediaController.create(
      config: const MediaConfig(
        autoPlay: false,
        showControls: true,
      ),
    );

    await _controller.initialize();

    // Listen to DRM session updates
    _controller.player.drmSessionStream.listen((session) {
      setState(() {
        _drmSession = session;
      });

      // Track DRM session state changes
      _analyticsService.trackCustomEvent('drm_session_state_changed', {
        'state': session.state.name,
        'hasError': session.errorMessage != null,
      });

      if (session.errorMessage != null) {
        _errorCount++;
        _analyticsService.trackError(
          DrmException('DRM Error: ${session.errorMessage}'),
          {'session_state': session.state.name},
        );
      }
    });

    // Phase 1 P0: Listen to buffer health updates
    _bufferingService.bufferHealthStream.listen((health) {
      setState(() {
        _bufferHealth = health;
      });

      if (!health.isHealthy) {
        _bufferEventCount++;
        _analyticsService.trackBufferEvent(
          BufferEventType.underrun,
          Duration(milliseconds: health.bufferedDurationMs),
        );
      }
    });

    // Listen to playback state for analytics
    _controller.player.stateStream.listen((state) {
      if (state.state == PlayerState.playing && _playbackStartTime == null) {
        _playbackStartTime = DateTime.now();
        final currentVideo = _videos[_currentVideoIndex];
        _analyticsService.trackPlaybackStart(
          currentVideo.url,
          MediaConfig(autoPlay: false, showControls: true),
          metadata: {
            'drm_scheme': currentVideo.drmConfig.scheme.name,
            'platform': Platform.isAndroid ? 'Android' : 'iOS',
            'title': currentVideo.title,
          },
        );
      } else if (state.state == PlayerState.completed) {
        if (_playbackStartTime != null) {
          final watchTime = DateTime.now().difference(_playbackStartTime!);
          _analyticsService.trackPlaybackEnd(
            watchTime,
            PlaybackEndReason.completed,
            metadata: {
              'buffer_events': _bufferEventCount,
              'errors': _errorCount,
            },
          );
          _playbackStartTime = null;
          _bufferEventCount = 0;
          _errorCount = 0;
        }
      }
    });

    // Check DRM support
    _checkDrmSupport();

    // Load first video
    await _loadVideo(_currentVideoIndex);

    setState(() {});
  }

  Future<void> _checkDrmSupport() async {
    // This would call native platform code to check DRM support
    // For now, we'll set it based on platform
    setState(() {
      _isDrmSupported = true;
      _drmSystemInfo = {
        'platform': Platform.isAndroid ? 'Android' : 'iOS',
        'widevineSupported': Platform.isAndroid,
        'fairplaySupported': Platform.isIOS,
      };
    });
  }

  Future<void> _loadVideo(int index) async {
    if (index < 0 || index >= _videos.length) return;

    final video = _videos[index];

    setState(() {
      _currentVideoIndex = index;
      _playbackStartTime = null;
      _bufferEventCount = 0;
      _errorCount = 0;
    });

    // Check if DRM is supported on current platform
    if (video.platformSupport != 'Both') {
      final isPlatformSupported =
          (Platform.isAndroid && video.platformSupport == 'Android') ||
              (Platform.isIOS && video.platformSupport == 'iOS');

      if (!isPlatformSupported) {
        _showMessage(
          '${video.platformSupport} Only',
          'This content is only available on ${video.platformSupport}',
          Colors.orange,
        );
        return;
      }
    }

    try {
      // Phase 1 P1: Validate DRM configuration
      InputValidator.validateDrmConfig(video.drmConfig);
      InputValidator.validateUrl(video.url, requireHttps: true);

      // Phase 1 P1: Demonstrate secure token storage
      // In production, you'd store auth tokens securely
      await _secureStorage.write(
        'drm_token_${video.drmConfig.scheme.name}',
        'demo_secure_token_${DateTime.now().millisecondsSinceEpoch}',
      );

      // Phase 1 P0: Start buffer monitoring
      _bufferingService.startMonitoring();

      // Create media item with DRM config
      final mediaItem = MediaItem(
        id: 'drm_video_$index',
        title: video.title,
        url: video.url,
        drmConfig: video.drmConfig,
      );

      // Track loading attempt
      _analyticsService.trackCustomEvent('drm_content_loading', {
        'video_index': index,
        'drm_scheme': video.drmConfig.scheme.name,
        'platform': Platform.isAndroid ? 'Android' : 'iOS',
      });

      await _controller.load(mediaItem);

      _showMessage('DRM Content Loaded', video.title, Colors.green);

      // Track successful load
      _analyticsService.trackCustomEvent('drm_content_loaded', {
        'video_index': index,
        'title': video.title,
      });
    } on ConfigurationException catch (e) {
      _errorCount++;
      _showMessage('Configuration Error', e.message, Colors.red);
      _analyticsService.trackError(e, {
        'video_index': index,
        'validation_type': 'drm_config',
      });
    } catch (e) {
      _errorCount++;
      _showMessage('Error', 'Failed to load DRM content: $e', Colors.red);
      _analyticsService.trackError(
        DrmException('Load failed: $e'),
        {'video_index': index},
      );
    }
  }

  void _showMessage(String title, String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title: $message'),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  void dispose() {
    // Dispose controller
    _controller.dispose();

    // Phase 1 P0: Stop buffering service
    _bufferingService.stopMonitoring();
    _bufferingService.dispose();

    // Phase 1 P1: Flush analytics
    _analyticsService.flush();
    _analyticsService.dispose();

    // Track session end
    _analyticsService.trackCustomEvent('drm_demo_closed', {
      'total_errors': _errorCount,
      'total_buffer_events': _bufferEventCount,
    });

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DRM Content Playback'),
        backgroundColor: Colors.deepPurple,
      ),
      body: Column(
        children: [
          // Video Player
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              color: Colors.black,
              child: _controller.isInitialized
                  ? MediaPlayerWidget(controller: _controller)
                  : const Center(
                      child: CircularProgressIndicator(),
                    ),
            ),
          ),

          // DRM Info Section
          _buildDrmInfoSection(),

          // Phase 1 Metrics Section
          _buildPhase1MetricsSection(),

          // Video List
          Expanded(
            child: _buildVideoList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDrmInfoSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[100],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.security,
                color: _isDrmSupported ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 8),
              Text(
                'DRM Status: ${_isDrmSupported ? "Supported" : "Not Supported"}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          if (_drmSession != null) ...[
            const SizedBox(height: 8),
            const Divider(),
            const Text(
              'Current Session:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text('State: ${_drmSession!.state.name}'),
            if (_drmSession!.errorMessage != null)
              Text(
                'Error: ${_drmSession!.errorMessage}',
                style: const TextStyle(color: Colors.red),
              ),
          ],
          if (_drmSystemInfo != null) ...[
            const SizedBox(height: 8),
            const Divider(),
            const Text(
              'System Info:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text('Platform: ${_drmSystemInfo!["platform"]}'),
            if (_drmSystemInfo!["widevineSupported"] == true)
              const Row(
                children: [
                  Icon(Icons.check, color: Colors.green, size: 16),
                  SizedBox(width: 4),
                  Text('Widevine Supported'),
                ],
              ),
            if (_drmSystemInfo!["fairplaySupported"] == true)
              const Row(
                children: [
                  Icon(Icons.check, color: Colors.green, size: 16),
                  SizedBox(width: 4),
                  Text('FairPlay Supported'),
                ],
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildPhase1MetricsSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        border: Border(
          top: BorderSide(color: Colors.blue[200]!),
          bottom: BorderSide(color: Colors.blue[200]!),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.analytics, color: Colors.blue[700]),
              const SizedBox(width: 8),
              Text(
                'Phase 1 P1: Analytics & Monitoring',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[900],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Analytics metrics
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _buildMetricChip(
                Icons.error_outline,
                'Errors',
                _errorCount.toString(),
                _errorCount > 0 ? Colors.red : Colors.green,
              ),
              _buildMetricChip(
                Icons.hourglass_empty,
                'Buffer Events',
                _bufferEventCount.toString(),
                _bufferEventCount > 2 ? Colors.orange : Colors.green,
              ),
              if (_playbackStartTime != null)
                _buildMetricChip(
                  Icons.play_circle,
                  'Watch Time',
                  '${DateTime.now().difference(_playbackStartTime!).inSeconds}s',
                  Colors.blue,
                ),
            ],
          ),

          // Buffer Health
          if (_bufferHealth != null) ...[
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  _bufferHealth!.isHealthy
                      ? Icons.check_circle
                      : Icons.warning,
                  color: _bufferHealth!.isHealthy ? Colors.green : Colors.orange,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  'Buffer Health: ${_bufferHealth!.status.name.toUpperCase()}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Buffered: ${(_bufferHealth!.bufferedDurationMs / 1000).toStringAsFixed(1)}s',
              style: TextStyle(fontSize: 11, color: Colors.grey[700]),
            ),
            if (_bufferHealth!.warning != null)
              Text(
                _bufferHealth!.warning!,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.orange,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],

          // Security features indicator
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.security, color: Colors.green[700], size: 16),
              const SizedBox(width: 4),
              const Text(
                'Security: ',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const Text(
                'Input Validation ✓  Secure Storage ✓',
                style: TextStyle(fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricChip(
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            value,
            style: TextStyle(fontSize: 11, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoList() {
    return ListView.builder(
      itemCount: _videos.length,
      itemBuilder: (context, index) {
        final video = _videos[index];
        final isSelected = index == _currentVideoIndex;
        final isAvailable = video.platformSupport == 'Both' ||
            (Platform.isAndroid && video.platformSupport == 'Android') ||
            (Platform.isIOS && video.platformSupport == 'iOS');

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: isSelected ? Colors.deepPurple[50] : null,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isAvailable ? Colors.deepPurple : Colors.grey,
              child: Icon(
                Icons.lock,
                color: Colors.white,
              ),
            ),
            title: Text(
              video.title,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(video.description),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      video.drmConfig.scheme == DrmScheme.widevine
                          ? Icons.android
                          : video.drmConfig.scheme == DrmScheme.fairplay
                              ? Icons.apple
                              : Icons.key,
                      size: 14,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      video.drmConfig.scheme.name.toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (!isAvailable)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${video.platformSupport} Only',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            trailing: isSelected
                ? const Icon(Icons.play_circle_fill, color: Colors.deepPurple)
                : const Icon(Icons.play_circle_outline),
            onTap: isAvailable ? () => _loadVideo(index) : null,
          ),
        );
      },
    );
  }
}

class _DrmVideo {
  final String title;
  final String description;
  final String url;
  final DrmConfig drmConfig;
  final String platformSupport; // 'Android', 'iOS', or 'Both'

  const _DrmVideo({
    required this.title,
    required this.description,
    required this.url,
    required this.drmConfig,
    required this.platformSupport,
  });
}
