# ZMedia Player - Roadmap

**Version:** 0.5.0
**Last Updated:** September 10, 2026
**Status:** Feature-complete for the 0.5.x line; distributed via GitHub releases.
`CHANGELOG.md`'s `[Unreleased]` holds the Android multi-header fix (issue #127 —
`MediaItem.httpHeaders` no longer collapses to its last entry, because
`DefaultHttpDataSource.Factory.setDefaultRequestProperties` replaces rather than merges and
was being called once per entry; iOS was never affected) together with the deprecation of the
never-wired `MediaConfig.httpHeaders`, and a new native-source-parsing regression guard,
`test/native_contract/android_http_headers_test.dart`, for a defect class neither
`flutter analyze` nor the mocked-channel suite can see. It also holds the same-family
fix one layer up: the notification-artwork frame extraction now carries
`MediaItem.httpHeaders` on both platforms (it was an unauthenticated request, so artwork
silently never appeared for a signed/authenticated media URL), guarded by
`test/native_contract/notification_artwork_headers_test.dart`.

`CHANGELOG.md`'s `[Unreleased]` additionally holds the load/error-semantics work:
a failed load now terminates in `PlayerState.error` instead of `paused`/`idle`
(issue #125), `PlayerPauseReason` became a wire-valued enum that actually emits
`user` (issue #126), and `MediaConfig.loadTimeout` bounds a load that goes silent.
Guarded by `test/native_contract/pause_reason_vocabulary_test.dart`.

The items below shipped in `v0.5.0`: the ExoPlayer 2 classpath upgrade note (issue #108),the `NetworkStatus` platform-quality fix (issue #112), the live-edge-offset
window-sanity fix (issue #109) with its manifest-anchor diagnostic (issue #110), and the
iOS counterpart to #112/#109: `NetworkMonitor.swift`'s `estimateBandwidth(from:)` no longer
reports `connectionType: "none"`/`downloadSpeed: 0` for a connected but unrecognized
transport, plus documentation of a previously-undocumented iOS behavior (iOS `downloadSpeed`
is a fixed per-transport constant, not a measurement); a behavior change so iOS's `liveLatency`
cushion is maintained after a rebuffer instead of drifting away from it indefinitely
(`AVPlayerItem.automaticallyPreservesTimeOffsetFromLive` flipped to `true`, at the cost of a
visible forward skip after each rebuffer, with no opt-out); a fix for 13 of the example app's
19 widget tests hanging on `pumpAndSettle`
against pages whose `MediaController` keeps real periodic timers (`BufferingService`/
`NetworkResilienceService`) running forever, bringing the example suite back to 19/19, then to
21/21 with the `liveEdgeOffset`/`isAtLiveEdge`/`positionBasis` readout added to
`wired_config_verification_page.dart`, then to 24/24 with a **Custom** stream-URL option added
to that same page's Source selector — pointing the harness at a stream this repo cannot itself
host (URL + `MediaItem.isLive` + an explicit `streamingFormat` override, since inference can
silently resolve a CDN-rewritten/signed URL to `progressive`, under which neither `HlsConfig`
nor `DashConfig` applies + one optional HTTP header) so the #109-shaped defect stream from a
device bug report, unreachable from the app's own bundled fixtures, can be verified the same
way without a rebuild; 11 feature pages added to `example/README.md`'s previously-incomplete
table; corrections to several stale hardcoded Dart test-suite counts across the docs; the
terminal-`error`/load-watchdog fix (issue #125) with its `MediaConfig.loadTimeout` addition
and the iOS main-thread `invokeMethod` fix found while tracing it; the native-sourced pause
attribution work (issue #126 — **breaking**: two new `PlayerPauseReason` members, and a
`pauseReasonStream` that now fires on every attributed pause rather than only on audio-focus
loss); and a documentation-only correction (issue #120) stating that `PlaybackState.liveEdgeOffset` measures
a different quantity on Android (distance from the published live edge, ~18s on a verification
stream) than on iOS (bounded near zero by construction during live playback, verified <1s on
the same stream) — making `isAtLiveEdge`/`defaultLiveEdgeTolerance` near-degenerate on iOS and
a configured `liveLatency` cushion unobservable through that field there.

`CHANGELOG.md`'s `[Unreleased]` also holds two further documentation-only corrections in the
same family. Issue #124: the docs claimed in several places that a frozen playhead grows
`liveEdgeOffset` "without bound on both platforms" (and contradicted themselves elsewhere in
the same file). It grows on **Android only** — on iOS the value is computed and emitted solely
from inside `AVPlayer.addPeriodicTimeObserver`'s block, which stops firing when time stops
progressing, so a hard stall freezes it. The documented `LiveStallWatchdog` example was also
inert during an *announced* stall on **both** platforms, because it stood down on
`state != PlayerState.playing` while a rebuffer is reported as `PlayerState.buffering`; it has
been rewritten to carry three signals (offset growth, absolute-basis position repetition, and
event staleness) and is now pinned by `test/core/live_stall_watchdog_test.dart`, which holds a
verbatim copy of it. Issue #110: "Android maintains the `liveLatency` cushion via
playback-speed adjustment" was false — verified against Media3 1.11.0's sources, the live
playback-speed control is switched off entirely for every ordinary HLS/DASH stream this
package plays, so `liveLatency` is a **join target** on Android and is *maintained* on iOS
only.

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
| Package version | see `pubspec.yaml` (also tracked in this file's own header above) |
| Dart SDK | >=3.0.0 <4.0.0 |
| Flutter SDK | >=3.19.0 (developed on 3.44.3) |
| iOS | 13.0+ |
| Android | minSdk 23 |
| Tests | 1175 passing (Dart layer; native has none) |

---

## Implemented (shipped)

The Dart layer has **zero stubs**. Features are available on both platforms unless a
platform is called out explicitly.

### Core
- `MediaPlayer` — primary interface, MethodChannel communication, broadcast state.
- `MediaController` — facade over `MediaPlayer` (auto-hiding controls, operation locks).
- `MediaConfig`, `CrashReporter`.
- Multiple-instance registry: one instance per `playerId`, 15-minute stale cleanup.

### Load & error semantics
- `load()` completing means the item was **handed to the platform**, not that it loaded —
  documented on the method, in `README.md`, `AGENTS.md` and
  [player-api.md](docs/api-reference/player-api.md#load-completing-is-not-loaded).
- `PlayerState.error` is **terminal** (issue #125): held until an explicit host command
  (`load`/`play`/`stop`/`seekTo`/`setPlaylist`/`skipToIndex`) or real forward progress from
  native. Suppressed at the source on both platforms (`Player.getPlayerError() != null` on
  Android, `currentItem?.status == .failed` on iOS) **and** latched in Dart, so new Dart
  against an older cached native build still behaves. Buffer telemetry keeps flowing while
  latched.
- `MediaConfig.loadTimeout` (issue #125) — Dart-only load watchdog, default 30s, `null`
  disables. Reports a `NetworkException` with `isTimeout: true` when a load is accepted and
  then goes silent; refuses to fire while the load is still progressing.
- `PlayerPauseReason` (issue #126) — wire-valued enum (`user`, `audioFocusLoss`,
  Android-only `audioBecomingNoisy` and `remote`) on `MediaPlayer.pauseReasonStream`, sourced
  natively on both platforms. **iOS `user` is host-inferred** (AVFoundation has no
  `reasonForPausing`) while Android's is player-reported — the same class of documented
  asymmetry as `liveEdgeOffset` (#120). An unattributed pause emits nothing rather than
  guessing. Guarded by `test/native_contract/pause_reason_vocabulary_test.dart`.

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
  (target offset from live edge; iOS 14+ only — a **join target** on both platforms, and
  *maintained* after a rebuffer on **iOS only**, via a visible forward skip since
  `automaticallyPreservesTimeOffsetFromLive = true`, with no opt-out. Android does not
  maintain it: ExoPlayer's live playback-speed control is switched off for ordinary HLS/DASH
  streams, issue #110),
  `maxBitrate`/`minBitrate`/`enableAdaptiveBitrate` (track-selection bounds; iOS honors
  only `maxBitrate`).
- Live-edge signal: `PlaybackState.liveEdgeOffset`, `isAtLiveEdge` /
  `isAtLiveEdgeWithin(tolerance)` / `defaultLiveEdgeTolerance` (15s), and `positionBasis`
  (`PositionBasis.absolute` / `.liveWindow`) — all mirrored on `MediaPlayer` and
  `MediaController`. A live `position` is window-relative and stays ~constant at the edge,
  so `liveEdgeOffset` — not `position` — is the signal a stall watchdog must use (issue #88),
  paired with an event-staleness check because iOS emits nothing at all during a hard stall
  and the offset freezes rather than growing there (issue #124). Android's
  `liveEdgeOffset` is sanity-checked against the live window's own duration before being
  trusted, falling back to a bounded computation when a manifest's unix-time anchor
  disagrees with its own segment timeline (issue #109); the same anchor defect silently
  defeats `liveLatency` on an affected manifest, which native now flags with a one-time
  diagnostic (issue #110) — see
  [live-streaming.md](docs/api-reference/live-streaming.md#manifest-time-anchor-defect-liveedgeoffset-and-livelatency).
  **Android and iOS measure `liveEdgeOffset` itself differently and the values are not
  comparable** (issue #120): Android reports distance from the published live edge (~18s
  verified on-device); iOS is bounded near zero by construction (<1s verified on the same
  stream), making `isAtLiveEdge`/`defaultLiveEdgeTolerance` near-degenerate on iOS and a
  `liveLatency` cushion held there unobservable through this field — see
  [Platform divergence](docs/api-reference/live-streaming.md#platform-divergence-this-value-measures-different-things).
- Explicit format declaration: `MediaItem.streamingFormat` + the `StreamingFormat` enum
  (`hls` / `dash` / `progressive`), with `resolvedStreamingFormat`, `StreamingFormat.fromUrl`
  and `.fromName`. Decides which of `hlsConfig`/`dashConfig` applies (they are never
  cross-applied) and overrides URL inference on the Dart side and on both natives.
- Every load path (`load`, `setPlaylist`, `skipToIndex`) carries the current `MediaConfig`
  snapshot, so a reload picks up a changed config immediately.
- Per-item HTTP headers: `MediaItem.httpHeaders` is the canonical, wired path and **every**
  entry reaches the wire on both platforms (Android: one
  `DefaultHttpDataSource.Factory.setDefaultRequestProperties` call with the whole map; iOS:
  one `AVURLAssetHTTPHeaderFieldsKey` assignment, with `Cookie` promoted to
  `AVURLAssetHTTPCookiesKey`). Android previously sent only the map's last entry (issue #127),
  now guarded by `test/native_contract/android_http_headers_test.dart`.
  `MediaConfig.httpHeaders` is deprecated and inert — no native code has ever read
  `config["httpHeaders"]`.
- The headers also reach the **notification-artwork** frame extraction, which makes its own
  HTTP requests against the media URL (Android `MediaMetadataRetriever`, iOS
  `AVAssetImageGenerator`) and used to make them unauthenticated — artwork silently never
  appeared for a signed/authenticated URL. `NotificationService.show()` now sends
  `httpHeaders` on its `mediaItem` payload; guarded by
  `test/native_contract/notification_artwork_headers_test.dart`. They are deliberately not
  applied to a `MediaItem.artworkUrl` fetch (independent, often third-party host).

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
- Artwork auto-generated from a video frame when `artworkUrl` is null; that frame fetch
  carries the item's `MediaItem.httpHeaders` on both platforms, so it works against an
  authenticated or signed media URL.
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
- **Authenticated notification artwork is unverified on device.** The frame extraction now
  receives `MediaItem.httpHeaders` on both platforms, but that is confirmed by source
  inspection and source-text guards only — no automated test executes Kotlin or Swift. Still
  to confirm on a device against a real signed/authenticated stream: that artwork appears
  where it previously did not, that a signed-cookie CDN is satisfied by the iOS
  `AVURLAssetHTTPCookiesKey` path in `makeAVURLAsset`, and that an unauthenticated URL (empty
  header map) is unchanged.

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
