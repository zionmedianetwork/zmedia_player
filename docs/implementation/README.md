# ZMedia Player - Implementation Guide

Technical documentation covering architecture, native implementations, and development processes.

---

## 📐 Documentation Index

### [Architecture Overview](architecture.md)
System design, component interactions, and architectural decisions.

### [Native Android Implementation](android.md)
ExoPlayer integration, DRM, notifications, PiP, and Chromecast.

### [Native iOS Implementation](ios.md)
AVPlayer integration, FairPlay DRM, notifications, PiP, and AirPlay.

### [Testing & Quality](testing.md)
Unit tests, performance tests, test coverage, and quality metrics.

### [Security](security.md)
Security audit checklist, DRM best practices, and compliance guidelines.

### [Better Player Comparison](better-player-parity.md)
Feature parity analysis with the popular `better_player` package.

---

## Architecture Highlights

### Flutter Layer
```
MediaPlayerWidget (UI)
       ↓
MediaController (High-level API)
       ↓
MediaPlayer (Core)
       ↓
Platform Channel
```

### Native Layer (Android)
```
FlutterMediaPlayerPlugin
  ├── MediaPlayerManager (ExoPlayer)
  ├── DrmHandler (Widevine)
  ├── NotificationHandler (MediaSession)
  ├── PipHandler (PictureInPictureParams)
  └── CastHandler (Google Cast SDK)
```

### Native Layer (iOS)
```
FlutterMediaPlayerPlugin
  ├── MediaPlayerManager (AVPlayer)
  ├── DrmHandler (FairPlay)
  ├── NotificationHandler (MPNowPlayingInfoCenter)
  ├── PipHandler (AVPictureInPictureController)
  └── AirPlayHandler (AVRoutePickerView)
```

---

## Development Status

### ✅ Completed Phases

1. **Phase 1 - Core Functionality**
   - Basic playback controls
   - MediaController architecture
   - Configuration system
   - Playlist management

2. **Phase 2 - Streaming & Subtitles**
   - HLS/DASH adaptive streaming
   - Subtitle support (SRT, WebVTT, ASS/SSA)
   - Quality/audio track selection
   - Bandwidth monitoring

3. **Phase 3 - Advanced Features**
   - Media notifications
   - Picture-in-Picture
   - Casting (AirPlay & Chromecast)
   - ListView integration

4. **Phase 4 - DRM & Polish**
   - Widevine DRM (Android)
   - FairPlay DRM (iOS)
   - EZDRM integration
   - Token-based DRM
   - Comprehensive testing

---

## Tech Stack

### Flutter/Dart
- **Flutter:** 3.x
- **Dart:** 3.x
- **Platform Channels:** MethodChannel for bidirectional communication

### Android
- **ExoPlayer:** 2.x (Media playback)
- **Kotlin:** Modern Android development
- **MediaSession:** System media controls
- **Google Cast SDK:** Chromecast support

### iOS
- **AVFoundation:** AVPlayer, AVKit
- **Swift:** Modern iOS development
- **AVAudioSession:** Background playback
- **AVRoutePickerView:** AirPlay integration

---

## Key Design Patterns

### Observer Pattern
- Event-driven architecture using Dart Streams
- Platform → Flutter event propagation
- State management with StreamControllers

### Factory Pattern
- MediaPlayer instance creation
- DRM configuration builders

### Strategy Pattern
- Platform-specific implementations
- Adaptive streaming algorithms

### Singleton Pattern
- MediaPlayer instance management
- Service managers (Cast, Notification, etc.)

---

## Performance Considerations

### Benchmarks
- DRM operations: < 7μs average
- Serialization: < 4μs per object
- License validation: < 1μs
- 94-99% faster than targets

### Optimization Strategies
1. Lazy initialization of heavy components
2. Stream-based state management
3. Native-side caching
4. Hardware acceleration
5. Efficient memory management

---

## Testing Strategy

### Unit Tests (113 tests)
- Model validation
- Serialization/deserialization
- Configuration handling
- Edge case coverage

### Performance Tests
- Operation benchmarks
- Regression testing
- Memory footprint validation

### Integration Tests (Planned)
- End-to-end flows
- Platform interaction testing
- Widget tests

---

## Contributing

### Development Setup
```bash
# Clone the repository
git clone https://github.com/zionmedianetwork/zmedia_player.git

# Install dependencies
flutter pub get

# Run tests
flutter test

# Run example app
cd example
flutter run
```

### Code Style
- Follow Dart/Flutter style guide
- Use meaningful variable names
- Document public APIs
- Write tests for new features

---

## References

- [Flutter Platform Channels](https://docs.flutter.dev/platform-integration/platform-channels)
- [ExoPlayer Documentation](https://exoplayer.dev/)
- [AVFoundation Programming Guide](https://developer.apple.com/av-foundation/)
- [Better Player Package](https://pub.dev/packages/better_player)

---

**Version:** 1.0.0  
**Last Updated:** October 19, 2025

