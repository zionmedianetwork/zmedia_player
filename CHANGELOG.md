# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- CI/CD pipeline with automated testing, linting, and analysis
- Pre-commit hooks for code quality enforcement
- Automated release workflow with semantic versioning

### Fixed
- Deprecated `Color.withOpacity()` replaced with `Color.withValues(alpha:)`
- Deprecated `WillPopScope` replaced with `PopScope`
- Deprecated `onPopInvoked` replaced with `onPopInvokedWithResult`
- Removed unused fields and debug print statements

## [0.1.0] - 2025-01-15

Initial release of ZMedia Player - A comprehensive Flutter media player package.

### Features
- 🎥 Video and audio playback
- 📱 iOS and Android support
- 🔐 DRM support (Widevine, FairPlay)
- 📡 Adaptive streaming (HLS, DASH)
- 📺 Chromecast and AirPlay support
- 🖼️ Picture-in-Picture mode
- 🔴 Live streaming with DVR
- 📝 Subtitle support (SRT, WebVTT, ASS, SSA)
- 📊 Playback analytics and metrics
- 💾 Caching and offline playback
- 🎚️ Customizable player controls
- 📋 Playlist management

### Platform Support
- **Android**: Minimum SDK 21 (Lollipop)
- **iOS**: Minimum iOS 12.0

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
