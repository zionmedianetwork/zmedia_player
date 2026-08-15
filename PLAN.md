# ZMedia Player - Roadmap

**Version:** 0.2.2
**Last Updated:** June 29, 2026
**Status:** Feature-complete for the 0.2.x line; distributed via GitHub releases.

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
| Package version | 0.2.2 |
| Dart SDK | >=3.0.0 <4.0.0 |
| Flutter SDK | >=3.19.0 (developed on 3.44.3) |
| iOS | 13.0+ |
| Android | minSdk 21 |
| Tests | 588 passing (Dart layer) |

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
- Live + DVR: `enableDvr`, `liveLatency`, segment prefetch.

### Subtitles
- SRT / WebVTT / ASS / SSA parsing and styling (`SubtitleService`, Dart-side).

### DRM
- Widevine (Android), FairPlay (iOS), PlayReady, token-based auth, EZDRM.
- Native certificate pinning (SHA-256 / SPKI) on license requests.

### Picture-in-Picture
- Both platforms: auto-enter-on-background, custom actions, aspect ratio.

### Casting
- Chromecast (**Android only** — `CastHandler` + `CastOptionsProvider`).
- AirPlay (**iOS only** — `AirPlayHandler` + `AirPlayButton`).

### Notifications
- Lock-screen / Control Center media notifications (`NotificationService` + native
  handlers), action stream.
- Artwork auto-generated from a video frame when `artworkUrl` is null.

### Caching / offline (Dart-side)
- `CacheService`: progressive download, LRU eviction, expiry, size management.

### Resilience & analytics (Dart-side)
- `NetworkResilienceService`: reconnect / retry.
- `AnalyticsService` / QoE metrics: startup time, rebuffering, bitrate.

### Security
- `PlatformSecureStorage` (Keychain / Keystore).
- `CertificatePinningConfig`.
- `InputValidation` (HTTPS-for-DRM enforcement).

### UI
- `MediaPlayerWidget`, `MediaListPlayer` (visibility-aware list playback).
- Material / Cupertino / Adaptive controls.
- `FullscreenMediaPlayer` with the orientation API
  (`preferredOrientations`, `rotationLocked`, `exitOrientations`) and fullscreen variants.
- Settings / quality / audio / subtitle / speed menus; badges and overlays.
- Android native view uses true Hybrid Composition (`initExpensiveAndroidView`).

---

## Known gaps / planned

This is the real backlog. State these honestly; do not mark them done.

- **No native automated tests.** Kotlin/Swift code has no test coverage. Several
  native paths still need on-device verification: DRM decryption, certificate
  pinning, casting, bandwidth metering.
- **DASH is Android-only.** No iOS DASH support.
- **Several subsystems are Dart-only** (no native counterpart): caching, analytics,
  network resilience, playlist, and subtitle logic. This is acceptable but worth
  noting when reasoning about behavior.
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
- **UI/UX:** control overlays and menus must follow the canonical specs and
  screenshots documented in `CLAUDE.md` (`docs/images/screenshots/controls_*`).
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

1. Native test coverage (JUnit / XCTest) and on-device verification of DRM,
   casting, cert pinning, and bandwidth metering.
2. Android foreground-service media session for full background audio.
3. iOS DASH support (close the Android/iOS streaming gap).
4. Offline DRM: persistent Widevine / FairPlay licenses and a download queue.
5. pub.dev publishing.
6. Stabilize the flaky DRM performance test.
