# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.5] - 2026-07-01


### Other Changes

- Merge pull request #63 from zionmedianetwork/fix/native-surface-leak-grey-systemui (@Adolphe Cher-Aime) (e7f6257)
- Merge pull request #62 from zionmedianetwork/fix/release-version-from-tag (@Adolphe Cher-Aime) (a025aa5)
- ci(release): derive current version from latest tag, not main pubspec (@Adolphe Cher-Aime) (cad9954)

**Full Changelog**: https://github.com/zionmedianetwork/zmedia_player/compare/v0.2.4...v0.2.5

## [Unreleased]

### BREAKING
- Removed `DrmConfig.allowOffline`, `DrmConfig.offlineLicenseDuration`, and
  `DrmConfig.autoRenewLicense` (and the corresponding constructor/factory parameters,
  `toMap`/`fromMap` keys, `==`/`hashCode`, and `copyWith` params). These fields never
  functioned: on Android, the offline-license methods they configured
  (`DrmHandler.acquireOfflineLicense`, `releaseOfflineLicense`, `renewOfflineLicense`)
  were stubs that always failed or no-op'd, and none of the three was reachable from the
  MethodChannel; iOS had no equivalent at all. Removing them changes no runtime
  behaviour — callers setting these fields were already getting no offline support and
  no auto-renewal. Offline DRM remains a planned future feature (see the
  [Offline DRM Roadmap](docs/api-reference/drm.md#offline-drm-roadmap) in the DRM guide);
  it will be reintroduced with a real, wired implementation rather than as inert config.
- Removed `CastDeviceType.dlna` and `CastDeviceType.miracast`. Neither value could ever
  be produced by native code — Android's `CastHandler` only emits `"chromecast"`, iOS's
  `AirPlayHandler` only emits `"airplay"`, and `CastDevice.fromMap` already falls back to
  `CastDeviceType.unknown` for anything else — so both variants were unreachable dead
  code. The corresponding unreachable `case CastDeviceType.dlna:` icon branch in
  `MediaControls` was also removed.
- Removed `CastConfig.enableDlna` (no DLNA support exists anywhere in this package) and
  `CastConfig.autoConnect` (auto-connecting to the last-used cast device would require
  persisting a device identifier and reacting to discovery results; no such mechanism
  exists in this package, and building a bespoke storage subsystem just for this field
  was out of scope). Both were already dead: neither was read by native code prior to
  this release. `CastConfig.enabled`, `enableChromecast`, `enableAirPlay`,
  `chromecastAppId`, `discoveryTimeout`, and `showCastButton` are unaffected.
- Removed `MediaConfig.notificationConfig`. Nothing ever read it — media playback
  notifications are configured exclusively through `NotificationService`'s own
  `NotificationConfig`, which is unaffected by this change.
- `NotificationConfig.priority` now defaults to `null` ("no explicit priority
  requested") instead of `NotificationPriority.high`. Native (`NotificationHandler`
  on Android) already resolves a missing/unrecognized priority to `IMPORTANCE_LOW`/
  `PRIORITY_LOW`, so this restores the pre-existing default behaviour every
  integrator who never set `priority` was already getting, and avoids a silent
  regression the `.high` default caused: this notification re-posts on every
  playback state/position tick, so a non-`low` default made every existing
  integrator's notification newly re-alert (sound/heads-up) on every tick purely
  from upgrading, with no code change on their part — and on Android specifically,
  triggered `NotificationManagerService`'s "noisy notification" throttling, which
  force-muted the notification altogether after a burst of ticks. An app that wants
  a louder/heads-up notification should now set `priority` explicitly (e.g.
  `NotificationPriority.high`). Source-breaking only for callers that relied on the
  removed non-`null` default's static type; passing an explicit
  `NotificationPriority` value is unaffected.

### Fixed
- Toggling live-stream DVR (`HlsConfig.enableDvr`/`DashConfig.enableDvr`) while the
  same media item keeps playing no longer leaves the lock-screen / notification
  scrubber permanently stuck at whichever seekability it had when the notification
  was first shown. `NotificationService.updateState()` (called on every
  `MediaPlayer.stateStream` event, not just once from `show()`) now re-sends the
  current `isLive`/`dvrEnabled` on every call, and `NotificationHandler` on both
  Android and iOS re-derives `isSeekable` and re-applies gating (Android:
  `ACTION_SEEK_TO` + `METADATA_KEY_DURATION`; iOS:
  `changePlaybackPositionCommand`/`skipForwardCommand`/`skipBackwardCommand` +
  `MPMediaItemPropertyPlaybackDuration`) from it. Previously only `show()` sent these
  fields, which — unlike title/artist — do not only change when the media item
  itself changes, so a DVR toggle on an already-playing live item (`updateConfig` +
  reload) went unnoticed by native indefinitely.
- Android media notifications no longer get silently muted by the OS
  ("`Muting recently noisy ...`" in logcat) after a burst of playback state/position
  updates. `NotificationHandler`'s `NotificationCompat.Builder` now sets
  `setOnlyAlertOnce(true)`: this notification is rebuilt and re-posted on every
  state/position tick, and without `onlyAlertOnce` each repost counted as a distinct
  alert to `NotificationManagerService`, which throttles and force-mutes a channel
  that alerts too frequently.
- `CastConfig` now actually reaches and does something on native code, on both
  platforms — previously it was silently dropped at three independent points, any one
  of which alone was sufficient to make it inert:
  - `MediaPlayer._ensureCastInitialized()` sent a freshly-constructed
    `const CastConfig()` default to the `initializeCast` channel call instead of the
    caller's `MediaConfig.castConfig`, discarding every field the caller set. It now
    sends `MediaConfig.castConfig` (falling back to a default only when unset).
  - Android's `CastHandler.initialize()` stored the config but never read it, and
    unconditionally used a hardcoded `"CC1AD845"` receiver app ID. It now honours
    `enabled`/`enableChromecast` (skipping native Cast setup when either is false),
    `chromecastAppId` (falling back to `"CC1AD845"`, Google's Default Media Receiver,
    when unset), and `discoveryTimeout` (auto-stops device discovery after the
    configured number of seconds).
  - iOS's `AirPlayHandler.initialize(config:player:)` stored the config but never read
    a single field from it. It now honours `enabled`/`enableAirPlay`, explicitly
    disabling `AVPlayer.allowsExternalPlayback` when either is false (previously,
    "disabling" AirPlay via config had zero effect since `AVPlayer` defaults that flag
    to `true`). `chromecastAppId` is Chromecast-only and is correctly never read here.
- Dragging the lock-screen / Control Center notification progress bar ("seekTo") now
  actually seeks the player, on both platforms (M-02). Previously:
  - Android: `NotificationHandler`'s `MediaSessionCompat.Callback.onSeekTo` was a
    literal no-op — the callback fired and did nothing.
  - iOS: `changePlaybackPositionCommand` already forwarded the requested position
    natively, but had nowhere to put it — `NotificationService.actionStream` was a
    bare `Stream<String>` and `MediaPlayer._handleNotificationAction` only ever
    extracted `arguments['action']`, so the forwarded position was silently dropped
    in Dart regardless of platform.
  - Fix: `android/.../NotificationHandler.kt`'s `onSeekTo` now forwards the
    requested position (milliseconds) via `sendActionToFlutter("seekTo", pos)`,
    matching iOS's existing `{"action": "seekTo", "position": <ms>}` payload shape
    exactly. A new `NotificationActionEvent` model (`action` + optional
    `Duration? position`) is parsed from that payload and delivered on two new
    typed streams: `MediaPlayer.notificationActionEventStream` and
    `NotificationService.actionEventStream`. The existing `Stream<String>`
    `MediaPlayer.notificationActionStream` / `NotificationService.actionStream` are
    kept working (and receive `"seekTo"` too, just without a position) but are now
    `@Deprecated` in favor of the typed streams. As with every other notification
    action, **the host app — not the package — is responsible for calling
    `controller.seekTo(event.position)`** on receipt; see the updated
    `docs/api-reference/advanced-features.md` snippet and the example app
    (`example/lib/pages/notifications_page.dart`,
    `example/lib/pages/multi_player_page.dart`).

- iOS: setting the playback speed no longer starts playback, so `MediaConfig.autoPlay:
  false` is finally honoured. On `AVPlayer`, assigning a non-zero `rate` **is** a
  transport command (equivalent to `play()` at that rate), and both
  `setPlaybackSpeed(speed:)` and `applyConfig()` assigned it directly. Because
  `MediaPlayer.load()`/`setPlaylist()` reset the speed to 1.0x on every load, every iOS
  player began playing as soon as its item reached `readyToPlay` — regardless of
  `autoPlay`. Any host keeping more than one `MediaController` alive (feeds, carousels,
  pre-warmed neighbours) got audio from players it never asked to play. Android was
  unaffected: ExoPlayer's `setPlaybackSpeed` changes `PlaybackParameters` and never
  touches `playWhenReady`.
  - `MediaPlayerInstance` now stores the requested speed separately from transport
    state. `setPlaybackSpeed` sets `AVPlayer.defaultRate` (iOS 16+), which never starts
    playback, and only assigns `rate` when the player is not paused. `play()` applies
    the stored speed (via `defaultRate` on iOS 16+, via `rate` pre-16, where starting
    *is* the intent), so a speed set while paused is honoured on the next play instead
    of being dropped.
  - `applyConfig()` routes `config["speed"]` through `setPlaybackSpeed` instead of
    assigning `player.rate`, which had started playback on every initialize.
  - `loadMediaItem`'s autoplay branch calls `play()` rather than `avPlayer?.play()`, so
    autoplay starts at the requested speed and configures the audio session identically
    to an explicit play.
  - Dart: the load-time speed reset in `MediaPlayer.load()` and `setPlaylist()` is now
    skipped when the speed is already 1.0 — the round trip was pure overhead, and it was
    the call that reached the iOS defect. The reset itself is kept, so a 2x speed still
    does not leak from one media item into the next.

- Grey video surface and Android "System UI has stopped" after prolonged use
  resolved — both were the same root cause: one shared player driving multiple
  native render surfaces as the host app mounts the player at up to three sites
  (inline / MiniPlayer / fullscreen) for a single controller and swaps between
  them on tab changes, fullscreen enter/exit and live recovery reloads.
  - iOS: each `UiKitView` host created its own `AVPlayerLayer` bound to the same
    `AVPlayer`, and every layer was re-bound on load/ready. A single `AVPlayer`
    driving more than one `AVPlayerLayer` is undefined behaviour on iOS and
    leaves the losing layer(s) grey — an orphan the host app cannot clear by
    navigating. `MediaPlayerInstance` now enforces a single active layer:
    `activateTopmostView()` binds only the most-recently-created (topmost) view
    and unbinds all others; `MediaPlayerView.onDeinit` promotes the next view
    when a host is torn down; and `handleAppDidBecomeActive` only re-attaches on
    the active view. (The prior standby re-attach only covered background→
    foreground, not reparent churn.)
  - Android: the platform view was a programmatic `PlayerView` (defaulting to a
    `SurfaceView`), whose dedicated SurfaceFlinger layer + BufferQueue was not
    reliably released on `dispose()`. Repeated create/dispose leaked graphics
    buffers until SurfaceFlinger / `system_server` was exhausted. The view is
    now inflated from `res/layout/zmedia_player_view.xml` with
    `app:surface_type="texture_view"`, and `dispose()` detaches the player and
    removes the view from its parent so the `TextureView` surface is freed
    immediately.
- Chromecast discovery never finding devices resolved: `MediaPlayer` never invoked
  the `initializeCast` method channel, so the native `CastHandler` was never created
  on the `MediaController`/`MediaPlayer` path (only the separate `CastService` called
  it). `startCastDiscovery` then ran `castHandlers[playerId]?.startDiscovery()` as a
  null-safe no-op that still reported success, leaving the UI spinning forever with
  zero devices. `MediaPlayer` now lazily calls `initializeCast` (once, guarded) before
  `startCastDiscovery`, `connectToCastDevice`, and `loadMediaOnCastDevice`.
- Chromecast crash on device selection resolved: `CastHandler.loadMedia` polled
  `RemoteMediaClient` readiness on `Dispatchers.IO`, but the poll reads the Cast SDK's
  `SessionManager.getCurrentCastSession()`, which asserts the main thread and threw
  `IllegalStateException` off the IO worker, hard-crashing the app on the first cast.
  The poll now runs on `Dispatchers.Main`; `delay()` suspends rather than blocks the
  thread, so the UI stays responsive (no ANR).
- Android fullscreen-exit crash/black-screen resolved: `MediaPlayerWidget` now composites
  the Android video surface with true Hybrid Composition
  (`PlatformViewsService.initExpensiveAndroidView`) instead of a Virtual Display
  `AndroidView`. This removes `VirtualDisplayController` entirely, eliminating the
  `getRenderTargetWidth → getWidth()`-on-null NPE that fired when a resize was posted to
  the platform `Handler` after the `SurfaceProducer` was released on exit. iOS `UiKitView`
  is unchanged.

### Changed
- iOS: `isPlaying` is now `timeControlStatus != .paused` instead of `rate > 0`, and the
  `readyToPlay` state notification uses the same test. **Behaviour change:** a player
  that has been told to play but is still buffering now reports `isPlaying == true`
  (previously `false` whenever `rate` dropped to 0 mid-stall). This reports intent to
  play rather than "currently emitting frames"; consumers keying UI off `isPlaying`
  should verify the new semantics suit them.

### Added
- `FullscreenMediaPlayer` orientation control (non-breaking; defaults preserve the prior
  landscape-locked behavior):
  - `preferredOrientations` — orientations applied while fullscreen is active
    (e.g. portrait fullscreen or portrait + free rotation).
  - `rotationLocked` — a `ValueListenable<bool>` that live-pins the device to portrait
    when true and re-applies `preferredOrientations` when false.
  - `exitOrientations` — orientations restored when the route pops (default: all four).

## [0.2.2] - 2026-06-25

### Fixed
- Fullscreen black-screen-with-audio resolved: when `FullscreenMediaPlayer` mounted a
  second `MediaPlayerWidget` for the same `playerId` while the inline player stayed
  mounted, two Android `AndroidView` hosts contended for one ExoPlayer surface and the
  fullscreen host rendered black. `getPlayerView()` now creates a fresh view per host
  (detaching ExoPlayer from the previous view first), and a new `reclaimVideoSurface()`
  re-attaches the player when a host mounts. iOS was already a multi-view design and is
  unaffected. The example demonstrates the recommended single-view usage pattern.
- `PipConfig.autoEnterOnBackground` is now forwarded to native on both iOS and Android.
  Previously, `checkPipAvailability()` sent only `playerId` over the method channel;
  the PiP config was never transmitted, so `canStartPictureInPictureAutomaticallyFromInline`
  (iOS 14.2+) and `setAutoEnterEnabled` (Android 12+) were silently never set.
- iOS `PipHandler.initialize(player:playerLayer:)` now accepts an optional `config`
  parameter; when provided it is persisted and applied via
  `canStartPictureInPictureAutomaticallyFromInline` on every code path, including the
  unchanged-layer branch that previously skipped `setupPipController`.
- Android `PipHandler.applyConfig()` introduced so that the config primed during
  `checkPipAvailability` is available when `enterPip` is subsequently called.
- `MediaConfig.allowBackgroundPlayback` is now consumed natively:
  - iOS: configures `AVAudioSession` category `.playback` at `applyConfig` time so
    audio continues when the app is backgrounded (host app must declare
    `UIBackgroundModes: audio` in Info.plist).
  - Android: sets ExoPlayer `WAKE_MODE_NETWORK` so the CPU/wifi lock is held during
    background playback (host app must run a foreground service with a media
    notification for full background audio; that service infrastructure is deferred).

## [Unreleased]

### BREAKING
- Renamed the `RepeatMode` enum to `MediaRepeatMode` (values `none`/`single`/`all`)

### Added
- Swift Package Manager support for iOS (alongside CocoaPods); enable with `flutter config --enable-swift-package-manager`
- `MediaConfig.respectSafeArea` — inset the video below the status bar/notch via `SafeArea`
- `MediaConfig.immersiveLandscape` — hide the system status bar in landscape (restored on portrait/dispose)
- Media-notification artwork auto-generated from a video frame when `MediaItem.artworkUrl` is absent (iOS `AVAssetImageGenerator`, Android `MediaMetadataRetriever`)
- DRM wired end-to-end on Android (Widevine) and iOS (FairPlay)
- CI/CD pipeline with automated testing, linting, and analysis
- Pre-commit hooks for code quality enforcement
- Automated release workflow with semantic versioning

### Changed
- Minimum iOS version raised from 12.0 to 13.0 (Swift concurrency; Flutter 3.44 dropped iOS 12)

### Fixed
- iOS landscape video scaling — `AVPlayerLayer` now resizes correctly on rotation
- `boxFit` property changes now propagate to the native view
- Multi-instance `MethodChannel` routing (events delivered to the correct player instance)
- Native certificate-pinning enforcement on DRM license requests
- Secure storage no longer downgrades to plaintext
- `PlaybackState.bufferedPosition` restored
- Control widgets now cancel their stream subscriptions (no leaked subscriptions)
- HTTPS enforced for DRM license/media URLs
- Deprecated `Color.withOpacity()` replaced with `Color.withValues(alpha:)`
- Deprecated `WillPopScope` replaced with `PopScope`
- Deprecated `onPopInvoked` replaced with `onPopInvokedWithResult`
- Removed unused fields and debug print statements

## [0.1.0] - 2025-01-15

Initial release of ZMedia Player - A comprehensive Flutter media player package.

### Features
- Video and audio playback
- iOS and Android support
- DRM support (Widevine, FairPlay)
- Adaptive streaming (HLS, DASH)
- Chromecast and AirPlay support
- Picture-in-Picture mode
- Live streaming with DVR
- Subtitle support (SRT, WebVTT, ASS, SSA)
- Playback analytics and metrics
- Caching and offline playback
- Customizable player controls
- Playlist management

### Platform Support
- **Android**: Minimum SDK 21 (Lollipop)
- **iOS**: Minimum iOS 13.0 (corrected; see Unreleased "Changed")

### Installation
```yaml
dependencies:
  zmedia_player:
    git:
      url: https://github.com/zionmedianetwork/zmedia_player.git
      ref: v0.1.0
```

### Documentation
- Comprehensive API documentation
- Example app with all features
- Migration guides and tutorials

[Unreleased]: https://github.com/zionmedianetwork/zmedia_player/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/zionmedianetwork/zmedia_player/releases/tag/v0.1.0
