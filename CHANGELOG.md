# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- Chromecast crash on device selection resolved: `CastHandler.loadMedia` polled
  `RemoteMediaClient` readiness on `Dispatchers.IO`, but the poll reads the Cast SDK's
  `SessionManager.getCurrentCastSession()`, which asserts the main thread and threw
  `IllegalStateException` off the IO worker, hard-crashing the app on the first cast.
  The poll now runs on `Dispatchers.Main`; `delay()` suspends rather than blocks the
  thread, so the UI stays responsive (no ANR).
- Android fullscreen-exit crash/black-screen resolved: `MediaPlayerWidget` now composites
  the Android video surface with true Hybrid Composition
  (`PlatformViewsService.initExpensiveAndroidView`) instead of a Virtual Display
  `AndroidView`. This removes `VirtualDisplayController` entirely, eliminating the
  `getRenderTargetWidth → getWidth()`-on-null NPE that fired when a resize was posted to
  the platform `Handler` after the `SurfaceProducer` was released on exit. iOS `UiKitView`
  is unchanged.

### Added
- `FullscreenMediaPlayer` orientation control (non-breaking; defaults preserve the prior
  landscape-locked behavior):
  - `preferredOrientations` — orientations applied while fullscreen is active
    (e.g. portrait fullscreen or portrait + free rotation).
  - `rotationLocked` — a `ValueListenable<bool>` that live-pins the device to portrait
    when true and re-applies `preferredOrientations` when false.
  - `exitOrientations` — orientations restored when the route pops (default: all four).

## [0.2.2] - 2026-06-25

### Fixed
- Fullscreen black-screen-with-audio resolved: when `FullscreenMediaPlayer` mounted a
  second `MediaPlayerWidget` for the same `playerId` while the inline player stayed
  mounted, two Android `AndroidView` hosts contended for one ExoPlayer surface and the
  fullscreen host rendered black. `getPlayerView()` now creates a fresh view per host
  (detaching ExoPlayer from the previous view first), and a new `reclaimVideoSurface()`
  re-attaches the player when a host mounts. iOS was already a multi-view design and is
  unaffected. The example demonstrates the recommended single-view usage pattern.
- `PipConfig.autoEnterOnBackground` is now forwarded to native on both iOS and Android.
  Previously, `checkPipAvailability()` sent only `playerId` over the method channel;
  the PiP config was never transmitted, so `canStartPictureInPictureAutomaticallyFromInline`
  (iOS 14.2+) and `setAutoEnterEnabled` (Android 12+) were silently never set.
- iOS `PipHandler.initialize(player:playerLayer:)` now accepts an optional `config`
  parameter; when provided it is persisted and applied via
  `canStartPictureInPictureAutomaticallyFromInline` on every code path, including the
  unchanged-layer branch that previously skipped `setupPipController`.
- Android `PipHandler.applyConfig()` introduced so that the config primed during
  `checkPipAvailability` is available when `enterPip` is subsequently called.
- `MediaConfig.allowBackgroundPlayback` is now consumed natively:
  - iOS: configures `AVAudioSession` category `.playback` at `applyConfig` time so
    audio continues when the app is backgrounded (host app must declare
    `UIBackgroundModes: audio` in Info.plist).
  - Android: sets ExoPlayer `WAKE_MODE_NETWORK` so the CPU/wifi lock is held during
    background playback (host app must run a foreground service with a media
    notification for full background audio; that service infrastructure is deferred).

## [Unreleased]

### BREAKING
- Renamed the `RepeatMode` enum to `MediaRepeatMode` (values `none`/`single`/`all`)

### Added
- Swift Package Manager support for iOS (alongside CocoaPods); enable with `flutter config --enable-swift-package-manager`
- `MediaConfig.respectSafeArea` — inset the video below the status bar/notch via `SafeArea`
- `MediaConfig.immersiveLandscape` — hide the system status bar in landscape (restored on portrait/dispose)
- Media-notification artwork auto-generated from a video frame when `MediaItem.artworkUrl` is absent (iOS `AVAssetImageGenerator`, Android `MediaMetadataRetriever`)
- DRM wired end-to-end on Android (Widevine) and iOS (FairPlay)
- CI/CD pipeline with automated testing, linting, and analysis
- Pre-commit hooks for code quality enforcement
- Automated release workflow with semantic versioning

### Changed
- Minimum iOS version raised from 12.0 to 13.0 (Swift concurrency; Flutter 3.44 dropped iOS 12)

### Fixed
- iOS landscape video scaling — `AVPlayerLayer` now resizes correctly on rotation
- `boxFit` property changes now propagate to the native view
- Multi-instance `MethodChannel` routing (events delivered to the correct player instance)
- Native certificate-pinning enforcement on DRM license requests
- Secure storage no longer downgrades to plaintext
- `PlaybackState.bufferedPosition` restored
- Control widgets now cancel their stream subscriptions (no leaked subscriptions)
- HTTPS enforced for DRM license/media URLs
- Deprecated `Color.withOpacity()` replaced with `Color.withValues(alpha:)`
- Deprecated `WillPopScope` replaced with `PopScope`
- Deprecated `onPopInvoked` replaced with `onPopInvokedWithResult`
- Removed unused fields and debug print statements

## [0.1.0] - 2025-01-15

Initial release of ZMedia Player - A comprehensive Flutter media player package.

### Features
- Video and audio playback
- iOS and Android support
- DRM support (Widevine, FairPlay)
- Adaptive streaming (HLS, DASH)
- Chromecast and AirPlay support
- Picture-in-Picture mode
- Live streaming with DVR
- Subtitle support (SRT, WebVTT, ASS, SSA)
- Playback analytics and metrics
- Caching and offline playback
- Customizable player controls
- Playlist management

### Platform Support
- **Android**: Minimum SDK 21 (Lollipop)
- **iOS**: Minimum iOS 13.0 (corrected; see Unreleased "Changed")

### Installation
```yaml
dependencies:
  zmedia_player:
    git:
      url: https://github.com/zionmedianetwork/zmedia_player.git
      ref: v0.1.0
```

### Documentation
- Comprehensive API documentation
- Example app with all features
- Migration guides and tutorials

[Unreleased]: https://github.com/zionmedianetwork/zmedia_player/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/zionmedianetwork/zmedia_player/releases/tag/v0.1.0
