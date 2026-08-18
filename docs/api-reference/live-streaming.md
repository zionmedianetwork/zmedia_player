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

> **`HlsConfig` and `DashConfig` are not currently wired to native code.** `enableLiveStream`,
> `enableDvr`, `liveLatency`, `enableSegmentPrefetch`, `maxPrefetchSegments`,
> `enableMpdCaching`, `mpdCacheExpiration`, `enableAdaptiveBitrate`, `bitrateStrategy`,
> `maxBitrate`/`minBitrate`, `enableAutoQualitySwitch`, and `qualitySwitchThreshold` are real,
> constructible Dart classes/fields — but `MediaPlayer.load()` never sends them over the
> platform channel, and neither the Android `HlsMediaSource.Factory`/`DashMediaSource.Factory`
> construction nor the iOS `AVPlayerItem` construction path reads them. Setting
> `MediaConfig.hlsConfig` / `MediaConfig.dashConfig` today has **no effect on playback** —
> nothing in this guide that references those fields currently changes native behavior. They
> are kept in the examples below only because that is the intended shape of a future,
> not-yet-implemented wiring; every claim about what they currently *do* has been removed.
> `isLive` itself is metadata only — it is not read by native code to alter playback either.

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
| Seeking within the live window / DVR | Whatever the manifest itself allows (its sliding window / `EXT-X-PLAYLIST-TYPE`) — not controlled by any flag in this package | Same |
| `HlsConfig`/`DashConfig` tuning (latency target, DVR toggle, prefetch count, ABR strategy) | Not wired — no effect | Not wired — no effect |
| Adaptive bitrate for HLS | ExoPlayer's own default track selection | AVPlayer's own default track selection |

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
wired to native `load()` — use it instead of `HlsConfig.streamingHeaders`, which is not read:

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

Whether you can seek backward at all, and how far, depends entirely on the manifest's own
live window — there is no package-level DVR toggle to enable or disable it.

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
    _controller = MediaController.create();
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

Seeking availability is a property of the manifest itself (its live window /
`EXT-X-PLAYLIST-TYPE:EVENT` for HLS, its DASH `timeShiftBufferDepth`), not something this
package can enable or disable. Check:
- The stream manifest actually declares a live window / DVR buffer
- You are seeking within that window — seeking earlier than the window start will fail or
  clamp, depending on the native player

### High latency behind live edge / frequent buffering

Latency and buffering are governed entirely by ExoPlayer's/AVPlayer's own defaults for the
manifest — there is no `liveLatency` or prefetch knob in this package that changes them
today. Reducing your CDN's segment duration and target latency at the encoder/packager level,
and using an LL-HLS-compliant manifest, are the levers that actually affect this.

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

**Status:** Active development — feature-complete, native layers need on-device verification
