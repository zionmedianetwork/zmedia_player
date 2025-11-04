import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';
import 'dart:io' show Platform;

class CastingDemoPage extends StatefulWidget {
  const CastingDemoPage({super.key});

  @override
  State<CastingDemoPage> createState() => _CastingDemoPageState();
}

class _CastingDemoPageState extends State<CastingDemoPage> {
  late MediaController _controller;
  CastService? _castService;

  CastStatus? _castStatus;
  List<CastDevice> _availableDevices = [];
  bool _isDiscovering = false;

  // NOTE: To test subtitle functionality, use an HLS stream with embedded subtitle tracks
  // The native players (ExoPlayer/AVPlayer) will automatically detect and expose them
  // Example: HLS manifest with WebVTT subtitle tracks in #EXT-X-MEDIA entries
  final List<MediaItem> _videos = [
    MediaItem(
      id: '1',
      url:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
      title: 'Big Buck Bunny',
      artist: 'Blender Foundation',
      artworkUrl:
          'https://peach.blender.org/wp-content/uploads/title_anouncement.jpg',
      duration: const Duration(minutes: 9, seconds: 56),
    ),
    MediaItem(
      id: '2',
      url:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
      title: 'Elephants Dream',
      artist: 'Blender Foundation',
      artworkUrl:
          'https://orange.blender.org/wp-content/themes/orange/images/media/splash.jpg',
      duration: const Duration(minutes: 10, seconds: 53),
    ),
    MediaItem(
      id: '3',
      url:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4',
      title: 'Sintel',
      artist: 'Blender Foundation',
      artworkUrl:
          'https://durian.blender.org/wp-content/uploads/2010/06/05.8a_comp_000272.jpg',
      duration: const Duration(minutes: 14, seconds: 48),
    ),
    MediaItem(
      id: '4',
      title: 'TV5',
      url:
          'https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/main.m3u8?ref=developerinsider.com',
    ),
  ];

  int _currentVideoIndex = 0;
  bool _localPlayback = true;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    // Create cast configuration
    final castConfig = CastConfig(
      enabled: true,
      enableChromecast: Platform.isAndroid,
      enableAirPlay: Platform.isIOS,
    );

    // Create media config
    final config = MediaConfig(
      autoPlay: false,
      castConfig: castConfig,
    );

    // Create controller
    _controller = MediaController.create(config: config);
    await _controller.initialize();

    // Initialize cast service
    _castService = CastService(castConfig);
    await _castService?.initialize(_controller.playerId, _controller.player);

    // Listen to cast status changes
    _controller.castStatusStream.listen((status) {
      setState(() {
        _castStatus = status;
        _localPlayback = !status.isCasting;
      });

      _showCastStatusSnackbar(status);
    });

    // Listen to device changes
    _castService?.devicesStream.listen((devices) {
      setState(() {
        _availableDevices = devices;
      });
    });

    // Load first video
    await _controller.load(_videos[_currentVideoIndex]);

    // On iOS, play immediately since AirPlay is controlled via player UI
    if (Platform.isIOS) {
      await _controller.play();
    }

    setState(() {});
  }

  void _showCastStatusSnackbar(CastStatus status) {
    if (!mounted) return;

    String message;
    Color color;

    switch (status.state) {
      case CastState.connected:
        message = 'Connected to ${status.connectedDevice?.name ?? "device"}';
        color = Colors.green;
        break;
      case CastState.casting:
        message = 'Now casting to ${status.connectedDevice?.name ?? "device"}';
        color = Colors.blue;
        break;
      case CastState.disconnected:
        if (status.connectedDevice != null) {
          message = 'Disconnected from cast device';
          color = Colors.orange;
        } else {
          return; // Don't show for initial state
        }
        break;
      case CastState.connecting:
        message = 'Connecting...';
        color = Colors.grey;
        break;
      case CastState.error:
        message = 'Cast error: ${status.errorMessage ?? "Unknown error"}';
        color = Colors.red;
        break;
      default:
        return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _startDiscovery() async {
    setState(() {
      _isDiscovering = true;
    });

    await _castService?.startDiscovery(_controller.playerId);

    // Stop discovery after 30 seconds
    Future.delayed(const Duration(seconds: 30), () {
      if (mounted && _isDiscovering) {
        _stopDiscovery();
      }
    });
  }

  Future<void> _stopDiscovery() async {
    setState(() {
      _isDiscovering = false;
    });

    await _castService?.stopDiscovery(_controller.playerId);
  }

  Future<void> _connectToDevice(CastDevice device) async {
    final success = await _castService?.connect(
      device: device,
      playerId: _controller.playerId,
    );

    if (success == true) {
      // Load current media on cast device
      await _castService?.loadMedia(
        mediaItem: _videos[_currentVideoIndex],
        playerId: _controller.playerId,
      );

      // Play on cast device
      await _castService?.play(_controller.playerId);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to connect to ${device.name}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _disconnect() async {
    await _castService?.disconnect(_controller.playerId);
  }

  Future<void> _changeVideo(int index) async {
    if (index < 0 || index >= _videos.length) return;

    setState(() {
      _currentVideoIndex = index;
    });

    if (_castStatus?.isCasting == true) {
      // Load on cast device
      await _castService?.loadMedia(
        mediaItem: _videos[index],
        playerId: _controller.playerId,
      );
      await _castService?.play(_controller.playerId);
    } else {
      // Load locally
      await _controller.load(_videos[index]);
      await _controller.play();
    }
  }

  Future<void> _togglePlayPause() async {
    if (_castStatus?.isCasting == true) {
      // Control cast device
      if (_controller.isPlaying) {
        await _castService?.pause(_controller.playerId);
      } else {
        await _castService?.play(_controller.playerId);
      }
    } else {
      // Control local player
      if (_controller.isPlaying) {
        await _controller.pause();
      } else {
        await _controller.play();
      }
    }
  }

  void _showSettingsMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SettingsMenu(
          controller: _controller,
          isAutoQualityEnabled: false,
          onQualitySelected: (track) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Quality changed to ${track.name}'),
                backgroundColor: Colors.purple,
                duration: const Duration(seconds: 2),
              ),
            );
          },
          onAutoQualityToggled: (enabled) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  enabled ? 'Auto quality enabled' : 'Auto quality disabled',
                ),
                backgroundColor: Colors.purple,
                duration: const Duration(seconds: 2),
              ),
            );
          },
          onAudioTrackSelected: (track) {
            final languageMap = {
              'en': 'English',
              'es': 'Spanish',
              'fr': 'French',
              'de': 'German',
              'it': 'Italian',
              'pt': 'Portuguese',
              'ru': 'Russian',
              'ja': 'Japanese',
              'ko': 'Korean',
              'zh': 'Chinese',
            };
            final language = track.language != null
                ? languageMap[track.language!.toLowerCase()] ??
                    track.language!.toUpperCase()
                : 'Unknown';

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Audio track changed to $language'),
                backgroundColor: Colors.purple,
                duration: const Duration(seconds: 2),
              ),
            );
          },
          onSubtitleSelected: (track) {
            final languageMap = {
              'en': 'English',
              'es': 'Spanish',
              'fr': 'French',
              'de': 'German',
              'it': 'Italian',
              'pt': 'Portuguese',
              'ru': 'Russian',
              'ja': 'Japanese',
              'ko': 'Korean',
              'zh': 'Chinese',
              'ar': 'Arabic',
              'hi': 'Hindi',
              'tr': 'Turkish',
              'nl': 'Dutch',
              'pl': 'Polish',
            };

            if (track == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Subtitles disabled'),
                  backgroundColor: Colors.purple,
                  duration: Duration(seconds: 2),
                ),
              );
            } else {
              final language = track.language != null
                  ? languageMap[track.language!.toLowerCase()] ??
                      track.language!.toUpperCase()
                  : 'Unknown';

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Subtitle changed to $language'),
                  backgroundColor: Colors.purple,
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          },
        );
      },
    );
  }

  @override
  void dispose() {
    if (_castStatus?.isCasting == true) {
      _castService?.disconnect(_controller.playerId);
    }
    _castService?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final castType = Platform.isAndroid ? 'Chromecast' : 'AirPlay';

    return Scaffold(
      appBar: AppBar(
        title: Text('$castType Demo'),
        backgroundColor: Colors.purple,
        actions: [
          // Settings menu button
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSettingsMenu,
            tooltip: 'Settings',
          ),
          if (_castStatus?.isCasting == true)
            IconButton(
              icon: const Icon(Icons.cast_connected),
              onPressed: _disconnect,
              tooltip: 'Disconnect',
            )
          else if (_castStatus?.isAvailable == true &&
              _availableDevices.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.cast),
              onPressed: () => _showDeviceSelectionDialog(),
              tooltip: 'Cast',
            ),
        ],
      ),
      body: Column(
        children: [
          // Video Player (only visible when not casting)
          if (_localPlayback)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                color: Colors.black,
                child: _controller.isInitialized
                    ? MediaPlayerWidget(
                        controller: _controller,
                        showControls: true,
                        customControls: MediaControls(
                          controller: _controller,
                          title: _videos[_currentVideoIndex].title,
                          showCastButton: true,
                          showPipButton: true,
                          showSettingsButton: true,
                          allowFullscreen: true,
                          showSubtitleControls: true,
                          showSpeedControls: true,
                          showVolumeControls: true,
                          showPlaylistControls: false,
                        ),
                      )
                    : const Center(
                        child: CircularProgressIndicator(),
                      ),
              ),
            ),

          // Casting Display
          if (!_localPlayback && _castStatus?.connectedDevice != null)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                color: Colors.purple[900],
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Platform.isAndroid ? Icons.cast_connected : Icons.airplay,
                      size: 64,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Casting to',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _castStatus!.connectedDevice!.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      _videos[_currentVideoIndex].title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),

          // Cast Status Card
          if (_castStatus != null)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _castStatus!.isCasting
                    ? Colors.purple[50]
                    : Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _castStatus!.isCasting ? Colors.purple : Colors.blue,
                  width: 2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _castStatus!.isCasting
                            ? Icons.cast_connected
                            : Icons.cast,
                        color: _castStatus!.isCasting
                            ? Colors.purple
                            : Colors.blue,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$castType Status',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _castStatus!.isCasting
                              ? Colors.purple[900]
                              : Colors.blue[900],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildStatusRow(
                      'State', _castStatus!.state.toString().split('.').last),
                  _buildStatusRow(
                      'Available', _castStatus!.isAvailable ? 'Yes' : 'No'),
                  _buildStatusRow(
                      'Casting', _castStatus!.isCasting ? 'Yes' : 'No'),
                  if (_castStatus!.connectedDevice != null)
                    _buildStatusRow(
                        'Device', _castStatus!.connectedDevice!.name),
                  if (_availableDevices.isNotEmpty)
                    _buildStatusRow(
                        'Devices Found', '${_availableDevices.length}'),
                ],
              ),
            ),

          // Video Selection
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select Video to Cast',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 120,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _videos.length,
                    itemBuilder: (context, index) {
                      final video = _videos[index];
                      final isSelected = index == _currentVideoIndex;

                      return GestureDetector(
                        onTap: () => _changeVideo(index),
                        child: Container(
                          width: 180,
                          margin: const EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.purple
                                  : Colors.grey[300]!,
                              width: isSelected ? 3 : 1,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.video_library,
                                size: 32,
                                color: isSelected ? Colors.purple : Colors.grey,
                              ),
                              const SizedBox(height: 8),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                child: Text(
                                  video.title,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isSelected
                                        ? Colors.purple
                                        : Colors.black,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (video.artist != null)
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                  child: Text(
                                    video.artist!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[600],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Cast Controls
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                border: Border(top: BorderSide(color: Colors.grey[300]!)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cast Actions',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),

                    // Discovery Button (Android only - iOS uses native AirPlay button)
                    if (Platform.isAndroid) ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed:
                              _isDiscovering ? _stopDiscovery : _startDiscovery,
                          icon:
                              Icon(_isDiscovering ? Icons.stop : Icons.search),
                          label: Text(_isDiscovering
                              ? 'Stop Discovery'
                              : 'Discover Devices'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                _isDiscovering ? Colors.orange : Colors.purple,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.all(16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // iOS AirPlay Instructions
                    if (Platform.isIOS) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue, width: 2),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.airplay,
                                    color: Colors.blue, size: 28),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'How to Use AirPlay',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              '1. Look for the AirPlay button (📡) in the video player above',
                              style: TextStyle(fontSize: 14),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              '2. Tap it to see available AirPlay devices',
                              style: TextStyle(fontSize: 14),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              '3. Select your device (Apple TV, Mac, etc.)',
                              style: TextStyle(fontSize: 14),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              '4. Video will stream to the selected device',
                              style: TextStyle(fontSize: 14),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.info_outline,
                                      color: Colors.blue, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'On Mac: Enable "AirPlay Receiver" in System Settings → General → AirDrop & Handoff',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.blue[900],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Available Devices
                    if (_availableDevices.isNotEmpty) ...[
                      const Text(
                        'Available Devices',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _availableDevices.length,
                        itemBuilder: (context, index) {
                          final device = _availableDevices[index];
                          final isConnected =
                              device.id == _castStatus?.connectedDevice?.id;

                          return Card(
                            color: isConnected ? Colors.purple[50] : null,
                            child: ListTile(
                              leading: Icon(
                                Platform.isAndroid ? Icons.cast : Icons.airplay,
                                color:
                                    isConnected ? Colors.purple : Colors.grey,
                              ),
                              title: Text(device.name),
                              subtitle: Text(
                                device.type.toString().split('.').last,
                              ),
                              trailing: isConnected
                                  ? const Icon(Icons.check_circle,
                                      color: Colors.green)
                                  : const Icon(Icons.arrow_forward_ios,
                                      size: 16),
                              onTap: isConnected
                                  ? null
                                  : () => _connectToDevice(device),
                            ),
                          );
                        },
                      ),
                    ] else if (_isDiscovering && Platform.isAndroid) ...[
                      const Center(
                        child: Column(
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('Searching for Chromecast devices...'),
                          ],
                        ),
                      ),
                    ] else if (Platform.isAndroid) ...[
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            'No Chromecast devices found. Tap "Discover Devices" to search.',
                            style: TextStyle(color: Colors.grey[600]),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],

                    if (_castStatus?.isCasting == true) ...[
                      const Divider(height: 32),

                      // Disconnect Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _disconnect,
                          icon: const Icon(Icons.close),
                          label: const Text('Disconnect'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.all(16),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // Instructions
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.purple[50],
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.purple),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    Platform.isAndroid
                        ? 'Make sure your Chromecast device is on the same WiFi network. '
                            'Tap "Discover Devices" to find available Chromecast devices.'
                        : 'Make sure your AirPlay device (Apple TV, Mac, HomePod, etc.) is on the same WiFi network. '
                            'Use the AirPlay button (📡) in the video player above to select your device.',
                    style: TextStyle(color: Colors.purple[900], fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _controller.isInitialized
          ? FloatingActionButton(
              onPressed: _togglePlayPause,
              backgroundColor: Colors.purple,
              child: Icon(
                _controller.isPlaying ? Icons.pause : Icons.play_arrow,
              ),
            )
          : null,
    );
  }

  Widget _buildStatusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          Text(
            value,
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  void _showDeviceSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
            'Select ${Platform.isAndroid ? 'Chromecast' : 'AirPlay'} Device'),
        content: _availableDevices.isEmpty
            ? const Text('No devices available. Start discovery first.')
            : SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _availableDevices.length,
                  itemBuilder: (context, index) {
                    final device = _availableDevices[index];
                    return ListTile(
                      leading:
                          Icon(Platform.isAndroid ? Icons.cast : Icons.airplay),
                      title: Text(device.name),
                      onTap: () {
                        Navigator.pop(context);
                        _connectToDevice(device);
                      },
                    );
                  },
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
