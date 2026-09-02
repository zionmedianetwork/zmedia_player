# ZMedia Player - Implementation Guide

Technical documentation covering architecture, native implementations, and development processes.

---

## Documentation Index

### Architecture & native implementation
System design, component interactions, and the per-feature native handler layout
(AndroidX Media3/ExoPlayer/Widevine/Chromecast on Android, AVPlayer/FairPlay/AirPlay on iOS) are
covered in the **Architecture Highlights** section below and in the root
[`CLAUDE.md`](../../CLAUDE.md) architecture overview.

### [Testing & Quality](testing.md)
Unit tests, performance tests, test coverage, and quality metrics.

### [Security](security.md)
Security audit checklist, DRM best practices, and compliance guidelines.

### [Better Player Comparison](better-player-comparison.md)
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
ZMediaPlayerPlugin
  ├── MediaPlayerManager (AndroidX Media3 ExoPlayer)
  ├── DrmHandler (Widevine)
  ├── NotificationHandler (MediaSession)
  ├── PipHandler (PictureInPictureParams)
  └── CastHandler (Google Cast SDK)
```

### Native Layer (iOS)
```
ZMediaPlayerPlugin
  ├── MediaPlayerManager (AVPlayer)
  ├── DrmHandler (FairPlay)
  ├── NotificationHandler (MPNowPlayingInfoCenter)
  ├── PipHandler (AVPictureInPictureController)
  └── AirPlayHandler (AVRoutePickerView)
```

---

## Development Status

### Completed Phases

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
- **AndroidX Media3:** 1.11.0 (ExoPlayer, `media3-exoplayer-hls`/`-dash`, `media3-datasource-okhttp`)
- **Kotlin:** Modern Android development
- **MediaSession:** System media controls
- **Google Cast SDK:** Chromecast support
- **Min/compile SDK:** minSdk 23, compileSdk 35

### iOS
- **Minimum iOS:** 13.0 (Swift concurrency; Flutter 3.44 dropped iOS 12)
- **Packaging:** Swift Package Manager (`ios/zmedia_player/Package.swift`) and CocoaPods
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

### Unit Tests (Dart — 1089 passing; run `flutter test` for the live count)
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

**Last Updated:** August 17, 2026
