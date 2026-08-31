# Models

Reference for the data types exported from `package:zmedia_player/zmedia_player.dart`.

## MediaItem

A single playable item.

```dart
const MediaItem({
  required String id,
  required String title,
  required String url,
  String? artist,
  String? album,
  Duration? duration,
  String? artworkUrl,
  String? mimeType,
  Map<String, String>? httpHeaders,
  MediaType mediaType = MediaType.video, // video | audio
  DrmConfig? drmConfig,
  Map<String, dynamic>? metadata,
  bool isLive = false,
  StreamingFormat? streamingFormat, // null = infer from the URL path
});
```

If `artworkUrl` is null, media notifications generate artwork from a video frame.

`url` accepts `http(s)://` and `file://` — local file playback is supported.
`InputValidator.validateUrl` rejects a bare filesystem path, so build the URI with
`LocalMediaUtils.fileUri(path)` rather than hand-constructing a `file://` string:

```dart
final path = '${(await getApplicationDocumentsDirectory()).path}/clip.mp4';
final item = MediaItem(id: 'local-clip', title: 'Local clip', url: LocalMediaUtils.fileUri(path));
```

A DRM-configured item cannot use a `file://` URL — DRM requires HTTPS for the media URL, so
`InputValidator` rejects the combination.

Equality is **id-based**: two `MediaItem`s with the same `id` are equal regardless of `url`,
`isLive`, `streamingFormat` or any other content field. Give variants of the same logical
stream distinct `id`s if you need to tell them apart.

### `streamingFormat` / `StreamingFormat`

```dart
enum StreamingFormat { hls, dash, progressive }
```

`streamingFormat` declares the container/manifest format of `url`, which is what selects the
streaming config that applies to this item: `hls` → `MediaConfig.hlsConfig`, `dash` →
`MediaConfig.dashConfig`, `progressive` → neither. That in turn decides whether `enableDvr`,
`liveLatency` and the bitrate bounds have any effect (see [Streaming](#streaming) below), and
on Android which Media3 `MediaSource` is built.

`null` (the default) means "infer from the URL", exposed as
`MediaItem.resolvedStreamingFormat`:

| Rule | Result |
|---|---|
| `streamingFormat` set | that value, always — inference is skipped entirely |
| URL *path* ends in `.m3u8` (case-insensitive) | `StreamingFormat.hls` |
| URL *path* ends in `.mpd` (case-insensitive) | `StreamingFormat.dash` |
| anything else, including a malformed URL | `StreamingFormat.progressive` |

The query string and fragment are stripped before matching, so
`…/manifest.mpd?token=abc.m3u8` is DASH, and matching is `endsWith` on the path, so
`/hls.m3u8-archive/eu/manifest.mpd` is DASH too. Inference never throws for any input.

Two helpers are exported alongside the enum: `StreamingFormat.fromUrl(String)` (the inference
above) and `StreamingFormat.fromName(Object?)` (decodes the serialized name; returns `null` for
an unknown or non-`String` value, meaning "fall back to inference").

Set it explicitly whenever the URL is not self-describing — CDN rewrites, signed URLs whose
path is masked, or extension-less manifest endpoints:

```dart
MediaItem(
  id: 'live',
  title: 'Live',
  url: 'https://cdn.example.com/live/eu/primary?token=abc',
  isLive: true,
  streamingFormat: StreamingFormat.dash,
);
```

It is serialized to native as the `streamingFormat` key of the `mediaItem` payload (`null`
when unset), and both Android and iOS prefer it over their own URL inference. See the
[Live Streaming guide](live-streaming.md#choosing-which-streaming-config-applies-streamingformat)
for why `hlsConfig` is never reused for a DASH item, and for the debug-only warning emitted
when a live item resolves to a format with no config.

## MediaConfig

Player configuration (passed to `MediaController.create` / `MediaPlayer`).

```dart
const MediaConfig({
  bool autoPlay = false,
  bool looping = false,
  BoxFit boxFit = BoxFit.contain,
  double volume = 1.0,
  double speed = 1.0,
  bool startMuted = false,
  Map<String, String>? httpHeaders,
  DrmConfig? drmConfig,
  SubtitleConfig? subtitleConfig,
  CacheConfig? cacheConfig,
  PipConfig? pipConfig,
  CastConfig? castConfig,
  bool showControls = true,
  Duration controlsTimeout = const Duration(seconds: 3),
  bool allowBackgroundPlayback = false,
  bool useHardwareAcceleration = true,
  BufferConfig? bufferConfig,
  HlsConfig? hlsConfig,          // partially wired to native code — see the Streaming section below
  DashConfig? dashConfig,        // partially wired to native code — see the Streaming section below
  AdaptiveCacheConfig? adaptiveCacheConfig, // Android-only transparent HLS/DASH segment cache
  bool enableSubtitles = true,
  bool respectSafeArea = false,     // inset video below status bar / notch
  bool immersiveLandscape = false,  // hide system status bar in landscape (restored on portrait)
  bool secureSurface = false,       // Android: blocks capture (FLAG_SECURE); iOS: detects capture only
});
```

`respectSafeArea` and `immersiveLandscape` are Flutter-layer and behave identically on iOS and
Android. `boxFit` maps to native video gravity (`contain` = aspect-fit, `cover` = aspect-fill,
`fill` = stretch) and updates the native view at runtime.

**`secureSurface` is asymmetric across platforms.** On Android it adds `FLAG_SECURE` to the
host window — a hard OS-level block: screenshots and screen recordings of that window fail
outright, and `MediaController.screenCaptureStream` never emits there (there is nothing to
report). On iOS there is no equivalent OS-level block available to a third-party app; setting
`secureSurface: true` instead starts observing `UIScreen.isCaptured` and reports changes via
`screenCaptureStream` — detection only, not prevention. Toggle it after construction with
`MediaController.setSecureSurface(bool)` / `MediaPlayer.setSecureSurface(bool)`.

**`speed` is a setting, never a transport command.** Setting `speed` (via `MediaConfig` or
`setSpeed`) changes the rate playback *will* run at; it never starts or stops playback. A paused
player stays paused when its speed changes, and the new speed applies on the next `play()`.
Conversely, with `autoPlay: false` the package guarantees no playback begins until you call
`play()` explicitly — on either platform. (An earlier iOS implementation violated this: setting
a speed assigned `AVPlayer.rate` directly, which *is* a play command, so `autoPlay: false` was
silently defeated. The current implementation splits `rate`/`defaultRate` so this no longer
happens.)

## PlaybackState / PlayerState

```dart
enum PlayerState { idle, buffering, ready, playing, paused, completed, error }

const PlaybackState({
  required PlayerState state,
  Duration position = Duration.zero,
  Duration duration = Duration.zero,
  double speed = 1.0,
  double volume = 1.0,
  bool isMuted = false,
  bool isBuffering = false,
  double bufferPercentage = 0.0,
  Duration bufferedPosition = Duration.zero,
  String? errorMessage,
});
// getters: progress (0..1), canPlay, canPause, canSeek
```

## Playlist

```dart
enum PlaybackMode { sequential, shuffle }
enum MediaRepeatMode { none, single, all } // renamed from RepeatMode

const Playlist({
  required String id,
  required String title,
  required List<MediaItem> items,
  int currentIndex = 0,
  PlaybackMode mode = PlaybackMode.sequential,
  MediaRepeatMode repeatMode = MediaRepeatMode.none,
  Map<String, dynamic>? metadata,
  List<int>? shuffleOrder, // permutation used in shuffle mode
});
// getters: currentItem, hasNext, hasPrevious, nextIndex, previousIndex, totalDuration, length, isEmpty
// ops: copyWith, addItem, insertItem, removeItemAt, moveToIndex
```

## DRM

```dart
enum DrmScheme { token, widevine, fairplay, ezdrm, playready, clearkey }

// Factories:
DrmConfig.widevine({required String licenseUrl, Map<String, String>? headers,
    WidevineSecurityLevel? minWidevineSecurityLevel, ...});
DrmConfig.fairplay({required String licenseUrl, required String certificateUrl,
    String? contentId, Map<String, String>? headers, ...});
DrmConfig.token({required String licenseUrl, required String token, String? keyId, ...});
DrmConfig.ezdrm({required EzdrmConfig ezdrmConfig, ...});
```

DRM requires HTTPS for license and media URLs (enforced by `InputValidator`). Each factory
accepts an optional `certificatePinning: CertificatePinningConfig`. See the [DRM Guide](drm.md)
for scheme-by-scheme platform support (`playready` exists in the enum but only works on the
rare Android device that ships a system PlayReady CDM, and has no iOS path at all) and for
what "offline DRM" does and does not mean today. `minWidevineSecurityLevel` is
Android/Widevine-only: an opt-in, fail-closed minimum `MediaDrm` security level checked before
a DRM session is created.

## Streaming

```dart
enum BitrateSelectionStrategy { auto, lowest, highest, medium }

// StreamingConfig — adaptive bitrate + quality-switch thresholds.
// HlsConfig / DashConfig — extend it with: enableDvr, liveLatency, plus the
//   deprecated enableLiveStream (use MediaItem.isLive instead).
// QualityTrack — id, bitrate, resolution, codec.
// AudioTrack — id, language, codec, channels.
```

Which of `hlsConfig`/`dashConfig` applies to a given item is decided by that item's
[`MediaItem.resolvedStreamingFormat`](#streamingformat--streamingformat) — its explicit
`streamingFormat` when set, otherwise path-based URL inference. The two are never
cross-applied, so an app that serves HLS on one platform and DASH on the other must set both.

`HlsConfig`/`DashConfig` are serialized to the platform channel and read by native for a
specific subset of fields — `enableDvr` (Dart-side seek gate for
`MediaPlayer.isSeekable`/`seekTo`; also gates whether native reports a duration for the live
item at all — see below), `liveLatency` (`MediaItem.LiveConfiguration` on Android, `AVPlayerItem
.configuredTimeOffsetFromLive` on iOS 14+), and the inherited `enableAdaptiveBitrate`/
`maxBitrate`/`minBitrate` (`DefaultTrackSelector` on Android; iOS honors only `maxBitrate` via
`preferredPeakBitRate` — no faithful `minBitrate`/force-non-adaptive equivalent exists on
AVPlayer). `bitrateStrategy`, `enableAutoQualitySwitch`, `qualitySwitchThreshold`, and
`enableBandwidthEstimation` still cross the channel but are not read by either platform. See
the [Live Streaming guide](live-streaming.md) for the full field-by-field wiring table. DASH is
Android-only; AVPlayer on iOS has no DASH support.

With `enableDvr: true`, native also derives and reports a duration for a live item — the
current DVR window length (`Timeline.Window.durationMs` on Android, `AVPlayerItem
.seekableTimeRanges` on iOS), re-derived as the window grows, rather than the unbounded total
broadcast time. `MediaPlayer.dvrEnabled`/`.isSeekable` expose the Dart-side gate directly. The
config snapshot that decides all of this is carried on every `MediaPlayer.load()`,
`setPlaylist()` and `skipToIndex()` call — not only at `initialize()`/`updateConfig()` time — so
playlist-driven items honor the current config too (`skipToNext`/`skipToPrevious`/auto-advance
route through `skipToIndex`). See the
[Live Streaming guide](live-streaming.md#what-actually-works-today).

## Subtitles

```dart
enum SubtitleFormat { srt, webvtt, ass, ssa, ttml }
enum SubtitleAlignment { left, center, right }

const SubtitleConfig({
  double fontSize, int fontColor, int backgroundColor, // ARGB ints, e.g. 0xFFFFFFFF
  bool showOutline, double verticalPosition, SubtitleAlignment alignment, ...
});
```

## Other models

- **Buffering:** `BufferingConfig`, `BufferHealth`, `BufferStatus` (healthy/warning/critical/underrun), `BufferStatistics`.
- **Network:** `NetworkStatus`, `NetworkQuality`, `ConnectionType`, `NetworkChangeEvent`.
- **Analytics:** `QoEMetrics`, `PerformanceMetrics`, `EngagementMetrics`, `PlaybackEndReason`, `BufferEventType`.
- **Notifications:** `NotificationConfig`, `NotificationAction`, `NotificationPriority` — pass a
  `NotificationConfig` to `NotificationService` directly (not `MediaConfig`) to drive media
  playback notifications; there is no `MediaConfig.notificationConfig`.
  `showSeekForward`/`showSeekBackward` (both default `false`) are honoured on **both**
  platforms under one contract: **the seek control is offered iff the flag is `true` AND the
  item is seekable** (`MediaPlayer.isSeekable`, i.e. not a live stream without DVR). Android
  renders a `NotificationCompat.Action` and advertises `ACTION_FAST_FORWARD`/`ACTION_REWIND`;
  iOS enables `MPRemoteCommandCenter.skipForwardCommand`/`.skipBackwardCommand`. `seekInterval`
  (default `10`) is display-only on both platforms — it labels the Android button and sets
  iOS's `preferredIntervals`; the host app performs the actual seek from
  `NotificationService.actionEventStream` (`NotificationActions.seekForward` /
  `.seekBackward`, wire values `'seekForward'` / `'seekBackward'`).
  `priority`, `dismissible`, and `customActions` remain **Android only**.
- **PiP:** `PipConfig`, `PipAction`, `PipState`, `PipStatus`, `PipActionEvent` (delivered via
  `MediaPlayer.pipActionStream` when a custom `PipConfig.actions` entry is tapped —
  Android-only).
- **Cast:** `CastDevice`, `CastDeviceType`, `CastState`, `CastStatus`, `CastConfig`. The
  `CastConfig` passed via `MediaConfig.castConfig` now actually reaches native code:
  `enabled`/`enableChromecast` gate Chromecast init on Android, `enabled`/`enableAirPlay` gate
  AirPlay init on iOS, `chromecastAppId` overrides the receiver app ID on Android (falls back to
  Google's Default Media Receiver `CC1AD845` when unset), and `discoveryTimeout` bounds Android
  Chromecast discovery. `enableDlna` and `autoConnect` were removed: this package has no DLNA
  support, and auto-connecting to the last-used device would require a persistence mechanism
  this package doesn't have — both were dead config before removal, and leaving them in would
  have kept implying behaviour that didn't exist.
- **Cache/buffer sub-configs:** `CacheConfig`, `BufferConfig`, `AdaptiveCacheConfig`
  (Android-only, opt-in, off by default transparent HLS/DASH segment cache — a read-through
  cache of what has already played, not a download-ahead/offline mechanism; DRM-protected
  items are never written to it — see [Advanced Features](advanced-features.md#caching--offline)).
- **Feed / pool:** `MediaFeedConfig`, `MediaFeedItemState` (see [Advanced Features](advanced-features.md#media-feed)
  for `MediaFeed`/`MediaPlayerPool`).
- **Security:** `ScreenCaptureStatus` (see `secureSurface` above).

Most models provide `copyWith`, and the serializable ones provide `toMap()` / `fromMap()`.

### `BufferConfig` is only partly honoured on iOS

This is a platform capability difference, not a wiring gap, and it is worth knowing before you tune
buffering:

| Field | Android (Media3/ExoPlayer) | iOS (AVFoundation) |
|---|---|---|
| `targetBufferMs` | Applied | Applied, via `AVPlayerItem.preferredForwardBufferDuration` |
| `minBufferMs` | Applied | **Ignored** |
| `maxBufferMs` | Applied | **Ignored** |
| `rebufferMs` | Applied | **Ignored** |

Android maps all four onto `DefaultLoadControl.setBufferDurationsMs`. AVFoundation exposes no
equivalent for a minimum buffer before playback starts, a maximum buffer cap, or a
resume-after-stall threshold, so those three values are accepted and silently ignored on iOS. Set
them if you target Android; do not rely on them for iOS behaviour.
