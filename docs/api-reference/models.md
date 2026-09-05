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

/// Which timeline `PlaybackState.position` is measured against.
enum PositionBasis {
  absolute,   // from the media start — a fixed zero point
  liveWindow, // from the start of the live/DVR window, which itself slides forward
}

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
  Duration? liveEdgeOffset,                          // null for VOD
  PositionBasis positionBasis = PositionBasis.absolute,
});
// getters: progress (0..1), canPlay, canPause, canSeek,
//          isAtLiveEdge, isPositionWindowRelative
// methods: isAtLiveEdgeWithin(Duration tolerance)
// static:  defaultLiveEdgeTolerance == Duration(seconds: 15)
```

`copyWith` takes `liveEdgeOffset` and `positionBasis`, plus a
`bool clearLiveEdgeOffset = false` flag — because `liveEdgeOffset` is legitimately
nullable, `?? this.liveEdgeOffset` alone could never reset a previously reported
offset back to `null`, which is how `load()` drops a stale live-edge signal when
switching to a VOD item. `clearLiveEdgeOffset: true` wins over any value passed
alongside it. Both new fields participate in `==`/`hashCode` and appear in
`toString()`.

**Live-edge fields.** `liveEdgeOffset` is how far behind the live edge the playhead
is, native-sourced on every `onPositionChanged` event (Android:
`Player.getCurrentLiveOffset()`, sanity-checked against the live window's own
duration and rejected in favor of a bounded fallback when it exceeds that duration
— a manifest whose time anchor disagrees with its segment timeline can otherwise
report broadcast age instead of live-edge distance, see
[live-streaming.md](live-streaming.md#manifest-time-anchor-defect-liveedgeoffset-and-livelatency);
iOS: end of `AVPlayerItem.seekableTimeRanges.last` minus `currentTime()`, bounded by
construction). It is `null` for VOD and whenever the platform cannot answer
yet; it *is* reported for live streams both with and without `enableDvr`.
`isAtLiveEdge` is `liveEdgeOffset <= defaultLiveEdgeTolerance` (15s), and `false`
whenever the offset is `null`.

**The two platforms measure different quantities under this one field name**
(issue #120), and the values are not comparable. Android's computation measures
distance from the *published* live edge (commonly 15-30s during healthy
playback of a standard stream). iOS's "bounded by construction" phrasing above
is doing real work: because AVPlayer keeps the playhead pinned to the end of
the seekable range during live playback, the subtraction reads under a second
there, essentially regardless of how the stream is actually behaving — which
in turn makes `isAtLiveEdge` effectively always `true` on iOS, and means a
`liveLatency` cushion configured on iOS cannot be observed through this field.
See [live-streaming.md](live-streaming.md#platform-divergence-this-value-measures-different-things)
for the full explanation, including what still works identically on both
platforms (stall detection and DVR scrub-back).

**`positionBasis` matters for stall detection.** On `PositionBasis.liveWindow` the
window start slides forward with the playhead, so a *constant* `position` is what
healthy playback looks like — not a stall. Branch on this rather than inferring the
basis from your own `enableDvr` config. See
[Live Streaming](live-streaming.md#stall-watchdog-for-live-streams).

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
item at all — see below), `liveLatency` (`MediaItem.LiveConfiguration` on Android, *maintained*
via playback-speed adjustment; `AVPlayerItem.configuredTimeOffsetFromLive` on iOS 14+ for the
join position, also **maintained** after a rebuffer since this package sets
`automaticallyPreservesTimeOffsetFromLive = true` — at the cost of a visible forward skip
right after the rebuffer, with no opt-out — see
[`HlsConfig.liveLatency`'s dartdoc](../../lib/src/models/streaming_config.dart) and the
[Live Streaming guide](live-streaming.md) for the full trade-off), and the inherited
`enableAdaptiveBitrate`/
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
route through `skipToIndex`). Re-issuing the same playlist is still not a way to *apply* a
changed config to the item playing right now: `setPlaylist` stores the snapshot but skips the
load when the item at `startIndex` is already loaded and in progress (see
[Extending a playlist in place](player-api.md#extending-a-playlist-in-place)) — use
`updateConfig()` or `load()` for that. See the
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
  `NetworkStatus.fromPlatform` honours the platform's `quality` field when it parses to a
  `NetworkQuality` member, falling back to `NetworkQuality.fromBandwidth(downloadSpeed)` only
  when `quality` is absent or unparseable (issue #112 — see the
  [`onNetworkStatusChanged` payload table](events.md#onnetworkstatuschanged) for the full
  contract and why this matters). `toMap()`/`fromPlatform()` round-trip `quality` symmetrically.
  **`downloadSpeed` is not a measurement on iOS.** Android's value derives from
  `NetworkCapabilities.linkDownstreamBandwidthKbps` (a system-provided hint, falling back to a
  fixed per-transport estimate only when that hint is absent or non-positive). iOS has no
  equivalent API on `NWPath`/`Network.framework` and *always* returns a fixed constant chosen
  purely from the active interface type (ethernet 50 Mbps, Wi-Fi 10 or 5 Mbps, cellular 2 Mbps,
  loopback 1000 Mbps, any other/unrecognized transport 1 Mbps) — it never reflects actual
  throughput. A consumer using `downloadSpeed` for adaptive-streaming or quality-selection
  decisions should treat it as a rough, interface-derived floor on iOS, not a bandwidth
  measurement. `connectionType` on iOS reports `"unknown"` (not `"none"`) for a *connected* path
  whose interface matched none of the recognized types — `"none"` is reserved for the two
  genuine offline paths — mirroring Android's `"unknown"` fallback in its own `connectionType`
  `when` block.
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
  `priority`, `dismissible`, and `customActions` remain **Android only**. A
  `NotificationConfig` reaches native only at `NotificationService.initialize()`; to change any
  of these at runtime call `NotificationService.updateConfig(config, playerId:)`, which
  re-sends it and re-renders a showing notification (`show()` alone renders from whatever
  config native already holds).
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

#### `toMap()` returns copies, not live references

`toMap()` never hands out a reference to the model's own collection fields. Every
collection-valued entry — `DrmConfig.headers` / `.customData`, `MediaItem.httpHeaders` /
`.metadata`, `SubtitleTrack.metadata`, `CastDevice.capabilities`,
`PerformanceMetrics.context` — is copied on the way out, so mutating the returned payload
can never mutate the model, and two `toMap()` calls never share the same inner collection:

```dart
const item = MediaItem(
  id: '1',
  title: 'Test',
  url: 'https://example.com/video.mp4',
  httpHeaders: {'Cookie': 'signed=1'},
);

final map = item.toMap();
(map['httpHeaders'] as Map<String, String>)['Cookie'] = 'tampered';

print(item.httpHeaders); // {Cookie: signed=1} — unchanged
```

Two caveats:

- The copies are **shallow**. A collection nested *inside* a `Map<String, dynamic>` value
  (e.g. `metadata: {'chapters': [...]}`) is still shared with the model; only the top-level
  map/list is duplicated.
- The **fields are not copied at construction**. These constructors are `const`, so a
  caller that keeps a reference to the map it passed in can still mutate the model through
  it. Pass a map you do not retain, or pass `Map.unmodifiable(...)`, if that matters to you.

A `null` collection field still serializes as a **present key with a `null` value** — it is
never widened to an empty collection — so the MethodChannel payload shape is unchanged.

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
