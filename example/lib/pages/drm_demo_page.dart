import 'dart:io';
import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';

/// Demo page for DRM (Digital Rights Management) content playback
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

    // Create media item with DRM config
    final mediaItem = MediaItem(
      id: 'drm_video_$index',
      title: video.title,
      url: video.url,
      drmConfig: video.drmConfig,
    );

    try {
      await _controller.load(mediaItem);
      _showMessage('DRM Content Loaded', video.title, Colors.green);
    } catch (e) {
      _showMessage('Error', 'Failed to load DRM content: $e', Colors.red);
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
    _controller.dispose();
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
