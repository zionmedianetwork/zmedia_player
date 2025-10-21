# ZMedia Player - API Reference

Complete API documentation for the ZMedia Player Flutter package.

---

## 📚 Documentation Index

### [Getting Started](getting-started.md)
Quick start guide, installation, and basic usage examples.

### [Player API](player-api.md)
Core `MediaPlayer` and `MediaController` API reference with all methods and properties.

### [Events & Callbacks](events.md)
All available events, streams, and callback handlers.

### [Live Streaming](live-streaming.md)
HLS/DASH live streaming with DVR functionality and low-latency support.

### [DRM Configuration](drm.md)
Digital Rights Management setup for Widevine, FairPlay, and EZDRM.

### [Advanced Features](advanced-features.md)
Notifications, Picture-in-Picture, Casting (AirPlay & Chromecast).

### [Models & Data Structures](models.md)
All data models: MediaItem, Playlist, Tracks, Configurations.

---

## Quick Links

- [Main README](../../README.md) - Project overview
- [Implementation Details](../implementation/) - Architecture and internals
- [Project Summary](../summary/) - Development progress and status

---

## API Overview

### Core Classes

```dart
MediaPlayer        // Main player instance
MediaController    // High-level controller
MediaPlayerWidget  // UI widget with controls
```

### Key Features

- ✅ **Basic Playback** - Play, pause, seek, volume, speed
- ✅ **Playlists** - Sequential, shuffle, repeat modes
- ✅ **Adaptive Streaming** - HLS/DASH with quality selection
- ✅ **Subtitles** - SRT, WebVTT, ASS/SSA formats
- ✅ **DRM** - Widevine, FairPlay, token-based
- ✅ **Notifications** - Media controls in system tray
- ✅ **Picture-in-Picture** - Floating video playback
- ✅ **Casting** - AirPlay (iOS) and Chromecast (Android)

---

## Platform Support

| Feature | Android | iOS |
|---------|---------|-----|
| Basic Playback | ✅ | ✅ |
| HLS/DASH | ✅ | ✅ |
| Subtitles | ✅ | ✅ |
| DRM (Widevine) | ✅ | ❌ |
| DRM (FairPlay) | ❌ | ✅ |
| Notifications | ✅ | ✅ |
| Picture-in-Picture | ✅ | ✅ |
| Chromecast | ✅ | ❌ |
| AirPlay | ❌ | ✅ |

---

## Need Help?

- 📖 Browse the guides in this folder
- 🐛 [Report issues](https://github.com/zionmedianetwork/zmedia_player/issues)
- 💬 [Discussions](https://github.com/zionmedianetwork/zmedia_player/discussions)

---

**Version:** 0.1.0  
**Last Updated:** October 19, 2025

