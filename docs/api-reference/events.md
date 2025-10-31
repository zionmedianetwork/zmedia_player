# ZMedia Player - Events API Reference

## Overview

The ZMedia Player exposes events through a comprehensive stream-based API. This document provides a complete reference of all available event streams and their use cases.

---

## Event Streams

### 1. State Stream (`stateStream`)

**Type**: `Stream<PlaybackState>`
**Access**: `player.stateStream`

The primary event stream that emits comprehensive playback state updates.

#### PlaybackState Properties:
```dart
class PlaybackState {
  final PlayerState state;           // Current player state
  final Duration position;            // Current playback position
  final Duration duration;            // Total media duration
  final double speed;                 // Playback speed (0.25 - 4.0)
  final double volume;                // Volume level (0.0 - 1.0)
  final bool isMuted;                 // Mute status
  final bool isBuffering;             // Buffering status
  final double bufferPercentage;      // Buffer percentage (0.0 - 1.0)
  final Duration bufferedPosition;    // Buffered position
  final String? errorMessage;         // Error message if any

  // Computed properties
  double get progress;                // Progress percentage (0.0 - 1.0)
  bool get canPlay;                   // Can start playback
  bool get canPause;                  // Can pause playback
  bool get canSeek;                   // Can seek
}
```

#### PlayerState Enum:
```dart
enum PlayerState {
  idle,       // No media loaded
  buffering,  // Loading/buffering media
  ready,      // Ready to play
  playing,    // Currently playing
  paused,     // Paused
  completed,  // Playback completed
  error,      // Error occurred
}
```

#### Usage Example:
```dart
player.stateStream.listen((PlaybackState state) {
  print('State: ${state.state}');
  print('Position: ${state.position}');
  print('Duration: ${state.duration}');
  print('Buffering: ${state.isBuffering}');
  print('Buffer %: ${state.bufferPercentage}');
  print('Volume: ${state.volume}');
  print('Speed: ${state.speed}');
  print('Muted: ${state.isMuted}');
  print('Progress: ${state.progress}');

  if (state.state == PlayerState.error) {
    print('Error: ${state.errorMessage}');
  }
});
```

---

### 2. Position Stream (`positionStream`)

**Type**: `Stream<Duration>`
**Access**: `player.positionStream`

Emits periodic updates of the current playback position. Updates approximately every 500ms during playback.

#### Usage Example:
```dart
player.positionStream.listen((Duration position) {
  print('Position: ${formatDuration(position)}');
  // Update progress slider
  setState(() {
    _currentPosition = position;
  });
});
```

**Use Cases:**
- Progress bar updates
- Time display
- Position-based triggers
- Sync with other components

---

### 3. Duration Stream (`durationStream`)

**Type**: `Stream<Duration>`
**Access**: `player.durationStream`

Emits the total duration when media is loaded or duration changes.

#### Usage Example:
```dart
player.durationStream.listen((Duration duration) {
  print('Duration: ${formatDuration(duration)}');
  setState(() {
    _totalDuration = duration;
  });
});
```

**Use Cases:**
- Setting progress bar max value
- Displaying total time
- Calculating remaining time
- Validation for seek operations

---

### 4. Volume Stream (`volumeStream`)

**Type**: `Stream<double>`
**Access**: `player.volumeStream`

Emits volume level changes (0.0 to 1.0).

#### Usage Example:
```dart
player.volumeStream.listen((double volume) {
  print('Volume: ${(volume * 100).toInt()}%');
  setState(() {
    _currentVolume = volume;
  });
});
```

**Use Cases:**
- Volume slider updates
- Volume indicator UI
- Audio mixing
- Volume persistence

---

### 5. Speed Stream (`speedStream`)

**Type**: `Stream<double>`
**Access**: `player.speedStream`

Emits playback speed changes (0.25x to 4.0x).

#### Usage Example:
```dart
player.speedStream.listen((double speed) {
  print('Speed: ${speed}x');
  setState(() {
    _currentSpeed = speed;
  });
});
```

**Use Cases:**
- Speed control UI
- Speed indicator display
- Speed presets
- User preference tracking

---

### 6. Subtitle Tracks Stream (`subtitleTracksStream`)

**Type**: `Stream<List<SubtitleTrack>>`
**Access**: `player.subtitleTracksStream`

Emits when available subtitle tracks change or selection changes.

#### SubtitleTrack Model:
```dart
class SubtitleTrack {
  final String id;               // Unique identifier
  final String name;             // Display name
  final String? language;        // Language code (e.g., 'en', 'es')
  final String? url;             // Subtitle file URL
  final SubtitleFormat format;   // SRT, WebVTT, ASS, etc.
  final bool isSelected;         // Currently selected
  final bool isEmbedded;         // Embedded in video
  final Map<String, dynamic>? metadata;
}
```

#### Usage Example:
```dart
player.subtitleTracksStream.listen((List<SubtitleTrack> tracks) {
  print('Available subtitles: ${tracks.length}');

  for (final track in tracks) {
    print('  - ${track.name} (${track.language})');
    if (track.isSelected) {
      print('    [SELECTED]');
    }
  }

  setState(() {
    _availableSubtitles = tracks;
    _selectedSubtitle = tracks.firstWhere(
      (t) => t.isSelected,
      orElse: () => null,
    );
  });
});
```

**Use Cases:**
- Subtitle selection menu
- Language preferences
- Accessibility features
- Multi-language content

---

### 7. Quality Tracks Stream (`qualityTracksStream`)

**Type**: `Stream<List<QualityTrack>>`
**Access**: `player.qualityTracksStream`

Emits when available quality/resolution tracks change (HLS/DASH adaptive streaming).

#### QualityTrack Model:
```dart
class QualityTrack {
  final String id;              // Unique identifier
  final String name;            // Display name (e.g., "1080p", "720p")
  final int bitrate;            // Bitrate in bits/second
  final int? width;             // Video width in pixels
  final int? height;            // Video height in pixels
  final double? frameRate;      // Frame rate (e.g., 30.0, 60.0)
  final bool isSelected;        // Currently selected
  final bool isAvailable;       // Available for selection
  final String? codec;          // Video codec
}
```

#### Usage Example:
```dart
player.qualityTracksStream.listen((List<QualityTrack> tracks) {
  print('Available qualities: ${tracks.length}');

  for (final track in tracks) {
    String label = track.name;
    if (track.height != null) {
      label += ' (${track.height}p)';
    }
    print('  - $label @ ${track.bitrate / 1000000}Mbps');
    if (track.isSelected) {
      print('    [SELECTED]');
    }
  }

  setState(() {
    _availableQualities = tracks;
    _selectedQuality = tracks.firstWhere(
      (t) => t.isSelected,
      orElse: () => null,
    );
  });
});
```

**Use Cases:**
- Quality selection menu
- Adaptive bitrate display
- Bandwidth-based quality switching
- Quality preferences
- Data saver mode

---

### 8. Audio Tracks Stream (`audioTracksStream`)

**Type**: `Stream<List<AudioTrack>>`
**Access**: `player.audioTracksStream`

Emits when available audio tracks change (multi-language audio).

#### AudioTrack Model:
```dart
class AudioTrack {
  final String id;              // Unique identifier
  final String name;            // Display name
  final String? language;       // Language code (e.g., 'en', 'es', 'fr')
  final bool isSelected;        // Currently selected
  final bool isAvailable;       // Available for selection
  final String? codec;          // Audio codec
  final int? channels;          // Audio channels (2, 6, etc.)
  final int? sampleRate;        // Sample rate in Hz
}
```

#### Usage Example:
```dart
player.audioTracksStream.listen((List<AudioTrack> tracks) {
  print('Available audio tracks: ${tracks.length}');

  for (final track in tracks) {
    String label = track.name;
    if (track.language != null) {
      label += ' (${track.language})';
    }
    if (track.channels != null) {
      label += ' ${track.channels}.0';
    }
    print('  - $label');
    if (track.isSelected) {
      print('    [SELECTED]');
    }
  }

  setState(() {
    _availableAudioTracks = tracks;
    _selectedAudioTrack = tracks.firstWhere(
      (t) => t.isSelected,
      orElse: () => null,
    );
  });
});
```

**Use Cases:**
- Audio language selection
- Multi-language content
- Audio format preferences
- Accessibility (audio descriptions)

---

## Complete Usage Example

```dart
import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';

class PlayerEventsDemo extends StatefulWidget {
  @override
  _PlayerEventsDemoState createState() => _PlayerEventsDemoState();
}

class _PlayerEventsDemoState extends State<PlayerEventsDemo> {
  late MediaController _controller;
  PlaybackState _state = const PlaybackState(state: PlayerState.idle);
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 1.0;
  double _speed = 1.0;
  List<SubtitleTrack> _subtitles = [];
  List<QualityTrack> _qualities = [];
  List<AudioTrack> _audioTracks = [];

  @override
  void initState() {
    super.initState();
    _controller = MediaController.create();
    _setupEventListeners();
    _loadMedia();
  }

  void _setupEventListeners() {
    // Listen to all state changes
    _controller.player.stateStream.listen((state) {
      setState(() => _state = state);
      print('State changed: ${state.state}');
    });

    // Position updates
    _controller.player.positionStream.listen((position) {
      setState(() => _position = position);
    });

    // Duration updates
    _controller.player.durationStream.listen((duration) {
      setState(() => _duration = duration);
      print('Duration: ${formatDuration(duration)}');
    });

    // Volume changes
    _controller.player.volumeStream.listen((volume) {
      setState(() => _volume = volume);
      print('Volume: ${(volume * 100).toInt()}%');
    });

    // Speed changes
    _controller.player.speedStream.listen((speed) {
      setState(() => _speed = speed);
      print('Speed: ${speed}x');
    });

    // Subtitle tracks
    _controller.player.subtitleTracksStream.listen((tracks) {
      setState(() => _subtitles = tracks);
      print('Subtitle tracks updated: ${tracks.length}');
    });

    // Quality tracks
    _controller.player.qualityTracksStream.listen((tracks) {
      setState(() => _qualities = tracks);
      print('Quality tracks updated: ${tracks.length}');
    });

    // Audio tracks
    _controller.player.audioTracksStream.listen((tracks) {
      setState(() => _audioTracks = tracks);
      print('Audio tracks updated: ${tracks.length}');
    });
  }

  Future<void> _loadMedia() async {
    final mediaItem = MediaItem(
      id: '1',
      title: 'Sample Video',
      url: 'https://example.com/video.m3u8',
      mediaType: MediaType.video,
    );
    await _controller.load(mediaItem);
  }

  String formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Player Events Demo')),
      body: Column(
        children: [
          // Video player
          AspectRatio(
            aspectRatio: 16 / 9,
            child: MediaPlayerWidget(
              controller: _controller,
              showControls: true,
            ),
          ),

          // State information
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('State: ${_state.state}'),
                Text('Position: ${formatDuration(_position)}'),
                Text('Duration: ${formatDuration(_duration)}'),
                Text('Volume: ${(_volume * 100).toInt()}%'),
                Text('Speed: ${_speed}x'),
                Text('Buffering: ${_state.isBuffering}'),
                Text('Buffer: ${(_state.bufferPercentage * 100).toInt()}%'),
                Text('Subtitles: ${_subtitles.length}'),
                Text('Qualities: ${_qualities.length}'),
                Text('Audio Tracks: ${_audioTracks.length}'),
              ],
            ),
          ),
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

## Stream Best Practices

### 1. Always Cancel Subscriptions

```dart
StreamSubscription? _subscription;

void setupListener() {
  _subscription = player.stateStream.listen((state) {
    // Handle state
  });
}

@override
void dispose() {
  _subscription?.cancel();
  super.dispose();
}
```

### 2. Use StreamBuilder for UI

```dart
StreamBuilder<PlaybackState>(
  stream: controller.player.stateStream,
  builder: (context, snapshot) {
    if (!snapshot.hasData) {
      return CircularProgressIndicator();
    }

    final state = snapshot.data!;
    return Text('State: ${state.state}');
  },
)
```

### 3. Handle Errors

```dart
player.stateStream.listen(
  (state) {
    // Handle state
  },
  onError: (error) {
    print('Stream error: $error');
  },
  onDone: () {
    print('Stream closed');
  },
);
```

### 4. Combine Multiple Streams

```dart
import 'package:rxdart/rxdart.dart';

Rx.combineLatest2(
  player.positionStream,
  player.durationStream,
  (Duration position, Duration duration) {
    return position.inSeconds / duration.inSeconds;
  },
).listen((progress) {
  print('Progress: ${(progress * 100).toInt()}%');
});
```

---

## Event Stream Characteristics

| Stream | Frequency | When Emitted | Broadcast |
|--------|-----------|--------------|-----------|
| `stateStream` | On state change | State transitions, errors | ✅ Yes |
| `positionStream` | ~500ms | During playback | ✅ Yes |
| `durationStream` | On load | Media loaded, duration known | ✅ Yes |
| `volumeStream` | On volume change | Volume adjustments | ✅ Yes |
| `speedStream` | On speed change | Speed adjustments | ✅ Yes |
| `subtitleTracksStream` | On track change | Tracks loaded/changed | ✅ Yes |
| `qualityTracksStream` | On track change | Tracks loaded/changed | ✅ Yes |
| `audioTracksStream` | On track change | Tracks loaded/changed | ✅ Yes |

**Note**: All streams are **broadcast streams**, meaning multiple listeners can subscribe simultaneously.

---

## Performance Considerations

### 1. Position Stream Throttling

The position stream is automatically throttled to emit at most every 500ms to prevent excessive UI updates.

### 2. Selective Listening

Only subscribe to the streams you need:

```dart
// ❌ Don't listen to everything if you don't need it
player.stateStream.listen(...);
player.positionStream.listen(...);
player.durationStream.listen(...);
player.volumeStream.listen(...);
player.speedStream.listen(...);

// ✅ Only listen to what you need
player.stateStream.listen(...);
player.positionStream.listen(...);
```

### 3. Dispose Properly

Always dispose the controller when done:

```dart
@override
void dispose() {
  _controller.dispose(); // Closes all streams
  super.dispose();
}
```

---

## Comparison with Other Patterns

### Callback-Based (Legacy Pattern)
```dart
// ❌ Old pattern (not used in ZMedia Player)
player.onStateChanged = (state) {
  // Handle state
};
player.onPositionChanged = (position) {
  // Handle position
};
```

### Stream-Based (ZMedia Player)
```dart
// ✅ Modern, reactive pattern
player.stateStream.listen((state) {
  // Handle state
});
player.positionStream.listen((position) {
  // Handle position
});
```

**Benefits of Streams:**
- Type-safe
- Composable
- Testable
- Flutter-idiomatic
- Memory-efficient
- Multiple listeners supported

---

## Summary

The ZMedia Player provides **8 comprehensive event streams** covering:

1. ✅ **Playback state** - Complete player state with rich metadata
2. ✅ **Position tracking** - Real-time position updates
3. ✅ **Duration info** - Media length information
4. ✅ **Volume control** - Volume level changes
5. ✅ **Speed control** - Playback speed changes
6. ✅ **Subtitle management** - Available and selected subtitles
7. ✅ **Quality selection** - Video quality/resolution options
8. ✅ **Audio tracks** - Multi-language audio support

All streams follow Flutter's reactive programming model and are broadcast streams supporting multiple simultaneous listeners.

---

**Document Version**: 1.0
**Last Updated**: October 19, 2025
**Status**: Complete
