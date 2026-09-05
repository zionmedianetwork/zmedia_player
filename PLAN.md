# ZMedia Player - Roadmap

**Version:** 0.3.0
**Last Updated:** September 5, 2026
**Status:** Feature-complete for the 0.3.x line; distributed via GitHub releases.
`CHANGELOG.md`'s `[Unreleased]` holds 4 `feat:` and 12 `fix:` commits landed since the
`v0.3.0` tag (August 18, 2026) — a `feat:` present means the next release is a MINOR
bump to 0.4.0.

> This file is the authoritative implementation roadmap referenced by `CLAUDE.md`.
> It tracks current state and the real backlog. For architecture, UI/UX specs, and
> the contribution/branching/release workflow, see `CLAUDE.md`.

---

## Mission

A production-grade, enterprise-ready Flutter media player for Android and iOS with
DRM, adaptive streaming, Picture-in-Picture, casting, and live/DVR playback — built
on ExoPlayer (Android) and AVPlayer (iOS) behind a single Dart API.

---

## Environment

| | |
|---|---|
| Package version | 0.3.0 |
| Dart SDK | >=3.0.0 <4.0.0 |
| Flutter SDK | >=3.19.0 (developed on 3.44.3) |
| iOS | 13.0+ |
| Android | minSdk 23 |
| Tests | 1089 passing (Dart layer; native has none) |

---

## Implemented (shipped)

The Dart layer has **zero stubs**. Features are available on both platforms unless a
platform is called out explicitly.

### Core
- `MediaPlayer` — primary interface, MethodChannel communication, broadcast state.
- `MediaController` — facade over `MediaPlayer` (auto-hiding controls, operation locks).
- `MediaConfig`, `CrashReporter`.
- Multiple-instance registry: one instance per `playerId`, 15-minute stale cleanup.

### Playback
- play / pause / stop / seek, volume / mute.
- Playback speed 0.25x–4.0x, `boxFit`.
- Background audio via `allowBackgroundPlayback` (consumed natively on both platforms).

### Streaming
- HLS (both platforms).
- DASH (**Android only** — `DashMediaSource.kt`).
- Adaptive bitrate / bandwidth estimation (`StreamingService` + native `NetworkMonitor`).
- Quality and audio-track selection.
- Live + DVR: `enableDvr` (seek gating + DVR-window duration reporting), `liveLatency`
  (target offset from live edge; iOS 14+ only), `maxBitrate`/`minBitrate`/
  `enableAdaptiveBitrate` (track-selection bounds; iOS honors only `maxBitrate`).
- Live-edge signal: `PlaybackState.liveEdgeOffset`, `isAtLiveEdge` /
  `isAtLiveEdgeWithin(tolerance)` / `defaultLiveEdgeTolerance` (15s), and `positionBasis`
  (`PositionBasis.absolute` / `.liveWindow`) — all mirrored on `MediaPlayer` and
  `MediaController`. A live `position` is window-relative and stays ~constant at the edge,
  so `liveEdgeOffset` is the signal a stall watchdog must use (issue #88).
- Explicit format declaration: `MediaItem.streamingFormat` + the `StreamingFormat` enum
  (`hls` / `dash` / `progressive`), with `resolvedStreamingFormat`, `StreamingFormat.fromUrl`
  and `.fromName`. Decides which of `hlsConfig`/`dashConfig` applies (they are never
  cross-applied) and overrides URL inference on the Dart side and on both natives.
- Every load path (`load`, `setPlaylist`, `skipToIndex`) carries the current `MediaConfig`
  snapshot, so a reload picks up a changed config immediately.

### Subtitles
- SRT / WebVTT / ASS / SSA parsing and styling (`SubtitleService`, Dart-side).

### DRM
- Widevine (Android), FairPlay (iOS), PlayReady, token-based auth, EZDRM.
- Native certificate pinning (SHA-256 / SPKI) on license requests.

### Picture-in-Picture
- Both platforms: auto-enter-on-background, aspect ratio.
- Custom actions (**Android only** — `PipConfig.actions` renders `RemoteAction`s; taps deliver
  `PipActionEvent` on `MediaPlayer.pipActionStream`. No AVKit API exists for custom PiP action
  buttons on iOS). `showPlaybackControls` gates them on Android and partially maps to iOS
  `requiresLinearPlayback` (iOS 14+).

### Casting
- Chromecast (**Android only** — `CastHandler` + `CastOptionsProvider`).
- AirPlay (**iOS only** — `AirPlayHandler` + `AirPlayButton`).

### Notifications
- Lock-screen / Control Center media notifications (`NotificationService` + native
  handlers), action stream.
- Artwork auto-generated from a video frame when `artworkUrl` is null.
- Runtime reconfiguration via `NotificationService.updateConfig(config, playerId:)` —
  re-sends the config over `initializeNotification` and re-renders an already-showing
  notification. Config otherwise only ever reaches native at `initialize()`.

### Caching / offline (Dart-side)
- `CacheService`: progressive download, LRU eviction, expiry, size management.

### Resilience & analytics
- `NetworkResilienceService`: reconnect / retry. **Native-backed** — `NetworkMonitor`
  (`ConnectivityManager.NetworkCallback` on Android, `NWPathMonitor` on iOS) pushes
  `onNetworkStatusChanged`, and every `MediaPlayer` owns a live instance exposed as
  `networkStatus` / `networkStatusStream` / `networkChangeStream`.
- `AnalyticsService` / QoE metrics (Dart-side): startup time, rebuffering, bitrate.

### Security
- `PlatformSecureStorage` (Keychain / Keystore).
- `CertificatePinningConfig`.
- `InputValidation` (HTTPS-for-DRM enforcement).

### UI
- `MediaPlayerWidget`, `MediaListPlayer` (visibility-aware list playback), `MediaFeed`
  (player-pool-backed feed).
- Material / Cupertino / Adaptive controls.
- `FullscreenMediaPlayer` with the orientation API
  (`preferredOrientations`, `rotationLocked`, `exitOrientations`) and fullscreen variants.
- Settings / quality / audio / subtitle / speed menus; badges and overlays.
- Android native view uses true Hybrid Composition (`initExpensiveAndroidView`).

---

## Known gaps / planned

This is the real backlog. State these honestly; do not mark them done.

- **No native automated tests.** Kotlin/Swift code has no test coverage. The paths
  still needing on-device verification are DRM decryption, certificate pinning, and
  bandwidth metering. Verified on-device so far: core playback, fullscreen, custom
  controls, quality/subtitles, background audio and media notifications — including
  runtime `NotificationService.updateConfig` changes — on **both** a physical iPhone
  and a physical Android device; Chromecast discovery + load and Hybrid Composition
  fullscreen on Android (Note 9P); live DVR seek gating and DVR-window duration on
  Android against a live HLS stream (the equivalent iOS wiring is not yet verified).
- **DASH is Android-only.** No iOS DASH support.
- **Several subsystems are Dart-only** (no native counterpart): caching, analytics,
  playlist, and subtitle logic. This is acceptable but worth noting when reasoning
  about behavior. (Network resilience is *not* in this list any more — it is backed by
  the native `NetworkMonitor` on both platforms.)
- **Android background audio** needs a foreground service with a media notification
  for full support; the service infrastructure is deferred.
- **pub.dev publishing** is not done yet — the package is distributed via GitHub
  releases.
- **Flaky test:** one DRM performance test is timing-based and can flake.

---

## Contributor guidance

- **Delegate Flutter/Dart work to the `flutter-expert` subagent** (mandatory per
  `CLAUDE.md`) for anything touching `lib/`, `test/`, `example/`, or the native
  plugin layer (`android/`, `ios/`).
- **Public API:** export new public classes from the barrel file
  `lib/zmedia_player.dart`. Anything not exported is internal.
- **Native symmetry:** when adding a native capability, add the matching handler on
  both platforms to keep the MethodChannel contract symmetric. Per-feature handlers
  are mirrored under
  `android/src/main/kotlin/com/zionmedianetwork/zmedia_player/` and
  `ios/zmedia_player/Sources/zmedia_player/`.
- **UI/UX:** control overlays and menus must follow the canonical spec written out in
  `CLAUDE.md`. The reference screenshots it cites (`docs/images/screenshots/controls_*`)
  are **not in the repository**; the written spec is the authority until they are
  restored.
- **Branching & commits:** one task = one branch (`feat/`, `fix/`, `docs/`,
  `chore/`, `test/`); conventional-commit messages; commits owned by the local
  GitHub user. See the Branching Strategy and Release Workflow sections of
  `CLAUDE.md` for the full process.

### Local workflow

```bash
flutter pub get
flutter analyze
flutter test
cd example && flutter run   # manual / on-device verification
```

---

## Next candidate work

Loosely ordered, not committed. Pull from here when planning the next release.

1. Native test coverage (JUnit / XCTest) and on-device verification of the paths still
   unverified: DRM decryption, cert pinning, and bandwidth metering (casting has since
   been verified on Android; iOS AirPlay has not).
2. Android foreground-service media session for full background audio.
3. iOS DASH support (close the Android/iOS streaming gap).
4. Offline DRM: persistent Widevine / FairPlay licenses and a download queue.
5. pub.dev publishing.
6. Stabilize the flaky DRM performance test.
