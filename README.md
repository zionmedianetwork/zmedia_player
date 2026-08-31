# ZMedia Player

A comprehensive Flutter media player package with advanced features for video and audio playback across Android and iOS platforms.

[![Version](https://img.shields.io/github/v/release/zionmedianetwork/zmedia_player?label=version&color=blue&sort=semver)](https://github.com/zionmedianetwork/zmedia_player/releases)
[![Tests](https://img.shields.io/badge/tests-1044%20passing-brightgreen.svg)](docs/summary/test-coverage.md)
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
- Playlist management with sequential/shuffle modes and `MediaRepeatMode` (none/single/all),
  extendable in place without restarting the item already playing
- Broadcast-stream state model with typed exceptions and error recovery

**Streaming & subtitles**
- HLS adaptive streaming (Android + iOS) and DASH (Android only — AVPlayer has no DASH
  support), quality switching via each native player's own defaults
- Live HLS/DASH playback (`MediaItem.isLive`); `HlsConfig`/`DashConfig.enableDvr` gates seeking
  (and reports a DVR-window duration) on a live stream, `liveLatency` sets a target offset from
  the live edge (iOS 14+), and `maxBitrate`/`minBitrate`/`enableAdaptiveBitrate` bound track
  selection — beyond that, remaining seek range and buffering behavior are still governed by the
  native player's own defaults for the manifest (see the
  [Live Streaming guide](docs/api-reference/live-streaming.md) for the full field-by-field wiring
  table and platform caveats)
- `MediaItem.streamingFormat` (`StreamingFormat.hls`/`.dash`/`.progressive`) states an item's
  format explicitly, deciding which of `hlsConfig`/`dashConfig` applies; leave it `null` to
  infer from the URL path (`endsWith('.m3u8')`/`endsWith('.mpd')`, query and fragment ignored)
- Live-edge signal: `liveEdgeOffset` (how far behind the live edge the playhead is, sourced from
  `Player.getCurrentLiveOffset()` on Android and `AVPlayerItem.seekableTimeRanges` on iOS),
  `isAtLiveEdge`, and `positionBasis` — so a healthy live edge is distinguishable from a frozen
  playhead (on a sliding window, `position` stays constant during *healthy* playback)
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

// Extending a playlist in place does NOT restart the item already playing --
// re-issue setPlaylist to append items (a sliding window for content that is
// authorised per item) or to change mode/repeatMode mid-playback:
await _controller.setPlaylist(playlist.copyWith(
  items: [...playlist.items, nextEpisode],
));
```

`setPlaylist` and `skipToIndex` carry the current `MediaConfig` snapshot to native on every
call, exactly like `load` does, so per-item streaming settings (`hlsConfig`/`dashConfig`,
`enableDvr`, bitrate bounds, …) are never stale for playlist-driven items. `skipToNext`,
`skipToPrevious` and auto-advance on completion all route through `skipToIndex`.

> `setPlaylist` skips reloading the item at `startIndex` only when it is byte-for-byte the item
> already loaded *and* still in progress. A changed `url`, `httpHeaders`, or `drmConfig` for the
> same `id` is a genuine change and still reloads, as does a stopped/completed/errored player.
> `skipToIndex` always reloads (that is how `MediaRepeatMode.single` repeats an item).
> A changed `MediaConfig` is **not** a reason to reload: a `setPlaylist` carrying a new config
> for an unchanged, in-progress item stores that config (the next real load uses it) but keeps
> playing. Call `updateConfig()` to apply a config change to live playback immediately, or
> `load()` to apply it *and* reload. See
> [Player API](docs/api-reference/player-api.md#extending-a-playlist-in-place).

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
behavior (ExoPlayer/AVPlayer) — no `HlsConfig` is required to enable it. `HlsConfig`/`DashConfig`
are read by native for a specific subset of fields: `enableDvr` (seek gating + live-window
duration reporting), `liveLatency` (target offset from the live edge, iOS 14+), and
`maxBitrate`/`minBitrate`/`enableAdaptiveBitrate` (track-selection bounds — iOS honors only
`maxBitrate`). See the [Live Streaming guide](docs/api-reference/live-streaming.md) for the full
field-by-field wiring table.

Exactly one of the two configs applies to a given item, chosen by
`MediaItem.resolvedStreamingFormat`: the item's explicit `MediaItem.streamingFormat` when set,
otherwise inferred from the URL's *path* (`endsWith('.m3u8')` → HLS, `endsWith('.mpd')` → DASH,
anything else → progressive; query string and fragment ignored, malformed URLs never throw).
They are never cross-applied — an app that serves HLS to one platform and DASH to the other
must set **both** `hlsConfig` and `dashConfig`, and in debug builds a live item that resolves to
a format with no config logs a one-time warning explaining that `enableDvr` fell back to
`false`. Set `streamingFormat` explicitly when the URL is not self-describing:

```dart
await controller.load(const MediaItem(
  id: 'live', title: 'Live Stream',
  url: 'https://cdn.example.com/live/eu/primary?token=abc', // no .m3u8/.mpd in the path
  isLive: true,
  streamingFormat: StreamingFormat.dash,
));
```

```dart
final controller = MediaController.create();

await controller.load(const MediaItem(
  id: 'hls', title: 'HLS Stream', url: 'https://example.com/playlist.m3u8',
));
```

For a live stream, DVR seeking must be opted into explicitly — without it, `seekTo` throws:

```dart
final controller = MediaController.create(
  config: const MediaConfig(hlsConfig: HlsConfig(enableDvr: true)),
);

await controller.load(const MediaItem(
  id: 'live', title: 'Live Stream', url: 'https://example.com/live.m3u8', isLive: true,
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

**Never build a stall detector on `position` for a live stream.** When
`controller.positionBasis == PositionBasis.liveWindow` (always on Android for a live item; on
iOS whenever `enableDvr: true`), the window start slides forward with the playhead, so a
*constant* `position` is exactly what healthy playback looks like. Use the native-sourced
live-edge signal instead:

```dart
final Duration? behind = controller.liveEdgeOffset; // null for VOD
final bool atEdge = controller.isAtLiveEdge;        // within 15s of the edge

// A frozen playhead in a sliding window makes `liveEdgeOffset` grow without bound;
// a healthy edge keeps it bounded, whatever `position` is doing.
if (controller.positionBasis == PositionBasis.liveWindow && !atEdge) {
  // ... escalate
}
```

See [Stall watchdog for live streams](docs/api-reference/live-streaming.md#stall-watchdog-for-live-streams)
for a complete, copy-pasteable implementation covering VOD, live-without-DVR and live-with-DVR.

### Media Notifications

```dart
final notifications = NotificationService(const NotificationConfig(
  enabled: true,
  channelId: 'media_playback',
  showPlayPause: true,
  showNext: true,
  showPrevious: true,
  // Opt-in (both default to false). A seek control is rendered only when the
  // flag is true AND the item is seekable (not a live stream without DVR).
  showSeekForward: true,
  showSeekBackward: true,
  seekInterval: 10, // display-only: labels the control, does not perform the seek
));

// Pass the player so lock-screen state stays in sync:
await notifications.initialize(controller.playerId, mediaPlayer: controller.player);

await notifications.show(
  mediaItem: mediaItem,
  state: controller.state,
  playerId: controller.playerId,
);

notifications.actionEventStream.listen((event) {
  // NotificationActions: 'play' | 'pause' | 'next' | 'previous' | 'stop'
  //                    | 'seekForward' | 'seekBackward' | 'seekTo'
  // NotificationService renders and forwards only — your app performs the call.
  switch (event.action) {
    case NotificationActions.seekForward:
      controller.seekForward(const Duration(seconds: 10));
      break;
    case NotificationActions.seekBackward:
      controller.seekBackward(const Duration(seconds: 10));
      break;
  }
});
```

When `MediaItem.artworkUrl` is null, the notification artwork is generated from a video frame
(iOS `AVAssetImageGenerator`, Android `MediaMetadataRetriever`).

`showSeekForward` / `showSeekBackward` follow one contract on both platforms: **the control is
offered if and only if the flag is `true` and the current item is seekable**
(`MediaPlayer.isSeekable`). Android adds a `NotificationCompat.Action` and advertises
`ACTION_FAST_FORWARD`/`ACTION_REWIND`; iOS enables
`MPRemoteCommandCenter.skipForwardCommand`/`.skipBackwardCommand`. `seekInterval` only labels
the control (Android button text, iOS `preferredIntervals`) — apply the matching `Duration`
yourself in the `actionEventStream` handler. See
[Advanced Features](docs/api-reference/advanced-features.md#media-notifications).

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

**Operation ordering:** every method above is submitted to a per-controller FIFO queue and
runs one at a time, in submission order. Calling while another operation is in flight queues
the new call — it is never rejected — so ordinary interleaved input (`pause()` immediately
followed by `play()`, muting a player that is still loading) always takes effect, in order.
The returned `Future` completes once that call has actually run. A wedged native call fails
with `TimeoutException` after 10 s so the queue always advances, and an operation still
queued when `dispose()` runs is dropped as a no-op. See
[Operation ordering](docs/api-reference/player-api.md#operation-ordering-serialization-queue).

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
  enableBuiltInGestures: true,          // default; false = host owns all gestures

  aspectRatio: 16 / 9,                  // optional; overrides the video's natural ratio
  expandToFill: false,                  // true = fill the parent instead of sizing to a ratio
  onTap: () {},
)
```

#### Gesture callbacks

Every forwarded gesture comes in two flavours: a bare `VoidCallback` and a
position-carrying counterpart.

| Bare | Position-carrying | Details type |
|---|---|---|
| `onTap` | `onTapDown` | `TapDownDetails` |
| `onDoubleTap` | `onDoubleTapDown` | `TapDownDetails` |
| `onLongPress` | `onLongPressStart` | `LongPressStartDetails` |

Rules (identical for all three gestures):

1. Both variants may be supplied and **both fire**, in `GestureDetector`'s own order —
   the position-carrying one first, the bare one second.
2. Supplying **either** variant means the host owns that gesture, so the built-in
   default is suppressed. The built-in defaults are: single tap toggles the controls
   overlay, double tap toggles play/pause. Long press has no built-in default.
3. `details.localPosition` is relative to the **player widget's own box** (after any
   `aspectRatio` sizing) — divide by the widget's width, not the screen width.
   `details.globalPosition` stays screen-relative.
4. A callback fires only if no widget in the controls overlay claimed the gesture first
   (see *Gesture ownership* below). Tap and double tap behave identically whether the
   overlay is visible or hidden, `localPosition` included; long press is absorbed by the
   visible built-in overlay.

Direction-aware double-tap seek — left half rewinds, right half fast-forwards:

```dart
LayoutBuilder(
  builder: (context, constraints) => MediaPlayerWidget(
    controller: _controller,
    onDoubleTapDown: (details) {
      final isLeftHalf = details.localPosition.dx < constraints.maxWidth / 2;
      final target = isLeftHalf
          ? _controller.position - const Duration(seconds: 10)
          : _controller.position + const Duration(seconds: 10);
      _controller.seekTo(target < Duration.zero ? Duration.zero : target);
    },
  ),
)
```

#### Gesture ownership

**A gesture is handled by the topmost widget in the controls overlay that claims it, and only
reaches the package's built-in tap detector when no overlay widget claimed it — regardless of
whether the overlay is currently visible.**

The controls overlay is always mounted and always hit-testable, and the package's own
full-surface tap detector is stacked *below* it. So a gesture zone you declare inside
`customControls` (e.g. left/right double-tap seek zones) keeps working when the overlay
auto-hides, instead of being taken over by the package.

Consequences when you supply `customControls`:

- The package does **not** fade or unmount your overlay. Drive visibility yourself from
  `controller.controlsVisible` (or extend `CustomControlsBase`, which hands you
  `ControlsState.isVisible` and a ready-made fade animation).
- Zero opacity does not stop hit testing. Wrap chrome that must not be tappable while hidden in
  `IgnorePointer(ignoring: !state.isVisible)`, and gate any full-bleed scrim on visibility too —
  a `Container` with a `color` is opaque to hit tests and would swallow the tap meant to reveal
  the controls. Returning `const SizedBox.shrink()` while hidden restores the pre-0.3.1
  "unmounted" behaviour entirely.
- `enableBuiltInGestures: false` removes the package detector altogether: none of `onTap`,
  `onTapDown`, `onDoubleTap`, `onDoubleTapDown`, `onLongPress` or `onLongPressStart` are then
  invoked by the package, and any pointer your overlay does not claim reaches the native
  platform view directly.

The built-in controls are unaffected: while hidden they stay non-hit-testable, invisible, and
out of the semantics tree. While *visible* they forward background taps and double taps —
position included — back to your `onTap` / `onTapDown` / `onDoubleTap` / `onDoubleTapDown`
via `MediaControls.onBackgroundTap` / `onBackgroundTapDown` / `onBackgroundDoubleTap` /
`onBackgroundDoubleTapDown`, so those four fire identically in both states. Long press is not
forwarded, so it fires only while the overlay is hidden.

**Sizing: `aspectRatio` / `expandToFill`.** By default (`expandToFill: false`) the widget sizes
itself from `aspectRatio`, falling back to the video's natural ratio (16:9 when unknown), so it
always has an intrinsic size. `expandToFill: true` skips that and fills whatever space the
parent gives it — which means the parent **must** hand it a definite size: constraints that are
bounded with a non-zero minimum in both axes, i.e. `Positioned.fill` inside a `Stack`,
`SizedBox.expand`, an `Expanded`, or a `Scaffold` body.

If the constraints could let the widget collapse instead — loose/zero-minimum (a
**non-positioned `Stack` child** gets `BoxConstraints.loose`) or unbounded in an axis (an
unbounded `Column`/`ListView` child) — the widget falls back to a definite size derived from the
video aspect ratio rather than laying out at `Size(0, 0)`. It fills the bounded axis and derives
the other from the ratio; when both axes are unbounded it uses the screen width. In debug builds
the fallback also reports a `FlutterError` explaining the cause and the remedy (it never throws,
is compiled out of release builds, and is reported at most once per constraint condition). An
explicit `aspectRatio` always wins over `expandToFill`.

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
`playerId` so multiple players can run concurrently. Every call that makes native load a media
item — `load` (`{playerId, mediaItem, config}`), `setPlaylist`
(`{playerId, playlist, startIndex, config}`) and `skipToIndex` (`{playerId, index, config}`) —
carries the current `MediaConfig` snapshot under a `config` key, so a rebuilt config takes
effect on the next load without a separate `updateConfig()` call; the key is optional on the
native side, so an older native build safely ignores it. See [`CLAUDE.md`](CLAUDE.md),
[`AGENTS.md`](AGENTS.md) and [`docs/implementation/`](docs/implementation/) for the full
architecture.

## Contributing

Contributions are welcome. Branch off `main` as `feat/…` or `fix/…`, keep
`flutter analyze` clean and `flutter test` green (currently 1044), and open a PR.

## License

MIT License — see [LICENSE](LICENSE).

## Project Status

**Active development — feature-complete, hardening in progress.**

The full feature set (core playback, streaming/subtitles, notifications, PiP, casting, DRM)
is implemented across the Dart and native layers, and the audit-driven P0–P3 remediation has
landed (DRM wiring, per-`playerId` MethodChannel routing, native certificate pinning, secure
storage without plaintext fallback, `bufferedPosition`, leaked-subscription fixes, HTTPS-for-DRM).

### Quality Metrics

- **Tests:** 1044 automated tests — run `flutter test` for the current count.
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
