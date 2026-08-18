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
  NotificationConfig? notificationConfig,
  PipConfig? pipConfig,
  CastConfig? castConfig,
  bool showControls = true,
  Duration controlsTimeout = const Duration(seconds: 3),
  bool allowBackgroundPlayback = false,
  bool useHardwareAcceleration = true,
  BufferConfig? bufferConfig,
  HlsConfig? hlsConfig,          // not currently wired to native code — see the Streaming section below
  DashConfig? dashConfig,        // not currently wired to native code — see the Streaming section below
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
// HlsConfig / DashConfig — extend it with: enableLiveStream, enableDvr, liveLatency,
//   enableAdaptiveBitrate, enableSegmentPrefetch (HLS) / enableMpdCaching (DASH).
// QualityTrack — id, bitrate, resolution, codec.
// AudioTrack — id, language, codec, channels.
```

`HlsConfig`/`DashConfig` are constructible and accepted by `MediaConfig`, but their fields
above are **not currently wired to native code** — `MediaPlayer.load()` never sends them to
the platform channel, so setting them has no effect on playback today. See the
[Live Streaming guide](live-streaming.md) for what actually governs live/adaptive behavior in
the meantime. DASH is Android-only; AVPlayer on iOS has no DASH support.

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
- **Notifications:** `NotificationConfig`, `NotificationAction`, `NotificationPriority`.
- **PiP:** `PipConfig`, `PipAction`, `PipState`, `PipStatus`.
- **Cast:** `CastDevice`, `CastDeviceType`, `CastState`, `CastStatus`, `CastConfig`.
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
