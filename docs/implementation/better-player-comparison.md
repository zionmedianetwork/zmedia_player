# Better Player vs ZMedia Player — Feature Comparison

A single, current comparison between [`better_player`](https://pub.dev/packages/better_player)
and `zmedia_player`. This is the canonical comparison doc (the former
`better-player-parity.md` has been folded in here).

## Executive summary

`zmedia_player` is at **effective feature parity** with `better_player` for everything a
production media app needs — and goes beyond it in a few areas (ASS/SSA subtitles, real-time
bandwidth estimation, a dedicated quality-tracks stream). The differences are architectural:
`zmedia_player` integrates **directly** with AndroidX Media3/ExoPlayer (Android) and AVPlayer (iOS) rather than
layering on top of `video_player`/Chewie, and exposes a **stream-based, type-safe** API instead
of a single callback bus.

- **Architecture:** direct native integration (no `video_player` intermediary).
- **API:** unified `MediaConfig`, `MediaItem`, and per-event broadcast streams; `MediaController`
  (`ChangeNotifier` facade) over a lower-level `MediaPlayer`.
- **Remaining gaps vs better_player:** playlist persistence and thumbnail/preview generation are
  not built in (both are easy to do in app code); iOS DASH is not supported (Android only);
  native Kotlin/Swift code has no automated tests yet.

## Package overview

| | Better Player | ZMedia Player |
|---|---|---|
| Base | Chewie + `video_player` | Direct AndroidX Media3/ExoPlayer / AVPlayer integration |
| API style | Callback event bus (`addEventsListener`) | Per-event broadcast streams + `ChangeNotifier` |
| License | Apache-2.0 | MIT |
| Status | Maintained | Active |

---

## Feature comparison matrix

Legend: ✅ implemented · ➖ not built in (do in app code) · 🟦 platform-specific · ⭐ beyond better_player

| Feature | Better Player | ZMedia Player | Notes |
|---|---|---|---|
| **Core playback** | | | |
| Play / pause / stop | ✅ | ✅ | |
| Seek (+ seekForward/Backward helpers) | ✅ | ✅ | |
| Volume / mute | ✅ | ✅ | 0.0–1.0 |
| Playback speed | ✅ | ✅ | 0.25×–4.0× |
| Progress tracking | ✅ | ✅ | Real-time position stream |
| **Media formats** | | | |
| MP4 / MOV / AVI, audio, network, local, asset | ✅ | ✅ | Native player formats |
| **Streaming** | | | |
| HLS (+ track selection, subtitles) | ✅ | ✅ | Both platforms |
| DASH | ✅ | 🟦 ✅ Android | iOS DASH not supported |
| Adaptive bitrate / auto quality | ✅ | ✅ | `StreamingService` + native ABR |
| Manual quality / audio track selection | ✅ | ✅ | |
| Bandwidth estimation | ➖ | ⭐ ✅ | Real-time `bandwidthStream` |
| **Subtitles** | | | |
| SRT / WebVTT (+ HTML), external files, styling | ✅ | ✅ | `SubtitleService` |
| Multiple tracks + runtime switching | ✅ | ✅ | |
| ASS / SSA | ➖ | ⭐ ✅ | Advanced SubStation Alpha |
| **Playlist** | | | |
| Sequential / shuffle / repeat (none/single/all) | ✅ | ✅ | Fisher–Yates shuffle |
| Add/remove/move, next/previous, queue | ✅ | ✅ | |
| Extend/re-issue the queue without restarting the current item | ➖ | ⭐ ✅ | `setPlaylist` skips the reload for an unchanged, in-progress start item |
| Playlist persistence (save/restore) | ✅ | ➖ | Not built in; do in app code |
| **Configuration** | | | |
| HTTP headers, BoxFit, autoplay, looping | ✅ | ✅ | Unified `MediaConfig` |
| Background playback | ✅ | ✅ | Config-driven on both platforms |
| **UI** | | | |
| Default + fully custom controls | ✅ | ✅ | Material / Cupertino / Adaptive |
| Controls auto-hide, progress bar | ✅ | ✅ | |
| Buffering / error / placeholder widgets | ✅ | ✅ | |
| Fullscreen | ✅ | ✅ | `FullscreenMediaPlayer` + orientation API (`preferredOrientations` / `rotationLocked` / `exitOrientations`) |
| **Advanced** | | | |
| Picture-in-Picture | ✅ | ✅ | Both platforms; auto-enter-on-background, custom actions |
| Media notifications (lock screen) | ✅ | ✅ | Both platforms; action stream; artwork auto-generated from a video frame when absent. Seek-forward/backward controls are opt-in (`showSeekForward`/`showSeekBackward`) and gated on seekability on both platforms. Config is applied at `initialize()` and changed at runtime via `NotificationService.updateConfig` |
| ListView integration (auto play/pause) | ✅ | ✅ | `MediaListPlayer` (visibility-aware) |
| Disk cache + download-to-play (LRU, progress) | ✅ | ✅ | `CacheService` (Dart); non-DRM only — no offline DRM license on either platform |
| Thumbnail / preview generation | ✅ | ➖ | Not built in |
| **Casting** | | | |
| Chromecast | ➖ | 🟦 ✅ Android | `CastHandler` + `CastOptionsProvider` (Google Play Services) |
| AirPlay | ➖ | 🟦 ✅ iOS | `AirPlayHandler` + `AirPlayButton` |
| **DRM** | | | |
| Widevine (Android) | ✅ | ✅ | `DrmHandler` |
| FairPlay (iOS) | ✅ | ✅ | `DrmHandler` |
| ClearKey / token-based / EZDRM | partial | ✅ | `DrmScheme` enum; token + EZDRM factories |
| PlayReady | ➖ | 🟦 not functional | `DrmScheme.playready` exists, but Android gates on `isPlayReadySupported()` (fails without a system CDM on most devices) and iOS has no PlayReady path at all |
| Certificate pinning on license requests | ➖ | ⭐ ✅ | SHA-256/SPKI pins, native |
| **Events & state** | | | |
| State / position / duration / volume / speed streams | callback | ✅ streams | Typed broadcast streams |
| Subtitle / audio / quality tracks streams | partial | ✅ | Quality-tracks stream ⭐ |
| Buffering / error / ready / completion events | ✅ | ✅ | |
| Buffer health + network-quality streams | ➖ | ⭐ ✅ | `BufferingService` / `NetworkResilienceService` |
| QoE / analytics metrics | ➖ | ⭐ ✅ | `AnalyticsService` (`QoEMetrics`) |
| **Platform** | | | |
| Android (AndroidX Media3/ExoPlayer) / iOS (AVPlayer) | ✅ | ✅ | Direct integration both sides |
| Secure storage (Keychain / Keystore) | ➖ | ⭐ ✅ | DRM tokens / credentials |

---

## API structure comparison

**Better Player** — separate config + data-source classes, one callback bus:

```dart
final controller = BetterPlayerController(
  BetterPlayerConfiguration(autoPlay: true, looping: false),
);
await controller.setupDataSource(
  BetterPlayerDataSource(BetterPlayerDataSourceType.network, 'https://…/video.m3u8'),
);
controller.addEventsListener((event) {
  if (event.betterPlayerEventType == BetterPlayerEventType.play) { /* … */ }
});
BetterPlayer(controller: controller);
```

**ZMedia Player** — unified config + `MediaItem`, per-event streams:

```dart
final controller = MediaController.create(
  config: const MediaConfig(autoPlay: true, looping: false, showControls: true),
);
await controller.load(const MediaItem(
  id: '1', title: 'Video', url: 'https://…/video.m3u8',
));
controller.player.stateStream.listen((state) {
  if (state.state == PlayerState.playing) { /* … */ }
});
MediaPlayerWidget(controller: controller, showControls: true);
```

| Aspect | Better Player | ZMedia Player |
|---|---|---|
| Configuration | Separate config classes | Unified `MediaConfig` |
| Events | Single callback bus | Per-event typed streams |
| Data source | Separate `DataSource` | Integrated `MediaItem` |
| State | Manual polling | `ChangeNotifier` + streams |

---

## Architecture comparison

```
Better Player                         ZMedia Player
BetterPlayer (widget)                 MediaPlayerWidget
  → BetterPlayerController              → MediaController (facade)
  → VideoPlayerController (pkg)         → MediaPlayer (core)
  → platform channels                  → platform channels (direct)
  → ExoPlayer / AVPlayer               → AndroidX Media3/ExoPlayer / AVPlayer
```

Better Player reuses `video_player` (less native code, but an extra abstraction and a
feature ceiling set by that package). ZMedia Player integrates with the native players
directly — more native code to maintain, in exchange for control and feature velocity. The
native layer is decomposed into symmetric per-feature handlers on both platforms (see
`docs/implementation/README.md`).

---

## Migration path from Better Player

| Better Player | ZMedia Player |
|---|---|
| `BetterPlayerController` | `MediaController` |
| `BetterPlayerConfiguration` | `MediaConfig` |
| `BetterPlayerDataSource` | `MediaItem` |
| `BetterPlayer` widget | `MediaPlayerWidget` |
| `addEventsListener()` | per-event streams on `controller.player` |
| `setupDataSource()` | `load()` / `setPlaylist()` |
| `play()` / `pause()` / `seekTo()` / `setVolume()` | same |
| `videoPlayerController.value` | `controller.state` (richer model) |

---

## Remaining gaps (the honest backlog)

These are the only meaningful things `better_player` offers that `zmedia_player` does not build
in today:

1. **Playlist persistence** — save/restore queue state. Easy in app code (shared prefs / DB).
2. **Thumbnail / preview generation** — video-frame extraction for scrubbing previews.
3. **iOS DASH** — DASH is Android-only here (HLS covers iOS adaptive streaming).
4. **Native automated tests** — Kotlin/Swift handlers have no unit tests yet; DRM decryption,
   certificate pinning, casting, and bandwidth metering need on-device verification.

Everything else better_player provides is implemented. See [`PLAN.md`](../../PLAN.md) for the
maintained current-state roadmap and [`docs/summary/features.md`](../summary/features.md) for the
full feature inventory.

---

**Last updated:** August 17, 2026
