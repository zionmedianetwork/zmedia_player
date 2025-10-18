# ZMedia Player Example App

A beautiful and comprehensive example app showcasing all features of the ZMedia Player Flutter package.

## 🎯 Features Demonstrated

### 1. **Simple Player** 📹
- Basic video playback with default controls
- Auto-play functionality
- Play, pause, and seek operations
- Volume control
- Real-time state monitoring
- Fullscreen support

### 2. **Full Featured Player** 🎬
- Custom video controls with beautiful UI
- **BoxFit Options**: All 7 BoxFit modes (contain, cover, fill, fitWidth, fitHeight, none, scaleDown)
- **Speed Control**: Adjustable playback speed from 0.25x to 4.0x
- **Volume Control**: Fine-grained volume adjustment with slider
- **Mute/Unmute**: Quick toggle for audio
- **Video Selection**: Browse and switch between multiple videos
- **Debug Mode**: Real-time state information display
- Custom overlay controls with auto-hide

### 3. **Playlist Demo** 📑
- Full playlist management with 8+ videos
- **Sequential Playback**: Play videos in order
- **Shuffle Mode**: Random playback order
- **Repeat Modes**:
  - None: Play once and stop
  - Single: Repeat current video
  - All: Loop entire playlist
- Next/Previous track navigation
- Visual playlist with current item indicator
- Tap to play any video in the playlist

### 4. **Settings & Configuration** ⚙️
- Interactive configuration panel
- **Playback Settings**:
  - Auto-play toggle
  - Looping mode
  - Start muted option
- **Volume & Speed**:
  - Volume slider (0-100%)
  - Speed slider with presets
- **Display Settings**:
  - BoxFit mode selection
  - Show/hide controls toggle
- **Performance**:
  - Hardware acceleration toggle
- **HTTP Headers**:
  - Add custom headers for authenticated requests
- **Real-time State Display**:
  - Current playback state
  - Position and duration
  - All active settings

## 🎨 UI/UX Features

### Beautiful Modern Design
- **Dark Theme**: Elegant dark color scheme
- **Material Design 3**: Latest Material Design guidelines
- **Gradient Backgrounds**: Eye-catching gradient effects
- **Smooth Animations**: Fluid transitions and interactions
- **Card-based Layout**: Clean and organized interface
- **Responsive Design**: Adapts to different screen sizes

### Color Palette
- Primary: Indigo (`#6366F1`)
- Secondary: Purple (`#8B5CF6`)
- Accent: Pink (`#EC4899`)
- Success: Green (`#10B981`)
- Background: Dark Slate (`#0F172A`)
- Card: Slate (`#1E293B`)

## 📱 Screenshots

The app features:
- Gradient app bars with flexible space
- Feature cards with icons and descriptions
- Slick video player interface
- Customizable controls
- Interactive settings panel

## 🚀 Getting Started

### Prerequisites
- Flutter 3.19 or higher
- Dart 3.0 or higher
- Android SDK (for Android)
- Xcode (for iOS)

### Running the App

1. Navigate to the example directory:
```bash
cd example
```

2. Install dependencies:
```bash
flutter pub get
```

3. Run the app:
```bash
flutter run
```

## 📦 Package Features Showcased

### Phase 1 Features (Implemented)
✅ **Basic Media Playback**
- Play, pause, stop operations
- Seek to position
- Volume control with mute

✅ **Cross-Platform Support**
- Android (ExoPlayer)
- iOS (AVPlayer)

✅ **HTTP Headers Support**
- Custom headers for authenticated media
- Per-request configuration

✅ **BoxFit Support**
- All 7 Flutter BoxFit options
- Dynamic BoxFit changes during playback

✅ **Playback Speed Control**
- Speed range: 0.25x to 4.0x
- Preset speed options
- Real-time speed adjustment

✅ **Playlist Management**
- Sequential and shuffle modes
- Repeat modes (none, single, all)
- Next/previous navigation
- Skip to specific index

✅ **State Management**
- Comprehensive state tracking
- Real-time position updates
- Event streaming
- Error handling

✅ **Widget Integration**
- MediaPlayerWidget for video display
- CustomControls for UI
- Gesture handling
- Fullscreen support

## 🎬 Sample Videos

The app includes 8 sample videos from:
- **Blender Foundation**: Big Buck Bunny, Elephant's Dream, Sintel, Tears of Steel
- **Google**: Various demo videos

All videos are publicly accessible and used for demonstration purposes.

## 🏗️ Architecture

### File Structure
```
example/lib/
├── main.dart                          # App entry point
├── pages/
│   ├── home_page.dart                 # Landing page with feature cards
│   ├── simple_player_page.dart        # Basic player demo
│   ├── full_featured_player_page.dart # Advanced player with all features
│   ├── playlist_demo_page.dart        # Playlist management demo
│   └── settings_page.dart             # Configuration panel
├── widgets/
│   └── custom_controls.dart           # Custom video controls overlay
└── data/
    └── sample_videos.dart             # Sample video data
```

### Key Components

1. **MediaController**: Main controller for player operations
2. **MediaPlayerWidget**: Video display widget
3. **CustomControls**: Custom overlay controls
4. **Sample Videos**: Curated list of demo videos

## 🔧 Configuration Examples

### Basic Configuration
```dart
MediaController.create(
  config: MediaConfig(
    autoPlay: true,
    volume: 0.8,
    showControls: true,
  ),
);
```

### Advanced Configuration
```dart
MediaController.create(
  config: MediaConfig(
    autoPlay: false,
    looping: true,
    boxFit: BoxFit.contain,
    volume: 1.0,
    speed: 1.5,
    startMuted: false,
    httpHeaders: {
      'Authorization': 'Bearer your-token',
      'User-Agent': 'YourApp/1.0',
    },
    showControls: true,
    useHardwareAcceleration: true,
  ),
);
```

## 📚 Learning Resources

### Topics Covered
- Flutter video playback
- State management with ChangeNotifier
- Custom widget creation
- Playlist management
- Platform channels
- Material Design 3
- Responsive UI design
- Error handling

## 🎯 Use Cases

This example app demonstrates solutions for:
- Video streaming apps
- Educational platforms
- Entertainment apps
- Video conferencing
- Media libraries
- Content management systems

## 🔮 Future Enhancements (Planned)

### Phase 2
- HLS/DASH streaming support
- Subtitle support (SRT, WebVTT)
- Alternative resolution selection
- Cache system for offline playback

### Phase 3
- Picture-in-Picture (PiP) mode
- ListView integration
- Media notifications
- Background playback
- AirPlay and Chromecast support

### Phase 4
- DRM support (Widevine, FairPlay)
- Performance optimizations
- Comprehensive testing
- Additional documentation

## 🤝 Contributing

Feel free to:
- Report bugs
- Suggest features
- Submit pull requests
- Improve documentation

## 📄 License

This example app is part of the ZMedia Player package and follows the same license.

## 💡 Tips

1. **For Best Performance**: Enable hardware acceleration in settings
2. **Network Testing**: Try different videos to test network handling
3. **Playlist Testing**: Use shuffle and repeat modes to test playlist behavior
4. **Speed Testing**: Try extreme speeds (0.25x and 4.0x) to test stability
5. **BoxFit Testing**: Compare different BoxFit modes with various video aspect ratios

## 🐛 Troubleshooting

### Video Not Playing
- Check internet connection
- Verify video URL is accessible
- Check device permissions

### Performance Issues
- Enable hardware acceleration
- Close other apps
- Check device capabilities

### Controls Not Showing
- Tap the video to toggle controls
- Check showControls setting
- Verify controls timeout setting

## 📞 Support

For issues or questions:
- Check the main package README
- Review the code examples
- Open an issue on GitHub

---

**Made with ❤️ using Flutter and ZMedia Player**
