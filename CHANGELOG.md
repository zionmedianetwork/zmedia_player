# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.3] - 2026-06-29


### 🚀 Features

- 🚀 feat!: add Swift Package Manager support for the iOS plugin (@Adolphe Cher-Aime) (8df53b4)
- 🚀 feat(example): add fully-custom controls & overlay demo page (@Adolphe Cher-Aime) (e41fa7b)

### 🐛 Bug Fixes

- 🐛 fix(controls): stop MaterialMediaControls overflow in short inline players (@Adolphe Cher-Aime) (91ac5c8)
- 🐛 fix(cast): initialize native CastHandler from MediaPlayer so discovery works (@Adolphe Cher-Aime) (bc778db)
- 🐛 fix(cast,fullscreen): main-thread cast crash + Hybrid Composition exit crash + orientation API (@Adolphe Cher-Aime) (0bb5c9a)
- 🐛 fix(fullscreen): resolve black-screen-with-audio from single native view contention (@Adolphe Cher-Aime) (e9e0893)
- 🐛 fix(pip): forward PiP config to native so auto-enter-on-background works (@Adolphe Cher-Aime) (ee81097)
- 🐛 fix(release): force-push the ephemeral release branch to survive re-runs (@Adolphe Cher-Aime) (887064e)
- 🐛 fix(release): use RELEASE_PAT for PR creation; don't abort release if blocked (@Adolphe Cher-Aime) (98fd24b)
- 🐛 fix: landscape video scaling, notification thumbnails, and configurable safe-area (@Adolphe Cher-Aime) (f7ce638)
- 🐛 fix: media notification Now Playing state sync and iOS seek action strings (@Adolphe Cher-Aime) (de72bf0)
- 🐛 fix: playlist auto-advance, real shuffle order, and play-after-completion restart (@Adolphe Cher-Aime) (88514c7)
- 🐛 fix: iOS audio session, fullscreen rendering, and controls overflow (@Adolphe Cher-Aime) (2100e0b)
- 🐛 fix(example): device-testing fixes for the feature gallery (@Adolphe Cher-Aime) (c530bcf)
- 🐛 fix: native lifecycle hardening (coroutines, notifications, iOS KVO) (@Adolphe Cher-Aime) (647e3ea)
- 🐛 fix: harden subtitle parsers, fix backoff, add value-model equality (@Adolphe Cher-Aime) (5f65e68)
- 🐛 fix: P1 UI stubs, cache directory, and Android bandwidth estimate (@Adolphe Cher-Aime) (2679147)
- 🐛 fix: P1 core correctness and MediaController facade completion (@Adolphe Cher-Aime) (7b16c80)
- 🐛 fix: enforce certificate pinning and stop secure-storage plaintext fallback (@Adolphe Cher-Aime) (8181417)
- 🐛 fix: wire DRM end-to-end on Android and iOS (@Adolphe Cher-Aime) (5829aa8)
- 🐛 fix: P0 core correctness and security fixes (@Adolphe Cher-Aime) (840cdb5)

### ⚡ Performance Improvements

- ⚡ perf/a11y: scope controls rebuilds, fix seek-on-drag, add accessibility (@Adolphe Cher-Aime) (1ea070e)

### 📚 Documentation

- 📚 docs: consolidate, purge, and update documentation to current state (@Adolphe Cher-Aime) (d22af44)
- 📚 docs(fullscreen): document orientation API + Hybrid Composition; demo in example (@Adolphe Cher-Aime) (a8d606c)
- 📚 docs: comprehensive accuracy sweep, add AGENTS.md, remove emojis (@Adolphe Cher-Aime) (dacd9f9)
- 📚 docs(example): rewrite README to match the current feature-gallery app (@Adolphe Cher-Aime) (eff0a12)
- 📚 docs: correct stale status claims to reflect real readiness (@Adolphe Cher-Aime) (8fe0031)
- 📚 docs: add codebase audit and remediation roadmap (@Adolphe Cher-Aime) (39f8022)
- 📚 docs: require flutter-expert subagent for all code work (@Adolphe Cher-Aime) (d285c06)
- 📚 docs: move release notes into docs/releases and index them (@Adolphe Cher-Aime) (dbe9e9e)

### ✅ Tests

- ✅ test: add MethodChannel/controller harness; fix 2 bugs it surfaced (@Adolphe Cher-Aime) (63c0eef)

### Other Changes

- Merge pull request #58 from zionmedianetwork/docs/consolidate-cleanup (@Adolphe Cher-Aime) (bcd541b)
- Merge pull request #57 from zionmedianetwork/fix/alelouya-cast-fullscreen-patches (@Adolphe Cher-Aime) (6d21a6f)
- Merge pull request #56 from zionmedianetwork/chore/release-always-bump-badges (@Adolphe Cher-Aime) (3cdfa81)
- ci(release): always bump version; refresh README version + tests badges (@Adolphe Cher-Aime) (7e69761)
- Merge pull request #55 from zionmedianetwork/chore/sync-version-0.2.2 (@Adolphe Cher-Aime) (61c212b)
- chore(release): sync version to 0.2.2 to match released tag (@Adolphe Cher-Aime) (d7f43a3)
- Merge pull request #53 from zionmedianetwork/fix/fullscreen-single-native-view (@Adolphe Cher-Aime) (360fbdd)
- Merge pull request #52 from zionmedianetwork/fix/pip-config-autoenter-forwarding (@Adolphe Cher-Aime) (46daf21)
- Merge pull request #50 from zionmedianetwork/fix/release-workflow-hardening (@Adolphe Cher-Aime) (e534f8d)
- Merge pull request #49 from zionmedianetwork/fix/release-workflow-pr-permissions (@Adolphe Cher-Aime) (621edab)
- Merge pull request #48 from zionmedianetwork/docs/comprehensive-update (@Adolphe Cher-Aime) (63d191e)
- Merge pull request #47 from zionmedianetwork/fix/landscape-and-notification-thumbnail (@Adolphe Cher-Aime) (eb7f229)
- Merge pull request #46 from zionmedianetwork/chore/ios-spm-support (@Adolphe Cher-Aime) (22d673a)
- Merge pull request #45 from zionmedianetwork/chore/flutter-344-integration (@Adolphe Cher-Aime) (1ba5635)
- chore!: upgrade to Flutter 3.44.3 and rename RepeatMode -> MediaRepeatMode (@Adolphe Cher-Aime) (2c065bb)
- Merge chore/rewrite-example-app: feature-gallery example rewrite + device-test fixes + README (@Adolphe Cher-Aime) (0e71cc6)
- Merge fix/playback-fullscreen-notifications: iOS audio/fullscreen, playlist auto-advance/shuffle, play-restart, notification sync (@Adolphe Cher-Aime) (e44a76d)
- chore: rewrite example app as a feature-per-page gallery (@Adolphe Cher-Aime) (b91bbb3)
- Merge pull request #44 from zionmedianetwork/test/methodchannel-harness (@Adolphe Cher-Aime) (eb6d674)
- Merge pull request #43 from zionmedianetwork/docs/correct-status-claims (@Adolphe Cher-Aime) (2507f48)
- Merge pull request #42 from zionmedianetwork/fix/p2-native-lifecycle (@Adolphe Cher-Aime) (d8787a0)
- Merge pull request #41 from zionmedianetwork/fix/p2-ui-perf-a11y (@Adolphe Cher-Aime) (636e71b)
- Merge pull request #40 from zionmedianetwork/fix/p2-parsing-robustness (@Adolphe Cher-Aime) (aba71e7)
- Merge pull request #39 from zionmedianetwork/fix/p1-ui-cache-bandwidth (@Adolphe Cher-Aime) (bb2f353)
- Merge pull request #38 from zionmedianetwork/fix/p1-core-facade (@Adolphe Cher-Aime) (6ebfcb0)
- Merge pull request #37 from zionmedianetwork/fix/p0-native-security (@Adolphe Cher-Aime) (3611584)
- Merge pull request #36 from zionmedianetwork/fix/p0-drm-wiring (@Adolphe Cher-Aime) (07aafd2)
- Merge pull request #35 from zionmedianetwork/fix/p0-core-correctness (@Adolphe Cher-Aime) (c8b1b68)
- Merge pull request #34 from zionmedianetwork/docs/structure-and-introduce-claude (@Adolphe Cher-Aime) (721a247)

**Full Changelog**: https://github.com/zionmedianetwork/zmedia_player/compare/v0.1.0...v0.2.3

## [Unreleased]

### Fixed
- Chromecast discovery never finding devices resolved: `MediaPlayer` never invoked
  the `initializeCast` method channel, so the native `CastHandler` was never created
  on the `MediaController`/`MediaPlayer` path (only the separate `CastService` called
  it). `startCastDiscovery` then ran `castHandlers[playerId]?.startDiscovery()` as a
  null-safe no-op that still reported success, leaving the UI spinning forever with
  zero devices. `MediaPlayer` now lazily calls `initializeCast` (once, guarded) before
  `startCastDiscovery`, `connectToCastDevice`, and `loadMediaOnCastDevice`.
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
