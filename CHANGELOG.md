# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- **13 of the example app's 19 widget tests hung and failed with `pumpAndSettle timed out`**,
  in `example/test/pages/wired_config_verification_page_test.dart` (all 6),
  `example/test/pages/measurement/scroll_bandwidth_page_test.dart` (5 of 5) and
  `example/test/pages/measurement/live_offscreen_bandwidth_page_test.dart` (2 of 3) — a
  pre-existing regression, reproduced identically against a clean `origin/main` worktree, not
  introduced by this branch. All three pages mount a real (mocked-channel) `MediaController`
  that calls `initialize()`/`load()`, which starts `BufferingService.startMonitoring`'s
  periodic 500ms `Timer` (and, on `wired_config_verification_page_test.dart`,
  `NetworkResilienceService`'s 5s one too); each tick round-trips the mocked platform
  buffer-status channel and schedules a new frame, so `pumpAndSettle` — which waits for zero
  scheduled frames — could never converge on these pages and always burned its full retry
  budget before throwing. `example/test/pages/media_feed_pool_page_test.dart` had already hit
  and solved the identical problem (see its `_pumpOnDeviceScreen`/`_cleanUp` doc comments);
  the three fixed files now follow the same established pattern — bounded, explicitly-sized
  `pump()` sequences instead of `pumpAndSettle`, each sized to the specific async chain it
  follows (initial `initialize()`/`load()`, a reload via `updateConfig()`+`load()`, or a
  single mocked platform round trip) — rather than waiting for a tree that never settles. No
  assertion was weakened or removed: the DVR-toggle-reloads-and-flips-the-seek-outcome
  end-to-end coverage in `wired_config_verification_page_test.dart` and the narrow-viewport
  layout regression coverage in all three files still run, and still pass for the reason they
  were written to check. One additional latent issue surfaced and was fixed while bounding
  `scroll_bandwidth_page_test.dart`'s teardown: a `MediaListPlayer` visibility-driven
  autoplay/pause `Future.delayed(300ms)` could still be pending when a test ended right after
  dragging the feed, tripping flutter_test's "Timer is still pending" invariant — its
  `_cleanUp` now flushes a bounded window sized past that debounce. The v0.3.0 GitHub release
  body claimed "871 package tests and 19 example tests pass" — that published artifact is
  unchanged (it is a historical record), but it is the origin of the "19 example tests pass"
  claim that has been false since whichever change introduced these hangs, undetected because
  no in-repo doc asserted the example suite's count at all (see the `Changed` entry below).
  Result: 19/19 example tests passing; the package suite is unaffected.

- **iOS `NetworkMonitor.estimateBandwidth(from:)` reported `connectionType: "none"` and
  `downloadSpeed: 0` for a *connected* `NWPath`, the iOS counterpart to issue #112's Android
  fix.** Its final fallthrough — reached for a satisfied path whose interface matched none of
  `.wiredEthernet`/`.wifi`/`.cellular`/`.loopback`/`.other` — returned `(0.0, "none")`, the same
  shape `offlineStatus()` uses for a genuine disconnection. `"none"` is meant to be a reliable
  reachability discriminator independent of `quality`/`isAvailable` (see the `onNetworkStatusChanged`
  discussion added for #112); this fallthrough silently broke that promise on iOS. It now returns
  `(1.0, "unknown")`, mirroring `NetworkMonitor.kt`'s own unrecognized-transport fallthrough
  (`estimateBandwidthFromType`'s `else -> 1000` Kbps / `connectionType`'s `else -> "unknown"`).
  Both genuine offline paths (`offlineStatus()` and the `guard path.status == .satisfied` early
  return in `getNetworkStatus(from:)`) are unchanged and still report `"none"`/`0`/`"offline"`.
  `test/models/network_status_vocabulary_test.dart`'s drift guard already covers the new literal
  (`"unknown"` was already an accepted intentional-fallback value) — no test change was needed.

- **`cd example && flutter analyze` reported 2 warnings**, both in `example/pubspec.yaml`:
  `invalid_dependency` (a publishable-looking package with a `path: ../` dependency and no
  `publish_to` marker) and `asset_directory_does_not_exist` (a declared `assets/images/` with
  no corresponding directory and no reference anywhere under `example/lib`). Added
  `publish_to: none` — the example is never published — and removed the dead `assets/images/`
  entry; the sibling `assets/videos/` entry is unchanged and still backs
  `local_file_playback_page.dart`. `cd example && flutter analyze` now reports 0 issues,
  which is what lets the new `example-tests` CI job (see the `Added` entry below) enforce a
  clean analyze rather than tolerate pre-existing warnings.

### Changed
- **`example/README.md`'s feature table was missing 11 of the app's 27 feature pages** —
  `local_file_playback_page.dart`, `cache_playback_page.dart`,
  `adaptive_cache_playback_page.dart`, `secure_output_page.dart`, `multi_player_page.dart`,
  and all six pages under `pages/measurement/`. Each added row names the specific public API
  the page demonstrates (derived from the page's own dartdoc and code, not its filename); the
  six `measurement/` pages are on-device measurement *harnesses* for this package's own
  pool/prewarm/prefetch defaults, not general usage demos, so they now live in their own
  "Measurement harnesses (Stage 7a)" section rather than the main gallery table, with that
  distinction called out explicitly. The "Project structure" tree (previously missing several
  already-existing pages, predating this change) was brought up to date to match. No stale API
  names were found in the previously-existing rows.
- **Corrected stale hardcoded Dart test-suite counts across the docs** (`AGENTS.md`,
  `README.md`, `docs/README.md`, `docs/implementation/README.md`,
  `docs/implementation/testing.md`, `docs/summary/README.md`, `docs/summary/phases.md`,
  `docs/summary/test-coverage.md`): several asserted a stale **1089**, when `flutter test`
  currently reports **1104** — the count drifts on every commit that adds a test, which is
  exactly how it went stale by 15. Every live (non-historical) count now explicitly hedges
  with "run `flutter test` for the current count" rather than asserting a number that will go
  stale on the next commit; a couple were simplified to drop the number entirely in favor of
  just that instruction. Historical snapshots (the v0.1.0 `113/113`/`179/179` figures, the
  DRM `47 tests` figure in `docs/summary/production-readiness.md`, and
  `docs/implementation/codebase-audit.md`'s references to the original findings) are
  unaffected — they are explicitly-marked historical records, not current-state claims.
  Separately, **no doc stated the `example/` app's own test count anywhere**, part of why the
  13 hangs above went unnoticed for so long — `docs/implementation/testing.md` and
  `docs/summary/test-coverage.md` now state it (19, `cd example && flutter test`) alongside
  the package count.
- **Documented that `liveLatency` behaves differently on Android and iOS**, not just that both
  are "wired": Android's ExoPlayer actively maintains the target offset from the live edge via
  playback-speed adjustment, while iOS's `AVPlayerItem.configuredTimeOffsetFromLive` (this
  package sets `automaticallyPreservesTimeOffsetFromLive = false`) is honored only once, at
  join/seek time, and is never restored after a rebuffer — so the iOS playhead drifts further
  from the live edge as rebuffers accumulate, the opposite direction from Android's manifest
  time-anchor defect (issue #110), which drifts *toward* a stale target. No behavior changed;
  `automaticallyPreservesTimeOffsetFromLive` remains `false`. See `HlsConfig`/`DashConfig
  .liveLatency`'s dartdoc and the [Live Streaming guide](docs/api-reference/live-streaming.md)
  for the full trade-off — whether to flip it to `true` (trading the drift for a visible forward
  skip after each rebuffer) is left as an open question for a future, deliberate change.
- **Documented that iOS `NetworkStatus.downloadSpeed` is a fabricated constant, not a
  measurement.** `NetworkMonitor.swift`'s `estimateBandwidth(from:)` returns a fixed
  per-transport value (ethernet 50, wifi 5–10, cellular 2, loopback 1000, other/unknown 1 Mbps)
  chosen purely from interface type — it never reads any system throughput signal. Android's
  equivalent is at least link-derived (`NetworkCapabilities.linkDownstreamBandwidthKbps`, a
  system hint, floored to a similar transport-based estimate only when that hint is degenerate).
  A consumer using `downloadSpeed` for adaptive-streaming decisions should treat it as a rough
  per-platform floor on iOS, not an actual bandwidth measurement. See
  `docs/api-reference/models.md`'s Network section and
  `docs/api-reference/events.md#onnetworkstatuschanged`.
- **Documented that a consuming app must remove its own ExoPlayer 2 dependency (issue
  #108).** v0.3.0's breaking-changes note announced the move to AndroidX Media3 1.11.0
  (replacing ExoPlayer 2.19.1), but its Upgrading section only covered bumping the pinned
  ref and the `actionStream` → `actionEventStream` migration. It never said to delete an
  app-side `implementation 'com.google.android.exoplayer:exoplayer:2.x'`. With both
  libraries on the classpath, `androidx.media3.ui.PlayerView` inflates a layout whose
  `AspectRatioFrameLayout` can resolve to the legacy class, throwing
  `ClassCastException: com.google.android.exoplayer2.ui.AspectRatioFrameLayout cannot be
  cast to androidx.media3.ui.AspectRatioFrameLayout` — which presents as **audio playing
  with no video**, because the platform view never constructs while decoding continues
  normally. The omission mattered because the failure is latent and non-deterministic:
  which class wins is a dependency-resolution accident, so it can surface weeks after the
  upgrade that caused it, on the first clean/Gradle sync/cache eviction, with nothing in
  the app's own history pointing at it. Now covered in `README.md`'s Android platform
  setup, a dedicated
  [ExoPlayer 2 on the classpath](docs/api-reference/getting-started.md#exoplayer-2-on-the-classpath)
  section in the getting-started guide, `docs/QUICK_START.md`'s platform notes, `AGENTS.md`
  and `CLAUDE.md`. No code change — the package's own dependency was always correct.
- **`NetworkStatus.fromPlatform` no longer discards the platform's `quality`, so a `0`
  bandwidth hint on a connected device no longer reports offline** (closes
  [#112](https://github.com/zionmedianetwork/zmedia_player/issues/112)). Both natives
  compute and transmit a `quality` string alongside `downloadSpeed` — see the header
  comments of `NetworkMonitor.kt`/`NetworkMonitor.swift`, which document the payload as
  `(quality, downloadSpeed, isMetered, connectionType)` — but `fromPlatform` ignored it and
  always recomputed quality from `downloadSpeed` via `NetworkQuality.fromBandwidth`. On
  Android API >= 23, `downloadSpeed` derives from `NetworkCapabilities
  .linkDownstreamBandwidthKbps`, which Android documents as a hint that may be absent or
  inaccurate — `0` is a legal value on a live, connected network. `fromBandwidth(0)` falls
  through every branch to `NetworkQuality.offline`, so a zero-bandwidth hint on an
  otherwise-connected wifi/cellular link made `NetworkStatus.isAvailable` report `false`
  while the device was online — silently, since no analyzer error or test failure can catch
  a `Map<String, dynamic>` payload key that's transmitted but never read. `fromPlatform` now
  parses `data['quality']` into a `NetworkQuality` and uses it directly, falling back to
  `fromBandwidth` only when the key is absent or unparseable (an older native build, or a
  hand-built map, keeps working exactly as before). `NetworkMonitor.kt`'s API >= 23 branch
  is also floored: when `linkDownstreamBandwidthKbps` yields a non-positive value on a
  network with real capabilities in hand, it now falls back to the same
  `estimateBandwidthFromType` transport-based estimate the pre-Android-M branch already
  used, so `downloadSpeed` itself — which is public and consumed for adaptive-streaming
  decisions — no longer degenerates to `0` on a connected link either;
  `offlineStatus()` (the canonical no-connection map) is unaffected. iOS's
  `estimateBandwidth(from:)` derives its estimate from the transport/interface type rather
  than from a system bandwidth hint, so it has no equivalent degenerate-hint path and needed
  no analogous floor. Deriving `isAvailable` from `connectionType` instead of `quality` (one
  of the three fixes the issue offered) was deliberately **not** done here — it's the more
  principled separation of reachability from link quality, but it changes the meaning of a
  widely-consumed public getter and belongs in its own change with its own deprecation
  story. See the [`onNetworkStatusChanged` payload table](docs/api-reference/events.md#onnetworkstatuschanged)
  for the full contract. Regression coverage: `test/models/network_status_test.dart`
  (new), plus an extended `test/models/network_status_vocabulary_test.dart` drift guard for
  the `quality` vocabulary (previously only `connectionType` was guarded, on the reasoning
  that `quality` was unread dead data — no longer true) and an updated expectation in
  `test/core/media_player_network_status_test.dart`.
- **`liveEdgeOffset` could report a value far larger than the live window itself, permanently
  breaking `isAtLiveEdge` (Android, issue #109).** `currentLiveEdgeOffsetMs()` trusted
  `Player.getCurrentLiveOffset()` unconditionally whenever it was not `C.TIME_UNSET` — but that
  API computes `nowUnixTime - windowStartTime - position`, and for DASH `windowStartTime`
  derives from `manifest.availabilityStartTimeMs`. A packager that anchors
  `availabilityStartTime` to broadcast start while re-basing its segment timeline to a rolling
  window produces a `getCurrentLiveOffset()` that reports broadcast age, not distance from the
  edge — and it returns a real, finite number rather than `C.TIME_UNSET`, so the existing
  `C.TIME_UNSET`-only fallback could never catch it. Observed on a real manifest:
  `liveEdgeOffset=1973165ms` (~33 minutes) reported against a 61466ms DVR window, while the
  playhead was genuinely ~3.7s from the edge — an offset larger than the window itself is
  impossible by construction. `currentLiveEdgeOffsetMs()` now rejects a reported offset that
  exceeds the live window's own known duration and uses the bounded fallback
  (`window.durationMs - position`) instead — a genuinely independent computation unaffected by
  the poisoned anchor, so it is preferred over clamping the invalid value to the window bound
  (which would merely fabricate a different lie: "exactly at the window start"). When the
  window's duration is not yet known, the reported value is trusted as before — there is
  nothing to sanity-check it against. iOS's equivalent (`AVPlayerItem.seekableTimeRanges.last`
  minus `currentTime()`) is bounded by construction — both operands share the item's own
  timeline, with no unix-time anchor involved — and needed no change.

### Added
- **CI now runs the example app's own test suite** (`example/test/`, 24 tests). Previously
  nothing in `.github/workflows/ci.yml` ever executed it — which is how 13 of those tests sat
  broken from v0.3.0 until a recent fix (see the `pumpAndSettle` entry under `Fixed` above),
  and how v0.3.0's release notes could claim "19 example tests pass" while most were failing,
  with no gate to catch either. A new `example-tests` job (`needs: lint-analyze-test`) resolves
  dependencies for both the root package and `example/` (the example depends on `zmedia_player`
  via a `path: ../` dependency), then runs `flutter analyze` and `flutter test` inside
  `example/`. `ci-success` now depends on `example-tests` as well, in both its `needs:` list
  and the shell condition that inspects each job's `result` — so a red example suite blocks
  merges the same way a red package suite already does.
- **One-time diagnostic for the manifest time-anchor defect above, making issue #110
  attributable.** The same poisoned anchor that broke `liveEdgeOffset` also silently defeats
  `HlsConfig`/`DashConfig.liveLatency` on an affected Android/DASH stream:
  `MediaItem.LiveConfiguration.targetOffsetMs` is computed from that identical anchor, so
  Media3 clamps the live join to the real edge regardless of the configured target — previously
  a silent, unattributable failure indistinguishable from a wiring bug. Android now logs a
  `Log.w` (tag `MediaPlayerInstance`), at most once per loaded item, naming the observed
  offset, the window duration, and the `liveLatency` consequence, with a pointer to issue #110.
  Not emitted on the routine 500ms position tick — only the first time the mismatch is
  observed for the current item. This is a manifest/packaging defect this package cannot
  correct; the diagnostic exists solely to name it. See
  [Manifest time-anchor defect](docs/api-reference/live-streaming.md#manifest-time-anchor-defect-liveedgeoffset-and-livelatency)
  for the full worked example and detection guidance.
- **On-device live-edge readout in the example app**, so issues #109/#110 can be verified by
  eye on a real device instead of only via `adb logcat` — CI never builds native code and every
  test in the suite mocks the `MethodChannel`, so an on-device check against a real stream was
  otherwise the only verification path with no way to visually confirm it.
  `example/lib/pages/wired_config_verification_page.dart`'s Live Latency section now renders
  `PlaybackState.liveEdgeOffset`/`.isAtLiveEdge`/`.positionBasis` (issue #88) as their own rows
  (previously only referenced, apologetically, in that section's disclaimer text) plus a
  color-coded `_LiveEdgeCaseBanner` distinguishing the three cases a tester needs to tell apart
  at a glance: a rejected/out-of-window offset (the issue #109 defect signature — must not
  appear after the fix now on `main`), a healthy live edge, and VOD's
  `null`/`absolute`. `example/README.md`'s row for the page documents the addition; the page's
  own dartdoc and `_LiveLatencyDisclaimer` were rewritten to point at the new rows instead of
  disclaiming that they were not wired in.
- **Custom stream URL support in the example app's verification harness**, so a stream this
  repo cannot itself host — most pointedly the specific manifest behind an #109-shaped defect
  report, whose unix-time anchor disagrees with its own segment timeline — can be pointed at
  `example/lib/pages/wired_config_verification_page.dart` and re-checked against the
  `enableDvr`/`liveLatency` and `liveEdgeOffset`/`isAtLiveEdge`/`positionBasis` readouts already
  on that page, without a rebuild. The Source `SegmentedButton` gained a third **Custom**
  option alongside the existing Live HLS / VOD MP4 built-ins (unchanged); selecting it reveals a
  URL field, a `MediaItem.isLive` toggle (default `true`), an explicit
  `MediaItem.streamingFormat` override (`auto`/`hls`/`dash`/`progressive`, with the *resolved*
  format shown live) and one optional HTTP header/value pair for a signed-cookie or
  token-gated origin, then a "Load custom stream" button that reloads through the page's
  existing `_reloadWithCurrentSettings` path — the same one the built-in sources use — so it
  picks up the current `enableDvr`/`liveLatency` settings exactly as they do. The format
  override matters specifically because of how `MediaItem.resolvedStreamingFormat` infers from
  a URL (see `MediaItem.streamingFormat`'s dartdoc): a CDN-rewritten, signed, or
  extension-less URL can silently resolve to `StreamingFormat.progressive`, under which
  neither `HlsConfig` nor `DashConfig` ever applies — making `enableDvr`/`liveLatency` look
  broken when they are simply not being consulted for that item at all.
  `_reloadWithCurrentSettings` now also sends the current settings as a `DashConfig` alongside
  the existing `HlsConfig` (previously `HlsConfig` only), since a pasted-in custom URL may
  resolve to either format and the two are never cross-applied — this has no effect on the two
  existing built-in sources (Live HLS resolves to `hls`, VOD MP4 to `progressive`, so the added
  `DashConfig` never applies to either). An empty URL is rejected inline (no load attempted) via
  a `_customUrlError` message rather than a wasted round trip. `example/README.md`'s row for the
  page documents the addition; 3 new widget tests cover revealing the Custom fields, the
  empty-URL rejection, and a valid URL producing the expected `MediaItem` (24 example tests
  total, up from 21).

## [0.4.0] - 2026-09-02

### Added
- **`NotificationService.updateConfig(NotificationConfig, {required String playerId})`** —
  the missing way to change a notification's configuration at runtime. `NotificationConfig`
  reached native only through `initialize()` (`initializeNotification`), and `show()` renders
  from whatever config native already holds, so flipping e.g. `showSeekForward` after
  construction had *no effect whatsoever* on device: the only workaround was to build an
  entirely new `NotificationService` and re-initialize it. `updateConfig` stores the new
  config, re-sends it over the same `initializeNotification` call (both plugins rebuild their
  per-player handler from that payload), and **re-renders a notification that is currently
  showing** — reusing the stored `MediaItem` and most recent `PlaybackState` — so the change
  is visible immediately without a second `show()`. If nothing is showing, nothing is
  displayed. Called before `initialize()`, it stores the config without touching the channel
  and the next `initialize()` sends it; disabling (`enabled: false`) dismisses a showing
  notification first, because every method (including `dismiss`) no-ops while disabled;
  enabling completes the native setup for a service that was initialized while disabled.
  Existing `MediaPlayer` stream subscriptions are reused, never duplicated.
- **`MediaItem.streamingFormat` and the `StreamingFormat` enum** (`hls`, `dash`,
  `progressive`) — an explicit, optional declaration of an item's container/manifest format
  that decides which streaming config applies to it (`hls` -> `MediaConfig.hlsConfig`,
  `dash` -> `MediaConfig.dashConfig`, `progressive` -> neither). It takes precedence over URL
  inference on the Dart side *and* on both native platforms, so a manifest behind a CDN
  rewrite, a signed URL whose path is masked, or an extension-less endpoint no longer has to
  hope the URL string cooperates. Defaults to `null`, which keeps the previous
  infer-from-the-URL behaviour. Fully supported in the constructor, `copyWith`, `toMap`/
  `fromMap` and `toString`; `MediaItem`'s id-based equality is unchanged (no content field
  has ever participated in it). Exported from `lib/zmedia_player.dart` via
  `src/models/media_item.dart`.
- **`MediaItem.resolvedStreamingFormat`** — the format that actually applies: the explicit
  `streamingFormat` when set, otherwise inference from the URL.
- **`StreamingFormat.fromUrl(String)` / `StreamingFormat.fromName(Object?)`** — the inference
  routine and the wire-name decoder, exposed so hosts can reproduce the package's own
  resolution. `fromName` returns `null` (i.e. "infer") for an unknown or non-`String` value
  rather than guessing a concrete format.
- **Debug-only diagnostic for an unconfigured live item.** Loading an item with
  `isLive: true` that resolves to a format whose config is `null` now logs a warning naming
  the resolved format, the missing config (`MediaConfig.hlsConfig`/`MediaConfig.dashConfig`,
  or "progressive media has none"), the consequence (`enableDvr` falls back to `false` ->
  `isSeekable == false` -> no live-window duration) and the remedy. Compiled out of release
  builds and logged at most once per resolved format per `MediaPlayer` instance, so
  reloading a misconfigured item cannot spam the log. This is the missing signal behind the
  "app just behaves differently on one platform" failure mode: an app serving HLS to one
  platform and DASH to another must set **both** `hlsConfig` and `dashConfig`, because the
  two are deliberately never cross-applied.

- **Live-edge signal** (closes [#88](https://github.com/zionmedianetwork/zmedia_player/issues/88)).
  With DVR enabled, a healthy live edge was previously indistinguishable from a frozen
  playhead: `position` is window-relative for a live item, so at the live edge of a
  *sliding* window the playhead and the window start advance together and `position` stays
  roughly constant. A host stall watchdog that sampled `position` and escalated when it
  stopped advancing therefore escalated forever against perfectly healthy playback. Three
  new public members close that gap:
  - `PlaybackState.liveEdgeOffset` (`Duration?`) — how far behind the live edge the
    playhead currently is. `null` for VOD and while the platform cannot answer yet;
    reported for live streams **with and without** `enableDvr`. Unlike `position`, it grows
    without bound against a genuinely frozen playhead, which makes it the reliable live
    stall signal.
  - `PlaybackState.isAtLiveEdge` (`bool`) plus `isAtLiveEdgeWithin(Duration tolerance)` and
    the public constant `PlaybackState.defaultLiveEdgeTolerance` (**15 seconds**, matching
    video.js's `liveTolerance` default — a healthy standard-HLS player rides 15-30s behind
    the edge, so a tighter threshold would report `false` for a healthy stream).
    `isAtLiveEdge` is always `false` when `liveEdgeOffset` is `null`.
  - `PlaybackState.positionBasis` (new exported enum `PositionBasis` — `absolute` |
    `liveWindow`) plus the derived `PlaybackState.isPositionWindowRelative` — reports which
    timeline `position` is currently measured against, so a host can branch correctly
    without inferring the basis from its own `MediaConfig`. VOD is `absolute` on both
    platforms; a live item is `liveWindow` on Android (ExoPlayer's `getCurrentPosition()`
    is window-relative for any live item) and `liveWindow` on iOS only when
    `enableDvr: true` (without DVR, iOS position is the `AVPlayerItem`'s own absolute
    timeline). That divergence is deliberate — each platform reports the basis its values
    are actually on.

  All three are surfaced on `MediaPlayer` (`liveEdgeOffset`, `isAtLiveEdge`,
  `positionBasis`) and on the `MediaController` facade. `position` itself is unchanged —
  DVR scrubbers keep working exactly as before. See
  [Stall watchdog for live streams](docs/api-reference/live-streaming.md#stall-watchdog-for-live-streams)
  for a complete worked implementation covering VOD, live-without-DVR and live-with-DVR.

- **Data contract — `onPositionChanged` gains two optional keys** (native -> Dart). The
  existing ~500ms position event now carries them; deliberately no new high-frequency
  channel event was added.
  - `positionBasis` (`String`, optional) — `"absolute"` or `"liveWindow"`. An absent or
    unrecognised value falls back to `PositionBasis.absolute`, preserving pre-existing
    behaviour on older cached native builds.
  - `liveEdgeOffset` (`int`, milliseconds, optional) — **omitted entirely rather than sent
    as a sentinel** when unknown; a missing key clears `PlaybackState.liveEdgeOffset` to
    `null`, so a stale offset can never make a freshly-loaded VOD item read as "at the live
    edge".

  Native sources: Android uses `Player.getCurrentLiveOffset()` (falling back to
  `Timeline.Window.durationMs - Player.getCurrentPosition()` when that returns
  `C.TIME_UNSET`) and `Timeline.Window.isLive()` for the basis; iOS uses the end of
  `AVPlayerItem.seekableTimeRanges.last` minus `AVPlayerItem.currentTime()`.
  `configuredTimeOffsetFromLive`/`recommendedTimeOffsetFromLive` were evaluated and
  rejected on iOS — both are *target* offsets, constant by construction and therefore
  useless as a liveness signal.

- `MediaPlayerWidget.enableBuiltInGestures` (`bool`, default `true`) — opt out of the
  package's own tap/double-tap/long-press handling over the video surface. When `false`,
  the transparent full-surface `GestureDetector` is not mounted at all and none of
  `onTap`, `onTapDown`, `onDoubleTap`, `onDoubleTapDown`, `onLongPress` or
  `onLongPressStart` are ever invoked by the package, letting a host that
  supplies `customControls` own every gesture. Also forwarded by
  `FullscreenMediaPlayer.enableBuiltInGestures` and
  `MediaListPlayer.enableBuiltInGestures` (both default `true`).
- `MediaControls.onBackgroundTap` / `onBackgroundTapDown` / `onBackgroundDoubleTap` /
  `onBackgroundDoubleTapDown` — callbacks for a tap/double-tap on the overlay's empty
  background, in bare and position-carrying flavours. `MediaPlayerWidget` forwards its own
  `onTap`/`onTapDown`/`onDoubleTap`/`onDoubleTapDown` through these so they fire
  identically whether the overlay is visible or hidden; because the background detector
  fills the same box as the player's own tap detector, `localPosition` is identical on both
  paths, which is what makes direction-aware double-tap seek work with the **default**
  controls and not just with `customControls`. Both variants fire when both are supplied
  (position-carrying first), and supplying either suppresses the overlay's own default. With
  all four `null` the previous behaviour is kept: a background tap calls
  `showControlsTemporarily()` and no double-tap recognizer is installed at all.
- `MediaPlayerWidget` now exposes position-carrying counterparts for every gesture it
  forwards: `onTapDown` (`GestureTapDownCallback`), `onDoubleTapDown`
  (`GestureTapDownCallback`), and `onLongPressStart`
  (`GestureLongPressStartCallback`). Previously `onTap`, `onDoubleTap` and
  `onLongPress` were bare `VoidCallback`s, so a host app could not tell *where* the
  player was tapped and therefore could not implement direction-aware double-tap seek
  (double-tap the left half to rewind, the right half to fast-forward) — the
  near-universal video-player convention — without shadowing the package's own tap
  detector with its own full-bleed gesture layer. Fixes
  [#83](https://github.com/zionmedianetwork/zmedia_player/issues/83).

  Interaction rules, identical for all three gestures:
  - The existing bare callbacks are **unchanged and fully source-compatible**; nothing
    needs to migrate.
  - Both variants may be supplied and **both fire**, in `GestureDetector`'s own order:
    the position-carrying variant first (on pointer-down / press recognition), the bare
    variant second (on gesture recognition).
  - Supplying **either** variant means the host owns that gesture, so the widget's
    built-in default no longer runs (single tap → `toggleControls`, double tap →
    `togglePlayPause`; long press has no built-in default).
  - `details.localPosition` is relative to the player widget's own box — the box
    `MediaPlayerWidget` occupies after any `aspectRatio` sizing — so hosts divide by the
    widget's own width, not the screen width. `details.globalPosition` remains
    screen-relative.
  - A callback fires only when no widget in the always-mounted controls overlay claimed
    the gesture first; overlay *visibility* is not what decides ownership. Tap and double
    tap (including the position-carrying variants) fire identically in both visibility
    states — with the default controls, the visible overlay re-emits them through the new
    `MediaControls.onBackgroundTapDown` / `onBackgroundDoubleTapDown`, whose detector fills
    the same box, so `localPosition` is byte-for-byte the same on both paths. Long press
    is **not** forwarded to the built-in overlay, so `onLongPress` / `onLongPressStart`
    fire only while the overlay is hidden (or, with `customControls`, whenever the host's
    overlay does not claim the press).
  - `enableBuiltInGestures: false` disables the position-carrying callbacks exactly as it
    disables the bare ones, on both the detector path and the overlay-forwarding path.

  Documented in the README (`MediaPlayerWidget` → "Gesture callbacks" / "Gesture
  ownership"), `docs/api-reference/advanced-features.md` ("Gesture callbacks" /
  "Direction-aware double-tap seek" / "`MediaControls` background callbacks"),
  `docs/api-reference/player-api.md`, `AGENTS.md`, and the `MediaPlayerWidget` /
  `MediaControls` dartdoc. Covered by 41 widget tests in
  `test/widgets/media_player_widget_gestures_test.dart`.

- Debug-only diagnostic when the new `expandToFill` size floor engages: `MediaPlayerWidget`
  reports a `FlutterError` (via `FlutterError.reportError`) naming the offending constraints,
  the likely cause (non-positioned `Stack` child, unbounded `Column`/`ListView`) and the remedy
  (`Positioned.fill`, `SizedBox.expand`, or `expandToFill: false`). It is compiled out of
  release builds, never throws, and is emitted at most once per constraint condition rather
  than once per frame — turning a previously silent black screen into a loud, actionable error.

### Fixed
- **`MediaFeed` no longer lets a failed controller call escape as an unhandled async error.**
  `_pauseOthers` called `other.pause()` as a bare statement, discarding a `Future` that can
  still fail; the same held for the autoplay `play()`, the `muteWhenNotVisible`
  `toggleMute()` calls, the live-item `MediaPlayerPool.release()`, the `autoPause` `pause()`,
  and all five `MediaFeedItemState` action callbacks (`play`, `pause`, `togglePlayPause`,
  `toggleMute`, `seekTo` — `VoidCallback`/`ValueChanged`, so the `Future` is discarded by the
  signature itself). Since the operation queue landed, contention no longer throws, but a
  genuine native failure — or a `dispose()` racing a queued `pause()` — still surfaced in the
  ambient `Zone`'s uncaught-error handler with nothing naming the item or the operation.
  All of these now run through an internal guard: a `PlayerDisposedException` is swallowed
  **silently** (an expected teardown race while scrolling), and any other failure is swallowed
  but reported with `debugPrint`, prefixed `MediaFeed:` and naming both the operation and the
  item — matching how `_activate`/`_prewarmIndex` already report theirs. Failures stay
  per-item: one controller failing to pause never prevents the others in the same
  `_pauseOthers` loop from being paused. **Behaviour change for hosts:** these failures no
  longer reach a `runZonedGuarded`/`PlatformDispatcher.onError` crash reporter, so diagnose
  feed playback problems from the `MediaFeed:` debug output instead. `MediaFeed`'s own
  `unawaited(_activate(...))`/`unawaited(_prewarmAround(...))` are deliberately left alone —
  an exception from a host's `itemAt` callback is a host bug that should stay loud.
  Regression coverage: `test/widgets/media_feed_pause_others_failure_test.dart`.
- **`toMap()` no longer hands out live references to a model's own collection fields.**
  `DrmConfig.toMap()` emitted `'headers': headers` and `'customData': customData`,
  `MediaItem.toMap()` emitted `'httpHeaders': httpHeaders` and `'metadata': metadata`,
  `SubtitleTrack.toMap()` emitted `'metadata': metadata`, `CastDevice.toMap()` emitted
  `'capabilities': capabilities`, and `PerformanceMetrics.toMap()` emitted
  `'context': context` — each one the *same* `Map`/`List` instance the model holds. A caller
  who mutated what `toMap()` returned therefore mutated the model itself, and two `toMap()`
  calls on the same object handed out the same mutable inner collection, so tampering with
  one serialization corrupted the next. The round trip was also asymmetric:
  `DrmConfig.fromMap` has always copied defensively (`Map<String, String>.from(...)`) on the
  way in while `toMap()` aliased on the way out. Every one of those entries is now a copy.
  The copies are **shallow** — a collection nested inside a `Map<String, dynamic>` value is
  still shared — and a `null` field still serializes as a present key with a `null` value, so
  the MethodChannel payload shape is byte-for-byte unchanged and nothing native reads is
  affected. `MediaPlayer`'s private `_configToMap` was given the same treatment for
  `MediaConfig.httpHeaders`; that map is encoded by the platform codec immediately, so the
  aliasing was never observable there, and the change is consistency/defence-in-depth only.
  The fields themselves are deliberately **not** copied at construction: every one of these
  constructors is `const`, and copying in the constructor body would have removed `const`
  and broken existing `const MediaItem(...)` / `const SubtitleTrack(...)` call sites.
  Regression coverage: `test/models/to_map_defensive_copy_test.dart`.
- `MediaController` now **queues** operations instead of rejecting them. Previously
  `_executeOperation` held a per-controller boolean lock that never queued: while it was
  held by a live operation, a "non-critical" call (`setVolume`, `toggleMute`, `setSpeed`,
  `setSubtitleTrack`, `setSecureSurface`) was rejected immediately with
  `OperationBusyException`, and a "critical" call slept 100 ms, then 200 ms, and then threw
  a bare `StateError`. Ordinary interleaved user input — "pause A, then play B" from two
  UI events, or muting a player while it is still loading — could therefore fail purely on
  timing. Because these calls are routinely fire-and-forget in feed-style UIs (a `dispose()`
  racing a mid-flight op is normal and must be swallowed), the throw disappeared silently
  and the operation simply never happened: in a shorts/reels feed a fast A→B→A→B swipe
  produced overlapping `play`/`pause` on one controller, the losing `pause()` threw, and
  that short stayed audible with nothing left to retry it. Operations submitted through
  `MediaController` are now appended to a per-controller FIFO queue and run strictly in
  submission order, one at a time; nothing is dropped and no operation throws merely
  because another was in flight. (#86)
- `MediaController`'s auto-hide controls timer is no longer armed after `dispose()`. A
  post-`dispose()` code path that reached `_showControlsTemporarily()` (now including a
  queued operation dropped by disposal) used to leave a pending `Timer` behind.

- `NotificationConfig.showSeekForward` / `showSeekBackward` are now honoured, identically,
  on both platforms (#81). Previously neither platform implemented the documented API:
  Android parsed both flags into private fields it never read again, so no seek button was
  ever added to the notification regardless of config; iOS ignored the flags entirely and
  gated `MPRemoteCommandCenter.skipForwardCommand`/`.skipBackwardCommand` on `isSeekable`
  alone, so any seekable item got the skip commands even when the consumer explicitly set
  `showSeekForward: false`. The two platforms therefore disagreed and neither matched the
  API. Both now enforce one contract: **a seek control is offered if and only if the flag
  is `true` AND the item is seekable** (`MediaPlayer.isSeekable` — a live stream without
  DVR can never show one, even if asked). Concretely:
  - **Android** — `NotificationHandler` adds a `NotificationCompat.Action`
    (`"Forward {seekInterval}s"` / `"Back {seekInterval}s"`, using
    `android.R.drawable.ic_media_ff`/`ic_media_rew`) whose `PendingIntent` routes through
    the existing `NotificationActionReceiver` → `MediaSessionCompat.Callback` path as a
    synthetic `KEYCODE_MEDIA_FAST_FORWARD`/`KEYCODE_MEDIA_REWIND`. New `onFastForward()`/
    `onRewind()` callbacks forward `"seekForward"`/`"seekBackward"` to Dart. The media
    session also now advertises `PlaybackStateCompat.ACTION_FAST_FORWARD`/`ACTION_REWIND`
    under the same gate, so Bluetooth / Android Auto / Wear surfaces offer the controls
    too. The buttons are deliberately kept out of the three `MediaStyle` compact-view
    slots, which stay reserved for previous / play-pause / next.
  - **iOS** — `skipForwardCommand.isEnabled` / `skipBackwardCommand.isEnabled` are now
    `showSeekForward && isSeekable` / `showSeekBackward && isSeekable` (was `isSeekable`
    alone); the two flags are read from the config alongside `showPlayPause`/`showNext`/
    `showPrevious`/`showStop`, and the command targets reject defensively if invoked while
    ungated. `preferredIntervals` continues to use `seekInterval`.

  The gating is re-derived on every `showNotification`/`updateNotificationState` call on
  both platforms, so a mid-playback seekability change (e.g. toggling DVR on a live
  stream) adds or removes the controls without re-initializing.

  **Behaviour change to be aware of:** an app that set `showSeekForward: false` (or left
  the default) on iOS previously still got skip controls; those now correctly disappear.
  An app that set `showSeekForward: true` on Android previously got nothing; it now gets a
  real button. No MethodChannel payload change was required — `NotificationConfig.toMap()`
  already sent `showSeekForward`, `showSeekBackward`, and `seekInterval` correctly; they
  simply were not acted on.
- `NotificationActions.seekForward` / `.seekBackward` now hold the wire values both native
  handlers actually emit — `'seekForward'` / `'seekBackward'`. They previously read
  `'seek_forward'` / `'seek_backward'`, which neither Android nor iOS has ever sent, so any
  `case NotificationActions.seekForward:` branch was dead code and silently never fired.
  Existing apps that switch on the literal `'seekForward'`/`'seekBackward'` (as the README,
  `AGENTS.md`, and the example app always have) are unaffected; apps using the constants
  gain working branches.

- **Streaming config was selected by a substring scan of the whole media URL, so a DASH
  stream could silently pick up `hlsConfig` (or nothing at all).** `MediaPlayer.load()`
  matched `url.contains('.m3u8')` *before* `url.contains('.mpd')`, which mis-classified any
  URL that merely mentioned `.m3u8` anywhere — a signed URL with a query parameter, a CDN
  rewrite carrying the original path, a path segment such as
  `/hls.m3u8-archive/…/manifest.mpd`. Selection now uses the URL's **path only** (query
  string and fragment stripped via `Uri.tryParse`, with a safe truncation fallback for an
  unparseable URL, which never throws) and matches with a case-insensitive `endsWith`, so at
  most one format can match and the result is order-independent. The knock-on effects of a
  wrong match were invisible: `enableDvr` silently became `false`, which gated
  `MediaPlayer.isSeekable`/`seekTo` and suppressed live-window duration reporting.
- **The same substring scan existed independently in native code and is fixed there too.**
  Android (`MediaPlayerManager.kt`) used it to choose between `HlsMediaSource`/
  `DashMediaSource`/`ProgressiveMediaSource` (on both the DRM and non-DRM paths), to decide
  whether adaptive segment caching applied, and to pick `hlsConfig` vs `dashConfig` for the
  live-latency target and track-selection bitrate bounds; iOS
  (`MediaPlayerManager.swift`) used it to pick the same config and to decide whether to parse
  the HLS manifest for quality tracks. Both now resolve format the same way Dart does, and
  both prefer the explicit `streamingFormat` hint over inference.
- `CastHandler.kt` now honours an explicit `streamingFormat` when choosing the cast
  `MediaInfo` contentType, instead of always guessing `application/x-mpegurl` /
  `application/dash+xml` from the URL string.

- **Playlist load paths now carry the current `MediaConfig` snapshot** (#82). `setPlaylist`
  and `skipToIndex` previously sent no `config` key over the MethodChannel, even though
  native loads `items[startIndex]`/`playlist[index]` through the very same `loadMediaItem`
  the `load` path uses — so playlist-driven items were loaded against whatever config native
  had stored at `initialize()`/the last explicit `updateConfig()` call. The mismatch was
  silent: playback worked, just not with the `MediaConfig`-level settings
  (`hlsConfig`/`dashConfig`, `enableDvr`, `liveLatency`, bitrate bounds, `adaptiveCacheConfig`,
  `autoPlay`, …) the caller asked for. Both payloads now carry `config`, and native replaces
  its stored config from it *before* any config-dependent work, exactly as the `load` path
  does — and, exactly as on the `load` path, deliberately does **not** re-run
  `applyConfig()`/volume-speed-mute reapplication, which would undo an in-progress runtime
  `setMuted()`. `skipToNext`, `skipToPrevious` and playlist auto-advance on completion all
  route through `skipToIndex`, so they are covered too.

  Data-contract change (both directions stay backward compatible):

  | MethodChannel call | Payload before | Payload now |
  |---|---|---|
  | `setPlaylist` | `{playerId, playlist, startIndex}` | `{playerId, playlist, startIndex, config}` |
  | `skipToIndex` | `{playerId, index}` | `{playerId, index, config}` |

  `config` is optional on the native side (Android `ZMediaPlayerPlugin.handleSetPlaylist`/
  `handleSkipToIndex`, iOS `handleSetPlaylist`/`handleSkipToIndex`): an absent key leaves the
  stored config untouched, so an older Dart caller cannot break a newer native build, and an
  older native build simply ignores the new key. The MethodChannel protocol version is
  unchanged. Per-item `httpHeaders`/`drmConfig` live on `MediaItem` and were never affected.

- `setPlaylist` no longer restarts the item that is already playing. Native
  (`MediaPlayerInstance.setPlaylist` in `android/.../MediaPlayerManager.kt` and
  `ios/.../MediaPlayerManager.swift`) called `loadMediaItem(items[startIndex])`
  unconditionally, so **every** `setPlaylist` call re-loaded the current item — losing
  the playback position and forcing a re-buffer. Both platforms now skip that load when
  the item at `startIndex` is the item already loaded *and* that item is still in
  progress. `currentPlaylist`/`currentIndex` are still updated unconditionally on both
  platforms: only the load is skipped, so the queue contents and position pointer always
  refresh. (#79)

  **What this enables:** a playlist can now be **extended (or re-issued) in place without
  restarting the current item**. Consumers that cannot authorise a whole playlist upfront
  — e.g. per-item signed cookies, where pre-authorising 40 episodes would mean ~80 network
  round-trips before the first frame — can keep a sliding window populated
  (`setPlaylist([current, next, next2])`, extended as the viewer advances) at no playback
  cost. The same now applies to re-issuing a playlist purely to change
  `Playlist.mode`/`Playlist.repeatMode` (e.g. toggling shuffle), which previously
  re-buffered the item under the viewer. The capture-position / re-issue / seek-back /
  resume workaround is no longer needed.

  **What still reloads** (the guard compares the *whole serialized media item*, not just
  `id`, so a deliberate re-issue of the same item is never silently swallowed): a
  different `id`; the same `id` with a changed `url`, changed `httpHeaders` (refreshed
  signed cookies / `Authorization`), or a changed `drmConfig` (including a rotated
  `drmConfig.headers` value, which `DrmConfig`'s own `==` does not compare); a missing
  `id` on both sides, which is never treated as identity on its own; and any state where
  nothing is in progress — never loaded, stopped, completed, or errored.

  `skipToIndex` (and therefore `skipToNext`/`skipToPrevious`) deliberately keeps its
  unconditional reload: skipping to the index you are already on is a restart, and
  `MediaRepeatMode.single` is implemented through exactly that call.

- `MediaPlayer.setPlaylist` no longer performs its "a load is coming" reset when the
  current item is not being reloaded. It previously always cleared the cached
  quality/audio/subtitle track lists (emptying the settings menu for an item that keeps
  playing), forced `PlayerState.buffering`, and sent a `setSpeed(1.0)` reset. It now
  mirrors the native guard (`MediaPlayer._isPlaylistReloadSkipped`) and skips all three
  when the item at `startIndex` is unchanged and in progress. This fix changes no
  MethodChannel payload — the `setPlaylist` call (including the `config` snapshot added
  in #82) is still issued on every invocation. As a safety net for a
  Dart/native disagreement (e.g. a cached older Dart build), native re-emits
  `onStateChanged`, `onDurationChanged` and the three `on*TracksChanged` events whenever
  it skips a load, so the Dart side re-syncs rather than stranding the UI. (#79)

  **Interaction with the playlist config snapshot (#82).** `setPlaylist` carries the
  current `MediaConfig` snapshot on every call, and native still stores it
  unconditionally — including when the load is skipped — so the next real load uses it.
  A changed `MediaConfig` does **not** by itself force a reload of an unchanged,
  in-progress item: `MediaConfig`/`HlsConfig`/`DashConfig` define no `operator ==` (a
  freshly built config is never equal to the previous one), and most `MediaConfig`
  streaming fields cannot take effect mid-item natively without a reload anyway. Use
  `updateConfig()` to apply a config change to live playback immediately, or `load()` to
  apply it *and* reload.

- **Gestures declared inside `customControls` no longer stop working when the controls
  overlay auto-hides** (#84). The overlay used to be built *only* while
  `MediaController.controlsVisible` was `true`, while the package's opaque tap detector was
  mounted *only* while it was `false` — so a host's left/right double-tap seek zones
  worked with the overlay visible and silently became the package's play/pause toggle the
  moment it hid. The controls overlay is now always mounted and always hit-testable, and
  the built-in tap detector is stacked **below** it. The rule is now: *a gesture is handled
  by the topmost widget in the controls overlay that claims it, and only reaches the
  built-in detector when no overlay widget claimed it — regardless of whether the overlay
  is currently visible.* The detector keeps `HitTestBehavior.opaque`, which is what stops
  the native platform view (`AndroidView`/`UiKitView`) beneath it from consuming taps;
  making it `translucent` and leaving it on top would not have worked, because gesture-arena
  members are added in hit-test order and ties go to the first member, so a topmost detector
  would beat both host zones and the built-in controls' own buttons.
- `MediaPlayerWidget.onTap` / `onDoubleTap` now fire consistently in both visibility
  states. Previously they could only fire while the overlay was hidden, because the visible
  built-in overlay covered the whole surface; they are now forwarded to the overlay's
  background handlers as well.
- `MaterialMediaControls` and `CupertinoMediaControls` no longer keep a private
  `_showControls` flag that defaulted to "visible" and was disconnected from
  `MediaController.controlsVisible`. Both now derive visibility from the controller and
  route their tap-to-toggle through `MediaController.toggleControls()`, so they auto-hide
  correctly and start hidden when used as `customControls` (which, with the change above,
  means being left mounted rather than unmounted). Both also handle double-tap
  (`togglePlayPause`) on their opaque root, which they previously delegated to the package
  detector that is no longer reachable through them.

- `MediaPlayerWidget(expandToFill: true)` no longer collapses to zero size when its parent
  supplies constraints that do not define a size. `expandToFill: true` deliberately skips the
  `AspectRatio` wrapper, which left the widget with no intrinsic size at all: given loose
  constraints (a non-positioned `Stack` child receives `BoxConstraints.loose` — the normal way
  to overlay chrome above a player), zero-minimum constraints, or constraints unbounded in an
  axis (an unbounded `Column`/`ListView` child), the whole subtree laid out at `Size(0, 0)`.
  That took the video *and* every control overlay (title, transport, scrubber, exit button)
  with it while audio kept playing, and — because a zero-size layout throws nothing — produced
  no exception, no `RenderFlex overflowed`, and no diagnostic of any kind.
  The `expandToFill: true` path now measures its incoming constraints: when they are bounded
  with a non-zero minimum in both axes (which includes every tight constraint, e.g.
  `Positioned.fill`, `SizedBox.expand`, a `Scaffold` body) the fill behaviour is unchanged, and
  otherwise the widget falls back to a definite size derived from the video's natural aspect
  ratio (16:9 when unknown) — filling the bounded axis and deriving the other, or using the
  screen width when both axes are unbounded. Behaviour with an explicit `aspectRatio`, or with
  `expandToFill: false`, is unchanged. ([#85](https://github.com/zionmedianetwork/zmedia_player/issues/85))

- `MediaPlayerWidget` no longer keeps the outgoing player's native view when its
  `controller` is swapped in place for one wrapping a different
  `MediaPlayer.playerId` (#80). `didUpdateWidget` previously rewired the
  `ChangeNotifier` subscription and then called an internal refresh that
  deliberately early-outs whenever a live native view already exists (to avoid
  surface churn on rotation/relayout). That early-out did not distinguish "same
  player, new layout" from "different player entirely", so a live controller swap
  left the widget driving the previous player's orphaned surface — visible to
  consumers as a fullscreen route that kept rendering the outgoing episode after
  an auto-advance. `didUpdateWidget` now compares
  `oldWidget.controller.player.playerId` against
  `widget.controller.player.playerId`; when they differ it performs a real
  teardown of the platform view (the same path `dispose()` takes, so the native
  surface is released rather than orphaned) and creates a fresh one bound to the
  new player on the following frame. The same-`playerId` case — including a
  second `MediaController` over the same `MediaPlayer` — keeps the existing
  surface untouched, so rotation and relayout still never churn the surface.
  The platform-view host is additionally keyed on the `playerId` so a swapped-in
  player can never be reconciled into the previous host (`creationParams`, which
  carry the `playerId`, are one-shot and are not re-sent on widget update).
  Keying `MediaPlayerWidget` on `controller.player.playerId` to force a remount
  is no longer necessary.
- `MediaPlayerWidget.didUpdateWidget` no longer reads the *outgoing* controller's
  `config` when the underlying player changed. A consumer that disposes the
  controller it is retiring before handing the widget a replacement previously
  triggered `PlayerDisposedException` from the `boxFit`-propagation comparison;
  that comparison is now skipped on a player swap (the newly created surface
  already carries the effective `boxFit` via `creationParams` and the `setBoxFit`
  push made when the platform view is created).

### Changed
- **Behaviour of every `MediaController` playback/track/config method** (`load`,
  `setPlaylist`, `play`, `pause`, `stop`, `seekTo`, `setVolume`, `toggleMute`, `setSpeed`,
  `setSubtitleTrack`, `setQualityTrack`, `enableAutoQuality`, `setAudioTrack`,
  `skipToNext`/`skipToPrevious`/`skipToIndex`, `setSecureSurface`, `updateConfig`,
  `initialize`): the returned `Future` now completes when the call's *turn* in the queue
  has run, so it can take longer than before to resolve when other work is in flight. It
  no longer completes with `OperationBusyException` or `StateError` for a busy controller.
  Head-of-line blocking stays bounded: each operation runs under a 10 s timeout (unchanged
  from before), so a wedged native call fails with `TimeoutException` and the queue
  advances rather than stalling forever.
- An operation still queued when `MediaController.dispose()` runs is now dropped and its
  `Future` completes normally as a no-op, without touching the disposed `MediaPlayer`. This
  matches the pre-existing `if (_isDisposed) return;` guard every public method already
  applies on entry, so a `dispose()` racing a queued call behaves the same as a call made
  after `dispose()`. An operation that is already *running* is not cancelled.
- `MediaController.isOperationInProgress` is now explicitly documented as informational
  only. It reports whether an operation is currently *running*, not whether the queue is
  empty, and callers never need to consult it before issuing a call (check-then-act on it
  was always racy). `MediaController.resetOperationState()` is retained for source
  compatibility but is now only a way to clear that informational flag — nothing gates on
  it, and a failed or timed-out operation can no longer leave the controller stuck.

- Documented that `NotificationConfig.seekInterval` is **display-only on both platforms**:
  it labels the Android notification action and sets iOS's
  `skipForwardCommand.preferredIntervals`, but neither platform performs the seek. The host
  app must apply the matching `Duration` when handling the `seekForward`/`seekBackward`
  event on `NotificationService.actionEventStream`, exactly as it already must call
  `play()`/`pause()` itself for the other controls.

- **Data contract:** the `mediaItem` payload sent over the MethodChannel gains a
  `streamingFormat` key (`'hls'`/`'dash'`/`'progressive'`, or `null` when the host left
  inference on). It is present on `load`'s `mediaItem`, on every item in `setPlaylist`'s
  playlist map, and on `loadMediaOnCastDevice`'s reduced `mediaItem` map. Native treats an
  absent or unrecognised value as "unset" and falls back to its own path-based inference, so
  an older Dart build against a newer native build (or vice versa) behaves exactly as before.

- **Android:** position updates are now also emitted while playback is stalled but the host
  still intends to play (`playWhenReady && Player.STATE_BUFFERING`), not only while
  `isPlaying`. Previously a rebuffer produced no position events at all, which would have
  frozen `liveEdgeOffset` at its last value instead of letting it visibly grow away from
  the live edge — defeating the new stall signal. Unchanged while genuinely paused, idle or
  ended. (iOS drives position from `AVPlayer.addPeriodicTimeObserver`, which only fires
  while time is progressing, so a hard stall still suspends updates there; this is
  documented as a platform caveat for watchdog authors.)

- The built-in controls overlay is now mounted at all times instead of being rebuilt each
  time it becomes visible. While hidden it is wrapped in `ExcludeSemantics` +
  `IgnorePointer` + a zero `AnimatedOpacity`, so it remains exactly as untappable and as
  invisible to screen readers as when it was not built at all — with the side benefit that
  its 300 ms fade-out can now actually run.
- **Behavioural note for `customControls` consumers:** the package no longer fades or
  unmounts a host-supplied overlay — the host owns its visibility (`CustomControlsBase`
  already provides `ControlsState.isVisible` / `.animation` for this). Because zero opacity
  does not stop hit testing, chrome that must not be tappable while hidden needs an explicit
  `IgnorePointer(ignoring: !state.isVisible)`, and a full-bleed scrim needs the same
  treatment or it will absorb the tap meant to reveal the controls. Returning
  `const SizedBox.shrink()` while hidden reproduces the previous behaviour exactly. See
  [Gesture ownership](docs/api-reference/advanced-features.md#gesture-ownership).

### Deprecated
- `OperationBusyException` — no longer thrown anywhere in this package. It existed solely
  for the "non-critical operation rejected because the lock was held" case that the queue
  removes, so any `catch (OperationBusyException)` / busy-retry handling in consumer code
  is now dead as a rejection path and can be deleted. The class is **retained, not
  removed**, because `MediaPlayerException` is `sealed`: deleting a member would break
  every exhaustive `switch` over the hierarchy. Exhaustive switches must therefore keep
  listing it. It will be removed in a future major release. (#86)

## [0.3.0] - 2026-08-18

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
- Removed `HlsConfig.enableSegmentPrefetch`, `HlsConfig.maxPrefetchSegments`,
  `DashConfig.enableSegmentPrefetch`, `DashConfig.maxPrefetchSegments`,
  `DashConfig.enableMpdCaching`, and `DashConfig.mpdCacheExpiration`. An audit of all
  209 fields across 18 config classes found `HlsConfig`/`DashConfig` had been entirely
  inert since the commit that introduced them — the models were added but
  `media_player.dart` was never touched, so `MediaPlayer.load()` never sent either
  config over the platform channel at all, and no Android
  `HlsMediaSource.Factory`/`DashMediaSource.Factory` construction path or iOS
  `AVPlayerItem` construction path read these six fields specifically, even after the
  rest of `HlsConfig`/`DashConfig` was wired up in this same release (see Added,
  below). HLS/DASH played anyway because native infers the media source type from the
  URL and ExoPlayer/AVPlayer buffer/adapt bitrate by default, so every value a
  consumer set happened to coincide with native's own behavior.
  `AdaptiveCacheConfig` (Android-only, transparent HLS/DASH segment cache — a
  read-through cache of what has already played) is the working equivalent for
  segment/MPD caching; there is no prefetch-count knob because ExoPlayer's own
  `LoadControl` already governs how far ahead of the playhead it buffers.
- Removed `StreamingConfig.streamingHeaders`. Never read by native, on either
  platform — `MediaItem.httpHeaders` is, and remains, the only header path that
  reaches native's `load()` call for manifest/segment requests. `HlsConfig` and
  `DashConfig` inherit from `StreamingConfig`, so this removal applies to both.

### Deprecated
- `HlsConfig.enableLiveStream` and `DashConfig.enableLiveStream` are now
  `@Deprecated`. Both duplicated `MediaItem.isLive`, which is already the canonical,
  fully-wired live flag driving `MediaPlayer.isLive`, `MediaPlayer.isSeekable`, and
  every other live-aware code path in this package — the config-level flags
  themselves were never read by native. They remain constructible and are not
  removed: `MediaPlayer.load()` now ORs whichever one applies (by URL match) into the
  effective `isLive` determination alongside `MediaItem.isLive`, so an app that
  already set the deprecated flag does not have its media silently stop being
  treated as live during the deprecation period. New code should set
  `MediaItem.isLive` instead.

### Fixed
- Live media never derived a duration, so a stream with `enableDvr: true` (see
  Added, below) reported `isSeekable: true` but no duration to seek within — the
  lock-screen/notification scrubber advertised `ACTION_SEEK_TO` with nothing to
  scrub over. Android's `notifyDurationChanged` read `exoPlayer.duration`, which is
  `C.TIME_UNSET` for a live stream, so the pre-existing `duration > 0` guard meant
  `onDurationChanged` simply never fired for live media. Android now reads the
  current `Timeline.Window` and reports `window.durationMs` when the item is live,
  DVR is enabled, and the window is seekable — re-polling on `onTimelineChanged`
  since a live window's known length grows over time. iOS derives the same from
  `AVPlayerItem.seekableTimeRanges`, since `AVPlayerItem.duration` is indefinite for
  a live item and never fires the usual duration KVO. iOS additionally needed
  position translation: `currentTime()` is on the item's absolute timeline while
  `seekableTimeRanges` is a sliding window, so a window-length duration measured
  against an absolute position would have produced a nonsense progress fraction.
  Reported position (and the position `seekTo` accepts) are now window-relative on
  iOS to match, with `seekTo` applying the inverse translation clamped to the
  currently known seekable range; ExoPlayer already reports window-relative
  positions, so Android needed no equivalent change. Verified on a Samsung Note 9P
  against a live HLS stream with a real 601-second DVR window: `dumpsys
  media_session` showed `actions=311` with a `600960`ms duration (matching the
  601.0s window measured from the HLS playlist) when DVR was enabled, `actions=55`
  with `0` duration when it was not, and the scrubber rendered and seeked correctly
  within the window; VOD was unaffected, reporting its real duration as before.
- `MediaPlayer.load()` left native holding a stale config on reload. `_configToMap`
  was only ever invoked from `initialize()` and `updateConfig()` — `load()` sent
  only `{playerId, mediaItem}` — so a host that rebuilt its `MediaConfig` (e.g.
  flipping `hlsConfig.enableDvr`) and called `load()` again, without an intervening
  explicit `updateConfig()` call, left native holding whatever config was current at
  `initialize()` time. This silently disabled `enableDvr`, `liveLatency`,
  `maxBitrate`, `minBitrate`, and `enableAdaptiveBitrate` for any runtime
  reconfiguration — exactly the pattern the new `_applyStreamingConfigForLoad`
  method (which recomputes `MediaPlayer.dvrEnabled`/`isLive` from the config on
  every `load()`, see Added, below) assumes works. `load()` now carries the current
  config snapshot with every call, on both platforms, applied before any
  config-dependent work runs (track-selection constraints, live latency,
  `adaptiveCacheConfig`, `autoPlay`); native deliberately does not re-run its own
  `applyConfig()`/volume-speed-mute reapplication from this path, since that would
  silently undo an in-progress runtime `setMuted()` call the config snapshot has no
  way to know about. Last write wins between `load()` and `updateConfig()` — they
  cannot diverge, since both are serialized from the same single
  `MediaPlayer._config` field. Known follow-up at the time of this release:
  `setPlaylist`/`skipToIndex` still called the single-argument native
  `loadMediaItem`, so per-item streaming config remained stale for playlist-driven
  items until an explicit `load()` or `updateConfig()` call. (Resolved since — see
  "Playlist load paths now carry the current `MediaConfig` snapshot" under
  `[Unreleased]`.)
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
- `MediaConfig.hlsConfig`/`.dashConfig` now actually reach native code. The same 209-field
  audit that found the removed prefetch/MPD-caching fields (see BREAKING, above) found the
  rest of `HlsConfig`/`DashConfig` reached nothing either — both were entirely inert since the
  commit that introduced them (added the models but never touched `media_player.dart`).
  `MediaPlayer.load()` now serializes whichever config applies to the loaded
  `MediaItem.url` (a URL containing `.m3u8` selects `hlsConfig`, one containing `.mpd` selects
  `dashConfig` — the same inference native itself uses for source type) and sends it over the
  platform channel. Fields actually read by native, per platform:
  - `enableDvr` — Dart-side only; gates `MediaPlayer.isSeekable`/`seekTo` (see below) and
    whether a live item's duration is reported at all (see Fixed, above).
  - `liveLatency` — Android: `MediaItem.LiveConfiguration.setTargetOffsetMs`. iOS:
    `AVPlayerItem.configuredTimeOffsetFromLive` (iOS 14+ only; silently has no effect on
    iOS 13).
  - `enableAdaptiveBitrate`/`maxBitrate`/`minBitrate` (inherited from `StreamingConfig`) —
    Android: `DefaultTrackSelector.Parameters` (`forceHighestSupportedBitrate` when ABR is
    disabled, `setMaxVideoBitrate`, `setMinVideoBitrate`). iOS: `AVPlayerItem
    .preferredPeakBitRate` for `maxBitrate` only — there is no faithful iOS equivalent for
    `minBitrate` or for forcing a single non-adaptive HLS variant, so both are documented as
    Android-only rather than approximated with a partial/misleading implementation.

  `bitrateStrategy`, `enableAutoQualitySwitch`, `qualitySwitchThreshold`, and
  `enableBandwidthEstimation` still cross the channel as part of the serialized config but are
  not read by either platform — see `StreamingConfig`'s dartdoc and the
  [Live Streaming guide](docs/api-reference/live-streaming.md) for the full field-by-field
  table.
- Live streams without DVR are no longer seekable. `MediaPlayer.seekTo` now throws
  `InvalidStateException` (`currentState: 'live-no-dvr'`) at a single choke point rather than
  forwarding a seek native would not honour — every path that can trigger a seek, including a
  lock-screen/Control Center "seekTo" notification action a host app forwards to `seekTo`, is
  caught by this same guard. Two new getters expose the underlying state:
  `MediaPlayer.dvrEnabled` (derived from whichever `HlsConfig`/`DashConfig` matched the loaded
  item's URL at `load()` time) and `MediaPlayer.isSeekable` (`false` only when `isLive &&
  !dvrEnabled`). Withheld natively too: Android's media session omits `ACTION_SEEK_TO` and iOS
  disables `changePlaybackPositionCommand`/`skipForwardCommand`/`skipBackwardCommand`. Verified
  on device via `dumpsys media_session`: VOD reports `actions=311` (`SEEK_TO` present), a live
  stream without DVR reports `actions=55` (absent), and toggling `enableDvr` and reloading
  restores `311` without the notification needing to be re-shown.
- `NotificationConfig.priority`, `.dismissible`, and `.customActions` now reach native
  (**Android only** — see each field's dartdoc for why there is no faithful iOS equivalent):
  `priority` drives both the `NotificationChannel` importance (set once, at
  `NotificationService.initialize()` time — Android does not allow an existing channel's
  importance to change later) and `NotificationCompat.setPriority` on every posted
  notification; `dismissible: true` posts the notification as non-ongoing
  (`setOngoing(false)`) with a delete intent so it can actually be swiped away (`false`, the
  default, matches the pre-existing ongoing behavior); `customActions` are rendered as
  additional `NotificationCompat.Action` buttons beyond the built-in
  play/pause/next/previous/stop/seek set, each dispatching its `NotificationAction.id` back
  through `NotificationService.actionEventStream` when tapped.
- `PipConfig.actions` and `.showPlaybackControls` now reach native (`actions` is
  **Android only** — AVKit exposes no API for custom PiP action buttons on iOS). Each
  `PipAction` is rendered as an `android.app.RemoteAction` via
  `PictureInPictureParams.Builder.setActions()`, capped at 3 visible actions regardless of
  platform API level (the system itself allows 3 on API 26-31, 5 on 32+); `showPlaybackControls:
  false` suppresses them entirely. Tapping an action is now delivered end to end: the existing
  native `onPipAction` broadcast — previously emitted with no Dart-side handler at all, the
  same defect class as the already-fixed `onDrmError` event — is parsed into a new
  `PipActionEvent` model and delivered on a new `MediaPlayer.pipActionStream`.
  `showPlaybackControls` is additionally honoured, partially, on iOS via
  `AVPictureInPictureController.requiresLinearPlayback` (iOS 14+, set to
  `!showPlaybackControls`), which hides the skip-forward/skip-back buttons and scrubbing bar
  from the system PiP overlay but cannot hide the mandatory system Play/Pause control.
- `DrmConfig.customData` now reaches native as license (key)-request-scoped HTTP properties,
  distinct from `DrmConfig.headers` (which applies to every DRM-related HTTP request on both
  platforms, including provisioning/the FairPlay certificate fetch). Android: each entry is set
  via `HttpMediaDrmCallback.setKeyRequestProperty`. iOS: each entry is set as a header on the
  license `POST` request built in `DrmHandler.requestLicense` only — not on the certificate
  `GET`. Values are converted for the wire: `String` passes through unchanged, `bool`/`int`/
  `double` use their own unambiguous string representation, nested `Map`/`List` values are
  JSON-encoded, and `null`/unsupported values are skipped (logged as a warning natively) rather
  than sent as the literal string `"null"`.
- `FullscreenMediaPlayer` orientation control (non-breaking; defaults preserve the prior
  landscape-locked behavior):
  - `preferredOrientations` — orientations applied while fullscreen is active
    (e.g. portrait fullscreen or portrait + free rotation).
  - `rotationLocked` — a `ValueListenable<bool>` that live-pins the device to portrait
    when true and re-applies `preferredOrientations` when false.
  - `exitOrientations` — orientations restored when the route pops (default: all four).

## [0.2.5] - 2026-07-01


### Other Changes

- Merge pull request #63 from zionmedianetwork/fix/native-surface-leak-grey-systemui (@Adolphe Cher-Aime) (e7f6257)
- Merge pull request #62 from zionmedianetwork/fix/release-version-from-tag (@Adolphe Cher-Aime) (a025aa5)
- ci(release): derive current version from latest tag, not main pubspec (@Adolphe Cher-Aime) (cad9954)

**Full Changelog**: https://github.com/zionmedianetwork/zmedia_player/compare/v0.2.4...v0.2.5

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

## [0.2.0] - 2026-06-23

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
