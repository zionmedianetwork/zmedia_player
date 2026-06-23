# ZMedia Player Documentation

Welcome to the complete documentation for the ZMedia Player Flutter package.

---

## Documentation Structure

This documentation is organized into three main sections:

### [API Reference](api-reference/)
**For users who want to integrate ZMedia Player into their apps**

- Quick start guides
- Complete API documentation
- Code examples
- Configuration guides
- DRM setup
- Advanced features (PiP, Casting, Notifications)

**Start here if you're using ZMedia Player in your project**

---

### [Implementation](implementation/)
**For developers who want to understand how it works**

- Architecture overview
- Native Android implementation (ExoPlayer)
- Native iOS implementation (AVPlayer)
- Platform channels design
- Testing strategies
- Security considerations
- Better Player comparison

**Start here if you're contributing or learning the internals**

---

### [Summary](summary/)
**For stakeholders who want to see what's been accomplished**

- Complete feature list
- Development phase summaries
- Test coverage reports
- Production readiness status
- Implementation timeline
- Key achievements

**Start here for project overview and status**

---

## Quick Navigation

### Getting Started
- [Installation & Setup](api-reference/README.md)
- [Basic Usage Examples](api-reference/README.md)
- [Main README](../README.md)

### Common Tasks
- [Playing Videos](api-reference/README.md)
- [Managing Playlists](api-reference/README.md)
- [Live Streaming Setup](api-reference/live-streaming.md)
- [Adding Subtitles](api-reference/README.md)
- [Setting up DRM](api-reference/drm.md)
- [Implementing Notifications](api-reference/README.md)
- [Enabling Picture-in-Picture](api-reference/README.md)
- [Adding Casting Support](api-reference/airplay.md)

### For Developers
- [Architecture Overview](implementation/README.md)
- [Running Tests](implementation/testing.md)
- [Contributing Guidelines](../CONTRIBUTING.md)

### Project Status
- [Complete Feature List](summary/features.md)
- [Phase Summaries](summary/phases.md)
- [Test Coverage Report](summary/test-coverage.md)
- [Production Readiness](summary/production-readiness.md)

---

## What is ZMedia Player?

ZMedia Player is a comprehensive Flutter media player package that provides:

- **Complete Playback Control** - Play, pause, seek, volume, speed
- **Adaptive Streaming** - HLS/DASH with automatic quality adjustment
- **Subtitle Support** - SRT, WebVTT, ASS/SSA formats
- **DRM Protection** - Widevine, FairPlay, EZDRM, token-based
- **Media Notifications** - System-level playback controls
- **Picture-in-Picture** - Floating video playback
- **Casting** - Chromecast (Android) and AirPlay (iOS)
- **Playlist Management** - Sequential, shuffle, and repeat modes (`MediaRepeatMode`)

### Platform Support

| Feature | Android | iOS |
|---------|---------|-----|
| Core Playback | Yes | Yes |
| HLS/DASH Streaming | Yes | Yes |
| Subtitles | Yes | Yes |
| DRM (Widevine) | Yes | No |
| DRM (FairPlay) | No | Yes |
| Notifications | Yes | Yes |
| Picture-in-Picture | Yes | Yes |
| Chromecast | Yes | No |
| AirPlay | No | Yes |

---

## Project Status

**Version:** 0.1.0
**Status:** **Active development — feature-complete, hardening in progress**

All features are implemented across the Dart and native layers. The project is
undergoing audit-driven correctness/security/robustness remediation — see the
[Codebase Audit & Remediation Roadmap](implementation/codebase-audit.md). It is
**not yet validated as production-ready end-to-end**: the native Android/iOS layers
are implemented but require on-device verification.

### Phase Completion
- **Phase 1** - Core Functionality (Complete)
- **Phase 2** - Streaming & Subtitles (Complete)
- **Phase 3** - Advanced Features (Complete)
- **Phase 4** - DRM & Polish (Complete)

### Key Metrics
- **Tests:** 578 automated tests passing (run `flutter test` for the current count);
  strong Dart-layer coverage, **no automated native tests yet**
- **Native verification:** DRM, casting, certificate pinning, and bandwidth metering
  are implemented but need on-device testing
- **Documentation:** Comprehensive guides for all features

---

## Documentation Index

### API Reference
- [API Reference Hub](api-reference/README.md)
- [Events & Callbacks](api-reference/events.md)
- [DRM Configuration](api-reference/drm.md)
- [Live Streaming](api-reference/live-streaming.md)
- [AirPlay Guide](api-reference/airplay.md)

### Implementation
- [Architecture Overview](implementation/README.md)
- [Testing Guide](implementation/testing.md)
- [Security Audit](implementation/security.md)
- [Better Player Comparison](implementation/better-player-comparison.md)
- [Better Player Parity](implementation/better-player-parity.md)
- [Codebase Audit & Remediation Roadmap](implementation/codebase-audit.md)

### Summary
- [Complete Feature List](summary/features.md)
- [Development Phases](summary/phases.md)
- [Test Coverage Report](summary/test-coverage.md)
- [Production Readiness](summary/production-readiness.md)

### Releases
- [Release Notes Index](releases/README.md)
- [v0.1.0 Release Notes](releases/RELEASE_NOTES_v0.1.0.md)

---

## Learning Path

### For New Users
1. Start with the [API Reference Hub](api-reference/README.md)
2. Read the Player API basics in the [API Reference](api-reference/README.md)
3. Explore advanced features in the [API Reference](api-reference/README.md)
4. Check out the [Example App](../example/)

### For Contributors
1. Understand [Architecture](implementation/README.md)
2. Review [Testing Guide](implementation/testing.md)
3. Read the [Security Audit](implementation/security.md)
4. Follow contribution guidelines

### For Project Managers
1. Review [Feature List](summary/features.md)
2. Check [Phase Summaries](summary/phases.md)
3. Verify [Production Readiness](summary/production-readiness.md)
4. Review [Test Coverage](summary/test-coverage.md)

---

## Examples

### Basic Usage
```dart
import 'package:zmedia_player/zmedia_player.dart';

// Create a controller
final controller = MediaController();

// Load and play a video
await controller.load(MediaItem(
  id: 'video1',
  title: 'My Video',
  url: 'https://example.com/video.mp4',
));
await controller.play();

// Use in a widget
MediaPlayerWidget(controller: controller);
```

### Advanced Features
```dart
// Enable Picture-in-Picture
await controller.enterPictureInPicture();

// Show notifications
await controller.showNotification();

// Add DRM protection
final drmItem = MediaItem(
  id: 'protected',
  title: 'Protected Content',
  url: 'https://example.com/drm-video.mpd',
  drmConfig: DrmConfig.widevine(
    licenseUrl: 'https://license-server.com/license',
  ),
);
```

See [API Reference](api-reference/) for complete examples.

---

## External Links

- **GitHub Repository:** [github.com/zionmedianetwork/zmedia_player](https://github.com/zionmedianetwork/zmedia_player)
- **Pub.dev Package:** [pub.dev/packages/flutter_media_player](https://pub.dev/packages/flutter_media_player)
- **Issue Tracker:** [GitHub Issues](https://github.com/zionmedianetwork/zmedia_player/issues)
- **Discussions:** [GitHub Discussions](https://github.com/zionmedianetwork/zmedia_player/discussions)

---

## Contributing

We welcome contributions! Please see:

- [Contributing Guidelines](../CONTRIBUTING.md)
- [Code of Conduct](../CODE_OF_CONDUCT.md)
- [Development Setup](implementation/README.md#contributing)

---

## License

This project is licensed under the MIT License - see the [LICENSE](../LICENSE) file for details.

---

## Support

- **Documentation Issues:** [File an issue](https://github.com/zionmedianetwork/zmedia_player/issues)
- **Feature Requests:** [Start a discussion](https://github.com/zionmedianetwork/zmedia_player/discussions)
- **Bug Reports:** [Report a bug](https://github.com/zionmedianetwork/zmedia_player/issues/new)

---

**Project:** ZMedia Player
**Organization:** Zion Media Network
**Version:** 0.1.0
**Status:** Active development — feature-complete, hardening in progress
