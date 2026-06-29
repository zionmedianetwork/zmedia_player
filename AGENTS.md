# AGENTS.md — ZMedia Player

Machine-oriented guide for AI agents and tools working **with** the `zmedia_player`
package (consuming its API) or **on** it (changing its source). Humans welcome too.
For the architecture narrative and contributor workflow, see [`CLAUDE.md`](CLAUDE.md).

---

## What this package is (in 5 lines)

- A Flutter **media player package** for video + audio on **Android (ExoPlayer)** and **iOS (AVPlayer)**.
- Public API is a **single barrel**: everything in [`lib/zmedia_player.dart`](lib/zmedia_player.dart) is public; anything else is internal.
- Two entry points: **`MediaController`** (reactive `ChangeNotifier` facade — use this for UI) and **`MediaPlayer`** (lower-level, stream-first, singleton per `playerId`).
- Dart talks to native over a single `MethodChannel` named `zmedia_player`, routed per `playerId`.
- Advanced features: HLS/DASH adaptive streaming, DRM (Widevine/FairPlay/EZDRM), subtitles, PiP, casting (Chromecast/AirPlay), lock-screen notifications, certificate pinning.

**Versions:** package `0.2.2` · Flutter SDK `>=3.19.0` (developed/verified on **3.44.3** / Dart **3.12**) · iOS **13.0+** · Android **minSdk 21**. iOS builds with **Swift Package Manager or CocoaPods**.

---

## Minimal working example

```dart
import 'package:zmedia_player/zmedia_player.dart';

final controller = MediaController.create(
  config: const MediaConfig(autoPlay: true),
);

await controller.load(const MediaItem(
  id: '1',
  title: 'Sample',
  url: 'https://example.com/video.mp4',
));

// In build():
MediaPlayerWidget(controller: controller, showControls: true);

// Always:
@override void dispose() { controller.dispose(); super.dispose(); }
```

`MediaController.create({String? playerId, MediaConfig? config})` makes a controller
(and its underlying `MediaPlayer`). It calls `initialize()` for you. One controller per
player; dispose it in `State.dispose()`.

---

## Public API map

Source of truth: [`lib/zmedia_player.dart`](lib/zmedia_player.dart). Each export below maps to one purpose.

### Core (`lib/src/core/`)
| Export | Purpose |
|---|---|
| `MediaController` | Reactive `ChangeNotifier` facade over `MediaPlayer`; use for UI. `create()` factory. |
| `MediaPlayer` | Lower-level engine; singleton per `playerId`; exposes all streams. |
| `MediaConfig` | Player configuration (autoPlay, boxFit, DRM, streaming, `respectSafeArea`, `immersiveLandscape`, …). |
| `CacheConfig`, `BufferConfig` | Cache + buffering sub-configs used by `MediaConfig`. |
| `CrashReporter` | Optional crash-reporting hook (`MediaPlayer.enableCrashReporting`). |
| `MediaPlayerException` (sealed) + subclasses | Typed errors: `MediaLoadException`, `NetworkException`, `DrmException`, `PlaybackException`, `InvalidStateException`, `PlayerDisposedException`, `ConfigurationException`, `PlatformOperationException`, `OperationBusyException`. |

### Models (`lib/src/models/`)
| Export | Purpose |
|---|---|
| `MediaItem` / `MediaType` | A playable item (url, title, artwork, drmConfig, headers) / `video`\|`audio`. |
| `PlaybackState` / `PlayerState` | State snapshot (position, duration, `bufferedPosition`, speed, volume, error) / `idle,buffering,ready,playing,paused,completed,error`. |
| `Playlist` / `PlaybackMode` / `MediaRepeatMode` | Item collection + shuffle order / `sequential`\|`shuffle` / `none`\|`single`\|`all`. **Note: the enum is `MediaRepeatMode`, not `RepeatMode`.** |
| `SubtitleTrack` / `SubtitleFormat` / `SubtitleConfig` / `SubtitleAlignment` | Subtitle track, format (`srt,webvtt,ass,ssa,ttml`), styling, alignment. |
| `QualityTrack` / `AudioTrack` | Selectable video-quality / audio-track descriptors. |
| `StreamingConfig` / `BitrateSelectionStrategy` / `HlsConfig` / `DashConfig` | Adaptive-streaming config + HLS/DASH (live, DVR, latency, prefetch). |
| `DrmConfig` / `DrmScheme` / `EzdrmConfig` / `DrmSession` | DRM config + factories (`.widevine`, `.fairplay`, `.ezdrm`, `.token`); session state. |
| `BufferingConfig` / `BufferHealth` / `BufferStatus` / `BufferStatistics` | Adaptive buffering config + health/stats. |
| `NetworkStatus` / `NetworkQuality` / `ConnectionType` / `NetworkChangeEvent` | Network monitoring model. |
| `QoEMetrics` / `PerformanceMetrics` / `EngagementMetrics` / `PlaybackEndReason` / `BufferEventType` | Analytics/QoE models. |
| `NotificationConfig` / `NotificationAction` / `NotificationPriority` | Lock-screen / Control Center notification config. |
| `PipConfig` / `PipAction` / `PipState` / `PipStatus` | Picture-in-Picture config + state. |
| `CastDevice` / `CastDeviceType` / `CastState` / `CastStatus` / `CastConfig` | Casting (Chromecast/AirPlay/DLNA) model. |

### Services (`lib/src/services/`)
| Export | Purpose |
|---|---|
| `NotificationService` | Lock-screen/Control Center media controls. `initialize(playerId, mediaPlayer:)` then `show()`/`dismiss()`; `actionStream`. |
| `CastService` | Cast device discovery + connection. |
| `StreamingService` | Bandwidth estimation + quality recommendation. |
| `CacheService` | Progressive download + cache management. |
| `SubtitleService` | Parse SRT/WebVTT/ASS/SSA into tracks. |
| `BufferingService` | Buffer-health monitoring (`bufferHealthStream`). |
| `NetworkResilienceService` | Network status + reconnection/retry. |
| `AnalyticsService` | QoE metrics collection. |

### Widgets (`lib/src/widgets/`)
| Export | Purpose |
|---|---|
| `MediaPlayerWidget` | The video surface + controls overlay. Primary widget. |
| `MediaControls`, `MaterialMediaControls`, `CupertinoMediaControls`, `AdaptiveMediaControls` | Built-in control overlays; `Adaptive` picks Material/Cupertino per platform. |
| `CustomControlsBase` / `ControlsState` | Base class to build a fully custom overlay; implement `buildControls(context, ControlsState)`. |
| `FullscreenMediaPlayer`, `MaterialFullscreenPlayer`, `CupertinoFullscreenPlayer` | Fullscreen route wrappers. |
| `SubtitleView` | Renders the active subtitle cue. |
| `SettingsMenu`, `QualityMenu`, `AudioTrackMenu`, `SubtitleMenu`, `SubtitleStylingMenu`, `SpeedMenu` | Bottom-sheet settings + submenus. |
| `QualityBadge`, `TimeDisplay`, `ControlButton`, `SeekBar`, `VolumeSlider`, `LiveBadge`, `BufferHealthBadge` | Reusable control components. |
| `BufferingIndicator`, `NetworkQualityIndicator`, `ErrorOverlay`, `FeedbackOverlay`, `VolumeChangeOverlay`, `SeekFeedbackOverlay`, `PlaybackFeedbackOverlay`, `ToastNotification` | Status/feedback overlays. |
| `MediaListPlayer` | Visibility-aware player for `ListView` (auto play/pause). |
| `AirPlayButton` | Native iOS AirPlay route picker (iOS only). |

### Security (`lib/src/security/`)
| Export | Purpose |
|---|---|
| `CertificatePinningConfig` | TLS pinning for license/CDN endpoints; pins are `hex(SHA-256(SPKI))`; enforced natively. |
| `SecureStorage` / `PlatformSecureStorage` / `SecureStorageException` | Keychain/Keystore-backed secure storage (no plaintext fallback). |
| `InputValidator` | URL/config validation; enforces HTTPS-for-DRM. |

---

## Streams to listen to

All are broadcast streams on `MediaPlayer` (reach via `controller.player`). `MediaController`
also re-emits via `ChangeNotifier`, so for UI you can just `AnimatedBuilder(animation: controller)`.

| Stream | Emits |
|---|---|
| `stateStream` | `PlaybackState` (full snapshot) |
| `positionStream` / `durationStream` | `Duration` (throttled position / total) |
| `volumeStream` / `speedStream` | `double` |
| `qualityTracksStream` / `audioTracksStream` / `subtitleTracksStream` | `List<…Track>` (populated **after Play**) |
| `bandwidthStream` | `int` (bits/sec) |
| `bufferHealthStream` | `BufferHealth` |
| `drmSessionStream` | `DrmSession` |
| `pipStatusStream` / `castStatusStream` / `castDevicesStream` | `PipStatus` / `CastStatus` / `List<CastDevice>` |
| `notificationActionStream` | `String` (action id) |

Native→Dart events (handled in `MediaPlayer._handleMethodCall`, dispatched by `playerId`):
`onPlaybackStateChanged`, `onPositionChanged`, `onDurationChanged`, `onVolumeChanged`,
`onSpeedChanged`, `onQualityTracksChanged`, `onSubtitleTracksChanged`, `onAudioTracksChanged`,
`onBandwidthUpdate`, `onBufferHealthUpdate`, `onDrmSessionUpdate`, `onNotificationAction`,
`onPipStatusChanged`, `onCastStatusChanged`, `onCastDevicesChanged`, `onError`.

---

## Feature snippets

### Playlist
```dart
await controller.setPlaylist(Playlist(
  id: 'p', title: 'My list', items: [item1, item2],
  mode: PlaybackMode.sequential,        // or .shuffle
  repeatMode: MediaRepeatMode.all,      // none | single | all
));
await controller.skipToNext();          // / skipToPrevious / skipToIndex
```

### Quality / subtitles / audio (after Play)
```dart
await controller.setQualityTrack(controller.qualityTracks.first);
await controller.enableAutoQuality();
await controller.setSubtitleTrack(controller.subtitleTracks.first); // null to disable
await controller.setAudioTrack(controller.audioTracks.first);
```

### DRM (HTTPS required)
```dart
final drm = Platform.isAndroid
  ? DrmConfig.widevine(licenseUrl: 'https://ls/widevine', headers: {'Authorization': 'Bearer …'})
  : DrmConfig.fairplay(licenseUrl: 'https://ls/fairplay', certificateUrl: 'https://srv/cert.cer');
await controller.load(MediaItem(id: 'p', title: 'Protected', url: 'https://cdn/v.mpd', drmConfig: drm));
controller.player.drmSessionStream.listen((s) => print(s.state));
```

### Notifications (lock screen / Control Center)
```dart
final notifications = NotificationService(const NotificationConfig(enabled: true));
await notifications.initialize(controller.playerId, mediaPlayer: controller.player); // pass the player!
await notifications.show(mediaItem: item, state: controller.state, playerId: controller.playerId);
notifications.actionStream.listen((a) { /* play|pause|next|previous|seekForward|seekBackward */ });
```
If `MediaItem.artworkUrl` is null, the artwork is auto-generated from a **video frame**.

### Fullscreen / landscape display
```dart
const MediaConfig(
  respectSafeArea: true,     // inset video below status bar / notch
  immersiveLandscape: true,  // hide system status bar in landscape (restored on portrait)
);
```

### PiP & casting
```dart
if (await controller.checkPipAvailability()) await controller.enterPictureInPicture();
await controller.startCastDiscovery();
await controller.connectAndLoadMedia(device);
```

---

## Conventions & gotchas

- **One barrel.** Add a new public type? Export it from `lib/zmedia_player.dart` or it's internal.
- **Always `dispose()`** controllers/services in `State.dispose()` — they hold native resources + timers.
- **`MediaRepeatMode`**, not `RepeatMode` (renamed; breaking).
- **DRM requires HTTPS** for both license and media URLs (`InputValidator` enforces it).
- **Quality/subtitle/audio tracks appear only after `play()`** — native reports them once buffering starts.
- **Notifications need the player**: `initialize(playerId, mediaPlayer: …)` or lock-screen state won't sync.
- **MethodChannel calls are async** — always `await`.
- **Multiple players**: use distinct `playerId`s (e.g. in a `ListView` with `MediaListPlayer`); events route by `playerId`.
- **iOS audio + silent switch**: the plugin sets `AVAudioSession` to `.playback` on `play()`; background audio needs `UIBackgroundModes: audio` in the host `Info.plist`.
- **`boxFit`** maps to native video gravity: `contain`→aspect-fit, `cover`→aspect-fill, `fill`→stretch. Changing it at runtime propagates to the native view.
- **Color formats** in `SubtitleConfig` are ARGB ints (e.g. `0xFFFFFFFF`).

---

## Repo / file map

```
lib/zmedia_player.dart            # PUBLIC API barrel (start here)
lib/src/core/                     # MediaPlayer, MediaController, MediaConfig, exceptions, crash reporter
lib/src/models/                   # MediaItem, PlaybackState, Playlist, DrmConfig, streaming/cast/pip/etc.
lib/src/services/                 # Notification, Cast, Streaming, Cache, Subtitle, Buffering, Network, Analytics
lib/src/widgets/                  # MediaPlayerWidget, controls, menus/, components/, overlays/
lib/src/security/                 # CertificatePinning, SecureStorage, InputValidation
android/src/main/kotlin/com/zionmedianetwork/zmedia_player/   # Kotlin: MediaPlayerManager + per-feature handlers
ios/zmedia_player/Sources/zmedia_player/                      # Swift: MediaPlayerManager + per-feature handlers (SPM layout)
ios/zmedia_player.podspec · ios/zmedia_player/Package.swift   # CocoaPods + SPM
test/                             # 588 Dart tests (core, models, services, widgets, memory, performance)
example/                         # Feature-per-page gallery app (verified on a physical iPhone)
docs/                             # api-reference/, implementation/, summary/ + QUICK_START
PLAN.md · CLAUDE.md               # Roadmap · contributor + architecture guide
```

**Native symmetry rule:** native code is decomposed into per-feature handlers mirrored across
Android and iOS (`MediaPlayerManager`, `DrmHandler`, `PipHandler`, `NotificationHandler`,
`BufferingHandler`, `CrashHandler`, `NetworkMonitor`, `SecureStorageHandler`, + the platform view).
Add a native capability → add the same handler on **both** platforms to keep the MethodChannel contract symmetric.

---

## If you change code

- **Delegate Flutter/Dart/native work to the `flutter-expert` subagent** (mandatory per `CLAUDE.md`) for anything under `lib/`, `test/`, `example/`, `android/`, `ios/`.
- Run `flutter analyze` (clean) and `flutter test` (currently **588**, keep green) before proposing changes.
- Branch off `main` as `feat/…`/`fix/…`; PR required (no direct push to `main`); commits authored by the repo owner (no `Co-Authored-By` except the release workflow).
- Verify on a real device when touching native paths (DRM, casting, PiP, notifications, layout/rotation).

---

## Current status (honest)

Feature-complete across Dart and native layers; the audit-driven P0–P3 remediation has landed
(DRM wiring, per-`playerId` MethodChannel routing, native certificate pinning, secure storage
without plaintext fallback, `bufferedPosition`, leaked-subscription fixes, HTTPS-for-DRM).
The **Dart layer is extensively tested (588 tests)**; **native Kotlin/Swift has no automated tests yet**,
so DRM decryption, casting, and bandwidth metering still warrant **on-device verification** before
production reliance. Core playback, fullscreen, custom controls, quality/subtitles, background audio,
and lock-screen notifications have been verified on a physical iPhone.
