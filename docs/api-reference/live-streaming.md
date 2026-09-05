# Live Streaming Guide

Complete guide to implementing live streaming with ZMedia Player.

---

## Overview

ZMedia Player plays live HLS and DASH manifests through the same `load()` path as VOD
content — set `MediaItem.isLive: true` and load the live manifest URL. Live playback quality
(live-edge behavior, seekable/DVR window, buffering, latency, and adaptive bitrate switching)
is governed entirely by the native player's own defaults for the manifest you give it —
ExoPlayer/Media3 on Android, AVPlayer on iOS — not by any configuration this package applies
on top.

> **`HlsConfig` and `DashConfig` are now partially wired to native code.** `MediaConfig.hlsConfig`
> / `MediaConfig.dashConfig` cross the platform channel and native reads a subset of their
> fields — see the table below for exactly which:
>
> | Field | Wired? | Android | iOS |
> |---|---|---|---|
> | `enableDvr` | **Yes** | Dart-side gate: `MediaPlayer.isSeekable`/`seekTo` reject seeking on a live item unless set (see [Seeking and live-edge detection](#seeking-and-live-edge-detection)). Native-side: once set, the current `Timeline.Window.durationMs` (the DVR window length) is reported as `PlaybackState.duration`, re-derived on every `onTimelineChanged` since a live window grows over time. Does not change what ExoPlayer itself does with the live window otherwise. | Same Dart-side gate; native derives the same window-length duration from `AVPlayerItem.seekableTimeRanges` (re-checked on every position tick, since `AVPlayerItem.duration` is indefinite for a live item and never fires the usual duration KVO) |
> | `liveLatency` | **Yes** | `MediaItem.LiveConfiguration.setTargetOffsetMs` — a *maintained* target: ExoPlayer adjusts playback speed to drift toward it over time. But see [Manifest time-anchor defect](#manifest-time-anchor-defect-liveedgeoffset-and-livelatency) below: a manifest whose unix-time anchor disagrees with its own segment timeline silently defeats this target on Android | `AVPlayerItem.configuredTimeOffsetFromLive` (iOS 14+ only — no effect on iOS 13) — a **join-time only** setting: honored once when playback starts (or on a seek to the live edge), never re-applied afterward. This package also sets `automaticallyPreservesTimeOffsetFromLive = false`, an independent AVFoundation setting that controls whether the player skips forward to restore the cushion after a rebuffer; `false` means it does not, so the playhead drifts **away** from the configured cushion after every rebuffer instead of holding it (see [dartdoc on `HlsConfig.liveLatency`](../../lib/src/models/streaming_config.dart) for the full trade-off — `true` would trade this drift for a visible forward skip after each rebuffer, and revisiting that choice is an open question, not a settled one) |
> | `enableAdaptiveBitrate` | **Yes (Android only)** | `DefaultTrackSelector` — `false` forces a single fixed track instead of ABR | Not honored — AVPlayer has no API to disable ABR |
> | `maxBitrate` | **Yes** | `DefaultTrackSelector.setMaxVideoBitrate` | `AVPlayerItem.preferredPeakBitRate` |
> | `minBitrate` | **Yes (Android only)** | `DefaultTrackSelector.setMinVideoBitrate` | Not honored — no faithful AVPlayer equivalent |
> | `streamingFormat` (on `MediaItem`, not on the streaming config) | **Yes** | Selects which of `hlsConfig`/`dashConfig` applies, and which Media3 `MediaSource` is built (`HlsMediaSource`/`DashMediaSource`/`ProgressiveMediaSource`), overriding URL inference | Selects which of `hlsConfig`/`dashConfig` applies, and whether the HLS manifest is parsed for quality tracks |
> | `enableLiveStream` | Deprecated | Not read by native. OR'd into `MediaPlayer.isLive` on the Dart side only — use `MediaItem.isLive` instead | Same |
> | `bitrateStrategy`, `enableAutoQualitySwitch`, `qualitySwitchThreshold`, `enableBandwidthEstimation` | No | Not read by either platform — see `StreamingConfig`'s dartdoc | Same |
>
> `HlsConfig.streamingHeaders`/`DashConfig` prefetch/MPD-caching fields (`enableSegmentPrefetch`,
> `maxPrefetchSegments`, `enableMpdCaching`, `mpdCacheExpiration`) never had an honest native
> implementation and were removed rather than shipped as silent no-ops — use `MediaItem.httpHeaders`
> for headers (see [below](#custom-headers-for-authenticated-live-manifests)) and
> `AdaptiveCacheConfig` for segment caching instead.
>
> **Reloading with a changed config actually takes effect — on every load path.**
> `MediaPlayer.load()`, `setPlaylist()` and `skipToIndex()` each carry the current
> `MediaConfig` snapshot (including `hlsConfig`/`dashConfig`) with every call, not only at
> `initialize()`/`updateConfig()` time — so toggling `enableDvr`/`liveLatency`/the bitrate
> bounds and loading again is honored immediately, whether you reload a single `MediaItem` or
> load/advance a playlist. `skipToNext`, `skipToPrevious` and playlist auto-advance on
> completion all route through `skipToIndex`, so they carry it too. Native replaces its stored
> config from the snapshot before any config-dependent work; the key is optional on the native
> side, so an older native build simply ignores it and behaves as before.
>
> One nuance for playlists: re-issuing the *same* playlist is not a way to force a reload.
> `setPlaylist` skips the load entirely when the item at `startIndex` is the item already
> loaded and still in progress (see
> [Extending a playlist in place](player-api.md#extending-a-playlist-in-place)). The new
> config snapshot is still stored in that case — the next real load uses it — but the item
> keeps playing with the streaming config it was loaded under. Call `updateConfig()` to apply
> a config change to live playback immediately, or `load()` on the item to apply it *and*
> reload.

`StreamingService` (`lib/src/services/streaming_service.dart`) is a related but separate,
**Dart-only** helper for bandwidth-based quality-track *recommendation* math (moving-average
bandwidth, threshold-based track selection). It is not connected to the native
`bandwidthStream` or to `setQualityTrack` automatically — see
[Monitoring connection quality](#monitoring-connection-quality) below for what wiring it
actually requires.

---

## Table of Contents

- [What actually works today](#what-actually-works-today)
- [Loading a live stream](#loading-a-live-stream)
- [Choosing which streaming config applies (`streamingFormat`)](#choosing-which-streaming-config-applies-streamingformat)
- [Seeking and live-edge detection](#seeking-and-live-edge-detection)
- [Knowing which timeline `position` is on](#knowing-which-timeline-position-is-on)
- [Stall watchdog for live streams](#stall-watchdog-for-live-streams)
- [Manifest time-anchor defect (`liveEdgeOffset` and `liveLatency`)](#manifest-time-anchor-defect-liveedgeoffset-and-livelatency)
- [Monitoring connection quality](#monitoring-connection-quality)
- [Complete example](#complete-example)
- [Troubleshooting](#troubleshooting)

---

## What actually works today

### Platform support

| Feature | Android | iOS |
|---------|---------|-----|
| HLS live playback | Yes (Media3 default live handling) | Yes (AVPlayer default live handling) |
| DASH live playback | Yes (Media3) | **No** — AVPlayer/AVFoundation has no MPEG-DASH support at all, regardless of configuration |
| Seeking within the live window | Whatever the manifest itself allows (its sliding window / `EXT-X-PLAYLIST-TYPE`) | Same |
| `enableDvr` (this package's own seek gate) | `MediaPlayer.isSeekable`/`seekTo` reject seeking on a live item unless `enableDvr: true` | Same |
| DVR window duration (`controller.duration` for a live item) | Reported once `enableDvr: true` — the live window's current known length, re-derived as it grows; `0`/unknown when DVR is off | Same, derived from `seekableTimeRanges` |
| `liveLatency` target | Wired, and *maintained* — ExoPlayer drifts playback speed toward it over time (no effect on a manifest with an inconsistent time anchor — see [below](#manifest-time-anchor-defect-liveedgeoffset-and-livelatency)) | Wired on iOS 14+ — `configuredTimeOffsetFromLive`, but **join-time only**: honored once at start/seek, then never restored — the playhead drifts *away* from it after every rebuffer (`automaticallyPreservesTimeOffsetFromLive` is deliberately `false`; see the wiring table above) |
| `maxBitrate` cap | Wired — `DefaultTrackSelector` | Wired — `preferredPeakBitRate` |
| `enableAdaptiveBitrate: false` / `minBitrate` | Wired — `DefaultTrackSelector` | Not honored — no faithful AVPlayer API |
| Adaptive bitrate for HLS | ExoPlayer's own track selection, constrained by `maxBitrate`/`minBitrate` when set | AVPlayer's own track selection, capped by `maxBitrate` when set |

Because DASH has no iOS path at all, a DASH manifest should only ever be loaded on Android in
your own platform-branching logic. Note that an app doing exactly this — HLS on iOS, DASH on
Android — must configure **both** `hlsConfig` and `dashConfig`; see
[Choosing which streaming config applies](#choosing-which-streaming-config-applies-streamingformat).

---

## Loading a live stream

```dart
import 'package:zmedia_player/zmedia_player.dart';

final controller = MediaController.create();

final liveStream = MediaItem(
  id: 'live_hls',
  title: 'Live Event',
  url: 'https://your-cdn.com/live/stream.m3u8',
  isLive: true, // metadata only — does not change native playback behavior
);

await controller.load(liveStream);
await controller.play();
```

DASH is the same shape, Android only:

```dart
final liveStream = MediaItem(
  id: 'live_dash',
  title: 'Live Event',
  url: 'https://your-cdn.com/live/stream.mpd',
  isLive: true,
);
```

If your manifest URL does not end in `.m3u8`/`.mpd` (CDN rewrite, signed URL, extension-less
endpoint), add `streamingFormat:` so the right streaming config is applied — see
[Choosing which streaming config applies](#choosing-which-streaming-config-applies-streamingformat).

### Custom headers for authenticated live manifests

`MediaItem.httpHeaders` (or `MediaConfig.httpHeaders`) is the header path that is actually
wired to native `load()`. `StreamingConfig` has no headers field of its own — it was removed
(it was never read by native); use `MediaItem.httpHeaders` for authenticated manifest/segment
requests:

```dart
final liveStream = MediaItem(
  id: 'live_event',
  title: 'Live Event',
  url: 'https://your-cdn.com/live/stream.m3u8',
  isLive: true,
  httpHeaders: const {
    'Authorization': 'Bearer YOUR_TOKEN',
    'X-Session-ID': 'session_123',
  },
);
```

---

## Choosing which streaming config applies (`streamingFormat`)

Exactly one of `MediaConfig.hlsConfig` / `MediaConfig.dashConfig` applies to a given
`MediaItem`, and it decides whether `enableDvr`, `liveLatency` and the bitrate bounds reach
the player at all. Which one applies follows the item's **resolved streaming format**
(`MediaItem.resolvedStreamingFormat`):

1. **`MediaItem.streamingFormat`, if you set it** — `StreamingFormat.hls`,
   `StreamingFormat.dash` or `StreamingFormat.progressive`. An explicit value always wins,
   on the Dart side and on both native platforms.
2. **Otherwise, inference from the URL's *path*.** The query string and fragment are stripped
   first, then the path is matched case-insensitively with `endsWith`: `.m3u8` → HLS, `.mpd` →
   DASH, anything else → progressive. A malformed URL never throws; it resolves to
   progressive.

Because the match is `endsWith` on the path, a signed URL such as
`…/manifest.mpd?token=abc.m3u8` resolves to DASH, and a rewritten path such as
`/hls.m3u8-archive/eu/manifest.mpd` resolves to DASH rather than HLS. (Before v0.3.1 the rule
was `url.contains('.m3u8')` tested before `url.contains('.mpd')`, which got both of those
wrong.)

Set `streamingFormat` explicitly whenever your URL is not self-describing — a CDN rewrite, a
signed URL whose path is masked, or an extension-less manifest endpoint:

```dart
final liveStream = MediaItem(
  id: 'live_dash',
  title: 'Live Event',
  // Nothing in this path says "DASH"; say so explicitly.
  url: 'https://your-cdn.com/live/eu/primary?token=abc',
  isLive: true,
  streamingFormat: StreamingFormat.dash,
);
```

`StreamingFormat.progressive` is also meaningful as an explicit value: it opts an item out of
every streaming config, even if its URL ends in `.m3u8`/`.mpd`.

### The two configs are never cross-applied

If your backend serves **HLS to one platform and DASH to another** (a common setup: `.m3u8`
for iOS, `.mpd` for Android), you must set **both** `hlsConfig` and `dashConfig`. Setting only
`hlsConfig` leaves DASH items with *no* streaming config at all, so `enableDvr` is `false`
there — which in turn makes the item non-seekable and suppresses the live-window duration:

```dart
final controller = MediaController.create(
  config: const MediaConfig(
    hlsConfig: HlsConfig(enableDvr: true, liveLatency: Duration(seconds: 6)),
    dashConfig: DashConfig(enableDvr: true, liveLatency: Duration(seconds: 6)),
  ),
);
```

The package deliberately does *not* fall back to `hlsConfig` for a DASH item — silently
applying an HLS config to a DASH stream would just replace one invisible surprise with
another. Instead, in **debug builds only**, loading a live item that resolves to a format
whose config is `null` logs a one-time warning per format, e.g.:

```text
MediaPlayer(player_1): WARNING - live item "live_dash" resolved to StreamingFormat.dash
(inferred from its URL), but MediaConfig.dashConfig is null. enableDvr therefore falls back
to false, so this stream is not seekable (MediaPlayer.isSeekable == false, seekTo throws
InvalidStateException) and no live-window duration is reported. To enable DVR, pass
dashConfig: DashConfig(enableDvr: true, ...) ...
```

The warning is compiled out of release builds and logged at most once per resolved format per
player instance, so reloading a misconfigured item does not spam the log.

---

## Seeking and live-edge detection

This package rejects `seekTo` outright on a live item unless DVR is explicitly enabled — set
`enableDvr: true` on whichever streaming config matches the item's
[resolved streaming format](#choosing-which-streaming-config-applies-streamingformat)
(`HlsConfig` for HLS, `DashConfig` for DASH):

```dart
final controller = MediaController.create(
  config: const MediaConfig(hlsConfig: HlsConfig(enableDvr: true)),
);
```

`MediaPlayer.isSeekable` reflects this: `false` for a live item unless `enableDvr` was set on
the config that matched its resolved streaming format at `load()` time (see `dvrEnabled`). This is purely a
Dart-side gate — how *far* you can actually seek, once allowed through, still depends entirely
on the manifest's own live window (its sliding window / `EXT-X-PLAYLIST-TYPE` for HLS, its DASH
`timeShiftBufferDepth`); this package does not extend or shrink that window itself.

With `enableDvr: true`, `controller.duration` for a live item is the DVR window's current
known length (not the total time the stream has been broadcasting, which is unbounded) —
expect it to grow over time as more of the window becomes available, and treat `0`/unknown as
"nothing known about the window yet" rather than "the stream just started." Without
`enableDvr: true`, duration stays unreported (`0`) for a live item, matching `isSeekable ==
false`. `controller.position` is always reported relative to the *start* of that window on both
platforms (Android's `ExoPlayer.getCurrentPosition()` is window-relative already; iOS
translates `AVPlayerItem.currentTime()`, which is on an absolute timeline, into the same
window-relative unit), so `position` and `duration` share the same zero point and
`controller.duration` works as a "jump to live edge" target on both platforms.

> **That window-relative basis has a cost.** Because the window *start* also slides forward,
> a playhead healthily riding the live edge reports a roughly **constant** `position` — which
> is indistinguishable, from `position` alone, from a genuinely frozen playhead. Do not build
> a stall detector on `position`. Use `liveEdgeOffset` / `positionBasis` instead; see
> [Stall watchdog for live streams](#stall-watchdog-for-live-streams).

```dart
// Seek back 30 seconds, if the manifest's live window covers it
await controller.seekTo(controller.position - const Duration(seconds: 30));

// Jump to the current live edge (the end of the current duration)
await controller.seekTo(controller.duration);
```

### How far behind the live edge am I?

Do **not** compute this yourself from `duration - position`. That arithmetic only
works when `enableDvr: true` (otherwise `duration` is `0`), and it measures the
end of the *known window*, which is not always the live edge. The package asks
the platform directly instead:

```dart
// Native-sourced, updated on the same ~500ms tick as position.
final Duration? behind = controller.liveEdgeOffset;  // null for VOD
final bool atEdge = controller.isAtLiveEdge;         // false for VOD
```

| API | Type | Value |
|-----|------|-------|
| `controller.liveEdgeOffset` / `player.liveEdgeOffset` / `state.liveEdgeOffset` | `Duration?` | Distance behind the live edge. `null` for VOD, and for a live item the platform cannot answer for yet. Reported for live streams **with and without** `enableDvr`. |
| `controller.isAtLiveEdge` / `player.isAtLiveEdge` / `state.isAtLiveEdge` | `bool` | `liveEdgeOffset <= PlaybackState.defaultLiveEdgeTolerance`. Always `false` when the offset is `null`. |
| `state.isAtLiveEdgeWithin(tolerance)` | `bool` | Same test with a caller-supplied tolerance. |
| `PlaybackState.defaultLiveEdgeTolerance` | `Duration` | **15 seconds.** |

**Why 15 seconds, and when to change it.** A healthy live player does *not* sit
at an offset of zero. A standard (non-low-latency) HLS or DASH player
deliberately rides roughly three target segment durations behind the edge —
commonly 15-30s — so a tolerance of a second or two would report
`isAtLiveEdge == false` for a perfectly healthy stream and light up a
"jump to live" button that does nothing useful. 15 seconds is the same default
[video.js uses for its equivalent `liveTolerance` option][videojs-live-tolerance],
and it absorbs ordinary edge jitter (an ABR switch, a segment boundary) without
flapping a LIVE badge, while still going `false` once a viewer has scrubbed
meaningfully back into a DVR window. Tighten it for low-latency HLS/DASH, widen
it for long-segment streams:

```dart
final atEdge = controller.state.isAtLiveEdgeWithin(const Duration(seconds: 4)); // LL-HLS
```

[videojs-live-tolerance]: https://videojs.com/guides/live/

Natively, `liveEdgeOffset` comes from `Player.getCurrentLiveOffset()` on Android
**when that value is sanity-checked against the live window and passes** —
falling back to `Timeline.Window.durationMs - Player.getCurrentPosition()`
when the platform-reported value is `C.TIME_UNSET`, **or** when it is larger
than the window's own known duration (impossible by construction, and a real
manifest defect — see
[Manifest time-anchor defect](#manifest-time-anchor-defect-liveedgeoffset-and-livelatency)
below). On iOS it is the end of `AVPlayerItem.seekableTimeRanges.last` minus
`AVPlayerItem.currentTime()`, which is bounded by construction (both operands
share the item's own timeline, with no unix-time anchor involved) and needs no
such check. It arrives on the existing `onPositionChanged` event under the
`liveEdgeOffset` key — see [Events](events.md#onpositionchanged).

```dart
// LIVE badge / "jump to live" affordance
if (controller.isAtLiveEdge)
  const Chip(label: Text('LIVE'))
else
  ElevatedButton(
    onPressed: () => controller.seekTo(controller.duration),
    child: const Text('Go to Live'),
  )
```

---

## Knowing which timeline `position` is on

`PlaybackState.positionBasis` (a `PositionBasis`) reports which timeline
`position` is currently measured against, so a host never has to infer it from
its own `MediaConfig`:

| Value | `position` is measured from | Does a constant `position` mean a stall? |
|-------|-----------------------------|------------------------------------------|
| `PositionBasis.absolute` | The start of the media — a fixed zero point | **Yes** |
| `PositionBasis.liveWindow` | The start of the live/DVR window, which itself slides forward in wall-clock time | **No** — that is what a healthy live edge looks like |

Which value you get, per case:

| Case | Android | iOS |
|------|---------|-----|
| VOD | `absolute` | `absolute` |
| Live, `enableDvr: false` | `liveWindow` | `absolute` |
| Live, `enableDvr: true` | `liveWindow` | `liveWindow` |

The live-without-DVR row genuinely differs by platform, and that is deliberate.
ExoPlayer's `getCurrentPosition()` is window-relative for *any* live item, DVR
or not; on iOS the plugin only translates `AVPlayerItem.currentTime()` into
window-relative units when the DVR window is in play, so without DVR position
stays on the item's own absolute timeline. Each platform reports the basis its
values are actually on — which is precisely why you should branch on
`positionBasis` rather than on your own `enableDvr` flag.

`positionBasis` is `PositionBasis.absolute` between a `load()` and the first
native position event, and on any older cached native build that predates the
field. `state.isPositionWindowRelative` is shorthand for
`positionBasis == PositionBasis.liveWindow`.

---

## Stall watchdog for live streams

This is the pattern the live-edge API exists for. **Sampling `position` and
escalating when it stops advancing is wrong for live streams** — on
`PositionBasis.liveWindow` the playhead and the window start advance together,
so a healthy live edge reports a roughly constant `position` and a naive
watchdog escalates forever (reload -> re-auth -> hard reopen, minting a new
native player every lap).

The reliable signal is `liveEdgeOffset`. Against a genuinely frozen playhead in
a sliding window it **grows without bound**; at a healthy edge it stays bounded
and jitters around the target latency.

```dart
import 'dart:async';
import 'package:zmedia_player/zmedia_player.dart';

/// Escalating stall watchdog that is correct for VOD, live-without-DVR and
/// live-with-DVR alike, because it branches on what the player reports rather
/// than on the app's own config.
class LiveStallWatchdog {
  LiveStallWatchdog(this.controller, {required this.onEscalate});

  final MediaController controller;
  final void Function(int level) onEscalate;

  /// Escalate once the playhead has fallen this far behind the live edge.
  /// Must comfortably exceed your stream's normal live latency — a standard
  /// HLS stream sits 15-30s behind the edge when perfectly healthy.
  static const _liveEdgeStallThreshold = Duration(seconds: 45);

  /// Absolute-basis fallback: how many consecutive samples `position` may
  /// repeat before we call it a stall. 6 x 2s = 12s of no progress.
  static const _absoluteStallSamples = 6;

  Timer? _timer;
  Duration? _lastPosition;
  int _repeats = 0;
  int _level = 0;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _sample());
  }

  void _sample() {
    // Only judge liveness while the player claims to be playing. A user pause
    // is not a stall.
    if (controller.state.state != PlayerState.playing) {
      _reset();
      return;
    }

    final stalled = controller.positionBasis == PositionBasis.liveWindow
        ? _liveWindowStalled()
        : _absoluteStalled();

    if (!stalled) {
      _reset();
      return;
    }

    _level++;
    onEscalate(_level);
  }

  /// On a sliding window, position is expected to be constant. Judge on the
  /// distance from the live edge instead: healthy playback keeps it bounded.
  bool _liveWindowStalled() {
    final offset = controller.liveEdgeOffset;

    // The platform cannot answer yet (playlist just loaded, or an older
    // native build). Fall back to the position-repeat heuristic rather than
    // guessing — but note it is weak on this basis, so it is only reached
    // when there is genuinely nothing better.
    if (offset == null) return _absoluteStalled();

    // Riding the edge: unambiguously healthy, whatever position is doing.
    if (controller.isAtLiveEdge) return false;

    return offset > _liveEdgeStallThreshold;
  }

  /// On an absolute basis (VOD, and live-without-DVR on iOS), a position that
  /// stops advancing really is a stall.
  bool _absoluteStalled() {
    final position = controller.position;
    if (position == _lastPosition) {
      _repeats++;
    } else {
      _lastPosition = position;
      _repeats = 0;
    }
    return _repeats >= _absoluteStallSamples;
  }

  void _reset() {
    _lastPosition = controller.position;
    _repeats = 0;
    _level = 0;
  }

  void dispose() => _timer?.cancel();
}
```

Wiring it up:

```dart
final watchdog = LiveStallWatchdog(
  controller,
  onEscalate: (level) async {
    switch (level) {
      case 1:
        await controller.load(currentItem);          // in-place reload
      case 2:
        await controller.load(await refreshedItem()); // fresh credentials
      default:
        await rebuildPlayerWithNewId();               // discard the controller
    }
  },
)..start();

// ...
watchdog.dispose();
```

**Platform notes for watchdog authors:**

- **Android** keeps emitting position events while playback is stalled but the
  host still intends to play (`playWhenReady && STATE_BUFFERING`), so
  `liveEdgeOffset` visibly grows through a rebuffer. It stays silent while
  genuinely paused, idle or ended.
- **iOS** drives position from `AVPlayer.addPeriodicTimeObserver`, which only
  fires while time is progressing. During a hard stall, updates stop entirely,
  so `liveEdgeOffset` freezes at its last value rather than growing. On iOS,
  also treat "no position/state event at all for several sampling intervals
  while `state == PlayerState.playing`" as a stall signal.
- `liveEdgeOffset` is `null` for VOD, so `isAtLiveEdge` is always `false`
  there — never use `isAtLiveEdge` as a proxy for "is this a live stream"; use
  `player.isLive` or `positionBasis` for that.

**Seeing these fields on a real device.** The example app's
`pages/wired_config_verification_page.dart` renders `liveEdgeOffset`,
`isAtLiveEdge`, `positionBasis`, and whether the offset is bounded by
`duration` as their own rows, plus a color-coded banner naming which case
you're looking at (defect/anomaly, healthy live edge, or VOD) — the only way
to confirm any of this by eye, since CI never builds native code and every
test in the package/example suites mocks the `MethodChannel`.

---

## Manifest time-anchor defect (`liveEdgeOffset` and `liveLatency`)

This is a manifest/packaging defect this package can detect and route around for
`liveEdgeOffset`, but cannot fix for `liveLatency` — the underlying arithmetic belongs to
Media3, and its input is the manifest.

**What it looks like.** On Android, `Player.getCurrentLiveOffset()` computes
`nowUnixTime - windowStartTime - position`. For DASH, `windowStartTime` derives from
`manifest.availabilityStartTimeMs`. Ordinarily that unix-time anchor and the manifest's own
segment timeline agree. If a packager anchors `availabilityStartTime` to when the broadcast
began, while re-basing the segment timeline to a rolling window (a live event that has been
running far longer than its DVR window covers is the common trigger), the two disagree —
`getCurrentLiveOffset()` then reports **broadcast age**, not distance from the live edge. It
returns a large, real number, not `C.TIME_UNSET`, so nothing about the value itself flags it
as wrong.

**Worked example (the real numbers this was diagnosed from — issues #109/#110).** A DASH DVR
stream (`suggestedPresentationDelay=PT18S`, `timeShiftBufferDepth=PT60S`, 6s segments)
reported:

```
liveEdgeOffset = 1973165ms  (~33 minutes)
position       = 57732ms
duration       = 61466ms    (the DVR window length)
```

The playhead was genuinely **~3.7s** from the edge (`duration - position`) — an offset of 33
minutes inside a 61-second window is impossible by construction. `liveLatency` was set to 18s,
read back correctly from `controller.config`, and had **zero measurable effect** on join
position or on how close to the edge playback settled (a probe at 45s produced an identical
result) — because `MediaItem.LiveConfiguration.targetOffsetMs` is computed from that same
poisoned anchor (`windowDefaultStartPositionUs`, derived from the same broken
`nowInWindowUs`), Media3 clamps the join to the real live edge regardless of the configured
target. The same broken offset also drives `DefaultLivePlaybackSpeedControl`, which compares it
against the target, sees ~33 minutes of "lag" and speeds up trying to close a gap that was
never real — eroding whatever cushion a join or a corrective `seekTo` established.

**How to detect it.**

- `liveEdgeOffset` (see [How far behind the live edge am I?](#how-far-behind-the-live-edge-am-i))
  is now sanity-checked against the live window's known duration on Android: a reported value
  larger than the window is rejected in favor of the bounded fallback
  (`duration - position`), which is unaffected by the anchor defect. So as of this fix,
  `controller.liveEdgeOffset` reads correctly (~3.7s in the example above) even on an affected
  manifest — you no longer need to guard against it app-side.
- The rejection itself is diagnostic: native logs a one-time-per-loaded-item warning (tag
  `MediaPlayerInstance`, `Log.w`) naming the observed offset, the window duration, and that
  `liveLatency` will not take effect on this stream — check `adb logcat` for it if `liveLatency`
  appears to do nothing. It is *not* emitted on the normal 500ms position tick — only once per
  item, the first time the mismatch is observed.
- `liveLatency` having no measurable effect on join position or steady-state cushion, on
  Android/DASH specifically, combined with chronic rebuffering, is the behavioral symptom (see
  [High latency behind live edge / frequent buffering](#high-latency-behind-live-edge--frequent-buffering)
  below).
- On device, the example app's `pages/wired_config_verification_page.dart` renders
  `liveEdgeOffset` and an explicit "offset <= duration" row against a real stream, so this
  fix (and the still-open issue #110 diagnostic) can be confirmed by eye rather than only via
  `adb logcat` — see the pointer in [Stall watchdog for live streams](#stall-watchdog-for-live-streams)
  above. That page's Source selector has a **Custom** option specifically for this: paste in
  the URL of a stream suspected of this defect (with an explicit `streamingFormat` override if
  the URL doesn't end in `.mpd`/`.m3u8` — see
  [Choosing which streaming config applies](#choosing-which-streaming-config-applies-streamingformat)
  — and an optional HTTP header for a signed/token-gated origin) and reload, rather than being
  limited to the app's own bundled fixtures.

**What to do about it.** Nothing in this package can correct the target offset on an affected
manifest — the join-position arithmetic belongs to Media3, and Media3's input is the
manifest's own (inconsistent) time anchor. This is a packager/origin-side defect: report it to
whoever operates the encoder/packager for the stream (an inconsistency between
`availabilityStartTime` and the segment timeline it publishes). As a stopgap, an app-side
corrective `seekTo(duration - desiredLatency)` after load can hold a cushion, but expect
`DefaultLivePlaybackSpeedControl` to erode it over time on the same stream, since it is working
from the same poisoned offset — periodic re-seeking is a treadmill, not a fix.

---

## Monitoring connection quality

`StreamingService` computes a recommended quality track from bandwidth samples you feed it —
it does not read the native bandwidth estimate on its own, and it does not call
`controller.setQualityTrack()` for you. Wiring it up end to end looks like this:

```dart
final streamingService = StreamingService(
  const StreamingConfig(
    enableBandwidthEstimation: true,
    enableAutoQualitySwitch: true,
  ),
);

// Feed it real bandwidth samples from the native estimate.
controller.player.bandwidthStream.listen(streamingService.updateBandwidth);

// Feed it the tracks the native player actually reported.
controller.player.qualityTracksStream.listen(streamingService.setAvailableQualityTracks);

// Act on its recommendation yourself — it does not call setQualityTrack for you.
streamingService.qualityStream.listen((recommended) {
  if (recommended != null) {
    controller.setQualityTrack(recommended);
  }
});
```

Dispose `streamingService` yourself when you are done with it — it is not owned by
`MediaController`/`MediaPlayer`.

### Handling network issues

```dart
controller.player.stateStream.listen((state) {
  if (state.state == PlayerState.buffering) {
    showBufferingIndicator();
  } else if (state.state == PlayerState.error) {
    handleStreamError(state.errorMessage);
  }
});
```

---

## Complete example

```dart
import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';

class LiveStreamPage extends StatefulWidget {
  const LiveStreamPage({super.key});

  @override
  State<LiveStreamPage> createState() => _LiveStreamPageState();
}

class _LiveStreamPageState extends State<LiveStreamPage> {
  late final MediaController _controller;
  bool _isAtLiveEdge = true;

  @override
  void initState() {
    super.initState();
    // enableDvr: true is required for seekTo/_jumpToLive below to work at
    // all — without it, isSeekable is false for a live item and seekTo
    // throws InvalidStateException.
    _controller = MediaController.create(
      config: const MediaConfig(hlsConfig: HlsConfig(enableDvr: true)),
    );
    _loadLiveStream();
    _listenToPosition();
  }

  Future<void> _loadLiveStream() async {
    final liveStream = MediaItem(
      id: 'live_event',
      title: 'Live Event',
      url: 'https://your-cdn.com/live/stream.m3u8',
      isLive: true,
    );

    await _controller.load(liveStream);
    await _controller.play();
  }

  void _listenToPosition() {
    _controller.player.positionStream.listen((position) {
      final duration = _controller.duration;
      final behindLive = (duration - position).inSeconds;

      setState(() {
        _isAtLiveEdge = behindLive < 5;
      });
    });
  }

  Future<void> _jumpToLive() async {
    await _controller.seekTo(_controller.duration);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Stream'),
        actions: [
          if (!_isAtLiveEdge)
            TextButton.icon(
              onPressed: _jumpToLive,
              icon: const Icon(Icons.fiber_manual_record, color: Colors.red),
              label: const Text('LIVE', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: MediaPlayerWidget(
              controller: _controller,
              showControls: true,
            ),
          ),
          // Your UI here
        ],
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

---

## Troubleshooting

### Can't seek within the live stream

First check `enableDvr: true` is set on the matching streaming config (`HlsConfig` for an item
that resolves to HLS, `DashConfig` for one that resolves to DASH — see
[Choosing which streaming config applies](#choosing-which-streaming-config-applies-streamingformat))
— without it, `seekTo` is rejected before it ever reaches native (see
[Seeking and live-edge detection](#seeking-and-live-edge-detection)). In debug builds, a live
item that resolved to a format with no config logs a warning saying exactly that; if your URL
does not end in `.m3u8`/`.mpd`, set `MediaItem.streamingFormat` explicitly. With `enableDvr: true`,
remaining seek availability is a property of the manifest itself (its live window /
`EXT-X-PLAYLIST-TYPE:EVENT` for HLS, its DASH `timeShiftBufferDepth`). Check:
- The stream manifest actually declares a live window / DVR buffer
- You are seeking within that window — seeking earlier than the window start will fail or
  clamp, depending on the native player

### `controller.duration` / notification scrubber stays at 0 for a live stream

Expected when `enableDvr` is not set — duration is only reported for a live item once DVR is
enabled on the matching streaming config (see the table above and
[Seeking and live-edge detection](#seeking-and-live-edge-detection)); it deliberately does not
report the unbounded, unknowable "time since the stream started broadcasting". If `enableDvr`
is already `true` and duration is still `0`, confirm it is set on the config for the format the
item actually resolved to (check the debug warning, or `MediaItem.resolvedStreamingFormat`),
and that the config actually reached native for *this* load — `load()`, `setPlaylist()` and
`skipToIndex()` all carry the current config snapshot on every call (see above), so a stale,
DVR-disabled config is only possible if the installed native build predates that wiring and
ignores the `config` key: rebuild the app so the native side matches this Dart package.

If you flipped `enableDvr` on an item that is *already playing*, re-issuing the same playlist
will not apply it: `setPlaylist` stores the new config but skips the reload when the start item
is already loaded and in progress. Call `updateConfig()`, or `load()` on the item, to apply it
now.

The same seekability gate also removes the notification's seek-forward/seek-backward controls:
`NotificationConfig.showSeekForward`/`showSeekBackward` are honoured only when the item is
seekable, so a live stream without DVR never shows them on either platform even if both flags
are `true`. Enabling `enableDvr` brings them back on the next notification update — no
re-initialize needed.

### My stall detector escalates forever on a healthy live stream

You are almost certainly sampling `controller.position`. On a live stream whose
`positionBasis` is `PositionBasis.liveWindow` (always on Android; on iOS whenever
`enableDvr: true`), the window start slides forward at the same rate as the playhead, so
`position` stays roughly **constant during perfectly healthy playback**. A watchdog that treats
"position stopped advancing" as a stall will reload, re-authenticate and hard-reopen the player
in an endless loop.

Branch on `controller.positionBasis` and judge liveness from `controller.liveEdgeOffset`
(which grows without bound against a genuinely frozen playhead) rather than from `position`.
See [Stall watchdog for live streams](#stall-watchdog-for-live-streams) for a complete,
copy-pasteable implementation covering VOD, live-without-DVR and live-with-DVR.

### `isAtLiveEdge` is false even though playback looks fine

`isAtLiveEdge` compares `liveEdgeOffset` against `PlaybackState.defaultLiveEdgeTolerance`
(15 seconds). Standard (non-low-latency) HLS/DASH streams with long target segment durations
legitimately ride 20-30s behind the edge. Widen the tolerance for your stream with
`controller.state.isAtLiveEdgeWithin(const Duration(seconds: 35))`, or reduce your segment
duration / switch to low-latency HLS if you actually want to be closer to the edge.

`isAtLiveEdge` is also always `false` for VOD (`liveEdgeOffset` is `null` there) — use
`player.isLive` to ask "is this live", not `isAtLiveEdge`.

If `liveEdgeOffset` instead reads as an implausibly large value — minutes, when `duration`
(the DVR window) is under a minute — that is not a tolerance problem; it is the manifest
time-anchor defect covered in
[Manifest time-anchor defect](#manifest-time-anchor-defect-liveedgeoffset-and-livelatency)
below. As of this fix, Android's `liveEdgeOffset` already falls back to a bounded computation
when it detects this, so a value larger than `duration` should not reach Dart any more; if you
still observe one, please file an issue with the manifest details.

### High latency behind live edge / frequent buffering

Set `liveLatency` on the matching streaming config to give the native player a target offset
from the live edge (`MediaItem.LiveConfiguration` on Android; `AVPlayerItem
.configuredTimeOffsetFromLive` on iOS 14+ — no effect on iOS 13). Beyond that target, actual
latency and buffering are still governed by ExoPlayer's/AVPlayer's own adaptive behavior for
the manifest. Reducing your CDN's segment duration at the encoder/packager level, and using an
LL-HLS-compliant manifest, are the other levers that affect this.

**On iOS specifically**, `liveLatency` only applies at join/seek time — it is not a maintained
target the way Android's is. This package sets `automaticallyPreservesTimeOffsetFromLive =
false`, so AVPlayer never skips forward to restore the configured cushion after a rebuffer; the
playhead is expected to drift further from the live edge, monotonically, as rebuffers
accumulate over a long session. This is not a bug to fix by retrying — it is the documented
behavior of the current configuration (see the wiring table and `HlsConfig.liveLatency`'s
dartdoc). If your app needs the cushion actively restored, track `liveEdgeOffset`/
`isAtLiveEdge` (see [Stall watchdog for live streams](#stall-watchdog-for-live-streams)) and
issue a corrective seek yourself; `automaticallyPreservesTimeOffsetFromLive` is not currently
exposed as a configuration option.

If `liveLatency` reaches native correctly (confirm via `controller.config`) but changing its
value has **no observable effect** on Android/DASH — join position and steady-state cushion stay
identical regardless of the configured target, alongside chronic rebuffering — check
`adb logcat` for the one-time `MediaPlayerInstance` warning about an inconsistent manifest time
anchor. This is a distinct, manifest-side defect, not a wiring bug; see
[Manifest time-anchor defect](#manifest-time-anchor-defect-liveedgeoffset-and-livelatency) above
for the full diagnosis and what to do about it.

### DASH does not load on iOS

Expected — AVPlayer has no MPEG-DASH decoder at all. Branch by platform and only ever load a
`.mpd` URL on Android.

### Sync issues between multiple viewers

Sync across viewers is a property of each viewer's live-edge distance under the native
player's own buffering behavior; this package does not offer a shared latency target to
coordinate it.

---

## Additional Resources

- **HLS Specification:** [RFC 8216](https://tools.ietf.org/html/rfc8216)
- **DASH Specification:** [ISO/IEC 23009-1](https://www.iso.org/standard/79329.html)
- **Low-Latency HLS:** [Apple Documentation](https://developer.apple.com/documentation/http_live_streaming/protocol_extension_for_low-latency_hls)

---

## Related Documentation

- [Getting Started](getting-started.md) - Basic setup
- [Events & Callbacks](events.md) - Stream events
- [Advanced Features](advanced-features.md) - Bandwidth & buffering streams

---

**Status:** Active development — `enableDvr` seek gating and DVR window duration reporting have
been verified on an Android device (Samsung Note 9P) against a live HLS stream with a real
601-second DVR window (`dumpsys media_session` showed `actions=311` with a 600960ms duration
when DVR was enabled, `actions=55` with `0` duration when it was not). The equivalent iOS
wiring (`seekableTimeRanges`-derived duration, position/seek translation,
`configuredTimeOffsetFromLive`) is implemented but not yet verified on a physical iOS device.
