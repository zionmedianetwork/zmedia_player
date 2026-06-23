# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-06-23


### 🚀 Features

- 🚀 feat!: add Swift Package Manager support for the iOS plugin (@Adolphe Cher-Aime) (8df53b4)
- 🚀 feat(example): add fully-custom controls & overlay demo page (@Adolphe Cher-Aime) (e41fa7b)

### 🐛 Bug Fixes

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

- 📚 docs: comprehensive accuracy sweep, add AGENTS.md, remove emojis (@Adolphe Cher-Aime) (dacd9f9)
- 📚 docs(example): rewrite README to match the current feature-gallery app (@Adolphe Cher-Aime) (eff0a12)
- 📚 docs: correct stale status claims to reflect real readiness (@Adolphe Cher-Aime) (8fe0031)
- 📚 docs: add codebase audit and remediation roadmap (@Adolphe Cher-Aime) (39f8022)
- 📚 docs: require flutter-expert subagent for all code work (@Adolphe Cher-Aime) (d285c06)
- 📚 docs: move release notes into docs/releases and index them (@Adolphe Cher-Aime) (dbe9e9e)

### ✅ Tests

- ✅ test: add MethodChannel/controller harness; fix 2 bugs it surfaced (@Adolphe Cher-Aime) (63c0eef)

### Other Changes

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

**Full Changelog**: https://github.com/zionmedianetwork/zmedia_player/compare/v0.1.0...v0.2.0

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
