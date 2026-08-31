# AGENTS.md — ZMedia Player

Machine-oriented guide for AI agents and tools working **with** the `zmedia_player`
package (consuming its API) or **on** it (changing its source). Humans welcome too.
For the architecture narrative and contributor workflow, see [`CLAUDE.md`](CLAUDE.md).

---

## What this package is (in 5 lines)

- A Flutter **media player package** for video + audio on **Android (AndroidX Media3/ExoPlayer)** and **iOS (AVPlayer)**.
- Public API is a **single barrel**: everything in [`lib/zmedia_player.dart`](lib/zmedia_player.dart) is public; anything else is internal.
- Two entry points: **`MediaController`** (reactive `ChangeNotifier` facade — use this for UI) and **`MediaPlayer`** (lower-level, stream-first, singleton per `playerId`).
- Dart talks to native over a single `MethodChannel` named `zmedia_player`, routed per `playerId`.
- Advanced features: HLS/DASH adaptive streaming, DRM (Widevine/FairPlay/EZDRM), subtitles, PiP, casting (Chromecast/AirPlay), lock-screen notifications, certificate pinning.

**Versions:** Flutter SDK `>=3.19.0` (developed/verified on **3.44.3** / Dart **3.12**) · iOS **13.0+** · Android **minSdk 23**, **compileSdk 35**, AndroidX Media3 **1.11.0**. iOS builds with **Swift Package Manager or CocoaPods**.

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
| `MediaController` | Reactive `ChangeNotifier` facade over `MediaPlayer`; use for UI. `create()` factory. Serializes every operation through a per-controller FIFO queue — see the gotcha below. |
| `MediaPlayer` | Lower-level engine; singleton per `playerId`; exposes all streams. |
| `MediaConfig` | Player configuration (autoPlay, boxFit, DRM, streaming, `respectSafeArea`, `immersiveLandscape`, `secureSurface`, …). |
| `CacheConfig`, `BufferConfig` | Cache + buffering sub-configs used by `MediaConfig`. |
| `CrashReporter` | Optional crash-reporting hook (`MediaPlayer.enableCrashReporting`). |
| `MediaPlayerException` (sealed) + subclasses | Typed errors: `MediaLoadException`, `NetworkException`, `DrmException`, `PlaybackException`, `InvalidStateException`, `PlayerDisposedException`, `ConfigurationException`, `PlatformOperationException`, `ProtocolMismatchException`. Plus **deprecated** `OperationBusyException` — never thrown any more (`MediaController` queues instead of rejecting), kept only so exhaustive `switch`es over the sealed hierarchy keep compiling. |
| `MediaPlayerPool` | Bounded pool of live `MediaController`/decoder sessions; underlies `MediaFeed`'s prewarm/activate/release lifecycle for scroll feeds. |
| `LocalMediaUtils` | Builds a `file://` URL from a filesystem path for local/cached-file playback (`fileUri`). |

### Models (`lib/src/models/`)
| Export | Purpose |
|---|---|
| `MediaItem` / `MediaType` / `StreamingFormat` | A playable item (url, title, artwork, drmConfig, headers) / `video`\|`audio` / `hls`\|`dash`\|`progressive`. `MediaItem.streamingFormat` (nullable) states the item's format explicitly and selects which of `hlsConfig`/`dashConfig` applies; `null` falls back to `MediaItem.resolvedStreamingFormat`'s path-based URL inference (`StreamingFormat.fromUrl`). Equality is id-based only. |
| `PlaybackState` / `PlayerState` | State snapshot (position, duration, `bufferedPosition`, speed, volume, error) / `idle,buffering,ready,playing,paused,completed,error`. |
| `Playlist` / `PlaybackMode` / `MediaRepeatMode` | Item collection + shuffle order / `sequential`\|`shuffle` / `none`\|`single`\|`all`. **Note: the enum is `MediaRepeatMode`, not `RepeatMode`.** |
| `SubtitleTrack` / `SubtitleFormat` / `SubtitleConfig` / `SubtitleAlignment` | Subtitle track, format (`srt,webvtt,ass,ssa,ttml`), styling, alignment. |
| `QualityTrack` / `AudioTrack` | Selectable video-quality / audio-track descriptors. |
| `StreamingConfig` / `BitrateSelectionStrategy` / `HlsConfig` / `DashConfig` | Adaptive-streaming config; `HlsConfig`/`DashConfig` wire `enableDvr` (seek gating + live duration reporting), `liveLatency`, and inherited `maxBitrate`/`minBitrate`/`enableAdaptiveBitrate` to native (see [live-streaming.md](docs/api-reference/live-streaming.md) for the per-field, per-platform table). Exactly one of the two applies per item, chosen by `MediaItem.resolvedStreamingFormat`; they are **never** cross-applied, so an HLS-on-iOS/DASH-on-Android app must set both. `enableLiveStream` is deprecated — use `MediaItem.isLive`. |
| `DrmConfig` / `DrmScheme` / `EzdrmConfig` / `DrmSession` | DRM config + factories (`.widevine`, `.fairplay`, `.ezdrm`, `.token`); session state. `DrmConfig.minWidevineSecurityLevel` sets the floor for Android Widevine only (no effect on iOS FairPlay). |
| `BufferingConfig` / `BufferHealth` / `BufferStatus` / `BufferStatistics` | Adaptive buffering config + health/stats. |
| `NetworkStatus` / `NetworkQuality` / `ConnectionType` / `NetworkChangeEvent` | Network monitoring model. |
| `QoEMetrics` / `PerformanceMetrics` / `EngagementMetrics` / `PlaybackEndReason` / `BufferEventType` | Analytics/QoE models. |
| `NotificationConfig` / `NotificationAction` / `NotificationPriority` | Lock-screen / Control Center notification config. `priority`, `dismissible`, and `customActions` are wired **Android only** — no faithful `MPRemoteCommandCenter` equivalent exists on iOS. `showSeekForward`/`showSeekBackward` are wired on **both** platforms with one contract: the control is offered iff `flag && MediaPlayer.isSeekable` (Android `ACTION_FAST_FORWARD`/`ACTION_REWIND` + a notification button; iOS `skipForwardCommand`/`skipBackwardCommand`). `seekInterval` is display-only on both — the host app performs the seek. |
| `PipConfig` / `PipAction` / `PipState` / `PipStatus` / `PipActionEvent` | Picture-in-Picture config + state. `PipConfig.actions`/`showPlaybackControls` are wired **Android only** for custom actions (`showPlaybackControls` partially affects iOS via `requiresLinearPlayback`, iOS 14+); tapping a custom action delivers a `PipActionEvent` on `MediaPlayer.pipActionStream`. |
| `CastDevice` / `CastDeviceType` / `CastState` / `CastStatus` / `CastConfig` | Casting (Chromecast/AirPlay) model — no DLNA support exists in this package. |

### Services (`lib/src/services/`)
| Export | Purpose |
|---|---|
| `NotificationService` | Lock-screen/Control Center media controls. `initialize(playerId, mediaPlayer:)` then `show()`/`dismiss()`; `actionEventStream` (`actionStream` is deprecated). Action wire values live in `NotificationActions` — `seekForward`/`seekBackward` are `'seekForward'`/`'seekBackward'`, matching what both native handlers emit. |
| `CastService` | Cast device discovery + connection. |
| `StreamingService` | Bandwidth estimation + quality recommendation. |
| `CacheService` | Downloads a media file to disk (`downloadAndCache`/`cacheMedia`/`preloadMedia`) and plays it back from there via `getCachedFileUri` — including fully offline for non-DRM content. Not a full download-manager (no background-transfer queue) and **not** offline DRM — no license can be persisted for offline playback on either platform. |
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
| `MediaFeed` | Scroll feed of players (TikTok/Reels-style) backed by `MediaPlayerPool`: bounded concurrent decoder sessions, a configurable prewarm window for upcoming items, activation debounce during fast flings, releasing players once they leave the live window, and an optional `autoPlayPolicy` (e.g. `conservativeAutoPlayPolicy`) to withhold autoplay on metered/poor connections. |
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
`MediaController` additionally exposes `errorStream` (re-emits `MediaPlayer.errorStream`) and
`error` (the most recently observed typed error, cleared once state moves on) directly, so a UI
doesn't have to reach through `controller.player` just for error state.

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
| `pipActionStream` | `PipActionEvent` (custom `PipConfig.actions` tap — Android only) |
| `notificationActionStream` | `String` (action id) |
| `errorStream` | `MediaPlayerException` (typed — see error categories below) |
| `pauseReasonStream` | `PlayerPauseReason` (distinguishes an audio-focus-loss pause from a user pause) |
| `networkStatusStream` / `networkChangeStream` | `NetworkStatus` / `NetworkChangeEvent` |

Native→Dart events (handled in `MediaPlayer._handleMethodCall`, dispatched by `playerId`):
`onPlaybackStateChanged`, `onPositionChanged`, `onDurationChanged`, `onVolumeChanged`,
`onSpeedChanged`, `onQualityTracksChanged`, `onSubtitleTracksChanged`, `onAudioTracksChanged`,
`onBandwidthUpdate`, `onBufferHealthUpdate`, `onDrmSessionUpdate`, `onNotificationAction`,
`onPipStatusChanged`, `onPipAction`, `onCastStatusChanged`, `onCastDevicesChanged`,
`onNetworkStatusChanged`, `onPlatformViewError`, `onError`.

**Error categories.** `onError` carries a `category` in its details, drawn from a vocabulary both
platforms share: `NETWORK`, `HTTP`, `DRM`, `DECODER`, `SOURCE`, `UNKNOWN`. Dart maps these onto the
sealed exception hierarchy and emits typed exceptions on `errorStream`. **The vocabulary is
guarded by a test that parses the native sources as text**
(`test/exceptions/error_category_vocabulary_test.dart`) — if you add or rename a category on one
platform, add it to `MediaErrorCategory` and to both native categorisers, or that test fails. The
same technique guards the `connectionType` vocabulary in
`test/models/network_status_vocabulary_test.dart`.

**Protocol version.** `initialize` exchanges a protocol version in both directions; a skew raises
`ProtocolMismatchException` rather than a raw `MissingPluginException`. If you add a MethodChannel
method that older native builds will not have, consider whether the version needs incrementing —
purely additive native→Dart events do not, since an old native build simply never sends them.

**`mediaItem` payload.** Includes `streamingFormat` (`'hls'`/`'dash'`/`'progressive'`, or `null`
when the host left inference on) alongside `isLive`. Native prefers it over its own URL sniffing
when picking `hlsConfig` vs `dashConfig`, the Media3 `MediaSource` type (Android), whether to
parse the HLS manifest for quality tracks (iOS), and the cast `MediaInfo` contentType
(`CastHandler.kt`); an absent/unknown value falls back to the same path-based inference Dart uses
(`endsWith('.m3u8')`/`endsWith('.mpd')` on the URL path). `loadMediaOnCastDevice`'s reduced
`mediaItem` map carries the key too.

**Config-snapshot payloads (`load`, `setPlaylist`, `skipToIndex`).** Every Dart entry point that
makes native load a media item carries the current `MediaConfig` snapshot under a `config` key,
serialized the same way `initialize`/`updateConfig` already do:

| Method | Payload |
| --- | --- |
| `load` | `{playerId, mediaItem, config}` |
| `setPlaylist` | `{playerId, playlist, startIndex, config}` |
| `skipToIndex` | `{playerId, index, config}` |

`skipToNext`, `skipToPrevious` and playlist auto-advance on completion all route through
`skipToIndex`, so they are covered by the same key. The snapshot is sent on **every** such call,
so a rebuilt config (e.g. flipping `hlsConfig.enableDvr`) takes effect on the next load —
including a playlist-driven one — without a separate `updateConfig()` call. On the next *load*,
specifically: see the same-item guard below, where a `setPlaylist` for the item already playing
stores the new config but does not reload. Native replaces its
stored config wholesale from this before any config-dependent work runs, but deliberately does
not re-run `applyConfig()`/volume-speed-mute reapplication from these paths (that would undo an
in-progress runtime `setMuted()` call — see `MediaPlayerManager.kt`'s/`.swift`'s `loadMediaItem`
doc). `config` is optional on the native side on all three: an absent key leaves the stored
config untouched, so an older Dart caller cannot break a newer native build. Per-item
`httpHeaders`/`drmConfig` are unaffected by all of this — they live on `MediaItem`, not
`MediaConfig`.

**`setPlaylist` and the same-item guard.** `MediaPlayer.setPlaylist()` sends the payload in the
table above (`{playerId, playlist, startIndex, config}`) on **every** call — the #79 fix changed
no payload. What it changed is what native does with it: `MediaPlayerInstance.setPlaylist` on
**both** platforms updates `currentPlaylist`/`currentIndex` unconditionally but **skips** its
`loadMediaItem` call when
`items[startIndex]` is, key for key, the item already loaded (`currentMediaItem`) *and* that
item is still in progress. So a playlist can be extended in place, or re-issued to change
`mode`/`repeatMode`, without restarting the item under the viewer.

- **Comparison:** whole-serialized-item structural equality (Kotlin `Map.equals`;
  `NSDictionary.isEqual(to:)` on iOS), not an `id` check. An `id` match alone would silently
  swallow deliberate re-issues — a re-signed `url`, refreshed `httpHeaders`, a rotated
  `drmConfig` token or `drmConfig.headers`. A missing `id` is never self-identifying.
- **In progress:** `STATE_READY`/`STATE_BUFFERING` on Android; on iOS a `.readyToPlay`
  `currentItem` plus a `currentItemIsSpent` flag (set by `stop()` and the play-to-end
  notification, cleared by `loadMediaItem`/`play`/`seekTo`) — iOS needs the flag because
  `stop()` there is pause + `seek(to: .zero)` and a finished item stays attached, neither of
  which is visible from `AVPlayer` state the way ExoPlayer's `playbackState` is.
- **`skipToIndex` deliberately has no guard** (and therefore neither do
  `skipToNext`/`skipToPrevious`): "skip to the index you are on" is a restart, and
  `MediaRepeatMode.single` is implemented through exactly that call from
  `MediaPlayer._handlePlaybackCompleted`.
- **A changed `MediaConfig` does not force a reload.** The `config` snapshot above is stored
  unconditionally and *first* — including on the skip path and the early-return paths — so the
  next real load uses it. But storing it never by itself triggers a load: a `setPlaylist` that
  carries a new config for an unchanged, in-progress item **stores the config and skips the
  load**, by design. (`MediaConfig`/`HlsConfig`/`DashConfig` define no `operator ==`, so a
  freshly built config is never equal to the previous one and comparing them would make the
  guard useless; and most `MediaConfig` streaming fields cannot take effect mid-item natively
  without a reload anyway.) `updateConfig()` is the "apply to live playback now" API; `load()`
  is "apply *and* reload".
- **Event coherence:** when native skips the load it re-emits `onStateChanged`,
  `onDurationChanged` and the three `on*TracksChanged` events. Dart mirrors the guard in
  `MediaPlayer._isPlaylistReloadSkipped` and skips its own "a load is coming" reset (clearing
  track lists, forcing `buffering`, resetting speed); the native re-emit is the safety net if
  the two comparisons ever disagree.

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

// Extending (or re-issuing) a playlist does NOT restart the item already
// playing -- useful for sliding-window queues and for toggling shuffle
// mid-playback. See docs/api-reference/player-api.md.
await controller.setPlaylist(Playlist(
  id: 'p', title: 'My list', items: [item1, item2, item3],
  mode: PlaybackMode.shuffle,
  repeatMode: MediaRepeatMode.all,
));
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
notifications.actionEventStream.listen((e) { /* play|pause|next|previous|stop|seekForward|seekBackward|seekTo */ });
```
If `MediaItem.artworkUrl` is null, the artwork is auto-generated from a **video frame**.

Seek controls are opt-in (`showSeekForward`/`showSeekBackward`, both default `false`) and are
rendered **iff the flag is true AND the item is seekable** — identical on Android and iOS.
`seekInterval` only labels the control; the host app must apply the same `Duration` when it
handles the `seekForward`/`seekBackward` event.

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
controller.player.pipActionStream.listen((e) { /* PipConfig.actions tap, Android only */ });
```

### Live streaming (DVR seek gating)
```dart
final controller = MediaController.create(
  config: const MediaConfig(hlsConfig: HlsConfig(enableDvr: true)),
);
await controller.load(MediaItem(id: 'live', title: 'Live', url: 'https://cdn/live.m3u8', isLive: true));
controller.player.isSeekable; // false for a live item unless enableDvr was set on the config
                              // matching its resolved StreamingFormat at load()
await controller.seekTo(pos); // throws InvalidStateException on live + !isSeekable

// URL not self-describing (CDN rewrite / signed / extension-less)? State the format:
await controller.load(MediaItem(
  id: 'live2', title: 'Live', url: 'https://cdn/live/eu/primary?token=abc',
  isLive: true, streamingFormat: StreamingFormat.dash,
));
```
Without `enableDvr: true`, a live item reports `isSeekable == false` and no duration; `seekTo`
throws rather than silently doing nothing. `hlsConfig` is never reused for a DASH item (and vice
versa) — in debug builds, a live item that resolves to a format whose config is `null` logs a
one-time warning naming the missing config and the consequence. See
[live-streaming.md](docs/api-reference/live-streaming.md).

---

## Conventions & gotchas

- **One barrel.** Add a new public type? Export it from `lib/zmedia_player.dart` or it's internal.
- **Always `dispose()`** controllers/services in `State.dispose()` — they hold native resources + timers.
- **`MediaRepeatMode`**, not `RepeatMode` (renamed; breaking).
- **DRM requires HTTPS** for both license and media URLs (`InputValidator` enforces it).
- **Streaming format is resolved per item, never cross-applied.** `MediaItem.streamingFormat`
  wins; otherwise it is inferred from the URL's *path* with `endsWith` (`.m3u8`/`.mpd`), query
  and fragment stripped — not a `contains` scan of the whole URL. Set it explicitly for
  rewritten/signed/extension-less manifest URLs.
- **Quality/subtitle/audio tracks appear only after `play()`** — native reports them once buffering starts.
- **Notifications need the player**: `initialize(playerId, mediaPlayer: …)` or lock-screen state won't sync.
- **MethodChannel calls are async** — always `await`.
- **`MediaController` operations are queued, not rejected.** Every controller method (`play`, `pause`, `seekTo`, `setVolume`, `load`, track selection, `updateConfig`, …) goes onto a per-controller FIFO queue and runs one at a time, in submission order. Calling while another operation is in flight is fine — the new call waits its turn, so interleaved `pause()`/`play()` or muting a player mid-`load()` always takes effect. Consequences: the returned `Future` resolves only once that call actually ran; each operation is capped at 10 s and fails with `TimeoutException` (so one wedged native call can't stall the queue); an operation still queued when `dispose()` runs is dropped and completes as a no-op; `isOperationInProgress` is informational only (check-then-act on it is racy — you don't need it). Do **not** rebuild a per-`playerId` promise chain on top of this.
- **Speed is a setting, transport is `play`/`pause`** — never conflate them. `setSpeed`/`MediaConfig.speed` must not start or stop playback on either platform, and with `autoPlay: false` nothing plays until an explicit `play()`. On iOS this means `AVPlayer.defaultRate` (+ a stored requested speed), *not* `rate`, which is a play command.
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
test/                             # 958 Dart tests (core, models, services, widgets, memory, performance, exceptions, security, crash_reporting)
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
- Run `flutter analyze` (clean) and `flutter test` (currently **958**, keep green) before proposing changes.
- **API/data-contract/feature changes require documentation in the same change** — root `README.md`, this file, every affected file under `docs/`, and `CHANGELOG.md`. See `CLAUDE.md`'s Development Workflow for the full rule and why (a MethodChannel payload change, in particular, is invisible to `flutter analyze` and to the test suite, since every test mocks the channel — documentation is the only place it's recorded).
- Branch off `main` as `feat/…`/`fix/…`; PR required (no direct push to `main`); commits authored by the repo owner (no `Co-Authored-By` except the release workflow).
- Verify on a real device when touching native paths (DRM, casting, PiP, notifications, layout/rotation).

---

## Current status (honest)

Feature-complete across Dart and native layers; the audit-driven P0–P3 remediation has landed
(DRM wiring, per-`playerId` MethodChannel routing, native certificate pinning, secure storage
without plaintext fallback, `bufferedPosition`, leaked-subscription fixes, HTTPS-for-DRM).
The **Dart layer is extensively tested (958 tests)**; **native Kotlin/Swift has no automated tests yet**,
so DRM decryption, casting, and bandwidth metering still warrant **on-device verification** before
production reliance. Core playback, fullscreen, custom controls, quality/subtitles, background audio,
and lock-screen notifications have been verified on a physical iPhone. Live-stream DVR seek gating
and DVR-window duration reporting (`enableDvr`) have been verified on a physical Android device
(Note 9P) against a live HLS stream; the equivalent iOS wiring has not yet been verified on a
physical device.
