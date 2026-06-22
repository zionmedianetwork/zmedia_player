# Codebase Audit & Remediation Roadmap

> **Status:** Principal-level engineering assessment of ZMedia Player v0.1.0.
> **Method:** Four independent deep-dive reviews covering the four layers — core Dart, services/models/security, widgets/UI, and the native platform + test suite.
> **Scope:** Findings and a prioritized remediation roadmap. This is an assessment document, not a changelog.

## Context

ZMedia Player is presented as an "enterprise-grade / production-ready" media player package (README, project docs claim *179/179 features, 113/113 tests, Production Ready*). This audit evaluates that claim against the actual code.

**Bottom line:** the architecture is genuinely well-designed — a clean facade pattern (`MediaPlayer` ↔ `MediaController`), symmetric per-feature native handler decomposition, a typed sealed exception hierarchy, and a broadcast-stream state model. However, **several headline features are non-functional or only partially wired**, and the test suite does not exercise the behavior that would have caught them. These are correctness and security defects, not polish items. The roadmap is sequenced so the highest-risk, lowest-effort fixes land first.

---

## Findings Synthesis (cross-cutting themes)

1. **DRM — the headline feature — is completely non-functional on both platforms.** `DrmHandler.kt` and `DrmHandler.swift` are architecturally correct (Widevine `DefaultDrmSessionManager` / FairPlay SPC-CKC via `AVContentKeySession`) but are **never imported or instantiated**. `loadMediaItem()` never reads `drmConfig`. The Dart `drmSessionStream` has no `onDrmSessionUpdate` handler, so it is permanently dead, and `EzdrmConfig` hardcodes EZDRM's **demo** FairPlay certificate for all deployments.

2. **Multi-instance support is broken at the core.** `MediaPlayer._channel` is a single static `MethodChannel`; each constructed instance overwrites the global `setMethodCallHandler`, so **only the last-created player receives native events**. Every multi-player scenario (the advertised `MediaListPlayer`, PiP overlay) silently stalls. The native side compounds this: Android `NOTIFICATION_ID = 1001` is shared across instances → notification thrashing.

3. **Security is partly illusory.** `CertificatePinning.calculateFingerprint` does hex-encoding instead of SHA-256 and is **never enforced natively** (no OkHttp pinner / URLSession delegate). Android `SecureStorageHandler` **silently falls back to plaintext `SharedPreferences`** when EncryptedSharedPreferences fails, with no signal to Dart. Input validation never enforces the documented "HTTPS-for-DRM" rule on the media URL.

4. **Visible UI correctness/leak bugs.** `PlaybackState.copyWith` drops `bufferedPosition` (and it's excluded from `==`/`hashCode`) → the seek-bar buffer indicator is always zero. The three primary controls widgets (`MediaControls`, `MaterialMediaControls`, `CupertinoMediaControls`) **leak stream subscriptions** (`.listen()` never cancelled in `dispose()`). Numerous stub buttons ship live (volume/fullscreen placeholders, a TODO PiP button, hardcoded `example.com` subtitle tracks). Accessibility is poor — only one widget uses `Semantics`; touch targets fall below 48dp.

5. **Subtitle parsing breaks on real-world files.** SRT fails on Windows CRLF (one giant block); WebVTT drops every cue that has an ID line; ASS truncates text at the first comma and throws `FormatException` on centiseconds; TTML is an explicit `return []` stub.

6. **The "113/113 tests passing / production ready" claim is misleading.** ~168 Dart `test()` cases exist, but they only validate model `toMap`/`fromMap`, config validation, and the exception hierarchy. There are **zero** MethodChannel round-trip tests, zero native (JUnit/XCTest) tests, zero widget/golden tests, and `drm_performance_test` just times object allocation. CLAUDE.md even references `test/core/media_controller_test.dart`, which **does not exist**.

7. **Android stack is end-of-life.** ExoPlayer `2.19.1` (`com.google.android.exoplayer2`, EOL 2024), `compileSdk 33`, Kotlin 1.7.10, `security-crypto:1.1.0-alpha06` (alpha in production). The bandwidth "estimate" reports the current track's declared bitrate, not measured throughput — so auto-quality can never correctly downgrade.

8. **Concurrency smell in the facade.** `MediaController._operationStateMonitor` force-resets the operation lock every 5s while the timeout is 10s, allowing two operations in-flight simultaneously and defeating the serialization guarantee.

---

## Remediation Roadmap

### P0 — Correctness & security blockers (contradict "production ready")

- **Fix the static MethodChannel handler** — `lib/src/core/media_player.dart:26,1499`. Register the handler **once** at class level and dispatch by `arguments['playerId']` to `_instances[id]`. Unblocks all multi-instance use.
- **Wire DRM on both platforms** — `android/.../MediaPlayerManager.kt` `loadMediaItem()` must read `mediaItem["drmConfig"]`, build `DrmHandler.createDrmSessionManager()`, and pass via `ExoPlayer.Builder.setDrmSessionManagerProvider`; `ios/Classes/MediaPlayerManager.swift` must instantiate `DrmHandler` and call `setupContentKeySession(for: asset)` before creating the `AVPlayerItem`. Make Swift `enum DrmError: Error` (force-casts currently crash on first failure). Add the `onDrmSessionUpdate` case in `media_player.dart` `_handleMethodCall` so `drmSessionStream` is alive.
- **Make certificate pinning real or remove the claim** — delete the fake `calculateFingerprint`; either implement native enforcement (OkHttp `CertificatePinner` on Android, `URLSessionDelegate`/TrustKit on iOS, fed by `CertificatePinningConfig.toMap()` at `initialize`) or downgrade the docs to "config-only, not yet enforced."
- **Stop the silent plaintext downgrade** — `android/.../SecureStorageHandler.kt`: remove the catch-fallback or surface `isEncrypted=false`/throw to Dart so callers can react.
- **Remove the EZDRM demo certificate fallback** — `lib/src/models/drm_config.dart:246`: make `certificateUrl` required for `EzdrmConfig.fairplay`.
- **Fix `PlaybackState`** — add `bufferedPosition` to `copyWith`, `==`, and `hashCode` (`lib/src/models/player_state.dart`). Restores the seek-bar buffer indicator everywhere.
- **Cancel leaked stream subscriptions** — store and `cancel()` the `.listen()` subscriptions in `_MediaControlsState`, `_MaterialMediaControlsState`, `_CupertinoMediaControlsState` `dispose()`.

### P1 — Functional gaps & facade completeness

- **Enforce HTTPS-for-DRM** — add `InputValidator.validateMediaItemWithDrm()` and call it in `MediaPlayer.load()`.
- **Replace `_operationStateMonitor`** with timestamp-based lock expiry (`media_controller.dart:619`); remove the 5s force-reset race.
- **Complete the `MediaController` facade** — add `setQualityTrack`/`setAudioTrack`/`enableAutoQuality` + `qualityTracks`/`audioTracks` getters, all routed through `_executeOperation`; subscribe to the quality/audio/volume/speed streams so the `ChangeNotifier` actually notifies.
- **Fix the `allowBackgroundPlaybook` typo** — `media_player.dart:1829` → `allowBackgroundPlayback` (background audio silently broken today).
- **Fix `NetworkChangeEvent` inverted quality flags** — `network_status.dart:311` (`qualityImproved`/`qualityDegraded` are swapped).
- **Fix the bandwidth estimate** — Android should read `bandwidthMeter.bitrateEstimate`, not `videoFormat.bitrate`, so auto-quality can downgrade.
- **Remove shipped stubs/placeholders** — wire volume + fullscreen buttons in Material/Cupertino controls; remove the hardcoded `example.com` subtitle tracks in `SubtitleView` and the `example.com` guard in `SubtitleService`; remove the duplicate fullscreen header + TODO PiP button in `_FullscreenPlayerRoute`.
- **Fix the cache directory** — add `path_provider`; replace `Directory.current`-based `_getAppCacheDirectory` with `getTemporaryDirectory()`/`getApplicationSupportDirectory()`.

### P2 — Robustness, performance, accessibility

- **Harden subtitle parsers** — normalize CRLF before SRT split; handle WebVTT cue-ID lines and `REGION`/`STYLE` blocks; fix ASS comma-in-text (`parts.sublist(9).join(',')`) and centisecond time parsing; document or implement TTML. Add a real-world test corpus.
- **Fix exponential backoff** — `network_resilience_service.dart:74` use `pow(multiplier, attempt-1)` (currently linear).
- **Reduce rebuilds** — replace the blanket `AnimatedBuilder(animation: controller)` in `MediaControls` with scoped `ValueListenableBuilder`s (position vs play-state vs static shell); remove empty `setState(() {})` flush hacks and per-frame `debugPrint`s in `MediaPlayerWidget`; seek only on `onChangeEnd`, not every drag frame.
- **Accessibility pass** — wrap all `GestureDetector` controls in `Semantics(button:true,label:…)`, raise touch targets to ≥48dp (remove `minimumSize: Size.zero`), add `semanticFormatterCallback` to the seek slider.
- **Add `==`/`hashCode`** to the value models missing them (`QualityTrack`, `AudioTrack`, `DrmConfig`, `EzdrmConfig`, `SubtitleConfig`, QoE/Engagement/Performance metrics).
- **Native lifecycle fixes** — scoped `CoroutineScope(... + SupervisorJob())` in `CastHandler`/`NotificationHandler` cancelled in `dispose()`; replace the `Thread.sleep` busy-wait in `CastHandler.loadMedia` with a coroutine + timeout; per-instance Android notification IDs; guard the iOS force-casts in `NetworkMonitor.swift`/`DrmHandler.swift`; replace timing `asyncAfter`/string-KVO with `readyForDisplay`/block-based KVO.

### P3 — Modernization & test foundation

- **Migrate Android ExoPlayer 2.x → AndroidX Media3** (`media3-migration.sh`); bump `compileSdk 35`, Kotlin 2.0.x, `security-crypto:1.0.0`.
- **Establish a real test harness** — MethodChannel contract tests via `TestDefaultBinaryMessenger` (verify outgoing arg maps incl. `drmConfig`; inject `onStateChanged`/`onPositionChanged` and assert stream transitions); add the missing `media_controller_test.dart`; service-layer tests (bandwidth thresholds, cache expiry, subtitle corpus); widget/golden tests for the controls per the CLAUDE.md design spec; at least smoke-level native tests (JUnit/XCTest).
- **Correct the documentation claims** — reconcile "113/113 / production ready / 179 features" with reality; fix the 15-min vs 30-min stale-instance discrepancy.

---

## Verification (for the eventual fixes)

- After P0/P1 Dart fixes: `flutter analyze` clean, `flutter test` green, and **new** tests prove: (a) two `MediaPlayer` instances both receive native events; (b) a DRM `load()` emits an `arguments` map containing `drmConfig`; (c) `drmSessionStream` emits on injected `onDrmSessionUpdate`; (d) `bufferedProgress` is non-zero after a buffered-position event.
- DRM end-to-end: play a known Widevine (Android) and FairPlay (iOS) test asset in `example/` and confirm decryption + a populated `drmSessionStream`.
- Multi-instance: run the `example/` list page with several players; confirm all update concurrently and notifications don't collide.
- Security: force an EncryptedSharedPreferences failure and confirm Dart is notified rather than silently writing plaintext; verify a cert-pin mismatch actually blocks a license request.
- Subtitles: load a Windows-CRLF SRT, an ID'd WebVTT, and a comma/centisecond ASS file; confirm correct cue counts.
- Memory: re-run `test/memory/` plus a new test asserting controls widgets cancel subscriptions on dispose.

---

## How to execute

This is a multi-PR roadmap, not a single change. Recommended order: **P0 as the first PR** (security/correctness), then P1, P2, P3 in sequence. Per the repo `CLAUDE.md`, all code implementation should be delegated to the `flutter-expert` subagent and done on `feat/`/`fix/` branches off `main`.
