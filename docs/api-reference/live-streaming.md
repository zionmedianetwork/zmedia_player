# Live Streaming Guide

Complete guide to implementing live streaming with ZMedia Player.

---

## Overview

ZMedia Player provides comprehensive support for live streaming via both HLS (HTTP Live Streaming) and DASH (Dynamic Adaptive Streaming over HTTP) protocols. This includes low-latency playback, DVR functionality, and adaptive bitrate streaming optimized for live content.

---

## Table of Contents

- [Features](#features)
- [HLS Live Streaming](#hls-live-streaming)
- [DASH Live Streaming](#dash-live-streaming)
- [Configuration Options](#configuration-options)
- [DVR Functionality](#dvr-functionality)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

---

## Features

### What's Supported

- ✅ **HLS Live Streams** - Apple's HTTP Live Streaming protocol
- ✅ **DASH Live Streams** - MPEG-DASH for live content
- ✅ **Low-Latency Mode** - Configurable latency targets (2-10 seconds)
- ✅ **DVR/Time-Shifting** - Seek within live streams
- ✅ **Live Edge Detection** - Automatic positioning at live edge
- ✅ **Adaptive Bitrate** - Quality adaptation for live content
- ✅ **Segment Prefetching** - Smooth playback with buffering
- ✅ **Live Catchup** - Jump to live after seeking backwards

### Platform Support

| Feature | Android | iOS |
|---------|---------|-----|
| HLS Live | ✅ | ✅ |
| DASH Live | ✅ | ✅ |
| DVR | ✅ | ✅ |
| Low-Latency | ✅ | ✅ |

---

## HLS Live Streaming

### Basic Setup

```dart
import 'package:flutter_media_player/flutter_media_player.dart';

// Create controller with HLS live configuration
final controller = MediaController.create(
  config: MediaConfig(
    hlsConfig: HlsConfig(
      enableLiveStream: true,          // Enable live streaming mode
      enableDvr: true,                 // Allow seeking in live stream
      liveLatency: Duration(seconds: 3), // Target latency
      enableAdaptiveBitrate: true,     // Adaptive quality
      enableSegmentPrefetch: true,     // Prefetch segments
      maxPrefetchSegments: 3,          // Number to prefetch
    ),
  ),
);

// Load live HLS stream
final liveStream = MediaItem(
  id: 'live_hls',
  title: 'Live Event',
  url: 'https://your-cdn.com/live/stream.m3u8',
);

await controller.load(liveStream);
await controller.play();
```

### Low-Latency HLS

For ultra-low latency streaming (LL-HLS):

```dart
final llHlsConfig = HlsConfig(
  enableLiveStream: true,
  enableDvr: false,                    // Often disabled for LL-HLS
  liveLatency: Duration(seconds: 2),   // Ultra-low latency
  enableSegmentPrefetch: true,
  maxPrefetchSegments: 1,              // Minimal prefetch for LL
);
```

---

## DASH Live Streaming

### Basic Setup

```dart
// Create controller with DASH live configuration
final controller = MediaController.create(
  config: MediaConfig(
    dashConfig: DashConfig(
      enableLiveStream: true,          // Enable live streaming mode
      enableDvr: true,                 // Allow seeking in live stream
      liveLatency: Duration(seconds: 3), // Target latency
      enableAdaptiveBitrate: true,     // Adaptive quality
      enableMpdCaching: true,          // Cache MPD manifest
      mpdCacheExpiration: Duration(minutes: 5),
      enableSegmentPrefetch: true,
      maxPrefetchSegments: 3,
    ),
  ),
);

// Load live DASH stream
final liveStream = MediaItem(
  id: 'live_dash',
  title: 'Live Event',
  url: 'https://your-cdn.com/live/stream.mpd',
);

await controller.load(liveStream);
await controller.play();
```

### Low-Latency DASH

For CMAF-based low-latency DASH:

```dart
final llDashConfig = DashConfig(
  enableLiveStream: true,
  enableDvr: false,                    // Often disabled for LL-DASH
  liveLatency: Duration(seconds: 2),   // Ultra-low latency
  enableMpdCaching: false,             // Minimal caching for LL
  enableSegmentPrefetch: true,
  maxPrefetchSegments: 1,
);
```

---

## Configuration Options

### Live Stream Flags

#### `enableLiveStream` (bool)
**Default:** `false`  
**Purpose:** Main flag to enable live streaming mode

```dart
HlsConfig(enableLiveStream: true)  // Enable live mode
```

**Effects:**
- Disables end-of-stream detection
- Enables live edge tracking
- Adjusts buffering strategy for live content
- Enables manifest refresh for live updates

#### `enableDvr` (bool)
**Default:** `false`  
**Purpose:** Enable DVR/time-shifting functionality

```dart
HlsConfig(
  enableLiveStream: true,
  enableDvr: true,  // Allow seeking within live window
)
```

**When to Enable:**
- ✅ Sports events with replay needs
- ✅ News broadcasts with scrubbing
- ✅ Events where users may join late

**When to Disable:**
- ❌ Ultra-low latency streams
- ❌ Real-time betting/trading apps
- ❌ Interactive live content

#### `liveLatency` (Duration?)
**Default:** `null` (auto)  
**Purpose:** Target latency from live edge

```dart
HlsConfig(
  enableLiveStream: true,
  liveLatency: Duration(seconds: 3),  // 3 second target latency
)
```

**Recommended Values:**
- **Standard Live:** 5-10 seconds
- **Low-Latency:** 2-5 seconds
- **Ultra-Low Latency:** < 2 seconds

**Trade-offs:**
- Lower latency = More rebuffering risk
- Higher latency = Smoother playback

---

## DVR Functionality

### Enable DVR

```dart
final controller = MediaController.create(
  config: MediaConfig(
    hlsConfig: HlsConfig(
      enableLiveStream: true,
      enableDvr: true,  // Enable DVR
      liveLatency: Duration(seconds: 5),
    ),
  ),
);
```

### Seek Within Live Window

```dart
// Get current position and duration
final position = controller.position;
final duration = controller.duration;

// Seek back 30 seconds
await controller.seekTo(position - Duration(seconds: 30));

// Jump to live edge
await controller.seekTo(duration);
```

### Detect Live Edge

```dart
// Listen to position updates
controller.player.positionStream.listen((position) {
  final duration = controller.duration;
  final isAtLiveEdge = (duration - position).inSeconds < 5;
  
  if (isAtLiveEdge) {
    print('Playing at live edge');
  } else {
    print('Playing ${(duration - position).inSeconds}s behind live');
  }
});
```

### Jump to Live Button

```dart
ElevatedButton(
  onPressed: () async {
    // Jump to live edge
    await controller.seekTo(controller.duration);
  },
  child: Text('Go to Live'),
)
```

---

## Best Practices

### 1. Choose Appropriate Latency

```dart
// For most use cases
HlsConfig(
  enableLiveStream: true,
  liveLatency: Duration(seconds: 5),  // Good balance
)

// For interactive events (gaming, betting)
HlsConfig(
  enableLiveStream: true,
  liveLatency: Duration(seconds: 2),  // Lower latency
  enableDvr: false,                    // Disable DVR
)

// For standard broadcasts
HlsConfig(
  enableLiveStream: true,
  liveLatency: Duration(seconds: 10), // More stable
  enableDvr: true,                     // Enable DVR
)
```

### 2. Handle Network Issues

```dart
controller.player.stateStream.listen((state) {
  if (state.state == PlayerState.buffering) {
    // Show buffering indicator
    showBufferingIndicator();
  } else if (state.state == PlayerState.error) {
    // Handle error, maybe retry
    handleStreamError(state.errorMessage);
  }
});
```

### 3. Monitor Connection Quality

```dart
// Create streaming service for bandwidth monitoring
final streamingService = StreamingService(
  StreamingConfig(
    enableBandwidthEstimation: true,
    enableAutoQualitySwitch: true,
  ),
);

streamingService.bandwidthStream.listen((bandwidth) {
  print('Bandwidth: ${streamingService.getFormattedBandwidth()}');
  
  // Adjust latency based on bandwidth
  if (bandwidth < 1000000) { // < 1 Mbps
    // Consider increasing latency for stability
  }
});
```

### 4. Prefetch Strategy

```dart
// For stable connections
HlsConfig(
  enableSegmentPrefetch: true,
  maxPrefetchSegments: 3,  // Prefetch more segments
)

// For low-latency or unstable connections
HlsConfig(
  enableSegmentPrefetch: true,
  maxPrefetchSegments: 1,  // Minimal prefetch
)
```

### 5. Custom Headers for Authentication

```dart
final controller = MediaController.create(
  config: MediaConfig(
    hlsConfig: HlsConfig(
      enableLiveStream: true,
      streamingHeaders: {
        'Authorization': 'Bearer YOUR_TOKEN',
        'X-Session-ID': 'session_123',
      },
    ),
  ),
);
```

---

## Complete Example

```dart
import 'package:flutter/material.dart';
import 'package:flutter_media_player/flutter_media_player.dart';

class LiveStreamPage extends StatefulWidget {
  @override
  _LiveStreamPageState createState() => _LiveStreamPageState();
}

class _LiveStreamPageState extends State<LiveStreamPage> {
  late MediaController _controller;
  bool _isAtLiveEdge = true;
  
  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }
  
  void _initializePlayer() {
    _controller = MediaController.create(
      config: MediaConfig(
        hlsConfig: HlsConfig(
          enableLiveStream: true,
          enableDvr: true,
          liveLatency: Duration(seconds: 5),
          enableAdaptiveBitrate: true,
          enableSegmentPrefetch: true,
          maxPrefetchSegments: 3,
        ),
      ),
    );
    
    _loadLiveStream();
    _listenToPosition();
  }
  
  Future<void> _loadLiveStream() async {
    final liveStream = MediaItem(
      id: 'live_event',
      title: 'Live Event',
      url: 'https://your-cdn.com/live/stream.m3u8',
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
        title: Text('Live Stream'),
        actions: [
          if (!_isAtLiveEdge)
            TextButton.icon(
              onPressed: _jumpToLive,
              icon: Icon(Icons.fiber_manual_record, color: Colors.red),
              label: Text('LIVE', style: TextStyle(color: Colors.white)),
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

### High Latency

**Problem:** Stream is too far behind live edge

**Solutions:**
1. Reduce `liveLatency` value
2. Reduce `maxPrefetchSegments`
3. Check network bandwidth
4. Verify CDN edge server proximity

```dart
HlsConfig(
  liveLatency: Duration(seconds: 2),  // Lower latency
  maxPrefetchSegments: 1,             // Less prefetching
)
```

### Frequent Buffering

**Problem:** Stream buffers frequently

**Solutions:**
1. Increase `liveLatency` value
2. Increase `maxPrefetchSegments`
3. Enable adaptive bitrate
4. Check available bandwidth

```dart
HlsConfig(
  liveLatency: Duration(seconds: 8),  // More buffer
  maxPrefetchSegments: 5,             // More prefetching
  enableAdaptiveBitrate: true,        // Adapt quality
)
```

### DVR Not Working

**Problem:** Cannot seek within live stream

**Checklist:**
- ✅ `enableLiveStream: true`
- ✅ `enableDvr: true`
- ✅ Stream manifest supports DVR (EXT-X-PLAYLIST-TYPE:EVENT for HLS)
- ✅ Sufficient DVR window on server

### Sync Issues

**Problem:** Multiple viewers out of sync

**Solution:** Use consistent latency targets

```dart
// All clients use same configuration
HlsConfig(
  enableLiveStream: true,
  liveLatency: Duration(seconds: 5),  // Same for all
)
```

---

## Additional Resources

- **HLS Specification:** [RFC 8216](https://tools.ietf.org/html/rfc8216)
- **DASH Specification:** [ISO/IEC 23009-1](https://www.iso.org/standard/79329.html)
- **Low-Latency HLS:** [Apple Documentation](https://developer.apple.com/documentation/http_live_streaming/protocol_extension_for_low-latency_hls)

---

## Related Documentation

- [Getting Started](README.md) - Basic setup
- [Events & Callbacks](events.md) - Stream events
- [Bandwidth Monitoring](../implementation/README.md#bandwidth-monitoring) - Network monitoring

---

**Version:** 0.1.0  
**Last Updated:** October 19, 2025  
**Status:** Production Ready

