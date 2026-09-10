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

  // Live streaming (see docs/api-reference/live-streaming.md)
  final Duration? liveEdgeOffset;     // Distance behind the live edge; null for VOD
  final PositionBasis positionBasis;  // Which timeline `position` is measured against

  // Computed properties
  double get progress;                // Progress percentage (0.0 - 1.0)
  bool get canPlay;                   // Can start playback
  bool get canPause;                  // Can pause playback
  bool get canSeek;                   // Can seek
  bool get isAtLiveEdge;              // Riding the live edge (within 15s); false for VOD
  bool get isPositionWindowRelative;  // positionBasis == PositionBasis.liveWindow

  bool isAtLiveEdgeWithin(Duration tolerance);

  static const Duration defaultLiveEdgeTolerance = Duration(seconds: 15);
}
```

#### PositionBasis Enum:
```dart
enum PositionBasis {
  absolute,    // `position` is measured from a fixed zero point (the media start)
  liveWindow,  // `position` is measured from the start of the live/DVR window,
               // which itself slides forward — a CONSTANT position on this basis
               // is a healthy live edge, not a stall
}
```

> **Read this before writing a stall detector.** On `PositionBasis.liveWindow`,
> `position` stays roughly constant during perfectly healthy playback, because
> the window start advances at the same rate as the playhead. Do not detect a
> live stall from `position`.
>
> `liveEdgeOffset` is the right signal **on Android**, where it grows without
> bound against a genuinely frozen playhead. It is **not sufficient on iOS**:
> both `notifyPositionChanged` call sites and the offset computation itself
> live inside `AVPlayer.addPeriodicTimeObserver`'s block, which stops firing
> when time stops progressing — so during an iOS hard stall the offset is
> never sampled and freezes at its last value instead of growing. A correct
> watchdog therefore also treats **no `onPositionChanged` arriving at all,
> while the host still intends to play**, as a stall signal (issue #124).
> See [Live Streaming](live-streaming.md#stall-watchdog-for-live-streams) for
> the three-signal implementation.
>
> **Android and iOS measure `liveEdgeOffset` itself differently, and the
> values are not comparable** — see
> [Platform divergence](live-streaming.md#platform-divergence-this-value-measures-different-things).
> `isAtLiveEdge` is effectively always `true` on iOS as a result.

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
  print('Position basis: ${state.positionBasis}');
  print('Behind live edge: ${state.liveEdgeOffset}');  // null for VOD
  print('At live edge: ${state.isAtLiveEdge}');

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

On Android this stream also ticks while playback is stalled but the host still
intends to play (`playWhenReady && STATE_BUFFERING`), so `stateStream`'s
`liveEdgeOffset` keeps updating through a rebuffer. It stays silent while
genuinely paused, idle or ended. On iOS the underlying
`AVPlayer.addPeriodicTimeObserver` only fires while time is progressing, so a
full stall suspends updates there — treat "no position event for several
sampling intervals while `state == playing`" as its own signal on iOS.

> `positionStream` carries only the `Duration`. The live-edge fields
> (`liveEdgeOffset`, `positionBasis`) that arrive on the *same* native event
> are surfaced through `stateStream` / `player.currentState`, or directly via
> `player.liveEdgeOffset` / `player.isAtLiveEdge` / `player.positionBasis`.

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

Speed is a *setting*, not a transport command: a speed change never starts or pauses playback.
An event on this stream says nothing about whether the player is playing — listen to
`playbackStateStream` for that.

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
  final String title;            // Display name
  final String? language;        // Language code (e.g., 'en', 'es')
  final String? url;             // Subtitle file URL
  final SubtitleFormat format;   // SRT, WebVTT, ASS, etc.
  final bool isSelected;         // Currently selected
  final bool isDefault;          // Default subtitle track
  final Map<String, dynamic>? metadata;
}
```

#### Usage Example:
```dart
player.subtitleTracksStream.listen((List<SubtitleTrack> tracks) {
  print('Available subtitles: ${tracks.length}');

  for (final track in tracks) {
    print('  - ${track.title} (${track.language})');
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

### 9. Error Stream (`errorStream`)

**Type**: `Stream<MediaPlayerException>`
**Access**: `player.errorStream` (also re-emitted by `MediaController.errorStream`)

The reachable half of the typed exception hierarchy. **Most real playback
failures arrive here, not as a thrown exception**: ExoPlayer and AVPlayer both
accept a media item synchronously and only afterwards discover network, HTTP,
DRM, decoder and source problems, so `load()` has usually already completed
successfully by the time the failure is detected. See
[`load()` completing is not "loaded"](#load-completing-is-not-loaded) below.

```dart
player.errorStream.listen((MediaPlayerException e) {
  if (e is NetworkException) {
    // e.isTimeout is true for a MediaConfig.loadTimeout watchdog failure
    showOfflineBanner();
  } else if (e is DrmException) {
    showDrmError(e);
  } else if (e is MediaLoadException) {
    showHttpError(e.statusCode);
  }
});
```

Emits exactly one typed exception per native `onError` event. Also emits a
`DrmException` whenever `drmSessionStream` reports `DrmSessionState.error`, so
DRM failures are reachable here rather than only as an untyped session state.

The exception subtype is chosen from the `category` key of the `onError`
payload — see [`onError`](#onerror) below.

---

### 10. Pause Reason Stream (`pauseReasonStream`)

**Type**: `Stream<PlayerPauseReason>`
**Access**: `player.pauseReasonStream`

Emits alongside a `paused` `PlaybackState` transition **when native attributes
the pause**. `PlaybackState` itself carries no field for this, so the reason
travels beside the state event rather than replacing it — both "the viewer
tapped pause" and "the OS revoked audio focus" are legitimately `paused`.

```dart
player.pauseReasonStream.listen((PlayerPauseReason reason) {
  switch (reason) {
    case PlayerPauseReason.user:
      // A deliberate pause. Do NOT auto-resume.
      break;
    case PlayerPauseReason.audioFocusLoss:
    case PlayerPauseReason.audioBecomingNoisy:
    case PlayerPauseReason.remote:
      // Not the viewer's doing — a "Resume" affordance is appropriate.
      break;
  }
});
```

| Member | Wire value | Android | iOS |
|---|---|---|---|
| `user` | `"user"` | player-reported (`PLAY_WHEN_READY_CHANGE_REASON_USER_REQUEST`) | **host-inferred** |
| `audioFocusLoss` | `"audioFocusLoss"` | player-reported (`..._AUDIO_FOCUS_LOSS`) | `AVAudioSession` interruption (call/Siri/alarm) |
| `audioBecomingNoisy` | `"audioBecomingNoisy"` | player-reported (`..._AUDIO_BECOMING_NOISY` — headphones unplugged / Bluetooth disconnected) | **never sent** |
| `remote` | `"remote"` | player-reported (`..._REMOTE` — notification, Bluetooth control, wearable, Android Auto) | **never sent** |

**A pause native cannot attribute emits nothing at all.**
`PlayerPauseReason.fromWireValue` returns `null` for an absent *and* for an
unrecognised value — deliberately unlike `MediaErrorCategory.fromWireValue`,
which falls back to `unknown`. There is no catch-all member to guess with, and
guessing `user` would be actively harmful for any host that keys "don't
auto-recover" off it.

**iOS `user` is host-inferred, Android's is player-reported.** AVFoundation
exposes no `reasonForPausing` — a `.paused` `timeControlStatus` carries no
explanation — so on iOS this package sets a flag when its own `pause()` runs
and attributes the resulting transition to it. Treat it as best-effort there.
This is the same class of documented cross-platform divergence as
`liveEdgeOffset` (see [Platform divergence](live-streaming.md#platform-divergence-this-value-measures-different-things)),
not a defect on either side.

> **Breaking change (issue #126).** This stream previously emitted **only**
> `PlayerPauseReason.audioFocusLoss`; the emission site compared the payload
> against a hardcoded string, which is why `PlayerPauseReason.user` was
> declared, exported and documented but could not be produced by any input.
> The stream is now chatty — it fires on every attributed pause — so code that
> treated *any* event here as "audio focus was lost" must switch on the value.
> Two new members (`audioBecomingNoisy`, `remote`) also break an exhaustive
> `switch` with no `default`.

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
| `stateStream` | On state change | State transitions, errors | Yes Yes |
| `positionStream` | ~500ms | During playback | Yes Yes |
| `durationStream` | On load | Media loaded, duration known | Yes Yes |
| `volumeStream` | On volume change | Volume adjustments | Yes Yes |
| `speedStream` | On speed change | Speed adjustments | Yes Yes |
| `subtitleTracksStream` | On track change | Tracks loaded/changed | Yes Yes |
| `qualityTracksStream` | On track change | Tracks loaded/changed | Yes Yes |
| `audioTracksStream` | On track change | Tracks loaded/changed | Yes Yes |
| `errorStream` | On failure | Native `onError`, or a `DrmSessionState.error` | Yes Yes |
| `pauseReasonStream` | On an *attributed* pause | Native attached a `pauseReason` | Yes Yes |

**Note**: All streams are **broadcast streams**, meaning multiple listeners can subscribe simultaneously.

---

## Native Event Payloads (MethodChannel contract)

These are the raw native -> Dart `MethodChannel` payloads that back the streams
above. Host apps never construct these; they are documented because a payload
key is invisible to `flutter analyze` and to the (channel-mocking) test suite,
so this table is the only place the contract is recorded.

### `onStateChanged`

Backs `stateStream`/`PlaybackState.state`, and `pauseReasonStream`.

| Key | Type | Required | Meaning |
|-----|------|----------|---------|
| `playerId` | String | yes | Routes the event to a `MediaPlayer` instance |
| `state` | String | yes | One of `idle`/`buffering`/`ready`/`playing`/`paused`/`completed`/`error`; parsed into `PlayerState` |
| `isBuffering` | bool | no (defaults `false`) | Whether the player is actively buffering |
| `bufferPercentage` | num | no (defaults `0.0`) | Percentage of the full duration buffered. Android: `Player.getBufferedPercentage()`. iOS: computed from the furthest end of any loaded time range; `0` for live/unknown-duration content |
| `pauseReason` | String | no | Why a `paused` transition happened — `"user"`/`"audioFocusLoss"`/`"audioBecomingNoisy"`/`"remote"`. **Omitted entirely** (never sent as `null`) when native cannot attribute the pause. See [Pause Reason Stream](#10-pause-reason-stream-pausereasonstream) for the per-platform availability table |

Native sources:

| | Android (ExoPlayer / Media3) | iOS (AVFoundation) |
|---|---|---|
| `state` | `Player.Listener.onPlaybackStateChanged` (`STATE_IDLE`/`BUFFERING`/`READY`/`ENDED`, with `READY` split on `playWhenReady`) and `onIsPlayingChanged` | `AVPlayer.timeControlStatus` KVO, with `AVPlayerItem.status` KVO for `buffering`/`ready`, and `AVPlayerItemDidPlayToEndTime` for `completed` |
| `pauseReason` | `Player.PlayWhenReadyChangeReason`, captured by `onPlayWhenReadyChanged` and read in `onIsPlayingChanged`. `END_OF_MEDIA_ITEM` and `SUPPRESSED_TOO_LONG` are deliberately unmapped (the first is not a pause; the second has no consumer-meaningful cause) | `consumePauseReason()` — the `AVAudioSession` interruption flag first, then the host-`pause()` flag. Never produces `audioBecomingNoisy` or `remote` |

#### Post-failure suppression (issue #125)

**Both natives deliberately stop sending this event while the player is in a
reported error**, and this is load-bearing rather than an optimisation.

Each platform emits a *quiescent* state as a direct consequence of a failure —
`STATE_IDLE` (`"idle"`) on Android, a `timeControlStatus` transition to
`.paused` (`"paused"`) on iOS — and it arrives immediately **after** the
`onError` that explains it. (On Android this ordering is guaranteed: Media3
queues `EVENT_PLAYER_ERROR` before `EVENT_PLAYBACK_STATE_CHANGED` and before
`onIsPlayingChanged`.) Applied as an ordinary transition, that trailing event
overwrote `PlayerState.error`, so a failed load ended up reported as `paused`
on iOS and `idle` on Android — byte-identical to a viewer pause.

- **Android** returns early from `onPlaybackStateChanged`/`onIsPlayingChanged`
  while `Player.getPlayerError() != null`, which is non-null from the error
  until the next `prepare()` — exactly the window that needs suppressing, since
  every real recovery goes through `prepare()`.
- **iOS** returns early from `handleTimeControlStatusChange` while
  `currentItem?.status == .failed || player.status == .failed`. This cannot
  hide a recovery: an `AVPlayerItem` failure is terminal by Apple's contract
  (the item must be replaced), and the only route back is `loadMediaItem()`,
  which always calls `replaceCurrentItem(with:)`.

Dart latches the error state independently (see
`MediaPlayer._handleStateChanged`), so **new Dart against an older cached
native build that lacks these suppressions still behaves correctly.** While
latched, `state` is pinned at `error` but `isBuffering`/`bufferPercentage`
still flow through, so host diagnostics keep updating.

### `onError`

Backs `errorStream` and `PlaybackState.errorMessage`/`PlayerState.error`.

| Key | Type | Required | Meaning |
|-----|------|----------|---------|
| `playerId` | String | yes | Routes the event to a `MediaPlayer` instance |
| `error` | String | yes | Human-readable message. Becomes `PlaybackState.errorMessage` and the exception's `message` |
| `category` | String | no | `NETWORK`/`HTTP`/`DRM`/`DECODER`/`SOURCE`/`UNKNOWN` — the `MediaErrorCategory` vocabulary that selects the exception subtype. Absent or unrecognised maps to `UNKNOWN` -> `PlaybackException` |
| `nativeErrorCode` | String or int | no | The platform's own code (`PlaybackException.errorCodeName` on Android, `NSError.code` on iOS). Stringified into `DrmException.errorCode`/`PlaybackException.errorCode` |
| `httpStatusCode` | int | no | HTTP status behind the failure, when one was recorded. Becomes `MediaLoadException.statusCode` for the `HTTP` category |

There is no `isTimeout` key: `NetworkException.isTimeout` is set only by the
Dart-side `MediaConfig.loadTimeout` watchdog (below), never by native.

Both natives emit this from KVO/listener callbacks whose delivery thread is not
guaranteed to be the main thread; iOS routes it through a helper that runs
**inline when already on main** and hops only when it is not, because an
unconditional hop would reorder `onError` after synchronously-emitted state
events — recreating the clobbering defect above by a different route.

#### `load()` completing is not "loaded"

`MediaPlayer.load()` resolving means the item was **handed to the platform**.
The manifest fetch, DRM handshake and first decode all still lie ahead, and any
of them can fail after the future has already completed successfully. Observe
the outcome on the streams instead:

| Outcome | Signal |
|---|---|
| Success | `stateStream` reaching `PlayerState.ready` or `PlayerState.playing` |
| Failure | `errorStream` emitting, with `currentState.state == PlayerState.error` |
| Neither (accepted, then silence) | `MediaConfig.loadTimeout` watchdog |

`PlayerState.error` is **terminal**: held until the next explicit host command
(`load`/`play`/`stop`/`seekTo`/`setPlaylist`/`skipToIndex`) or until native
reports real forward progress (`playing`/`completed`).

The watchdog (`MediaConfig.loadTimeout`, default 30s, `null` disables) is
**Dart-only** — it is never serialized into the `config` payload and no native
code reads it. On firing it synthesizes a `NetworkException` with
`isTimeout: true` onto `errorStream` and moves the state to
`PlayerState.error`. It refuses to fire unless the player is *still*
`buffering` **and** `position` has not advanced since the load, so a
slow-but-progressing manifest fetch or a long DRM handshake is never killed.

### `onPositionChanged`

| Key | Type | Required | Meaning |
|-----|------|----------|---------|
| `playerId` | String | yes | Routes the event to a `MediaPlayer` instance |
| `position` | int (ms) | yes | Playback position, on the basis given by `positionBasis` |
| `positionBasis` | String | no | `"absolute"` or `"liveWindow"`. Parsed into `PositionBasis`; absent or unrecognised falls back to `PositionBasis.absolute` |
| `liveEdgeOffset` | int (ms) | no | Distance behind the live edge. **Omitted entirely** (never a sentinel) for VOD and whenever the platform cannot answer; a missing key clears `PlaybackState.liveEdgeOffset` to `null` |

`positionBasis` and `liveEdgeOffset` deliberately ride this existing ~500ms
event rather than getting a channel event of their own: they are sampled from
the same native tick that produces `position` and are only meaningful next to
it.

Where each value comes from natively:

| | Android (ExoPlayer / Media3) | iOS (AVFoundation) |
|---|---|---|
| `liveEdgeOffset` | `Player.getCurrentLiveOffset()`, **sanity-checked against the live window first** (issue #109): used only when it is `C.TIME_UNSET` or `<= Timeline.Window.durationMs`. Falls back to `Timeline.Window.durationMs - Player.getCurrentPosition()` (both window-relative, so the difference is the distance to the live edge) both when the platform value is `C.TIME_UNSET` **and** when it exceeds the window's own duration — the latter is provably wrong (a manifest whose unix-time anchor disagrees with its segment timeline; see `docs/api-reference/live-streaming.md`'s "Manifest time-anchor defect" section) rather than trusted. **Both return paths are clamped to >= 0** (`coerceAtLeast(0L)`) | End of `AVPlayerItem.seekableTimeRanges.last` (`start + duration`) minus `AVPlayerItem.currentTime()`, **clamped to >= 0** (`max(0, ...)`) — bounded by construction (no unix-time anchor involved), so it needed no equivalent window check |

**The negative clamp is symmetric across platforms.** Both natives coerce a
negative computed offset to `0` before it crosses the channel — Android with
`coerceAtLeast(0L)` on both of its return paths, iOS with `max(0, ...)` — so
neither platform ever reports a negative offset, and neither reports `null`
where the other clamps. (`null` on either platform means "cannot answer at
all": not live, or the timeline/seekable range not yet established.) A
transient negative is normal on both: the playhead can read a few milliseconds
past the last observed edge between samples. `PlaybackState.isAtLiveEdgeWithin`
treats a zero or negative offset as "at the edge" either way.
| `positionBasis` | `"liveWindow"` whenever `Timeline.Window.isLive()` — ExoPlayer's `getCurrentPosition()` is window-relative for **any** live item, DVR or not | `"liveWindow"` only when the live **DVR** window translation is applied; a live item without `enableDvr` reports `"absolute"`, because there `position` is the `AVPlayerItem`'s own absolute timeline |

The `positionBasis` divergence between platforms for *live-without-DVR* is
real, not a bug: each platform reports the basis its position values are
actually on. Reporting a normalised lie on one platform would defeat the
purpose of the flag. `liveEdgeOffset` is reported for live streams **with and
without** DVR on both platforms.

**`liveEdgeOffset` itself diverges between platforms too, and more
fundamentally** (issue #120): Android's computation measures distance from
the *published* live edge (the manifest's own segment timeline), commonly
15-30s during healthy playback, while iOS's computation is bounded by the two
operands sharing the same loaded range — which means it reads under a second
during live playback there, essentially by construction rather than as a
reflection of stream health. The values are not comparable across platforms,
and `isAtLiveEdge`/`defaultLiveEdgeTolerance` are consequently near-degenerate
on iOS (effectively always `true`). See
[Platform divergence](live-streaming.md#platform-divergence-this-value-measures-different-things)
for the full explanation, including what still works identically on both
(frozen-playhead stall growth and DVR scrub-back).

`AVPlayerItem.configuredTimeOffsetFromLive` and `recommendedTimeOffsetFromLive`
were considered and rejected as the iOS source: both are *target* offsets (what
the app asked for / what the server recommends), so they are constant by
construction and useless as a liveness signal.

**When this event stops arriving.** Android keeps emitting it while
`playWhenReady && STATE_BUFFERING`, so it continues through a rebuffer. iOS
emits it only from `AVPlayer.addPeriodicTimeObserver`, which fires only while
time is progressing — so on iOS the event stops entirely during a hard stall.
"No `onPositionChanged` at all while the player reports `playing` or
`buffering`" is therefore itself a stall signal, and the only one available for
that case on iOS; see
[Stall watchdog for live streams](live-streaming.md#stall-watchdog-for-live-streams).

### `onNetworkStatusChanged`

Backs `NetworkStatus.fromPlatform` (`lib/src/models/network_status.dart`), and in turn
`MediaPlayer.networkStatus`/`.networkStatusStream`/`.networkChangeStream` and
`NetworkResilienceService`. Both natives compute and send this shape — see the header
comments of `NetworkMonitor.kt` (Android) and `NetworkMonitor.swift` (iOS), which document
the same `(quality, downloadSpeed, isMetered, connectionType)` contract.

| Key | Type | Required | Meaning |
|-----|------|----------|---------|
| `playerId` | String | yes | Routes the event to a `MediaPlayer` instance |
| `quality` | String | no | One of `excellent`/`good`/`fair`/`poor`/`offline` (`NetworkQuality.values.name`). **As of issue #112, this is honoured** — `fromPlatform` parses it into a `NetworkQuality` and uses it directly. Absent or unparseable falls back to `NetworkQuality.fromBandwidth(downloadSpeed)`, which is the only behavior an older native build (or a hand-built map) ever exercised |
| `downloadSpeed` | int (bytes/sec) | no (defaults `0`) | Estimated download bandwidth. Consumed directly for adaptive-streaming decisions, and as the `fromBandwidth` fallback input when `quality` is absent/unparseable |
| `isMetered` | bool | no (defaults `false`) | Whether the connection is metered (e.g. cellular) |
| `connectionType` | String | no (defaults `"unknown"`) | One of `wifi`/`cellular`/`mobile`/`ethernet`/`bluetooth`/`vpn`/`none`; parsed case-insensitively by `ConnectionType.fromString`, unrecognised values fall back to `ConnectionType.unknown` |

**Why honouring `quality` matters (issue #112).** Before this fix, `fromPlatform` always
recomputed quality from `downloadSpeed`, discarding the platform's own classification. On
Android API >= 23, `downloadSpeed` derives from `NetworkCapabilities
.linkDownstreamBandwidthKbps`, which Android documents as a hint that may legitimately be `0`
on a live, connected network. `NetworkQuality.fromBandwidth(0)` returns `NetworkQuality
.offline`, so a `0` bandwidth hint on an otherwise-connected device made `NetworkStatus
.isAvailable` report `false` while the device was online. `NetworkMonitor.kt` now also floors
that branch — when the `linkDownstreamBandwidthKbps` hint is non-positive on a network with
real capabilities in hand, it falls back to the same transport-based `estimateBandwidthFromType`
estimate the pre-Android-M branch already used — so `downloadSpeed` itself no longer degenerates
to `0` on a connected link either; `offlineStatus()` (the canonical no-connection map, shared by
every genuine offline path) is unaffected and still reports `quality: "offline"`, `downloadSpeed:
0`, `connectionType: "none"`.

iOS's `estimateBandwidth(from:)` derives its estimate from the transport/interface type rather
than from a system bandwidth hint (fixed per-transport constants: ethernet 50 Mbps, wifi 5-10
Mbps, cellular 2 Mbps, loopback 1000 Mbps, other/unrecognized 1 Mbps) — it never reads a system
bandwidth hint at all, so it has no direct equivalent of Android's `linkDownstreamBandwidthKbps`
degeneracy. **`downloadSpeed` on iOS is therefore not a measurement in any sense** — it is
always one of those fixed constants, chosen purely from interface type, whereas Android's is at
least link-derived (a system hint, floored to the same transport estimate only when the hint
itself is degenerate). A consumer relying on `downloadSpeed` for adaptive-streaming decisions
should treat it as a rough per-platform floor, not a throughput measurement, and doubly so on
iOS.

iOS *did* have its own fallthrough defect, fixed alongside the `quality`-honouring change above:
`estimateBandwidth(from:)`'s final fallthrough (a satisfied `NWPath` whose interface matched
none of `.wiredEthernet`/`.wifi`/`.cellular`/`.loopback`/`.other`) used to return
`(0.0, "none")` — a *connected* path reporting the same `downloadSpeed: 0`/`connectionType:
"none"` shape as a genuine disconnection. It now returns `(1.0, "unknown")`, mirroring Android's
own fallthrough (`estimateBandwidthFromType`'s `else -> 1000` Kbps / `connectionType`'s
`else -> "unknown"`). This was a real instance of the bug the next paragraph's discriminator
promise depends on: before this fix, `connectionType == "none"` could be emitted by iOS on a
connected device, silently breaking any code relying on it as a reachability signal (see issue
#112's discussion of that exact reliance). `offlineStatus()` and the `guard path.status ==
.satisfied` early return in `getNetworkStatus(from:)` — the two genuine no-connection paths —
are unaffected and still report `quality: "offline"`, `downloadSpeed: 0`, `connectionType:
"none"`.

Note that `isAvailable`/`quality` and `connectionType` remain two independent signals:
`connectionType == "none"` is set only by each platform's `offlineStatus()`/no-connection map
and is a reliable reachability discriminator on its own, whereas `quality`/`isAvailable` describe
link quality and can (rarely) be degraded on a connected link. Deriving `isAvailable` from
`connectionType` instead was considered and deliberately deferred — it changes the meaning of a
widely-consumed public getter and needs its own deprecation story, not a bug-fix side effect.

---

## Performance Considerations

### 1. Position Stream Throttling

The position stream is automatically throttled to emit at most every 500ms to prevent excessive UI updates.

### 2. Selective Listening

Only subscribe to the streams you need:

```dart
// Don't listen to everything if you don't need it
player.stateStream.listen(...);
player.positionStream.listen(...);
player.durationStream.listen(...);
player.volumeStream.listen(...);
player.speedStream.listen(...);

// Only listen to what you need
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
// Old pattern (not used in ZMedia Player)
player.onStateChanged = (state) {
  // Handle state
};
player.onPositionChanged = (position) {
  // Handle position
};
```

### Stream-Based (ZMedia Player)
```dart
// Modern, reactive pattern
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

The ZMedia Player provides **10 comprehensive event streams** covering:

1. **Playback state** - Complete player state with rich metadata
2. **Position tracking** - Real-time position updates
3. **Duration info** - Media length information
4. **Volume control** - Volume level changes
5. **Speed control** - Playback speed changes
6. **Subtitle management** - Available and selected subtitles
7. **Quality selection** - Video quality/resolution options
8. **Audio tracks** - Multi-language audio support
9. **Errors** - Typed, category-tagged failures (`errorStream`)
10. **Pause attribution** - Why a pause happened, when known (`pauseReasonStream`)

(Plus `bandwidthStream`, `bufferHealthStream`, `drmSessionStream`,
`pipStatusStream`/`pipActionStream`, `castStatusStream`/`castDevicesStream`,
`notificationActionStream`, `screenCaptureStream` and
`networkStatusStream`/`networkChangeStream` — see
[player-api.md](player-api.md) for the full inventory.)

All streams follow Flutter's reactive programming model and are broadcast streams supporting multiple simultaneous listeners.

---

**Document Version**: 1.1
**Last Updated**: September 10, 2026
**Status**: Complete
