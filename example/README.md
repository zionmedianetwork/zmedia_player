# ZMedia Player — Feature Gallery Example

A clean, **feature-per-page gallery** app that demonstrates the public API of the
`zmedia_player` Flutter package. Each page is a focused, self-contained example of
one capability — load it, read it, copy from it.

The home screen lists every feature; tap a card to open its demo page. Pages are
built against the **real public API** only (everything exported from
`package:zmedia_player/zmedia_player.dart`), initialize/dispose their controllers
correctly, and surface loading/error states.

> **Layout:** pages set `MediaConfig(respectSafeArea: true)` so the video is inset
> below the status bar/notch, and landscape fills the screen. Clients that want a
> fully immersive landscape can pass `immersiveLandscape: true` to hide the system
> status bar (it is restored on return to portrait / on dispose).

> This example has been exercised on a **physical iPhone (iOS 26)** — playback,
> fullscreen, custom controls, adaptive streaming/quality, subtitles, background
> audio, and lock‑screen notification controls were all verified on-device. The
> features that still need your own infrastructure or hardware (DRM, casting) are
> called out below.

---

## Requirements

- **Flutter** ≥ 3.19, **Dart** ≥ 3.0 (developed/verified on Flutter 3.44.3 / Dart 3.12)
- **iOS** 13.0+ (a physical device is required for DRM/FairPlay, PiP, casting, and
  to hear background audio over the silent switch)
- **Android** API 21+ (API 26+ for Picture-in-Picture)

The example app depends on the package via a local `path:` reference (`../`), so no
publishing step is needed.

### iOS dependency manager

The `zmedia_player` plugin supports **both Swift Package Manager and CocoaPods** for
iOS. By default Flutter uses CocoaPods; to build via SPM, enable it once with
`flutter config --enable-swift-package-manager` (Flutter then integrates the plugin's
`ios/zmedia_player/Package.swift`). Either path builds the same Swift sources.

## Running the app

```bash
cd example
flutter pub get
flutter run                 # pick a device when prompted
flutter run -d <device-id>  # or target a specific device (flutter devices)
```

First iOS build runs CocoaPods and a full Xcode build, so it can take a few
minutes. For a physical iPhone you must configure code signing once in Xcode
(open `example/ios/Runner.xcworkspace` → Runner target → Signing & Capabilities →
select your Team).

---

## Feature pages

| Page | File | Public API exercised |
|------|------|----------------------|
| **Simple Playback** | `pages/simple_playback_page.dart` | `MediaController.create` · `initialize` · `load(MediaItem)` · `play`/`pause`/`stop` · `seekForward`/`seekBackward` · `setVolume` · `toggleMute` |
| **Playlist** | `pages/playlist_page.dart` | `setPlaylist(Playlist)` · `skipToNext`/`skipToPrevious`/`skipToIndex` · `MediaRepeatMode` (none/all/single) · `PlaybackMode` (sequential/shuffle) · auto-advance on completion |
| **Adaptive Streaming & Quality** | `pages/streaming_quality_page.dart` | `player.qualityTracksStream` · `setQualityTrack` · `enableAutoQuality` · `player.bandwidthStream` · HLS & DASH sources |
| **Subtitles** | `pages/subtitles_page.dart` | `setSubtitleTrack` · `disableSubtitles` · `player.subtitleTracksStream` · `selectedSubtitleTrack` · `SubtitleConfig` |
| **DRM (Widevine / FairPlay / EZDRM)** | `pages/drm_page.dart` | `DrmConfig.widevine` · `DrmConfig.fairplay(certificateUrl:)` · `DrmConfig.ezdrm` · `EzdrmConfig` · `CertificatePinningConfig` · `player.drmSessionStream` |
| **Picture-in-Picture** | `pages/pip_page.dart` | `checkPipAvailability` · `enterPictureInPicture`/`exitPictureInPicture` · `pipStatusStream` · `PipConfig` |
| **Casting (Chromecast / AirPlay)** | `pages/casting_page.dart` | `startCastDiscovery`/`stopCastDiscovery` · `connectToCastDevice`/`connectAndLoadMedia`/`disconnectFromCastDevice` · `castStatusStream` · `player.castDevicesStream` · `AirPlayButton` |
| **Media Notifications** | `pages/notifications_page.dart` | `NotificationService` · `NotificationConfig` · `initialize(mediaPlayer:)` · `updateConfig` (runtime config changes — the action checkboxes) · `show`/`dismiss` · `actionStream` (lock-screen / Control Center controls) |
| **Fullscreen Playback** | `pages/fullscreen_page.dart` | `FullscreenMediaPlayer` · `MaterialFullscreenPlayer` · orientation control (`preferredOrientations` / live `rotationLocked` / `exitOrientations`) · a single `MediaController` shared across routes |
| **Adaptive Controls** | `pages/adaptive_controls_page.dart` | `AdaptiveMediaControls` (Material vs Cupertino) · `MaterialMediaControls` · `CupertinoMediaControls` · a minimal `CustomControlsBase` subclass |
| **Fully Custom Controls & Overlay** | `pages/custom_controls_page.dart` | `CustomControlsBase` → `buildControls(context, state)` with `ControlsState`; a hand-built branded overlay (custom seek bar, gestures, speed/quality pickers) injected via `MediaPlayerWidget.customControls`. Also demonstrates gesture ownership: double-tap seek zones that stay live while the overlay is hidden, chrome gated with `IgnorePointer(ignoring: !state.isVisible)`, and the `enableBuiltInGestures` opt-out |
| **Error Handling** | `pages/error_handling_page.dart` | `MediaPlayerException` hierarchy · `PlayerState.error` · `PlaybackState.errorMessage` · `player.stateStream` |
| **Network Status** | `pages/network_status_page.dart` | `MediaPlayer.networkStatus`/`.networkStatusStream`/`.networkChangeStream` · `NetworkStatus`/`NetworkQuality`/`ConnectionType`. Manual verification harness — no media is loaded; toggle airplane mode / switch Wi-Fi↔cellular to generate events. Documents that `downloadSpeed` is a system link *hint* on Android and a fixed per-transport constant on iOS, not a throughput measurement on either platform |
| **Wired Config Verification** | `pages/wired_config_verification_page.dart` | On-device harness for `HlsConfig.enableDvr`/`.liveLatency`, `NotificationConfig.customActions`/`.priority`/`.dismissible` (Android only), and `PipConfig.actions` (Android only). Its Live Latency section documents that `liveLatency` is a *maintained* target on Android (defeated only by a manifest time-anchor defect, issue #110) but a **join-time-only** setting on iOS 14+ (`automaticallyPreservesTimeOffsetFromLive = false` — no restore after a rebuffer) |
| **Media Feed (pooled controllers)** | `pages/media_feed_pool_page.dart`, `pages/feed_page.dart` | `MediaFeed` pooled-controller playback for a scrolling feed; per-item `_NetworkStatusLine` readout of `connectionType`/`quality`/`isMetered` for the most recently active controller |

---

## Sample media

All sample sources are defined in `lib/data/sample_media.dart`. They were chosen to
be **reachable and to carry an audio track** (so the audio/notification demos are
meaningful):

| Source | URL | Notes |
|--------|-----|-------|
| Big Buck Bunny (primary) | `https://www.w3schools.com/html/mov_bbb.mp4` | Direct HTTP 200, has audio — reliable first-load |
| Big Buck Bunny (full · 10 min) | `https://archive.org/download/BigBuckBunny_124/Content/big_buck_bunny_720p_surround.mp4` | Long clip for seek/playlist/notification tests; served via a 302 redirect so the first load can be slightly slower |
| Bee / Butterfly | `https://flutter.github.io/assets-for-api-docs/assets/videos/{bee,butterfly}.mp4` | Short Flutter test clips, both have audio |
| HLS (Apple bipbop, fMP4) | `https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8` | Multi-bitrate adaptive stream for the Quality/Subtitles pages |
| DASH (Akamai BBB 30fps) | `https://dash.akamaized.net/akamai/bbb_30fps/bbb_30fps.mpd` | Multi-bitrate DASH for the Quality page |

> The previously-used Google `commondatastorage.googleapis.com/gtv-videos-bucket`
> samples now return **HTTP 403** and have been removed. Some popular
> `test-videos.co.uk` clips are **video-only** (no audio) and are intentionally not
> used for the playback demos.

---

## Features that need a real device or extra setup

### DRM (Widevine / FairPlay / EZDRM)
- The DRM page demonstrates how to **construct** the config; it does not ship a live
  protected stream. Supply your own protected URL **and** license server.
- **Widevine:** Android device (API 21+); L1 needs a non-rooted device.
- **FairPlay:** iOS **physical device** with a valid FPS certificate + license
  server. `certificateUrl` is **required** by `DrmConfig.fairplay` (no default).
- `CertificatePinningConfig` pins are `hex(SHA-256(SPKI))`; pinning is enforced
  natively on the DRM license requests.

### Picture-in-Picture
- **iOS:** physical device (AVPictureInPictureController).
- **Android:** API 26+. The example's `android/.../MainActivity.kt` relays
  `onPictureInPictureModeChanged` to the plugin (required for PiP state).
- `checkPipAvailability()` returns `false` on unsupported devices; the button
  disables accordingly.

### Casting (Chromecast / AirPlay)
- **Chromecast:** Google Play Services + a Chromecast on the same Wi-Fi.
- **AirPlay:** an Apple TV / AirPlay display on the same Wi-Fi. `AirPlayButton`
  renders on iOS only.

### Media notifications (lock screen / Control Center)
- **iOS:** Now Playing info + remote commands. Background audio requires
  `UIBackgroundModes: audio` in `ios/Runner/Info.plist` (already configured here),
  and the app sets the audio session to `.playback` on play so audio is audible
  with the **silent switch on** and continues in the background.
- **Android 13+:** `POST_NOTIFICATIONS` runtime permission.
- **Artwork:** when a `MediaItem` has no `artworkUrl`, the notification artwork falls
  back to an **auto-generated frame** grabbed from the video (iOS
  `AVAssetImageGenerator`, Android `MediaMetadataRetriever`).
- The demo loads a short **playlist** so all lock-screen controls are exercisable:
  play/pause, next/previous, and ±10s skip.

### Quality tracks (HLS / DASH)
- Tracks are reported by the native player **after you press Play** and buffering
  starts — they won't appear before playback begins.

### Subtitles
- In-stream subtitle tracks require a stream that carries them (use the HLS source).
  Plain MP4s report no tracks; the package does not sideload external subtitle files
  from Dart alone.

---

## Project structure

```
example/
  lib/
    main.dart                       # App entry (dark Material 3, orientation reset on launch)
    data/
      sample_media.dart             # Reusable MediaItem / Playlist sample constants
    pages/
      home_page.dart                # Feature gallery (cards → pages)
      simple_playback_page.dart
      playlist_page.dart
      streaming_quality_page.dart
      subtitles_page.dart
      drm_page.dart
      pip_page.dart
      casting_page.dart
      notifications_page.dart
      fullscreen_page.dart
      adaptive_controls_page.dart
      custom_controls_page.dart     # Flagship: fully bespoke overlay via CustomControlsBase
      error_handling_page.dart
    widgets/
      feature_card.dart             # Card used on the home screen
      player_scaffold.dart          # Shared scaffold: AppBar + 16:9 player + scrollable body
  android/                          # Runner (PiP relay + permissions)
  ios/                              # Runner (background-audio mode, signing)
```

---

## See also

- Package API and guides: the repository [`README.md`](../README.md) and
  [`docs/`](../docs).
- Building custom controls: start from the **Fully Custom Controls & Overlay** page,
  which doubles as documentation for extending `CustomControlsBase`.
