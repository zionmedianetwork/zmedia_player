# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.
a step by step roadmap is available in PLAN.md. Always follow this file for implementation guidance

## Project Overview

ZMedia Player is a comprehensive Flutter media player package with advanced features for video and audio playback across Android and iOS platforms. It provides enterprise-grade capabilities including DRM support, adaptive streaming (HLS/DASH), Picture-in-Picture, casting (Chromecast/AirPlay), and live streaming.

**Version:** 0.1.0
**Flutter SDK:** >=3.19.0
**Dart SDK:** >=3.0.0 <4.0.0

## Development Commands

### Testing

```bash
# Run all tests
flutter test

# Run specific test file
flutter test test/core/media_controller_test.dart

# Run tests with coverage
flutter test --coverage

# Run performance tests
flutter test test/performance/

# Run memory leak tests
flutter test test/memory/

# Run crash reporting tests
flutter test test/crash_reporting/
```

### Building
```bash
# Get dependencies
flutter pub get

# Run example app
cd example && flutter run

# Build example app for Android
cd example && flutter build apk

# Build example app for iOS
cd example && flutter build ios

# Analyze code
flutter analyze

# Format code
dart format lib/ test/
```

### Plugin Development
```bash
# Clean build artifacts
flutter clean

# Build plugin
flutter pub get && flutter analyze

# Test on specific platform
cd example && flutter run -d <device-id>
```

## Architecture Overview

### High-Level Structure

The package follows **clean architecture** with clear separation between Flutter/Dart layer and native platform implementations:

```
┌─────────────────────────────────────────────────┐
│           Flutter/Dart Layer                    │
│  ┌──────────────┐  ┌──────────────────────┐    │
│  │ Controllers  │  │  Widgets             │    │
│  │ (Facade)     │  │  (UI Components)     │    │
│  └──────┬───────┘  └──────────────────────┘    │
│         │                                        │
│  ┌──────▼──────────────────────────────────┐   │
│  │   MediaPlayer (Core)                    │   │
│  │   - State Management                    │   │
│  │   - MethodChannel Communication         │   │
│  └──────┬──────────────────────────────────┘   │
└─────────┼──────────────────────────────────────┘
          │ MethodChannel
┌─────────▼──────────────────────────────────────┐
│         Native Platform Layer                   │
│  ┌─────────────────┐  ┌─────────────────────┐  │
│  │ Android (Kotlin)│  │  iOS (Swift)        │  │
│  │ - ExoPlayer     │  │  - AVPlayer         │  │
│  │ - Widevine DRM  │  │  - FairPlay DRM     │  │
│  │ - Chromecast    │  │  - AirPlay          │  │
│  └─────────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────┘
```

### Core Components

#### 1. MediaPlayer (`lib/src/core/media_player.dart`)
- **Primary interface** for all media operations
- Manages MethodChannel communication with native platforms
- Handles state management via broadcast streams
- Singleton per playerId pattern (multiple instances supported)
- Includes crash reporting integration

**Key responsibilities:**
- Load/play/pause/seek operations
- Playlist management
- Quality/subtitle/audio track selection
- DRM session handling
- PiP and casting coordination
- Bandwidth monitoring

#### 2. MediaController (`lib/src/core/media_controller.dart`)
- **Simplified facade** over MediaPlayer
- Follows Observer pattern (extends ChangeNotifier)
- Auto-hiding controls logic
- Prevents race conditions with operation locks
- Throttles position updates (500ms minimum interval)

**Use MediaController when:** Building UI components that need reactive state updates
**Use MediaPlayer when:** Need direct access to advanced features or custom integration

#### 3. Native Platform Managers

**Android:** `MediaPlayerManager.kt`
- ExoPlayer-based implementation
- Handles Widevine DRM
- Manages HLS/DASH adaptive streaming
- Chromecast integration via CastHandler

**iOS:** `MediaPlayerManager.swift`
- AVPlayer-based implementation
- Handles FairPlay DRM
- Manages HLS streaming
- AirPlay integration via AirPlayHandler

Both managers follow identical interface patterns defined by the MethodChannel protocol.

### Data Flow Patterns

#### Playback State Flow
```
User Action → MediaController → MediaPlayer → MethodChannel
                                              ↓
                                    Native Platform
                                              ↓
                                    Event Callbacks
                                              ↓
                        StreamController.broadcast()
                                              ↓
                        UI Updates via Stream Listeners
```

#### DRM License Acquisition
```
MediaItem(drmConfig) → MediaPlayer.load()
                              ↓
              Native Platform (DrmHandler)
                              ↓
         License Server Request (with auth headers)
                              ↓
         DRM Session State → drmSessionStream
```

### Services Layer

**StreamingService** (`lib/src/services/streaming_service.dart`)
- Bandwidth estimation algorithms
- Automatic quality selection based on network conditions
- Quality switch threshold management (default 0.8)

**CacheService** (`lib/src/services/cache_service.dart`)
- Progressive download with progress tracking
- Cache size management (configurable max size)
- Expiration policies (configurable duration)

**SubtitleService** (`lib/src/services/subtitle_service.dart`)
- SRT/WebVTT/ASS/SSA parsing
- Subtitle rendering with customizable styling
- Multi-language subtitle track management

**NotificationService** (`lib/src/services/notification_service.dart`)
- Media playback notifications (Android/iOS)
- Notification actions (play/pause/next/previous)
- Action stream for UI integration

**CastService** (`lib/src/services/cast_service.dart`)
- Device discovery (Chromecast/AirPlay)
- Connection management
- Media session control on cast devices

## Key Patterns and Conventions

### Instance Management
- **MediaPlayer uses factory pattern with instance registry**
- Each playerId gets a unique instance stored in `_instances` map
- Background cleanup timer removes stale instances (30min inactivity)
- Always dispose controllers to prevent memory leaks

### Error Handling
- Custom exceptions in `lib/src/core/exceptions.dart`
- Platform-specific error mapping (PlatformException → MediaPlayerException)
- CrashReporter integration for production error tracking
- Error state propagated via PlaybackState.state = PlayerState.error

### State Management
- **All state is broadcast via StreamControllers**
- Streams are broadcast type to allow multiple listeners
- Position updates throttled to prevent excessive notifications
- State transitions follow defined lifecycle: idle → loading → playing/paused → completed/error

### Native Communication Protocol

**MethodChannel calls (Dart → Native):**
- `initialize`: Setup player instance
- `load`: Load media with configuration
- `play/pause/stop`: Playback control
- `seekTo`: Position seeking
- `setQualityTrack`: Manual quality selection
- `enterPictureInPicture`: PiP mode activation
- `setDrmConfig`: DRM configuration

**Event callbacks (Native → Dart):**
- `onPlaybackStateChanged`: State transitions
- `onPositionChanged`: Playback position updates
- `onDurationChanged`: Media duration
- `onQualityTracksChanged`: Available quality tracks
- `onDrmSessionUpdate`: DRM session state
- `onBandwidthUpdate`: Network bandwidth estimation

## Testing Strategy

### Test Organization
- **Unit tests:** `test/core/`, `test/models/`, `test/services/`
- **Performance tests:** `test/performance/` (with specific targets)
- **Memory tests:** `test/memory/` (leak detection)
- **Integration tests:** `example/` app for manual testing

### Mock Strategy
- Use mocks for native platform communication in unit tests
- Memory leak tests use actual StreamController/Timer to verify cleanup
- Performance tests have specific latency targets (e.g., <100ms for DRM init)

### Test Coverage
- Current: 113/113 tests passing
- Focus on state management, playlist logic, DRM configuration, error handling
- Performance benchmarks included for critical paths

## Important Implementation Details

### DRM Multi-Platform Support
- **Android:** Widevine L1/L3 via ExoPlayer's DefaultDrmSessionManager
- **iOS:** FairPlay via AVContentKeySession
- **EZDRM integration:** Simplified license server configuration
- Token-based auth: Custom headers with JWT support

### Live Streaming DVR
- `enableDvr: true` allows seeking in live streams
- `liveLatency` configures target latency (default: 3s)
- Live edge detection via isLive flag
- Segment prefetching for smooth playback

### Picture-in-Picture
- Android: Uses `enterPictureInPictureMode()` API
- iOS: Uses `AVPictureInPictureController`
- Availability check before attempting PiP
- PiP state tracked via pipStatusStream

### Playlist Management
- Sequential and shuffle playback modes
- Repeat modes: none, single, all
- Auto-advance on completion
- Skip next/previous with boundary checks

## Common Gotchas

1. **Always initialize MediaPlayer before use** - Call `initialize()` explicitly or use MediaController.create() factory
2. **Dispose controllers in State.dispose()** - Prevents memory leaks and native resource cleanup
3. **DRM requires HTTPS** - License and media URLs must use secure connections
4. **PiP availability is platform/device dependent** - Always check `checkPipAvailability()` first
5. **Live streams need specific configuration** - Set `enableLiveStream: true` in HlsConfig/DashConfig
6. **Subtitle styling uses ARGB color format** - e.g., 0xFFFFFFFF for white, 0x80000000 for semi-transparent black
7. **Multiple instances are supported** - Use unique playerIds for concurrent players (e.g., ListView)
8. **MethodChannel calls are async** - Always await native operations to prevent race conditions

## Platform-Specific Notes

### Android
- Min SDK: 21 (Lollipop)
- Uses ExoPlayer 2.x
- Requires INTERNET and ACCESS_NETWORK_STATE permissions
- Chromecast requires Google Play Services

### iOS
- Min iOS: 12.0
- Uses AVPlayer/AVFoundation
- Requires NSAppTransportSecurity configuration for HTTP
- Background audio requires UIBackgroundModes in Info.plist
- FairPlay requires valid certificate from Apple

## Documentation Structure

- **`docs/api-reference/`** - User-facing API documentation and guides
- **`docs/implementation/`** - Architecture, testing, security documentation
- **`docs/summary/`** - Project status, metrics, feature lists
- **`example/`** - Full-featured demo app with all capabilities

## Development Workflow

1. Make changes in `lib/src/` or native code
2. Run `flutter analyze` to check for issues
3. Write/update tests in `test/`
4. Run `flutter test` to verify
5. Test in example app: `cd example && flutter run`
6. Update relevant documentation in `docs/` if adding features
7. Ensure no breaking changes to public API

## Branching Strategy

- Main branch: (not specified - check repository)
- Feature branches: Use descriptive names (e.g., `feat/bandwidth-monitoring-livestreaming`)
- Chore branches: Use `chore/` prefix (e.g., `chore/refactor-and-more`)
