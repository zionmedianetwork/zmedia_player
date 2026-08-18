# ZMedia Player

A comprehensive Flutter media player package with advanced features for video and audio playback across Android and iOS platforms.

[![Version](https://img.shields.io/github/v/release/zionmedianetwork/zmedia_player?label=version&color=blue&sort=semver)](https://github.com/zionmedianetwork/zmedia_player/releases)
[![Tests](https://img.shields.io/badge/tests-588%20passing-brightgreen.svg)](docs/summary/test-coverage.md)
[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS-lightgrey.svg)](docs/summary/features.md)

> **Working with this package as an AI agent or tool?** Start from [`AGENTS.md`](AGENTS.md) —
> a machine-oriented map of the public API, snippets, conventions, and gotchas.

## Table of Contents

- [Features](#features)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Documentation](#documentation)
- [API Reference](#api-reference)
- [Platform Setup](#platform-setup)
- [Example App](#example-app)
- [Project Status](#project-status)
- [Support](#support)

## Features

A comprehensive feature set across playback, streaming, subtitles, DRM, casting, PiP, and
notifications. See the [complete feature list](docs/summary/features.md) for the full breakdown.

**Core playback**
- Play / pause / stop / seek with volume, mute, and variable speed (0.25x–4.0x)
- Cross-platform: Android (AndroidX Media3/ExoPlayer) and iOS (AVPlayer)
- Custom HTTP headers for authenticated requests
- `BoxFit` video scaling (contain, cover, fill, …), applied to the native layer at runtime
- Playlist management with sequential/shuffle modes and `MediaRepeatMode` (none/single/all)
- Broadcast-stream state model with typed exceptions and error recovery

**Streaming & subtitles**
- HLS adaptive streaming (Android + iOS) and DASH (Android only — AVPlayer has no DASH
  support), quality switching via each native player's own defaults
- Live HLS/DASH playback (`MediaItem.isLive`); DVR/seeking availability and latency are
  governed entirely by the native player's defaults for the manifest — `HlsConfig`/
  `DashConfig`'s DVR/latency/prefetch fields are not yet wired to native code (see the
  [Live Streaming guide](docs/api-reference/live-streaming.md))
- Subtitles: SRT, WebVTT, ASS/SSA, and embedded tracks with customizable styling
- Manual and automatic quality/resolution selection; multiple audio tracks
- Progressive download/caching; real-time bandwidth estimation

**Advanced**
- Lock-screen / Control Center notifications with media controls; artwork falls back to an
  auto-generated video frame when no `artworkUrl` is provided
- Picture-in-Picture (iOS AVPictureInPictureController, Android `enterPictureInPictureMode`)
- Visibility-aware `ListView` playback (`MediaListPlayer`)
- Casting: Chromecast and AirPlay
- Configurable fullscreen display: `respectSafeArea`, `immersiveLandscape`, and
  per-route orientation control (`preferredOrientations`, live `rotationLocked`,
  `exitOrientations`) on `FullscreenMediaPlayer`

**DRM & security**
- Widevine (Android), FairPlay (iOS), EZDRM, and token-based DRM
- Native certificate pinning for license/CDN endpoints
- Keychain/Keystore-backed secure storage; HTTPS-for-DRM enforcement

## Installation

Add this to your package's `pubspec.yaml`:

```yaml
dependencies:
  zmedia_player:
    git:
      url: https://github.com/zionmedianetwork/zmedia_player.git
```

**Requirements:** Flutter `>=3.19.0` (developed/verified on **3.44.3** / Dart **3.12**),
iOS **13.0+**, Android **minSdk 23**. On iOS the plugin builds with **Swift Package Manager
or CocoaPods** (see [Platform Setup](#ios)).

## Quick Start

### Basic Usage

```dart
import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';

class SimplePlayerPage extends StatefulWidget {
  @override
  State<SimplePlayerPage> createState() => _SimplePlayerPageState();
}

class _SimplePlayerPageState extends State<SimplePlayerPage> {
  late final MediaController _controller;

  @override
  void initState() {
    super.initState();
    _controller = MediaController.create();
    _loadMedia();
  }

  Future<void> _loadMedia() async {
    await _controller.load(const MediaItem(
      id: '1',
      title: 'Sample Video',
      url: 'https://example.com/video.mp4',
      mediaType: MediaType.video,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Media Player')),
      body: AspectRatio(
        aspectRatio: 16 / 9,
        child: MediaPlayerWidget(controller: _controller, showControls: true),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
```

### Playlists

```dart
final playlist = Playlist(
  id: 'my_playlist',
  title: 'My Videos',
  items: [
    const MediaItem(id: '1', title: 'Video 1', url: 'https://example.com/video1.mp4'),
    const MediaItem(id: '2', title: 'Video 2', url: 'https://example.com/video2.mp4'),
  ],
  mode: PlaybackMode.sequential,     // or PlaybackMode.shuffle
  repeatMode: MediaRepeatMode.all,   // none | single | all
);

await _controller.setPlaylist(playlist);
await _controller.skipToNext(); // skipToPrevious() / skipToIndex(i)
```

### Custom Configuration

```dart
final controller = MediaController.create(
  config: const MediaConfig(
    autoPlay: true,
    volume: 0.8,
    boxFit: BoxFit.contain,
    showControls: true,
    allowBackgroundPlayback: true,
    respectSafeArea: true,        // inset video below status bar / notch
    immersiveLandscape: false,    // set true to hide the status bar in landscape
    httpHeaders: {'Authorization': 'Bearer your-token'},
  ),
);
```

### HLS/DASH Adaptive Streaming

Adaptive bitrate switching for an HLS master playlist is the native player's own default
behavior (ExoPlayer/AVPlayer) — no `HlsConfig` is required to enable it. `HlsConfig` and
`DashConfig` are constructible but **not currently wired to native code**; see the
[Live Streaming guide](docs/api-reference/live-streaming.md) for details.

```dart
final controller = MediaController.create();

await controller.load(const MediaItem(
  id: 'hls', title: 'HLS Stream', url: 'https://example.com/playlist.m3u8',
));
```

### Quality, Subtitles & Audio Tracks

> Tracks are reported by the native player **after `play()`** and buffering begins.

```dart
// Quality
await controller.setQualityTrack(controller.qualityTracks.first);
await controller.enableAutoQuality();
controller.player.qualityTracksStream.listen((tracks) => print(tracks.length));

// Subtitles
await controller.setSubtitleTrack(controller.subtitleTracks.first); // pass null to disable
await controller.disableSubtitles();

// Audio
await controller.setAudioTrack(controller.audioTracks.first);
```

### Live Streaming (HLS on Android + iOS; DASH on Android only)

```dart
final live = MediaController.create();
await live.load(const MediaItem(
  id: 'live',
  title: 'Live Event',
  url: 'https://example.com/live.m3u8',
  isLive: true, // metadata only
));
await live.play();
```

DVR/seeking availability, latency, and adaptive bitrate for live streams are governed by
each native player's own defaults for the manifest — see the
[Live Streaming guide](docs/api-reference/live-streaming.md) for what is and is not
currently configurable.

### Media Notifications

```dart
final notifications = NotificationService(const NotificationConfig(
  enabled: true,
  channelId: 'media_playback',
  showPlayPause: true,
  showNext: true,
  showPrevious: true,
));

// Pass the player so lock-screen state stays in sync:
await notifications.initialize(controller.playerId, mediaPlayer: controller.player);

await notifications.show(
  mediaItem: mediaItem,
  state: controller.state,
  playerId: controller.playerId,
);

notifications.actionStream.listen((action) {
  // 'play' | 'pause' | 'next' | 'previous' | 'seekForward' | 'seekBackward'
});
```

When `MediaItem.artworkUrl` is null, the notification artwork is generated from a video frame
(iOS `AVAssetImageGenerator`, Android `MediaMetadataRetriever`).

### Picture-in-Picture

```dart
if (await controller.checkPipAvailability()) {
  await controller.enterPictureInPicture();
}
controller.pipStatusStream.listen((status) => print('PiP active: ${status.isActive}'));
```

### Casting (Chromecast / AirPlay)

```dart
await controller.startCastDiscovery();
controller.player.castDevicesStream.listen((devices) => print('Found ${devices.length}'));
await controller.connectAndLoadMedia(selectedDevice);
```

### DRM-Protected Content

DRM requires HTTPS for both the license and media URLs.

```dart
// Android: Widevine
final widevine = DrmConfig.widevine(
  licenseUrl: 'https://your-license-server.com/widevine',
  headers: {'Authorization': 'Bearer YOUR_TOKEN'},
);

// iOS: FairPlay (certificateUrl is required)
final fairplay = DrmConfig.fairplay(
  licenseUrl: 'https://your-license-server.com/fairplay',
  certificateUrl: 'https://your-server.com/certificate.cer',
);

await controller.load(MediaItem(
  id: 'protected',
  title: 'Protected Content',
  url: 'https://your-cdn.com/video.mpd',
  drmConfig: Platform.isAndroid ? widevine : fairplay,
));

controller.player.drmSessionStream.listen((session) => print('DRM: ${session.state}'));
```

For EZDRM, token-based DRM, offline licenses, and troubleshooting, see the
[DRM Guide](docs/api-reference/drm.md).

## Documentation

- **[Documentation Hub](docs/)** — all guides and references
- **[AGENTS.md](AGENTS.md)** — machine-oriented API map for AI agents and tools

**API Reference** — [`docs/api-reference/`](docs/api-reference/)
- [Getting Started](docs/api-reference/getting-started.md) — install, setup, first player
- [Player API](docs/api-reference/player-api.md) — `MediaController` / `MediaPlayer` methods and getters
- [Models](docs/api-reference/models.md) — `MediaItem`, `Playlist`, `MediaConfig`, DRM, and other types
- [Events & Streams](docs/api-reference/events.md) — every stream and callback
- [Advanced Features](docs/api-reference/advanced-features.md) — PiP, casting, notifications, caching
- [Live Streaming](docs/api-reference/live-streaming.md) — HLS (Android + iOS) and DASH (Android only) live playback
- [DRM Configuration](docs/api-reference/drm.md) — Widevine, FairPlay, EZDRM
- [AirPlay & Chromecast](docs/api-reference/airplay.md) — casting guide

**Implementation** — [`docs/implementation/`](docs/implementation/)
- [Architecture Overview](docs/implementation/README.md)
- [Testing Guide](docs/implementation/testing.md)
- [Security](docs/implementation/security.md)

**Project Summary** — [`docs/summary/`](docs/summary/)
- [Feature List](docs/summary/features.md) · [Test Coverage](docs/summary/test-coverage.md) · [Production Readiness](docs/summary/production-readiness.md)

## API Reference

### MediaController

The reactive `ChangeNotifier` facade — use this for UI. Created with
`MediaController.create({String? playerId, MediaConfig? config})`.

**Key methods:** `load`, `setPlaylist`, `play`, `pause`, `stop`, `seekTo`, `seekForward`,
`seekBackward`, `setVolume`, `toggleMute`, `setSpeed`, `skipToNext`, `skipToPrevious`,
`skipToIndex`, `setQualityTrack`, `enableAutoQuality`, `setSubtitleTrack`, `setAudioTrack`,
`checkPipAvailability`, `enterPictureInPicture`, `startCastDiscovery`, `dispose`.

**Key getters:** `state`, `position`, `duration`, `volume`, `speed`, `isPlaying`, `isPaused`,
`isBuffering`, `hasError`, `bufferedProgress`, `hasNext`, `hasPrevious`, `qualityTracks`,
`subtitleTracks`, `audioTracks`, `player` (the underlying `MediaPlayer`).

See the [Player API](docs/api-reference/player-api.md) for full signatures.

### MediaPlayerWidget

```dart
MediaPlayerWidget(
  controller: _controller,
  showControls: true,
  customControls: MyCustomControls(),   // optional; overrides built-in controls
  placeholder: MyPlaceholderWidget(),
  errorWidget: MyErrorWidget(),
  boxFit: BoxFit.contain,
  allowFullscreen: true,
  onTap: () {},
)
```

### MediaItem

```dart
MediaItem(
  id: 'unique_id',
  title: 'Media Title',
  url: 'https://example.com/media.mp4',
  artist: 'Artist Name',
  artworkUrl: 'https://example.com/artwork.jpg',
  duration: const Duration(minutes: 5),
  mediaType: MediaType.video,
  httpHeaders: const {'Authorization': 'Bearer token'},
  drmConfig: null,
  isLive: false,
)
```

### Playlist

```dart
Playlist(
  id: 'playlist_id',
  title: 'Playlist Title',
  items: [mediaItem1, mediaItem2],
  currentIndex: 0,
  mode: PlaybackMode.sequential,   // or PlaybackMode.shuffle
  repeatMode: MediaRepeatMode.none, // none, single, or all
)
```

## Platform Setup

### Android

Add to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

Picture-in-Picture requires API 26+. Chromecast requires Google Play Services. For
notifications on Android 13+, request the `POST_NOTIFICATIONS` runtime permission.

**Background audio.** Setting `allowBackgroundPlayback: true` makes the plugin hold an
ExoPlayer wake lock (`WAKE_MODE_NETWORK`) so the decoder keeps running while the screen
is off. Android will still reclaim the process unless your app keeps a **foreground
service with a persistent media notification** alive for the duration of playback — the
plugin cannot do this on the host app's behalf. To enable it:

```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
```

Then run a `MediaSessionService` (or an equivalent `Service` started with
`startForeground()` and a media-style notification) from your app while audio is playing.
Without that service, `allowBackgroundPlayback` only prevents the decoder from idling; it
does not by itself guarantee the OS lets playback continue in the background.

### iOS

Minimum iOS **13.0**. The plugin supports **both Swift Package Manager and CocoaPods**.
Flutter uses CocoaPods by default; to build via SPM, enable it once:

```bash
flutter config --enable-swift-package-manager
```

HTTPS media needs no App Transport Security (ATS) changes. If you must serve
plain **HTTP** media, add a domain-scoped exception to
`ios/Runner/Info.plist` rather than disabling ATS globally with
`NSAllowsArbitraryLoads` (see `docs/implementation/security.md` for the
recommended, whitelisted-domain approach) — the plugin does not read, add,
or modify `Info.plist` on your behalf:

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSExceptionDomains</key>
  <dict>
    <key>your-http-media-domain.example.com</key>
    <dict>
      <key>NSExceptionAllowsInsecureHTTPLoads</key>
      <true/>
    </dict>
  </dict>
</dict>
```

For background audio:

```xml
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

FairPlay DRM requires a physical device and a valid Apple FPS certificate.

## Example App

A feature-per-page gallery app demonstrating the public API lives in [`example/`](example/):

```bash
cd example
flutter run
```

It covers simple playback, playlists, adaptive streaming/quality, subtitles, DRM, PiP,
casting, notifications, fullscreen, adaptive and fully custom controls, and error handling.
See the [example README](example/README.md). It has been verified on a physical iPhone.

## Architecture

Clean architecture with a clear split between the Flutter/Dart layer and native platforms:

```
lib/
  zmedia_player.dart   # public API barrel
  src/
    core/              # MediaPlayer, MediaController, MediaConfig, exceptions
    models/            # data models (MediaItem, Playlist, DrmConfig, ...)
    services/          # Notification, Cast, Streaming, Cache, Subtitle, Buffering, ...
    widgets/           # MediaPlayerWidget, controls, menus, components, overlays
    security/          # CertificatePinning, SecureStorage, InputValidation
android/               # Kotlin (AndroidX Media3/ExoPlayer) — per-feature handlers
ios/                   # Swift (AVPlayer) — per-feature handlers (SPM + CocoaPods)
example/               # demo application
```

Dart communicates with native over a single `MethodChannel` (`zmedia_player`), routed per
`playerId` so multiple players can run concurrently. See [`CLAUDE.md`](CLAUDE.md) and
[`docs/implementation/`](docs/implementation/) for the full architecture.

## Contributing

Contributions are welcome. Branch off `main` as `feat/…` or `fix/…`, keep
`flutter analyze` clean and `flutter test` green (currently 588), and open a PR.

## License

MIT License — see [LICENSE](LICENSE).

## Project Status

**Active development — feature-complete, hardening in progress.**

The full feature set (core playback, streaming/subtitles, notifications, PiP, casting, DRM)
is implemented across the Dart and native layers, and the audit-driven P0–P3 remediation has
landed (DRM wiring, per-`playerId` MethodChannel routing, native certificate pinning, secure
storage without plaintext fallback, `bufferedPosition`, leaked-subscription fixes, HTTPS-for-DRM).

### Quality Metrics

- **Tests:** 588 automated tests — run `flutter test` for the current count.
- **Coverage:** strong in the Dart layer (state, models, MethodChannel routing, subtitle
  parsing, retry/backoff, value-model equality). **Native (Kotlin/Swift) code has no automated
  tests yet**; several native paths (DRM decryption, certificate pinning, casting, bandwidth
  metering) warrant **on-device verification**.
- **Verified on-device — iPhone (iOS):** playback, fullscreen, custom controls,
  quality/subtitles, background audio, lock-screen notifications.
- **Verified on-device — Note 9P (Android 11):** Chromecast discovery + load (main-thread
  safe), fullscreen enter/exit via true Hybrid Composition (no surface-release crash), and
  inline controls layout (no overflow).

> Not yet validated as production-ready end-to-end. Verify DRM, casting, and security features
> on real Android and iOS devices before relying on them in production.

## Support

- Documentation: [docs/](docs/)
- Bugs: [GitHub Issues](https://github.com/zionmedianetwork/zmedia_player/issues)
- Questions: [GitHub Discussions](https://github.com/zionmedianetwork/zmedia_player/discussions)

---

Made by the Zion Media Network team.
