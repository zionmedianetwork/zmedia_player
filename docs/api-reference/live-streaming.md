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
> | `liveLatency` | **Yes** | `MediaItem.LiveConfiguration.setTargetOffsetMs` | `AVPlayerItem.configuredTimeOffsetFromLive` (iOS 14+ only — no effect on iOS 13) |
> | `enableAdaptiveBitrate` | **Yes (Android only)** | `DefaultTrackSelector` — `false` forces a single fixed track instead of ABR | Not honored — AVPlayer has no API to disable ABR |
> | `maxBitrate` | **Yes** | `DefaultTrackSelector.setMaxVideoBitrate` | `AVPlayerItem.preferredPeakBitRate` |
> | `minBitrate` | **Yes (Android only)** | `DefaultTrackSelector.setMinVideoBitrate` | Not honored — no faithful AVPlayer equivalent |
> | `enableLiveStream` | Deprecated | Not read by native. OR'd into `MediaPlayer.isLive` on the Dart side only — use `MediaItem.isLive` instead | Same |
> | `bitrateStrategy`, `enableAutoQualitySwitch`, `qualitySwitchThreshold`, `enableBandwidthEstimation` | No | Not read by either platform — see `StreamingConfig`'s dartdoc | Same |
>
> `HlsConfig.streamingHeaders`/`DashConfig` prefetch/MPD-caching fields (`enableSegmentPrefetch`,
> `maxPrefetchSegments`, `enableMpdCaching`, `mpdCacheExpiration`) never had an honest native
> implementation and were removed rather than shipped as silent no-ops — use `MediaItem.httpHeaders`
> for headers (see [below](#custom-headers-for-authenticated-live-manifests)) and
> `AdaptiveCacheConfig` for segment caching instead.
>
> **Reloading with a changed config now actually takes effect.** `MediaPlayer.load()` carries
> the current `MediaConfig` snapshot (including `hlsConfig`/`dashConfig`) with every call, not
> only at `initialize()`/`updateConfig()` time — so toggling `enableDvr`/`liveLatency`/the
> bitrate bounds and calling `load()` again on the same or a new `MediaItem` is honored
> immediately. **Known limitation:** `setPlaylist`/`skipToIndex` still route through a
> single-argument native `loadMediaItem` call that does not carry a config snapshot, so
> per-item streaming config can be stale for playlist-driven items until the next explicit
> `load()` or `updateConfig()` call.

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
- [Seeking and live-edge detection](#seeking-and-live-edge-detection)
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
| `liveLatency` target | Wired — `MediaItem.LiveConfiguration` | Wired on iOS 14+ — `configuredTimeOffsetFromLive` |
| `maxBitrate` cap | Wired — `DefaultTrackSelector` | Wired — `preferredPeakBitRate` |
| `enableAdaptiveBitrate: false` / `minBitrate` | Wired — `DefaultTrackSelector` | Not honored — no faithful AVPlayer API |
| Adaptive bitrate for HLS | ExoPlayer's own track selection, constrained by `maxBitrate`/`minBitrate` when set | AVPlayer's own track selection, capped by `maxBitrate` when set |

Because DASH has no iOS path at all, a `.mpd` URL should only ever be loaded on Android in
your own platform-branching logic.

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

## Seeking and live-edge detection

This package rejects `seekTo` outright on a live item unless DVR is explicitly enabled — set
`enableDvr: true` on whichever streaming config matches your URL (`HlsConfig` for `.m3u8`,
`DashConfig` for `.mpd`):

```dart
final controller = MediaController.create(
  config: const MediaConfig(hlsConfig: HlsConfig(enableDvr: true)),
);
```

`MediaPlayer.isSeekable` reflects this: `false` for a live item unless `enableDvr` was set on
the config that matched its URL at `load()` time (see `dvrEnabled`). This is purely a
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
window-relative unit), so `position` and `duration` share the same zero point and the examples
below (`controller.duration` for "jump to live edge", `duration - position` for "how far behind
live") work identically on both platforms.

```dart
// Seek back 30 seconds, if the manifest's live window covers it
await controller.seekTo(controller.position - const Duration(seconds: 30));

// Jump to the current live edge (the end of the current duration)
await controller.seekTo(controller.duration);
```

```dart
// Detect how far behind live the current position is
controller.player.positionStream.listen((position) {
  final duration = controller.duration;
  final behindLive = (duration - position).inSeconds;
  final isAtLiveEdge = behindLive < 5;

  if (isAtLiveEdge) {
    print('Playing at live edge');
  } else {
    print('Playing ${behindLive}s behind live');
  }
});
```

```dart
ElevatedButton(
  onPressed: () async {
    await controller.seekTo(controller.duration);
  },
  child: const Text('Go to Live'),
)
```

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

First check `enableDvr: true` is set on the matching streaming config (`HlsConfig` for `.m3u8`,
`DashConfig` for `.mpd`) — without it, `seekTo` is rejected before it ever reaches native (see
[Seeking and live-edge detection](#seeking-and-live-edge-detection)). With `enableDvr: true`,
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
is already `true` and duration is still `0`, confirm the config actually reached native for
*this* load — `load()` carries the current config snapshot on every call, but
`setPlaylist`/`skipToIndex` do not yet (see the known limitation above), so a playlist-driven
live item can still see a stale, DVR-disabled config.

The same seekability gate also removes the notification's seek-forward/seek-backward controls:
`NotificationConfig.showSeekForward`/`showSeekBackward` are honoured only when the item is
seekable, so a live stream without DVR never shows them on either platform even if both flags
are `true`. Enabling `enableDvr` brings them back on the next notification update — no
re-initialize needed.

### High latency behind live edge / frequent buffering

Set `liveLatency` on the matching streaming config to give the native player a target offset
from the live edge (`MediaItem.LiveConfiguration` on Android; `AVPlayerItem
.configuredTimeOffsetFromLive` on iOS 14+ — no effect on iOS 13). Beyond that target, actual
latency and buffering are still governed by ExoPlayer's/AVPlayer's own adaptive behavior for
the manifest. Reducing your CDN's segment duration at the encoder/packager level, and using an
LL-HLS-compliant manifest, are the other levers that affect this.

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
