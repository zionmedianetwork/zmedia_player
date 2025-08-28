# Flutter Media Player Package - Technical Requirements Document (TRD)

## 1. Document Information

| Field | Value |
|-------|-------|
| Document Title | Flutter Media Player Package TRD |
| Version | 1.0 |
| Date | August 27, 2025 |
| Status | Draft |

## 2. Executive Summary

This document outlines the technical requirements for developing a comprehensive Flutter media player package that provides advanced video and audio playback capabilities across Android and iOS platforms. The package will support modern streaming protocols, DRM protection, and provide a highly configurable API following software design best practices.

## 3. Project Overview

### 3.1 Purpose
To create a production-ready Flutter media player package that addresses the limitations of existing solutions by providing comprehensive media playback features with enterprise-grade capabilities.

### 3.2 Scope
- Cross-platform media player for Flutter applications
- Support for local and streaming media content
- Advanced features including DRM, PiP, and adaptive streaming
- Highly configurable and extensible architecture

## 4. Functional Requirements

### 4.1 Core Media Playback (FR-001)
- **Description**: Basic video and audio playback functionality
- **Requirements**:
  - Support for common media formats (MP4, MOV, AVI, MP3, AAC, etc.)
  - Play, pause, stop, seek operations
  - Volume control
  - Mute/unmute functionality
  - Progress tracking and scrubbing

### 4.2 Playlist Support (FR-002)
- **Description**: Comprehensive playlist management
- **Requirements**:
  - Create, modify, and delete playlists
  - Add/remove media items from playlists
  - Sequential and shuffle playback modes
  - Repeat modes (none, single, all)
  - Next/previous track navigation
  - Queue management (add to queue, clear queue)
  - Playlist persistence and restoration

### 4.3 Video in ListView Support (FR-003)
- **Description**: Seamless integration with Flutter ListView widgets
- **Requirements**:
  - Automatic pause/resume based on visibility
  - Memory-efficient video rendering in scrollable lists
  - Configurable auto-play behavior
  - Thumbnail generation and caching
  - Smooth scrolling performance optimization

### 4.4 Subtitles Support (FR-004)
- **Description**: Comprehensive subtitle functionality
- **Requirements**:
  - **Format Support**:
    - SRT (SubRip Subtitle) files
    - WebVTT with HTML tag support
    - HLS embedded subtitles
    - DASH subtitle tracks
  - **Features**:
    - Multiple subtitle tracks per video
    - Subtitle track switching during playback
    - Customizable subtitle styling (font, size, color, position)
    - Subtitle synchronization controls
    - External subtitle file loading

### 4.5 HTTP Headers Support (FR-005)
- **Description**: Custom HTTP header management for media requests
- **Requirements**:
  - Set custom headers for media URLs
  - Authentication token support
  - User-Agent customization
  - Referrer and other security headers
  - Per-request header configuration

### 4.6 Video BoxFit Support (FR-006)
- **Description**: Video display and scaling options
- **Requirements**:
  - Support all Flutter BoxFit options (contain, cover, fill, fitWidth, fitHeight, none, scaleDown)
  - Aspect ratio preservation
  - Custom scaling modes
  - Dynamic BoxFit changes during playback

### 4.7 Playback Speed Support (FR-007)
- **Description**: Variable playback speed control
- **Requirements**:
  - Speed range: 0.25x to 4.0x
  - Preset speed options (0.5x, 0.75x, 1.0x, 1.25x, 1.5x, 2.0x)
  - Custom speed values
  - Pitch correction option
  - Speed persistence across sessions

### 4.8 HLS Support (FR-008)
- **Description**: HTTP Live Streaming protocol support
- **Requirements**:
  - Adaptive bitrate streaming
  - Multiple quality track selection
  - Audio track selection (multiple languages)
  - Subtitle track selection from HLS manifest
  - Segmented subtitle support
  - Live stream support with DVR functionality

### 4.9 DASH Support (FR-009)
- **Description**: Dynamic Adaptive Streaming over HTTP support
- **Requirements**:
  - MPEG-DASH manifest parsing
  - Adaptive bitrate streaming
  - Multiple video quality tracks
  - Audio track selection
  - Subtitle track selection
  - Live and VOD content support

### 4.10 Alternative Resolution Support (FR-010)
- **Description**: Manual quality selection and management
- **Requirements**:
  - Available quality detection
  - Manual quality selection
  - Automatic quality switching based on bandwidth
  - Quality preference persistence
  - Bandwidth estimation and monitoring

### 4.11 Cache Support (FR-011)
- **Description**: Media caching for offline and performance optimization
- **Requirements**:
  - Progressive download caching
  - Configurable cache size limits
  - Cache expiration policies
  - Offline playback capability
  - Cache cleanup and management
  - Preload functionality for next items

### 4.12 Notifications Support (FR-012)
- **Description**: Media playback notifications and controls
- **Requirements**:
  - Media-style notification with playback controls
  - Lock screen media controls
  - Notification customization (artwork, title, artist)
  - Background playback support
  - Integration with system media session

### 4.13 Picture in Picture Support (FR-013)
- **Description**: PiP mode for video playback
- **Requirements**:
  - Automatic PiP on app backgrounding
  - Manual PiP activation
  - PiP window controls (play/pause, close)
  - Configurable PiP window size and position
  - Seamless transition back to full-screen

### 4.14 DRM Support (FR-014)
- **Description**: Digital Rights Management implementation
- **Requirements**:
  - **Token-based DRM**: Custom token authentication
  - **Widevine DRM**: Google's DRM solution for Android
  - **FairPlay DRM**: Apple's DRM solution for iOS
  - **EZDRM Integration**: Enterprise DRM service support
  - License acquisition and renewal
  - Offline license support
  - DRM session management

### 4.15 Screencast Support (FR-015)
- **Description**: Wireless media casting to external devices
- **Requirements**:
  - **AirPlay Support (iOS)**:
    - AirPlay video streaming to Apple TV and compatible devices
    - AirPlay audio streaming to AirPlay-enabled speakers
    - AirPlay mirroring support
    - Device discovery and selection
    - Connection status monitoring
    - Seamless handoff between local and AirPlay playback
  - **Chromecast Support (Android/iOS)**:
    - Google Cast SDK integration
    - Cast to Chromecast devices and Cast-enabled TVs
    - Custom receiver application support
    - Media queue management on Cast devices
    - Remote playback controls from sender device
    - Cast session management and recovery
  - **General Casting Features**:
    - Automatic device discovery on local network
    - Cast button integration in media controls
    - Volume control for cast devices
    - Metadata and artwork casting
    - Subtitle casting support
    - DRM content casting (where supported by target device)
    - Background casting support
    - Cast session persistence across app lifecycle

## 5. Non-Functional Requirements

### 5.1 Compatibility (NFR-001)
- **Flutter Version**: Compatible with Flutter 3.19+ and latest stable releases
- **Dart Version**: Support Dart 3.0+ with null safety
- **Platform Versions**:
  - Android: API level 21+ (Android 5.0+)
  - iOS: iOS 12.0+

### 5.2 Native Library Integration (NFR-002)
- **Android**: Utilize ExoPlayer 2.19+ for optimal performance
- **iOS**: Leverage AVPlayer and AVKit frameworks
- **Platform Channels**: Efficient method channel communication
- **Native Performance**: Hardware-accelerated video decoding

### 5.3 Platform Support (NFR-003)
- **Primary Platforms**: Android and iOS
- **Architecture Support**:
  - Android: ARM64, ARM32, x86_64
  - iOS: ARM64 (iPhone 5s+), x86_64 (Simulator)

### 5.4 Configuration & Customization (NFR-004)
- **Highly Configurable**: Extensive configuration options for all features
- **Theme Support**: Customizable UI components and styling
- **Plugin Architecture**: Extensible plugin system for additional features
- **Callback System**: Comprehensive event callback system

### 5.5 Performance (NFR-005)
- **Memory Efficiency**: Optimized memory usage for mobile devices
- **Battery Optimization**: Efficient power consumption
- **Smooth Playback**: Maintain 60fps during video playback
- **Fast Startup**: Media initialization under 500ms

### 5.6 Software Design Principles (NFR-006)
- **SOLID Principles**: Follow Single Responsibility, Open/Closed, Liskov Substitution, Interface Segregation, and Dependency Inversion
- **Clean Architecture**: Separate concerns with clear boundaries
- **Observer Pattern**: Event-driven architecture for state management
- **Factory Pattern**: Media player instance creation and management
- **Strategy Pattern**: Configurable behavior implementations

## 6. Technical Architecture

### 6.1 Package Structure
```
flutter_media_player/
├── lib/
│   ├── src/
│   │   ├── core/
│   │   │   ├── media_player.dart
│   │   │   ├── media_controller.dart
│   │   │   └── media_config.dart
│   │   ├── models/
│   │   │   ├── media_item.dart
│   │   │   ├── playlist.dart
│   │   │   ├── subtitle_track.dart
│   │   │   ├── drm_config.dart
│   │   │   └── cast_device.dart
│   │   ├── services/
│   │   │   ├── cache_service.dart
│   │   │   ├── notification_service.dart
│   │   │   ├── drm_service.dart
│   │   │   └── cast_service.dart
│   │   ├── widgets/
│   │   │   ├── media_player_widget.dart
│   │   │   ├── media_controls.dart
│   │   │   └── subtitle_view.dart
│   │   └── platform/
│   │       ├── android/
│   │       └── ios/
│   └── flutter_media_player.dart
├── android/
│   └── src/main/kotlin/
├── ios/
│   └── Classes/
└── example/
```

### 6.2 Core Classes Design

#### 6.2.1 MediaPlayer (Main Controller)
```dart
class MediaPlayer {
  // Factory constructor for different player types
  factory MediaPlayer({
    MediaConfig? config,
    DrmConfig? drmConfig,
  });
  
  // Core playback methods
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seekTo(Duration position);
  
  // Playlist management
  Future<void> setPlaylist(Playlist playlist);
  Future<void> addToPlaylist(MediaItem item);
  
  // Configuration methods
  void setBoxFit(BoxFit boxFit);
  void setPlaybackSpeed(double speed);
  void setSubtitleTrack(SubtitleTrack track);
  
  // Casting methods
  Future<List<CastDevice>> getAvailableCastDevices();
  Future<void> startCasting(CastDevice device);
  Future<void> stopCasting();
  bool get isCasting;
  Stream<CastState> get castStateStream;
  
  // Event streams
  Stream<PlayerState> get stateStream;
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
}
```

#### 6.2.2 MediaConfig (Configuration)
```dart
class MediaConfig {
  final bool autoPlay;
  final bool looping;
  final BoxFit boxFit;
  final double volume;
  final Map<String, String>? httpHeaders;
  final CacheConfig? cacheConfig;
  final NotificationConfig? notificationConfig;
  final PipConfig? pipConfig;
  final CastConfig? castConfig;
  
  const MediaConfig({
    this.autoPlay = false,
    this.looping = false,
    this.boxFit = BoxFit.contain,
    this.volume = 1.0,
    this.httpHeaders,
    this.cacheConfig,
    this.notificationConfig,
    this.pipConfig,
    this.castConfig,
  });
}
```

### 6.3 Platform-Specific Implementation

#### 6.3.1 Android Implementation
- **Base Library**: ExoPlayer 2.19+
- **DRM Integration**: Widevine ModularDrmScheme
- **Notifications**: MediaSessionCompat and NotificationCompat
- **PiP**: Android PictureInPictureParams API
- **Casting**: Google Cast SDK v21+ with MediaRouteSelector

#### 6.3.2 iOS Implementation
- **Base Library**: AVPlayer and AVPlayerViewController
- **DRM Integration**: AVContentKeySession for FairPlay
- **Background Audio**: AVAudioSession configuration
- **PiP**: AVPictureInPictureController
- **AirPlay**: AVRoutePickerView and AVPlayer's external playback

## 7. API Design

### 7.1 Widget Integration
```dart
class MediaPlayerWidget extends StatefulWidget {
  final MediaPlayer player;
  final bool showControls;
  final bool showCastButton;
  final Widget? placeholder;
  final BoxFit? boxFit;
  final VoidCallback? onTap;
  
  const MediaPlayerWidget({
    Key? key,
    required this.player,
    this.showControls = true,
    this.showCastButton = true,
    this.placeholder,
    this.boxFit,
    this.onTap,
  }) : super(key: key);
}
```

### 7.2 ListView Integration
```dart
class MediaPlayerListView extends StatelessWidget {
  final List<MediaItem> items;
  final MediaPlayerConfig config;
  final Widget Function(BuildContext, MediaItem, int) itemBuilder;
  
  const MediaPlayerListView({
    Key? key,
    required this.items,
    required this.config,
    required this.itemBuilder,
  }) : super(key: key);
}
```

## 8. Testing Strategy

### 8.1 Unit Testing
- Core functionality testing for all public APIs
- Mock platform channel testing
- Configuration validation testing
- State management testing

### 8.2 Integration Testing
- End-to-end playback scenarios
- Platform-specific feature testing
- DRM workflow testing
- Performance benchmarking

### 8.3 Example Application
- Comprehensive example demonstrating all features
- Different use case scenarios
- Performance testing playground

## 9. Documentation Requirements

### 9.1 API Documentation
- Complete dartdoc coverage for all public APIs
- Code examples for common use cases
- Migration guides from other players

### 9.2 Platform Setup Guides
- Android configuration and permissions
- iOS configuration and entitlements
- DRM setup instructions for each provider

### 9.3 Advanced Usage Guides
- Custom UI development
- Plugin development guide
- Performance optimization tips

## 10. Delivery Milestones

### 10.1 Phase 1 - Core Features (Weeks 1-6)
- Basic playback functionality
- Widget integration
- HTTP headers support
- BoxFit support
- Playback speed control

### 10.2 Phase 2 - Streaming & Subtitles (Weeks 7-10)
- HLS/DASH support
- Subtitle implementation
- Alternative resolution support
- Cache system

### 10.3 Phase 3 - Advanced Features (Weeks 11-14)
- Playlist management
- Notifications support
- Picture in Picture
- ListView integration
- Screencast support (AirPlay & Chromecast)

### 10.4 Phase 4 - DRM & Polish (Weeks 15-18)
- DRM implementation
- Performance optimization
- Testing and documentation
- Example application

## 11. Risk Assessment

### 11.1 Technical Risks
- **DRM Complexity**: High complexity in implementing multiple DRM systems
- **Platform Differences**: Significant API differences between Android and iOS
- **Performance**: Memory and battery optimization challenges
- **Casting Integration**: Complex integration with different casting protocols (AirPlay vs Chromecast)
- **Network Dependencies**: Casting functionality dependent on local network stability

### 11.2 Mitigation Strategies
- Early prototyping of DRM integration
- Platform-specific optimization teams
- Continuous performance monitoring and testing
- Separate casting module development with fallback mechanisms
- Comprehensive network error handling and recovery

## 12. Success Criteria

### 12.1 Functional Success
- All functional requirements implemented and tested
- Smooth playback on target devices
- Successful DRM content playback

### 12.2 Non-Functional Success
- Memory usage within acceptable limits
- Battery drain comparable to native players
- Startup time under 500ms
- 95%+ test coverage

## 13. Conclusion

This TRD outlines a comprehensive Flutter media player package that addresses modern mobile video playback requirements. The implementation will follow software engineering best practices while providing a highly configurable and performant solution for Flutter developers.

The package will serve as a production-ready alternative to existing solutions, with particular strength in enterprise features like DRM support and advanced streaming protocols.