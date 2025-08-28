# Flutter Media Player

A comprehensive Flutter media player package with advanced features for video and audio playback across Android and iOS platforms.

## Features

### Phase 1 (Current) - Core Features
- ✅ **Basic Media Playback**: Play, pause, stop, seek operations with volume control
- ✅ **Cross-Platform Support**: Android (ExoPlayer) and iOS (AVPlayer) implementations
- ✅ **Flutter Widget Integration**: Easy-to-use widgets with customizable controls
- ✅ **HTTP Headers Support**: Custom headers for authenticated media requests
- ✅ **BoxFit Support**: Multiple video scaling options (contain, cover, fill, etc.)
- ✅ **Playback Speed Control**: Variable speed from 0.25x to 4.0x
- ✅ **Playlist Management**: Basic playlist support with sequential playback
- ✅ **State Management**: Comprehensive state tracking and event streaming
- ✅ **Error Handling**: Robust error handling and recovery mechanisms

### Phase 2 (Planned) - Streaming & Subtitles
- 🔄 **HLS/DASH Support**: Adaptive streaming protocols
- 🔄 **Subtitle Support**: Multiple subtitle formats (SRT, WebVTT, etc.)
- 🔄 **Alternative Resolution**: Manual quality selection
- 🔄 **Cache System**: Media caching for offline playback

### Phase 3 (Planned) - Advanced Features
- 🔄 **Notifications**: Media playback notifications with controls
- 🔄 **Picture in Picture**: PiP mode for video playback
- 🔄 **ListView Integration**: Seamless integration with scrollable lists
- 🔄 **Screencast Support**: AirPlay and Chromecast integration

### Phase 4 (Planned) - DRM & Enterprise
- 🔄 **DRM Support**: Widevine, FairPlay, and token-based DRM
- 🔄 **Performance Optimization**: Memory and battery optimizations
- 🔄 **Testing Suite**: Comprehensive test coverage
- 🔄 **Documentation**: Complete API documentation and guides

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  flutter_media_player:
    git:
      url: https://github.com/your-org/flutter_media_player.git
```

## Quick Start

### Basic Usage

```dart
import 'package:flutter/material.dart';
import 'package:flutter_media_player/flutter_media_player.dart';

class SimplePlayerPage extends StatefulWidget {
  @override
  _SimplePlayerPageState createState() => _SimplePlayerPageState();
}

class _SimplePlayerPageState extends State<SimplePlayerPage> {
  late MediaController _controller;

  @override
  void initState() {
    super.initState();
    _controller = MediaController.create();
    _loadMedia();
  }

  void _loadMedia() async {
    final mediaItem = MediaItem(
      id: '1',
      title: 'Sample Video',
      url: 'https://example.com/video.mp4',
      mediaType: MediaType.video,
    );
    
    await _controller.load(mediaItem);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Media Player')),
      body: Column(
        children: [
          AspectRatio(
            aspectRatio: 16/9,
            child: MediaPlayerWidget(
              controller: _controller,
              showControls: true,
            ),
          ),
          // Add your custom controls here
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
```

### Advanced Usage with Playlist

```dart
// Create a playlist
final playlist = Playlist(
  id: 'my_playlist',
  title: 'My Videos',
  items: [
    MediaItem(
      id: '1',
      title: 'Video 1',
      url: 'https://example.com/video1.mp4',
      mediaType: MediaType.video,
    ),
    MediaItem(
      id: '2',
      title: 'Video 2',
      url: 'https://example.com/video2.mp4',
      mediaType: MediaType.video,
    ),
  ],
  mode: PlaybackMode.sequential,
  repeatMode: RepeatMode.all,
);

// Set the playlist
await _controller.setPlaylist(playlist);
```

### Custom Configuration

```dart
final controller = MediaController.create(
  config: MediaConfig(
    autoPlay: true,
    volume: 0.8,
    speed: 1.0,
    boxFit: BoxFit.contain,
    showControls: true,
    allowBackgroundPlayback: true,
    httpHeaders: {
      'Authorization': 'Bearer your-token',
      'User-Agent': 'YourApp/1.0',
    },
  ),
);
```

## API Reference

### MediaController

The main controller class for media playback operations.

#### Methods

- `load(MediaItem item)` - Load a single media item
- `setPlaylist(Playlist playlist)` - Set and load a playlist
- `play()` - Start playback
- `pause()` - Pause playback
- `stop()` - Stop playback
- `seekTo(Duration position)` - Seek to specific position
- `setVolume(double volume)` - Set volume (0.0 to 1.0)
- `setSpeed(double speed)` - Set playback speed (0.25x to 4.0x)
- `skipToNext()` - Skip to next item in playlist
- `skipToPrevious()` - Skip to previous item in playlist

#### Properties

- `state` - Current playback state
- `position` - Current playback position
- `duration` - Total media duration
- `volume` - Current volume level
- `speed` - Current playback speed
- `isPlaying` - Whether media is currently playing
- `isPaused` - Whether media is paused
- `hasNext` - Whether there's a next item in playlist
- `hasPrevious` - Whether there's a previous item in playlist

### MediaPlayerWidget

The main widget for displaying video content.

```dart
MediaPlayerWidget(
  controller: _controller,
  showControls: true,                    // Show default controls
  customControls: MyCustomControls(),    // Use custom controls
  placeholder: MyPlaceholderWidget(),    // Custom placeholder
  errorWidget: MyErrorWidget(),          // Custom error widget
  boxFit: BoxFit.contain,               // Video scaling mode
  allowFullscreen: true,                // Enable fullscreen
  onTap: () => print('Player tapped'),  // Tap callback
)
```

### MediaItem

Represents a media item that can be played.

```dart
MediaItem(
  id: 'unique_id',
  title: 'Media Title',
  artist: 'Artist Name',
  url: 'https://example.com/media.mp4',
  artworkUrl: 'https://example.com/artwork.jpg',
  duration: Duration(minutes: 5),
  mediaType: MediaType.video,
  httpHeaders: {'Authorization': 'Bearer token'},
  metadata: {'custom': 'data'},
)
```

### Playlist

Represents a collection of media items.

```dart
Playlist(
  id: 'playlist_id',
  title: 'Playlist Title',
  items: [mediaItem1, mediaItem2],
  currentIndex: 0,
  mode: PlaybackMode.sequential,  // or PlaybackMode.shuffle
  repeatMode: RepeatMode.none,    // none, single, or all
)
```

## Platform Setup

### Android

Add the following permissions to your `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

### iOS

Add the following to your `ios/Runner/Info.plist`:

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsArbitraryLoads</key>
  <true/>
</dict>
```

For background audio playback, add:

```xml
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

## Example App

Run the example app to see all features in action:

```bash
cd example
flutter run
```

The example app demonstrates:
- Basic video playback
- Playlist management
- Custom controls
- Settings configuration
- Error handling

## Architecture

The package follows clean architecture principles with clear separation of concerns:

```
lib/
├── src/
│   ├── core/           # Core player logic
│   ├── models/         # Data models
│   ├── widgets/        # Flutter widgets
│   └── platform/       # Platform-specific code
├── android/            # Android native implementation (ExoPlayer)
├── ios/                # iOS native implementation (AVPlayer)
└── example/            # Example application
```

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Roadmap

- **Phase 1** ✅ - Core playback features (Current)
- **Phase 2** 🔄 - Streaming and subtitles (In Progress)
- **Phase 3** 📅 - Advanced features (Planned)
- **Phase 4** 📅 - DRM and enterprise features (Planned)

## Support

For questions and support:
- 📖 Check the [documentation](https://github.com/your-org/flutter_media_player/wiki)
- 🐛 Report bugs on [GitHub Issues](https://github.com/your-org/flutter_media_player/issues)
- 💬 Join our [Discord community](https://discord.gg/your-discord)

---

Made with ❤️ by the Flutter Media Player team
