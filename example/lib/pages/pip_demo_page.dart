import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';

class PipDemoPage extends StatefulWidget {
  const PipDemoPage({super.key});

  @override
  State<PipDemoPage> createState() => _PipDemoPageState();
}

class _PipDemoPageState extends State<PipDemoPage> with WidgetsBindingObserver {
  late MediaController _controller;
  PipStatus? _pipStatus;

  bool _autoEnterOnBackground = false;
  double _aspectRatio = 16 / 9;
  bool _showControls = true;

  final List<MediaItem> _videos = [
    MediaItem(
      id: '1',
      url:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
      title: 'Big Buck Bunny',
      artworkUrl:
          'https://peach.blender.org/wp-content/uploads/title_anouncement.jpg',
    ),
    MediaItem(
      id: '2',
      url:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
      title: 'Elephants Dream',
      artworkUrl:
          'https://orange.blender.org/wp-content/themes/orange/images/media/splash.jpg',
    ),
    MediaItem(
      id: '3',
      url:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4',
      title: 'Sintel',
      artworkUrl:
          'https://durian.blender.org/wp-content/uploads/2010/06/05.8a_comp_000272.jpg',
    ),
  ];

  int _currentVideoIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    // Create PiP configuration
    final pipConfig = PipConfig(
      enabled: true,
      autoEnterOnBackground: _autoEnterOnBackground,
      aspectRatio: _aspectRatio,
      showPlaybackControls: _showControls,
    );

    // Create media config
    final config = MediaConfig(
      autoPlay: true,
      pipConfig: pipConfig,
    );

    // Create controller
    _controller = MediaController.create(config: config);
    await _controller.initialize();

    // Listen to PiP status changes
    _controller.pipStatusStream.listen((status) {
      setState(() {
        _pipStatus = status;
      });

      _showPipStatusSnackbar(status);
    });

    // Load first video
    await _controller.load(_videos[_currentVideoIndex]);

    // Check PiP availability
    await _checkPipAvailability();

    setState(() {});
  }

  Future<void> _checkPipAvailability() async {
    final isAvailable = await _controller.checkPipAvailability();

    if (!mounted) return;

    if (!isAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Picture-in-Picture is not available on this device'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void _showPipStatusSnackbar(PipStatus status) {
    if (!mounted) return;

    String message;
    Color color;

    switch (status.state) {
      case PipState.active:
        message = 'Entered Picture-in-Picture mode';
        color = Colors.green;
        break;
      case PipState.available:
        if (status.isActive) {
          message = 'Exited Picture-in-Picture mode';
          color = Colors.blue;
        } else {
          return; // Don't show notification for initial available state
        }
        break;
      case PipState.unavailable:
        message = 'Picture-in-Picture not available';
        color = Colors.orange;
        break;
      default:
        return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _enterPip() async {
    if (!_controller.isPipAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Picture-in-Picture is not available'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      await _controller.enterPictureInPicture();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to enter PiP: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _exitPip() async {
    try {
      await _controller.exitPictureInPicture();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to exit PiP: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _updatePipConfig() async {
    final pipConfig = PipConfig(
      enabled: true,
      autoEnterOnBackground: _autoEnterOnBackground,
      aspectRatio: _aspectRatio,
      showPlaybackControls: _showControls,
    );

    final newConfig = _controller.config.copyWith(pipConfig: pipConfig);
    await _controller.updateConfig(newConfig);
  }

  Future<void> _changeVideo(int index) async {
    if (index < 0 || index >= _videos.length) return;

    setState(() {
      _currentVideoIndex = index;
    });

    await _controller.load(_videos[index]);
    await _controller.play();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Auto-enter PiP when app goes to background (if enabled)
    if (state == AppLifecycleState.paused && _autoEnterOnBackground) {
      if (_controller.isPlaying && !_controller.isInPipMode) {
        _enterPip();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_controller.isInPipMode) {
      _controller.exitPictureInPicture();
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Picture-in-Picture Demo'),
        backgroundColor: Colors.teal,
        actions: [
          if (_controller.isPipAvailable && !_controller.isInPipMode)
            IconButton(
              icon: const Icon(Icons.picture_in_picture_alt),
              onPressed: _enterPip,
              tooltip: 'Enter PiP',
            ),
          if (_controller.isInPipMode)
            IconButton(
              icon: const Icon(Icons.fullscreen),
              onPressed: _exitPip,
              tooltip: 'Exit PiP',
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
              child: _controller.isInitialized
                  ? MediaPlayerWidget(
                      controller: _controller,
                      showControls: true,
                      customControls: MediaControls(
                        controller: _controller,
                        title: 'Picture-in-Picture Demo',
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

          // PiP Status Card
          if (_pipStatus != null)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color:
                    _pipStatus!.isActive ? Colors.green[50] : Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _pipStatus!.isActive ? Colors.green : Colors.blue,
                  width: 2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _pipStatus!.isActive
                            ? Icons.picture_in_picture_alt
                            : Icons.info_outline,
                        color:
                            _pipStatus!.isActive ? Colors.green : Colors.blue,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'PiP Status',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _pipStatus!.isActive
                              ? Colors.green[900]
                              : Colors.blue[900],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildStatusRow(
                      'State', _pipStatus!.state.toString().split('.').last),
                  _buildStatusRow(
                      'Supported', _pipStatus!.isSupported ? 'Yes' : 'No'),
                  _buildStatusRow(
                      'Active', _pipStatus!.isActive ? 'Yes' : 'No'),
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
                  'Select Video',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 100,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _videos.length,
                    itemBuilder: (context, index) {
                      final video = _videos[index];
                      final isSelected = index == _currentVideoIndex;

                      return GestureDetector(
                        onTap: () => _changeVideo(index),
                        child: Container(
                          width: 160,
                          margin: const EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color:
                                  isSelected ? Colors.teal : Colors.grey[300]!,
                              width: isSelected ? 3 : 1,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.video_library,
                                size: 32,
                                color: isSelected ? Colors.teal : Colors.grey,
                              ),
                              const SizedBox(height: 8),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                child: Text(
                                  video.title ?? 'Unknown',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color:
                                        isSelected ? Colors.teal : Colors.black,
                                  ),
                                  maxLines: 2,
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

          // Configuration
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
                      'PiP Configuration',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),

                    SwitchListTile(
                      title: const Text('Auto-enter on background'),
                      subtitle: const Text(
                          'Automatically enter PiP when app is minimized'),
                      value: _autoEnterOnBackground,
                      onChanged: (value) {
                        setState(() => _autoEnterOnBackground = value);
                        _updatePipConfig();
                      },
                    ),

                    SwitchListTile(
                      title: const Text('Show controls in PiP'),
                      subtitle: const Text(
                          'Display playback controls in PiP window (Android)'),
                      value: _showControls,
                      onChanged: (value) {
                        setState(() => _showControls = value);
                        _updatePipConfig();
                      },
                    ),

                    ListTile(
                      title: const Text('Aspect Ratio'),
                      subtitle: Slider(
                        value: _aspectRatio,
                        min: 1.0,
                        max: 2.39,
                        divisions: 20,
                        label: _aspectRatio.toStringAsFixed(2),
                        onChanged: (value) {
                          setState(() => _aspectRatio = value);
                        },
                        onChangeEnd: (value) {
                          _updatePipConfig();
                        },
                      ),
                      trailing: Text(_aspectRatio.toStringAsFixed(2)),
                    ),

                    const Divider(height: 32),

                    // PiP Actions
                    const Text(
                      'PiP Actions',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _controller.isPipAvailable &&
                                    !_controller.isInPipMode
                                ? _enterPip
                                : null,
                            icon: const Icon(Icons.picture_in_picture_alt),
                            label: const Text('Enter PiP'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.all(16),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed:
                                _controller.isInPipMode ? _exitPip : null,
                            icon: const Icon(Icons.fullscreen),
                            label: const Text('Exit PiP'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.all(16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Instructions
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.teal[50],
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.teal),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tap "Enter PiP" or minimize the app to enter Picture-in-Picture mode. '
                    'The video will continue playing in a floating window.',
                    style: TextStyle(color: Colors.teal[900], fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
}
