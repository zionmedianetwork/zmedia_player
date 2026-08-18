# Player API

`MediaController` (the reactive facade) and `MediaPlayer` (the engine). Use `MediaController`
for UI; reach `MediaPlayer` via `controller.player` when you need raw streams.

## MediaController

```dart
factory MediaController.create({String? playerId, MediaConfig? config});
```

Creates the controller and its underlying `MediaPlayer`, and calls `initialize()`.

### Playback control

| Method | Description |
|---|---|
| `Future<void> load(MediaItem item)` | Load a single item |
| `Future<void> setPlaylist(Playlist playlist, {int? startIndex})` | Load a playlist |
| `Future<void> play()` / `pause()` / `stop()` | Playback control |
| `Future<void> togglePlayPause()` | Toggle play/pause |
| `Future<void> seekTo(Duration position)` | Seek to a position. Throws `InvalidStateException` for a live item that is not seekable (`isLive && !dvrEnabled` — see [Live Streaming](live-streaming.md)) |
| `Future<void> seekForward([Duration duration])` / `seekBackward([Duration duration])` | Relative seek (default 10s) |
| `Future<void> setVolume(double volume)` | 0.0–1.0 |
| `Future<void> increaseVolume([double amount])` / `decreaseVolume([double amount])` | Step volume |
| `Future<void> toggleMute()` | Mute/unmute |
| `Future<void> setSpeed(double speed)` | 0.25–4.0. A setting, not a transport command — never starts or pauses playback |
| `Future<void> cycleSpeed()` | Cycle preset speeds |

### Playlist navigation

| Method | Description |
|---|---|
| `Future<void> skipToNext()` / `skipToPrevious()` | Move within the playlist |
| `Future<void> skipToIndex(int index)` | Jump to an index |

### Track selection

| Method | Description |
|---|---|
| `Future<void> setQualityTrack(QualityTrack track)` | Manual quality |
| `Future<void> enableAutoQuality()` | Adaptive bitrate |
| `Future<void> setSubtitleTrack(SubtitleTrack? track)` | Select (null to disable) |
| `Future<void> disableSubtitles()` / `cycleSubtitleTrack()` | Subtitle helpers |
| `Future<void> setAudioTrack(AudioTrack track)` | Select audio track |

> Quality, subtitle, and audio tracks are reported by the native player only **after `play()`**.

### Controls visibility

`showControls()`, `hideControls()`, `toggleControls()`, `showControlsTemporarily()`, `forceHideControls()`.

### Picture-in-Picture & casting

| Method | Description |
|---|---|
| `Future<bool> checkPipAvailability()` | Device/OS support check |
| `Future<void> enterPictureInPicture()` / `exitPictureInPicture()` | PiP control |
| `Future<void> startCastDiscovery()` / `stopCastDiscovery()` | Discover devices |
| `Future<void> connectToCastDevice(CastDevice device)` | Connect |
| `Future<void> connectAndLoadMedia(CastDevice device)` | Connect + load current media |
| `Future<void> disconnectFromCastDevice()` | Disconnect |

### Configuration & lifecycle

`Future<void> updateConfig(MediaConfig config)`, `String formatDuration(Duration)`, `void dispose()`.

### Security

| Method | Description |
|---|---|
| `Future<void> setSecureSurface(bool enabled)` | Android: hard-blocks capture (`FLAG_SECURE`). iOS: detection only (`UIScreen.isCaptured`) |

### Getters

State: `state`, `isPlaying`, `isPaused`, `isBuffering`, `hasError`, `isReady`, `isInitialized`.
Position: `position`, `duration`, `progress`, `bufferedProgress`, `formattedPosition`,
`formattedDuration`, `formattedRemainingTime`.
Audio: `volume`, `isMuted`, `speed`.
Content: `currentItem`, `currentPlaylist`, `hasNext`, `hasPrevious`.
Tracks: `qualityTracks`, `selectedQualityTrack`, `subtitleTracks`, `selectedSubtitleTrack`,
`audioTracks`, `selectedAudioTrack`.
PiP/Cast: `pipStatus`, `isPipAvailable`, `isInPipMode`, `castStatus`, `isCastAvailable`, `isCasting`.
Errors: `error` (most recently observed `MediaPlayerException`, or `null`), `errorStream`.
Other: `controlsVisible`, `isOperationInProgress`, `playerId`, `player` (the `MediaPlayer`),
`screenCaptureStream` (see [Advanced Features](advanced-features.md#screen-capture-protection)).

`MediaController` extends `ChangeNotifier`, so `AnimatedBuilder(animation: controller)` rebuilds on any change.

## MediaPlayer

```dart
factory MediaPlayer({String? playerId, MediaConfig? config});
```

One instance per `playerId` (registry-backed). Call `await initialize()` before `load()` if
you construct it directly. Native events are routed to the correct instance by `playerId`.

### Crash reporting (static)

```dart
MediaPlayer.enableCrashReporting(myCrashReporter);
MediaPlayer.disableCrashReporting();
```

### Methods

Playback: `initialize`, `load`, `setPlaylist`, `play`, `pause`, `stop`, `seekTo`, `setVolume`,
`setSpeed`, `setMuted`, `setBoxFit`. Tracks: `setQualityTrack`, `enableAutoQuality`,
`setSubtitleTrack`, `setAudioTrack`. Playlist: `skipToNext`, `skipToPrevious`, `skipToIndex`.
PiP: `checkPipAvailability`, `enterPictureInPicture`, `exitPictureInPicture`. Cast:
`startCastDiscovery`, `stopCastDiscovery`, `connectToCastDevice`, `loadMediaOnCastDevice`,
`disconnectFromCastDevice`. Security: `setSecureSurface`. Config/lifecycle: `updateConfig`,
`dispose`.

### Streams

`stateStream`, `positionStream`, `durationStream`, `volumeStream`, `speedStream`,
`subtitleTracksStream`, `qualityTracksStream`, `audioTracksStream`, `bandwidthStream` (bps),
`bufferHealthStream`, `pipStatusStream`, `pipActionStream` (carries `PipActionEvent` — a tap on
a custom `PipConfig.actions` entry, Android only), `castStatusStream`, `castDevicesStream`,
`drmSessionStream`, `errorStream` (typed `MediaPlayerException`s), `screenCaptureStream`,
`notificationActionEventStream` (carries `NotificationActionEvent`, including scrub-bar
position; prefer this over the deprecated `Stream<String> notificationActionStream`). See
[Events & Streams](events.md).

### Getters

`playerId`, `config`, `currentItem`, `currentPlaylist`, `currentState`, `isPlaying`,
`isInitialized`, `isDisposed`, `isLive`, `dvrEnabled` (whether DVR is enabled for the current
live item, derived from whichever `HlsConfig`/`DashConfig` matched its URL at `load()` time),
`isSeekable` (`false` only when `isLive && !dvrEnabled`), `currentBandwidth`, `networkQuality`,
`bufferStatistics`, `lastBufferHealth`, the track lists/selections, and the PiP/cast status
getters mirrored on the controller.

## Errors

All player errors are subclasses of the sealed `MediaPlayerException`:
`MediaLoadException`, `NetworkException`, `DrmException`, `PlaybackException`,
`InvalidStateException`, `PlayerDisposedException`, `ConfigurationException`,
`PlatformOperationException`, `OperationBusyException`. Errors also surface via
`PlaybackState.state == PlayerState.error` with `errorMessage`, and as typed exceptions on
`errorStream`/`error` (above).

## Feeds and pooled playback

For a scrolling feed that must bound how many native decoder sessions stay alive at once, see
`MediaFeed` and `MediaPlayerPool` in [Advanced Features](advanced-features.md#media-feed) —
they own a small pool of `MediaController`s internally rather than taking one per row from the
host, which is what `MediaListPlayer` does.
