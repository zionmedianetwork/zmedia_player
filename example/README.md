# ZMedia Player — Feature Gallery Example

A clean, feature-per-page gallery app demonstrating the public API of the
`zmedia_player` Flutter package.

## Running the App

```bash
cd example
flutter pub get
flutter run
```

To run on a specific device:

```bash
flutter run -d <device-id>
```

---

## Feature Pages

| Page | File | Public API Exercised |
|------|------|----------------------|
| **Simple Playback** | `pages/simple_playback_page.dart` | `MediaController.create`, `initialize`, `load(MediaItem)`, `play`, `pause`, `stop`, `seekForward`, `seekBackward`, `setVolume`, `toggleMute` |
| **Playlist** | `pages/playlist_page.dart` | `setPlaylist(Playlist)`, `skipToNext`, `skipToPrevious`, `skipToIndex`, `RepeatMode`, `PlaybackMode` |
| **Adaptive Streaming & Quality** | `pages/streaming_quality_page.dart` | `MediaPlayer.bandwidthStream`, `qualityTracksStream`, `setQualityTrack(QualityTrack)`, `enableAutoQuality`, `HlsConfig`, `DashConfig` |
| **Subtitles** | `pages/subtitles_page.dart` | `setSubtitleTrack(SubtitleTrack)`, `disableSubtitles`, `subtitleTracksStream`, `selectedSubtitleTrack`, `SubtitleConfig` |
| **DRM** | `pages/drm_page.dart` | `DrmConfig.widevine`, `DrmConfig.fairplay(certificateUrl:)`, `DrmConfig.ezdrm`, `EzdrmConfig.widevine/fairplay`, `CertificatePinningConfig`, `player.drmSessionStream` |
| **Picture-in-Picture** | `pages/pip_page.dart` | `checkPipAvailability`, `enterPictureInPicture`, `exitPictureInPicture`, `pipStatusStream`, `PipConfig`, `PipStatus` |
| **Casting** | `pages/casting_page.dart` | `startCastDiscovery`, `stopCastDiscovery`, `connectToCastDevice`, `connectAndLoadMedia`, `disconnectFromCastDevice`, `castStatusStream`, `castDevicesStream`, `AirPlayButton` |
| **Notifications** | `pages/notifications_page.dart` | `NotificationService`, `NotificationConfig`, `NotificationService.initialize`, `show`, `dismiss`, `actionStream` |
| **Fullscreen** | `pages/fullscreen_page.dart` | `FullscreenMediaPlayer`, `MaterialFullscreenPlayer`, shared `MediaController` across routes |
| **Adaptive Controls** | `pages/adaptive_controls_page.dart` | `AdaptiveMediaControls`, `AdaptiveControlStyle`, `MaterialMediaControls`, `CupertinoMediaControls`, `CustomControlsBase` (subclassed) |
| **Error Handling** | `pages/error_handling_page.dart` | `MediaLoadException`, `NetworkException`, `PlayerState.error`, `PlaybackState.errorMessage`, `player.stateStream` |

---

## Sample / Test Stream URLs

| Type | URL | Used in |
|------|-----|---------|
| MP4 (Big Buck Bunny) | `https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4` | Simple Playback, Fullscreen, Subtitles |
| MP4 (For Bigger *) | `https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4` etc. | Playlist, Adaptive Controls |
| MP4 (Sintel, Tears of Steel, Elephants Dream) | `https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/...` | Playlist |
| HLS (Apple bipbop fMP4) | `https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8` | Streaming Quality, Subtitles |
| DASH (Akamai BBB 30fps) | `https://dash.akamaized.net/akamai/bbb_30fps/bbb_30fps.mpd` | Streaming Quality |

---

## Features That Require a Real Device or Extra Setup

### DRM (Widevine / FairPlay / EZDRM)
- The DRM page shows the API but the placeholder URLs **will fail** — this is
  intentional and honest.
- Replace with your own DRM-protected stream URL + valid license server.
- **Widevine:** Android device (API 21+); L1 requires non-rooted device.
- **FairPlay:** iOS physical device with valid FPS certificate and license server.
  `certificateUrl` is required by `DrmConfig.fairplay` — there is no default.
- `EzdrmConfig` is pre-configured for EZDRM accounts — supply your own credentials.

### Picture-in-Picture
- **Android:** API 26 (Oreo) or higher. The `example/android` `MainActivity.kt`
  must relay `onPictureInPictureModeChanged` to the plugin.
- **iOS:** Physical device with AVPictureInPictureController support.
- `checkPipAvailability()` returns `false` on unsupported devices; the UI
  disables the Enter PiP button accordingly.

### Casting (Chromecast / AirPlay)
- **Chromecast:** Google Play Services + Chromecast device on the same Wi-Fi.
- **AirPlay:** Physical Apple TV or AirPlay-compatible display on the same Wi-Fi.
- `AirPlayButton` only renders on iOS (hides on Android).

### Media Notifications
- **Android 13+:** `POST_NOTIFICATIONS` runtime permission is required.
- **iOS:** User must grant notification permission at runtime.
- **Background audio (iOS):** `UIBackgroundModes` with `audio` must be declared
  in `ios/Runner/Info.plist`.

### Quality Tracks (HLS / DASH)
- Quality tracks are reported **by the native player after buffering starts**.
- Press Play on the Streaming Quality page, wait a few seconds for tracks.
- Works best on a physical device with a network connection.

### Subtitles
- In-stream subtitle tracks require a stream that carries them (the HLS bipbop
  stream is used as it may carry text tracks). Plain MP4 files without sideloaded
  subtitle files will report no tracks.

---

## Project Structure

```
example/
  lib/
    main.dart                         # App entry point (dark Material 3 theme)
    data/
      sample_media.dart               # Reusable MediaItem / Playlist constants
    pages/
      home_page.dart                  # Feature gallery list
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
      error_handling_page.dart
    widgets/
      feature_card.dart               # Card used on home page
      player_scaffold.dart            # Shared scaffold: AppBar + 16:9 player + body
```
