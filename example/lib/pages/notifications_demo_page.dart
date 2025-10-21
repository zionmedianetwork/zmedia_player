import 'package:flutter/material.dart';
import 'package:flutter_media_player/flutter_media_player.dart';

class NotificationsDemoPage extends StatefulWidget {
  const NotificationsDemoPage({super.key});

  @override
  State<NotificationsDemoPage> createState() => _NotificationsDemoPageState();
}

class _NotificationsDemoPageState extends State<NotificationsDemoPage> {
  late MediaController _controller;
  NotificationService? _notificationService;

  bool _notificationsEnabled = true;
  bool _showPlayPause = true;
  bool _showNext = true;
  bool _showPrevious = true;
  int _seekInterval = 10;

  final List<MediaItem> _playlist = [
    MediaItem(
      id: '1',
      url:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
      title: 'Big Buck Bunny',
      artist: 'Blender Foundation',
      album: 'Demo Videos',
      artworkUrl:
          'https://peach.blender.org/wp-content/uploads/title_anouncement.jpg',
    ),
    MediaItem(
      id: '2',
      url:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
      title: 'Elephants Dream',
      artist: 'Blender Foundation',
      album: 'Demo Videos',
      artworkUrl:
          'https://orange.blender.org/wp-content/themes/orange/images/media/splash.jpg',
    ),
    MediaItem(
      id: '3',
      url:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
      title: 'For Bigger Blazes',
      artist: 'Google',
      album: 'Demo Videos',
    ),
  ];

  int _currentIndex = 0;
  String? _lastNotificationAction;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    // Create notification configuration
    final notificationConfig = NotificationConfig(
      enabled: _notificationsEnabled,
      showPlayPause: _showPlayPause,
      showNext: _showNext,
      showPrevious: _showPrevious,
      seekInterval: _seekInterval,
      channelName: 'Media Playback',
      channelDescription: 'Controls for media playback',
    );

    // Create media config
    final config = MediaConfig(
      autoPlay: false,
      looping: false,
      notificationConfig: notificationConfig,
    );

    // Create controller
    _controller = MediaController.create(config: config);
    await _controller.initialize();

    // Initialize notification service
    _notificationService = NotificationService(notificationConfig);
    await _notificationService?.initialize(_controller.playerId,
        mediaPlayer: _controller.player);

    // Listen to notification actions
    _notificationService?.actionStream.listen((actionString) {
      setState(() {
        _lastNotificationAction = actionString;
      });

      _handleNotificationAction(actionString);
    });

    // Listen to player state changes to update notification
    _controller.addListener(_updateNotification);

    // Load first media item
    await _loadMedia(0);

    setState(() {});
  }

  void _handleNotificationAction(String action) {
    switch (action) {
      case 'play':
        _controller.play();
        break;
      case 'pause':
        _controller.pause();
        break;
      case 'next':
        _playNext();
        break;
      case 'previous':
        _playPrevious();
        break;
      case 'seekForward':
      case 'seek_forward':
        final newPosition =
            _controller.position + Duration(seconds: _seekInterval);
        _controller.seekTo(newPosition);
        break;
      case 'seekBackward':
      case 'seek_backward':
        final newPosition =
            _controller.position - Duration(seconds: _seekInterval);
        _controller
            .seekTo(newPosition.isNegative ? Duration.zero : newPosition);
        break;
      case 'stop':
        _controller.stop();
        break;
      default:
        break;
    }
  }

  Future<void> _loadMedia(int index) async {
    if (index < 0 || index >= _playlist.length) return;

    setState(() {
      _currentIndex = index;
    });

    final mediaItem = _playlist[index];
    await _controller.load(mediaItem);

    // Show notification
    if (_notificationService != null) {
      await _notificationService!.show(
        mediaItem: mediaItem,
        state: _controller.state,
        playerId: _controller.playerId,
      );
    }
  }

  void _updateNotification() {
    if (_notificationService != null && _controller.isInitialized) {
      _notificationService!.updateState(
        state: _controller.state,
        playerId: _controller.playerId,
      );
    }
  }

  void _playNext() {
    if (_currentIndex < _playlist.length - 1) {
      _loadMedia(_currentIndex + 1);
    }
  }

  void _playPrevious() {
    if (_currentIndex > 0) {
      _loadMedia(_currentIndex - 1);
    }
  }

  Future<void> _updateNotificationConfig() async {
    final notificationConfig = NotificationConfig(
      enabled: _notificationsEnabled,
      showPlayPause: _showPlayPause,
      showNext: _showNext,
      showPrevious: _showPrevious,
      seekInterval: _seekInterval,
    );

    // Reinitialize notification service
    _notificationService?.dispose();
    _notificationService = NotificationService(notificationConfig);
    await _notificationService?.initialize(_controller.playerId,
        mediaPlayer: _controller.player);

    // Re-subscribe to actions
    _notificationService?.actionStream.listen((actionString) {
      setState(() {
        _lastNotificationAction = actionString;
      });
      _handleNotificationAction(actionString);
    });

    // Update notification if playing
    if (_controller.isInitialized) {
      await _notificationService?.show(
        mediaItem: _playlist[_currentIndex],
        state: _controller.state,
        playerId: _controller.playerId,
      );
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_updateNotification);
    _notificationService?.dismiss(_controller.playerId);
    _notificationService?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications Demo'),
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
                  ? MediaPlayerWidget(
                      controller: _controller,
                      showControls: true,
                    )
                  : const Center(
                      child: CircularProgressIndicator(),
                    ),
            ),
          ),

          // Playlist
          Expanded(
            child: ListView.builder(
              itemCount: _playlist.length,
              itemBuilder: (context, index) {
                final item = _playlist[index];
                final isCurrentItem = index == _currentIndex;

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        isCurrentItem ? Colors.deepPurple : Colors.grey,
                    child: Icon(
                      isCurrentItem ? Icons.play_arrow : Icons.music_note,
                      color: Colors.white,
                    ),
                  ),
                  title: Text(
                    item.title ?? 'Unknown',
                    style: TextStyle(
                      fontWeight:
                          isCurrentItem ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(item.artist ?? 'Unknown Artist'),
                  trailing: isCurrentItem && _controller.isPlaying
                      ? const Icon(Icons.volume_up, color: Colors.deepPurple)
                      : null,
                  onTap: () => _loadMedia(index),
                );
              },
            ),
          ),

          // Notification Configuration
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              border: Border(top: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Notification Configuration',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Enable Notifications'),
                  value: _notificationsEnabled,
                  onChanged: (value) {
                    setState(() => _notificationsEnabled = value);
                    _updateNotificationConfig();
                  },
                  dense: true,
                ),
                SwitchListTile(
                  title: const Text('Show Play/Pause'),
                  value: _showPlayPause,
                  onChanged: _notificationsEnabled
                      ? (value) {
                          setState(() => _showPlayPause = value);
                          _updateNotificationConfig();
                        }
                      : null,
                  dense: true,
                ),
                SwitchListTile(
                  title: const Text('Show Next Button'),
                  value: _showNext,
                  onChanged: _notificationsEnabled
                      ? (value) {
                          setState(() => _showNext = value);
                          _updateNotificationConfig();
                        }
                      : null,
                  dense: true,
                ),
                SwitchListTile(
                  title: const Text('Show Previous Button'),
                  value: _showPrevious,
                  onChanged: _notificationsEnabled
                      ? (value) {
                          setState(() => _showPrevious = value);
                          _updateNotificationConfig();
                        }
                      : null,
                  dense: true,
                ),
                ListTile(
                  title: const Text('Seek Interval'),
                  subtitle: Slider(
                    value: _seekInterval.toDouble(),
                    min: 5,
                    max: 30,
                    divisions: 5,
                    label: '$_seekInterval seconds',
                    onChanged: _notificationsEnabled
                        ? (value) {
                            setState(() => _seekInterval = value.toInt());
                            _updateNotificationConfig();
                          }
                        : null,
                  ),
                  trailing: Text('${_seekInterval}s'),
                  dense: true,
                ),
                if (_lastNotificationAction != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.notifications,
                              color: Colors.deepPurple),
                          const SizedBox(width: 8),
                          Text(
                            'Last action: $_lastNotificationAction',
                            style: const TextStyle(color: Colors.deepPurple),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Instructions
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue[50],
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Minimize the app or lock your device to see the media notification. '
                    'Use the notification controls to control playback.',
                    style: TextStyle(color: Colors.blue[900], fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
