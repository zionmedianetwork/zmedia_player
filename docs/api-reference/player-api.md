# Player API

`MediaController` (the reactive facade) and `MediaPlayer` (the engine). Use `MediaController`
for UI; reach `MediaPlayer` via `controller.player` when you need raw streams.

## MediaController

```dart
factory MediaController.create({String? playerId, MediaConfig? config});
```

Creates the controller and its underlying `MediaPlayer`, and calls `initialize()`.

### Operation ordering (serialization queue)

Every `MediaController` method in the tables below is submitted to a per-controller **FIFO
queue** and runs one at a time, in submission order. A call made while another is still in
flight is *queued*, never rejected — so ordinary interleaved input works:

```dart
// No awaits between them: both run, in this order.
controller.pause();
controller.play();

// Muting a player that is still loading is fine — the mute is queued behind the load.
controller.load(item);
controller.setVolume(0.0);
```

Contract:

| | Behaviour |
|---|---|
| Ordering | FIFO by submission. The returned `Future` completes after *this* call has run — so it can resolve later than it used to when other work is in flight. |
| Busy controller | Never an error. There is no "critical vs non-critical" distinction: `setVolume`, `toggleMute`, `setSpeed`, `setSubtitleTrack` and `setSecureSurface` queue like everything else. |
| Failure isolation | A failing operation completes only *its own* `Future` with that error; the queue advances. |
| Head-of-line blocking | Bounded: each operation runs under a 10 s timeout, so a wedged native call fails with `TimeoutException` and the queue advances rather than stalling forever. |
| `dispose()` | An operation still *queued* when `dispose()` runs is dropped: its `Future` completes normally as a no-op and the disposed player is never touched — same as calling a method after `dispose()`. An operation already *running* is not cancelled. |
| Not a rate limiter | The queue is unbounded and never drops or collapses work (including repeated `seekTo`s). If you need debouncing — e.g. while dragging a scrub bar — do it in your UI before calling. |

> Before this behaviour existed, a busy controller rejected calls: non-critical ones threw
> `OperationBusyException` and critical ones threw `StateError` after a short wait. Both are
> gone; `OperationBusyException` is deprecated (see [Errors](#errors)). Hosts that built
> their own per-controller promise chain to work around it no longer need one.

### Playback control

| Method | Description |
|---|---|
| `Future<void> load(MediaItem item)` | Load a single item |
| `Future<void> setPlaylist(Playlist playlist, {int? startIndex})` | Load (or extend/re-issue) a playlist. Does **not** restart the item at `startIndex` if it is already the loaded, in-progress item — see [Extending a playlist in place](#extending-a-playlist-in-place) |
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
| `Future<void> skipToIndex(int index)` | Jump to an index. Always (re)loads, including when `index` is the current index — this is how `MediaRepeatMode.single` restarts an item |

### Extending a playlist in place

`setPlaylist` skips reloading the item at `startIndex` when it is already the loaded item
**and** that item is still in progress. Playback (position, play/pause state, speed) is
untouched; `Playlist` contents, `currentIndex`, `mode` and `repeatMode` always refresh.

This makes two previously expensive patterns free:

```dart
// 1. Sliding window — extend the queue as the viewer advances, without
//    restarting the episode being watched. Useful when playback
//    authorisation is scoped per item (e.g. per-episode signed cookies) and
//    pre-authorising the whole playlist is not viable.
await controller.setPlaylist(Playlist(
  id: 'series-1',
  title: 'Series 1',
  items: [current, next, next2],   // was [current, next]
));

// 2. Change mode/repeatMode mid-playback (e.g. toggling shuffle), which
//    requires re-issuing the playlist.
await controller.setPlaylist(playlist.copyWith(mode: PlaybackMode.shuffle));
```

**When it still reloads.** The guard compares the *whole serialized media item* on both
sides of the MethodChannel, not just `id`, so re-issuing an item deliberately still works:

| Change | Reloads? |
|---|---|
| Different `id` at `startIndex` | Yes |
| Same `id`, changed `url` (e.g. re-signed) | Yes |
| Same `id`/`url`, changed `httpHeaders` (refreshed signed cookie / `Authorization`) | Yes |
| Same `id`/`url`, changed `drmConfig` — including a rotated `drmConfig.headers` | Yes |
| Any other differing `MediaItem` field | Yes |
| Nothing loaded yet, or state is stopped / completed / errored | Yes |
| Identical item, currently playing / paused / buffering | **No** |
| Identical item, but the call carries a changed `MediaConfig` | **No** — see below |

A missing `id` is never self-identifying: two items are not "the same item" just because
both lack an `id` — the rest of the item (notably `url`) must still match.

**A changed `MediaConfig` does not force a reload.** `setPlaylist` carries the current
`MediaConfig` snapshot on every call (see [Config snapshot on the load
paths](#config-snapshot-on-the-load-paths)) and native stores it unconditionally — including
when it skips the load — so the next real load uses it. But storing it never by itself
triggers a load: a `setPlaylist` carrying a new config for an unchanged, in-progress item
**stores the config and keeps playing**, by design. Call `updateConfig()` to apply a config
change to live playback immediately, or `load()` to apply it *and* reload.

> `skipToNext`/`skipToPrevious` route through `skipToIndex`, as does playlist auto-advance when
> an item completes.

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
Live: `positionBasis` (`PositionBasis.absolute` | `.liveWindow` — which timeline `position` is
measured against), `liveEdgeOffset` (`Duration?`, distance behind the live edge; `null` for
VOD), `isAtLiveEdge` (within `PlaybackState.defaultLiveEdgeTolerance`, 15s; always `false` for
VOD). See [Live Streaming](live-streaming.md#stall-watchdog-for-live-streams) — do **not** build
a stall detector on `position` for a live stream.
Audio: `volume`, `isMuted`, `speed`.
Content: `currentItem`, `currentPlaylist`, `hasNext`, `hasPrevious`.
Tracks: `qualityTracks`, `selectedQualityTrack`, `subtitleTracks`, `selectedSubtitleTrack`,
`audioTracks`, `selectedAudioTrack`.
PiP/Cast: `pipStatus`, `isPipAvailable`, `isInPipMode`, `castStatus`, `isCastAvailable`, `isCasting`.
Errors: `error` (most recently observed `MediaPlayerException`, or `null`), `errorStream`.
Other: `controlsVisible`, `isOperationInProgress` (**informational only** — `true` while an
operation is *running*; it does not mean the queue is empty, and you never need to check it
before issuing a call, which was always racy), `playerId`, `player` (the `MediaPlayer`),
`screenCaptureStream` (see [Advanced Features](advanced-features.md#screen-capture-protection)).

`resetOperationState()` is retained for source compatibility and only clears the
`isOperationInProgress` flag; nothing gates on it, and a failed or timed-out operation can no
longer leave the controller stuck.

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
`setPlaylist` has the same "don't restart the item already playing" behaviour here as on
`MediaController` — see [Extending a playlist in place](#extending-a-playlist-in-place). When
the reload is skipped it also skips its own reset: the cached quality/audio/subtitle track
lists are kept, no `PlayerState.buffering` transition is emitted, and no `setSpeed(1.0)` reset
is sent.
PiP: `checkPipAvailability`, `enterPictureInPicture`, `exitPictureInPicture`. Cast:
`startCastDiscovery`, `stopCastDiscovery`, `connectToCastDevice`, `loadMediaOnCastDevice`,
`disconnectFromCastDevice`. Security: `setSecureSurface`. Config/lifecycle: `updateConfig`,
`dispose`.

#### Config snapshot on the load paths

Every method that makes native load a media item sends the current `MediaConfig` under a
`config` key, serialized exactly as `initialize`/`updateConfig` serialize it:

| MethodChannel call | Payload |
|---|---|
| `load` | `{playerId, mediaItem, config}` |
| `setPlaylist` | `{playerId, playlist, startIndex, config}` |
| `skipToIndex` | `{playerId, index, config}` |

Because the snapshot travels on **every** such call, rebuilding a `MediaConfig` (e.g. flipping
`hlsConfig.enableDvr`) and loading again is honored immediately — for playlist-driven items
too — with no separate `updateConfig()` call. Native replaces its stored config from the
snapshot *before* any config-dependent work, but deliberately does not re-apply
volume/speed/mute from it (that would undo an in-progress runtime `setMuted()`); use
`updateConfig()` when you want those applied. The key is optional on the native side: a native
build that predates it ignores it and keeps its stored config, exactly as before.

Per-item `httpHeaders` and `drmConfig` are unaffected — they live on `MediaItem`, so per-item
auth has always worked on the playlist path.

One nuance on the `setPlaylist` path: "honored immediately" means "on the next *load*". When
`setPlaylist` skips its load because the item at `startIndex` is unchanged and in progress
(see [Extending a playlist in place](#extending-a-playlist-in-place)), the new snapshot is
still stored, but the item keeps playing under the config it was loaded with. Re-issuing a
playlist is therefore not a way to apply a config change now — `updateConfig()` is, and
`load()` applies it *and* reloads.

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
live item, derived from whichever `HlsConfig`/`DashConfig` matched its
`MediaItem.resolvedStreamingFormat` at `load()` time — its explicit `MediaItem.streamingFormat`
if set, else path-based URL inference; see
[Live Streaming](live-streaming.md#choosing-which-streaming-config-applies-streamingformat)),
`isSeekable` (`false` only when `isLive && !dvrEnabled`), `liveEdgeOffset`,
`isAtLiveEdge`, `positionBasis`, `currentBandwidth`, `networkQuality`,
`bufferStatistics`, `lastBufferHealth`, the track lists/selections, and the PiP/cast status
getters mirrored on the controller.

The three live-edge getters are native-sourced and delivered on the existing `onPositionChanged`
event (see [Events](events.md#onpositionchanged)):

| Getter | Type | Value |
|---|---|---|
| `liveEdgeOffset` | `Duration?` | Distance behind the live edge. `null` for VOD and while the platform cannot answer. Reported for live streams with **and without** `enableDvr`. Android: `Player.getCurrentLiveOffset()`. iOS: end of `AVPlayerItem.seekableTimeRanges.last` minus `currentTime()`. |
| `isAtLiveEdge` | `bool` | `liveEdgeOffset <= PlaybackState.defaultLiveEdgeTolerance` (15s). `false` whenever the offset is `null`. Use `currentState.isAtLiveEdgeWithin(tolerance)` for a different threshold. |
| `positionBasis` | `PositionBasis` | Which timeline `currentState.position` is on. `liveWindow` means a **constant `position` is not a stall** — see [Live Streaming](live-streaming.md#knowing-which-timeline-position-is-on). |

## Errors

All player errors are subclasses of the sealed `MediaPlayerException`:
`MediaLoadException`, `NetworkException`, `DrmException`, `PlaybackException`,
`InvalidStateException`, `PlayerDisposedException`, `ConfigurationException`,
`PlatformOperationException`, `ProtocolMismatchException`, and the deprecated
`OperationBusyException`. Errors also surface via
`PlaybackState.state == PlayerState.error` with `errorMessage`, and as typed exceptions on
`errorStream`/`error` (above).

`MediaController` methods can additionally complete with a `TimeoutException` (not a
`MediaPlayerException`) when a native call exceeds the 10 s per-operation timeout — see
[Operation ordering](#operation-ordering-serialization-queue).

> **Deprecated: `OperationBusyException`.** Nothing in this package throws it any more —
> `MediaController` queues operations instead of rejecting them, so busy-retry handling in
> consumer code is dead as a rejection path and can be removed. The class is kept (not
> deleted) only because `MediaPlayerException` is `sealed`, so exhaustive `switch`es over the
> hierarchy must keep an arm for it. It will be removed in a future major release.

## Feeds and pooled playback

For a scrolling feed that must bound how many native decoder sessions stay alive at once, see
`MediaFeed` and `MediaPlayerPool` in [Advanced Features](advanced-features.md#media-feed) —
they own a small pool of `MediaController`s internally rather than taking one per row from the
host, which is what `MediaListPlayer` does.
