# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-11-30


### 🚀 Features

- 🚀 feat: implement comprehensive visual feedback overlay system (@Adolphe Cher-Aime) (afc397c)
- 🚀 feat: integrate status badges into control overlays (@Adolphe Cher-Aime) (52b1fb6)
- 🚀 feat: implement comprehensive error overlay widget (@Adolphe Cher-Aime) (7505c6a)
- 🚀 feat: integrate buffering and network indicators into fullscreen players (@Adolphe Cher-Aime) (42c0ca8)
- 🚀 feat: implement advanced buffering and network quality indicators (@Adolphe Cher-Aime) (46c0b5b)
- 🚀 feat: refactor controls UI to match design specifications (@Adolphe Cher-Aime) (e4ee180)
- 🚀 feat: add fullscreen demo page to example app (@Adolphe Cher-Aime) (3c34bfb)
- 🚀 feat: implement fullscreen widget variants (@Adolphe Cher-Aime) (3e5dc63)
- 🚀 feat: convert simple demo to use custom controls (@Adolphe Cher-Aime) (5252993)
- 🚀 feat: implement custom controls base class system (@Adolphe Cher-Aime) (1836ab9)
- 🚀 feat: implement adaptive widget selection system (@Adolphe Cher-Aime) (b4603cb)
- 🚀 feat: implement Cupertino controls and enhance mobile responsiveness (@Adolphe Cher-Aime) (0833683)
- 🚀 feat: add Material Design 3 controls showcase to streaming demo (@Adolphe Cher-Aime) (7a69d0e)
- 🚀 feat: implement Material Design 3 media controls (@Adolphe Cher-Aime) (14d4c5d)
- 🚀 feat: extract reusable media control components (@Adolphe Cher-Aime) (c06c0fb)
- 🚀 feat: implement native audio/subtitle track exposure with stale data fix (@Adolphe Cher-Aime) (c7563e5)
- 🚀 feat: create unified settings menu with tabs (@Adolphe Cher-Aime) (83109ae)
- 🚀 feat: implement audio track selection UI (@Adolphe Cher-Aime) (f623c6e)
- 🚀 feat: implement quality/resolution selection UI (@Adolphe Cher-Aime) (9471dd4)
- 🚀 feat: Add automated release workflow with semantic versioning (@Adolphe Cher-Aime) (c51cd73)

### 🐛 Bug Fixes

- 🐛 fix: adapt release workflow for branch protection rules (@Adolphe Cher-Aime) (97080a6)
- 🐛 fix: correct dry_run boolean evaluation in release workflow (@Adolphe Cher-Aime) (a86b4ef)
- 🐛 fix: enhance release pipeline with manual version and README badge update (@Adolphe Cher-Aime) (f557e89)
- 🐛 fix: wrap SettingsMenu in Material widget to fix fullscreen crash (@Adolphe Cher-Aime) (f251d31)
- 🐛 fix: remove scaffold wrappers from fullscreen demo (@Adolphe Cher-Aime) (13497b1)
- 🐛 fix: resolve tap detection and custom controls visibility issues (@Adolphe Cher-Aime) (43420c5)
- 🐛 fix: capture taps before they reach native platform view (@Adolphe Cher-Aime) (692bdd4)
- 🐛 fix: properly initialize fade animation in CustomControlsBase (@Adolphe Cher-Aime) (843c816)
- 🐛 fix: sync CustomControlsBase with MediaController state (@Adolphe Cher-Aime) (36e0e28)
- 🐛 fix: ensure tap detection works when controls hidden (@Adolphe Cher-Aime) (c187308)
- 🐛 fix: resolve overflow and button interaction issues (@Adolphe Cher-Aime) (0300a0e)
- 🐛 fix: allow button interaction in custom controls (@Adolphe Cher-Aime) (69ad268)
- 🐛 fix: make custom controls tappable when hidden (@Adolphe Cher-Aime) (c153352)
- 🐛 fix: handle disposed player in streaming demo page (@Adolphe Cher-Aime) (7dfe7a4)
- 🐛 fix: correct duration display in Material Design 3 controls (@Adolphe Cher-Aime) (5a0f2a3)
- 🐛 fix: resolve flutter analyze warnings in reusable components (@Adolphe Cher-Aime) (da2db45)
- 🐛 fix: reset playback speed to 1.0x when switching videos (@Adolphe Cher-Aime) (df13197)
- 🐛 fix: Comprehensive release workflow improvements for robustness (@Adolphe Cher-Aime) (2352ec8)
- 🐛 fix: Handle first release when no previous tags exist (@Adolphe Cher-Aime) (87dcfd6)
- 🐛 Fix CI analyzer configuration and remove debug print statements (@Adolphe Cher-Aime) (f3bb38c)
- 🐛 Fix Flutter analyzer warnings and adjust CI strictness (@Adolphe Cher-Aime) (ae139ee)
- 🐛 Fix Chromecast and AirPlay functionality (@Adolphe Cher-Aime) (9514c40)
- 🐛 Fix AirPlay integration to remove fake device and instructional modal (@Adolphe Cher-Aime) (6e3fbdf)
- 🐛 Fix type check errors and remove unused code (@Adolphe Cher-Aime) (cef88e5)
- 🐛 Fix BufferingService usage in DRM demo (@Adolphe Cher-Aime) (a00d406)
- 🐛 Fix iOS NetworkMonitor Swift compilation errors (@Adolphe Cher-Aime) (23b9eae)
- 🐛 Fix NetworkQuality enum conflict (@Adolphe Cher-Aime) (c307ea0)
- 🐛 Fix iOS playlist crash and complete Phase 0 critical bugs (@Adolphe Cher-Aime) (034300e)
- 🐛 Fix picture in picture (@Adolphe Cher-Aime) (8e98f11)
- 🐛 Fix memory leak (@Adolphe Cher-Aime) (529aec3)
- 🐛 Fix player state on ios (@Adolphe Cher-Aime) (468b4c9)
- 🐛 Fixing android fullscreen (@Adolphe Cher-Aime) (a9bc5f6)
- 🐛 Fix demo apps non stop loading (@Adolphe Cher-Aime) (bc24d75)
- 🐛 Fix notification service (@Adolphe Cher-Aime) (9db5b32)
- 🐛 Fix ios build (@Adolphe Cher-Aime) (22d5d56)
- 🐛 Fix platform view crash on android (@Adolphe Cher-Aime) (3f677b0)
- 🐛 Fix android build (@Adolphe Cher-Aime) (27bfcba)
- 🐛 Fix device discovery (@Adolphe Cher-Aime) (38f7662)
- 🐛 Fix cast (@Adolphe Cher-Aime) (6993248)
- 🐛 Fix video rendering issue (@Adolphe Cher-Aime) (26eac0c)
- 🐛 Fix exceptions (@Adolphe Cher-Aime) (0ef7404)

### 🔧 Refactoring

- 🔧 refactor: simplify fullscreen players to use updated control overlays (@Adolphe Cher-Aime) (27598ab)
- 🔧 refactor: improve quality menu UX (@Adolphe Cher-Aime) (b69351c)
- 🔧 Refactor media controls layout and improve gesture handling in media player widget (@Adolphe Cher-Aime) (7838771)
- 🔧 Refactor the examples (@Adolphe Cher-Aime) (541cd8a)
- 🔧 Refactor media player (@Adolphe Cher-Aime) (3d04909)
- 🔧 Refactor some stuff (@Adolphe Cher-Aime) (66b296e)

### 📚 Documentation

- 📚 docs: update PLAN.md metadata and add workflow instructions (@Adolphe Cher-Aime) (a401f81)
- 📚 docs: update Phase 2 completion to 55% (12/22 tasks) (@Adolphe Cher-Aime) (0769c2c)
- 📚 docs: update PLAN.md to mark buffering indicators as complete (@Adolphe Cher-Aime) (c90e683)
- 📚 docs: update PLAN.md to mark Phase 2 UI/UX tasks as complete (@Adolphe Cher-Aime) (312f48c)
- 📚 docs: mark custom controls base class task as complete in PLAN.md (@Adolphe Cher-Aime) (43ed6c5)
- 📚 docs: add native audio/subtitle track exposure task to Phase 2 (@Adolphe Cher-Aime) (1cf0475)
- 📚 docs: mark completed Phase 2 tasks in PLAN.md (@Adolphe Cher-Aime) (9ae54a8)
- 📚 docs: Update all documentation for accuracy (@Adolphe Cher-Aime) (098dba1)

### ✅ Tests

- ✅ test android (@Adolphe Cher-Aime) (79b4949)

### Other Changes

- Merge pull request #33 from zionmedianetwork/fix/release-workflow-branch-protection (@Adolphe Cher-Aime) (559a2f7)
- Merge pull request #32 from zionmedianetwork/fix/release-dry-run-boolean-check (@Adolphe Cher-Aime) (2929c49)
- Merge pull request #31 from zionmedianetwork/fix/release-pipeline-manual-version (@Adolphe Cher-Aime) (b84832f)
- Merge pull request #30 from zionmedianetwork/feat/visual-feedback-enhancements (@Adolphe Cher-Aime) (145c7c7)
- Merge pull request #29 from zionmedianetwork/feat/status-badges-indicators (@Adolphe Cher-Aime) (6a6f7f3)
- Merge branch 'main' into feat/status-badges-indicators (@Adolphe Cher-Aime) (e923aa1)
- Merge pull request #28 from zionmedianetwork/feat/error-overlay-enhancement (@Adolphe Cher-Aime) (228d189)
- Merge pull request #27 from zionmedianetwork/feat/buffering-indicator-enhancement (@Adolphe Cher-Aime) (0eaf667)
- Merge pull request #26 from zionmedianetwork/feat/fullscreen-widget-variants (@Adolphe Cher-Aime) (a3b06c6)
- chore: add docs/images/screenshots to gitignore (@Adolphe Cher-Aime) (023c040)
- Merge pull request #25 from zionmedianetwork/feat/custom-controls-base-class (@Adolphe Cher-Aime) (9b3da5c)
- Merge pull request #24 from zionmedianetwork/feat/adaptive-widget-selection (@Adolphe Cher-Aime) (80650f8)
- Merge pull request #23 from zionmedianetwork/feat/cupertino-controls (@Adolphe Cher-Aime) (2e9ce6c)
- Merge pull request #22 from zionmedianetwork/feat/material-design-3-controls (@Adolphe Cher-Aime) (b67fe9c)
- Merge pull request #21 from zionmedianetwork/feat/reusable-component-extraction (@Adolphe Cher-Aime) (5d6e338)
- Merge pull request #20 from zionmedianetwork/feat/speed-controls-enhancement (@Adolphe Cher-Aime) (fe72a1e)
- Merge branch 'main' into feat/speed-controls-enhancement (@Adolphe Cher-Aime) (2098863)
- Merge pull request #19 from zionmedianetwork/feat/native-audio-subtitle-track-exposure (@Adolphe Cher-Aime) (919fdd8)
- Merge pull request #19 from zionmedianetwork/feat/native-audio-subtitle-track-exposure (@Adolphe Cher-Aime) (8e53473)
- Merge pull request #18 from zionmedianetwork/docs/update-plan (@Adolphe Cher-Aime) (331a7db)
- Merge pull request #17 from zionmedianetwork/feat/subtitle-controls-enhancement (@Adolphe Cher-Aime) (a9cc59c)
- Merge branch 'main' into feat/subtitle-controls-enhancement (@Adolphe Cher-Aime) (aa2f1e3)
- Merge pull request #16 from zionmedianetwork/feat/audio-track-selection-ui (@Adolphe Cher-Aime) (4200f0f)
- Merge pull request #16 from zionmedianetwork/feat/audio-track-selection-ui (@Adolphe Cher-Aime) (72a992f)
- Update instructions (@Adolphe Cher-Aime) (a679d62)
- Merge pull request #15 from zionmedianetwork/feat/quality-resolution-selection-ui (@Adolphe Cher-Aime) (066e626)
- Enable bitrate (@Adolphe Cher-Aime) (8ba111a)
- Merge pull request #14 from zionmedianetwork/docs/review-roadmap (@Adolphe Cher-Aime) (32e63db)
- Update claude with commit instructions (@Adolphe Cher-Aime) (70ca003)
- Update plan with tasks to create bottomsheet (@Adolphe Cher-Aime) (e87641f)
- Update roadmap adding UI/UX phase (@Adolphe Cher-Aime) (7fce3d4)
- Merge pull request #13 from zionmedianetwork/fix/release-pipeline (@Adolphe Cher-Aime) (c97ed0a)
- Merge pull request #12 from zionmedianetwork/feature/release-pipeline (@Adolphe Cher-Aime) (5b7574d)
- Merge pull request #11 from zionmedianetwork/feature/ci-pipeline (@Adolphe Cher-Aime) (570f283)
- Add pre-commit hooks and apply automatic formatting fixes (@Adolphe Cher-Aime) (6fc78d1)
- Remove hardcoded Flutter version from CI configuration (@Adolphe Cher-Aime) (9c22e57)
- Add CI pipeline configuration for Flutter project (@Adolphe Cher-Aime) (050b7d9)
- Merge pull request #10 from zionmedianetwork/feature/chromescast (@Adolphe Cher-Aime) (ae503b8)
- Improve AirPlay UX: always show button and add iOS-specific instructions (@Adolphe Cher-Aime) (365d960)
- Add native AirPlay button integration for iOS (@Adolphe Cher-Aime) (04d8a8d)
- Implement real Chromecast device discovery (@Adolphe Cher-Aime) (c4f283b)
- Merge pull request #9 from zionmedianetwork/chore/refactor-and-more (@Adolphe Cher-Aime) (02d2d47)
- Update claude file (@Adolphe Cher-Aime) (5bc768c)
- Create comprehensive PLAN.md roadmap and remove old planning docs (@Adolphe Cher-Aime) (8c05bc5)
- Improve DRM demo debugging and playback initialization (@Adolphe Cher-Aime) (fd697d7)
- Implement native secure storage for Phase 1 P1 (@Adolphe Cher-Aime) (647a4ce)
- Integrate Phase 1 P1 features into DRM demo example (@Adolphe Cher-Aime) (a6876e9)
- Implement Phase 1 P1: Analytics and Security Hardening (@Adolphe Cher-Aime) (47ce69c)
- Implement Phase 1 P0: Adaptive buffering and network resilience (@Adolphe Cher-Aime) (abb831a)
-  Fix bugs (@Adolphe Cher-Aime) (ef60b0c)
- Merge pull request #8 from zionmedianetwork/chore/controls-overlay (@Adolphe Cher-Aime) (b33bcaa)
- Update control overlay icons (@Adolphe Cher-Aime) (0b4763e)
- Merge pull request #7 from zionmedianetwork/feat/bandwidth-monitoring-livestreaming (@Adolphe Cher-Aime) (368eaaa)
- Adaptive bitrate setup (@Adolphe Cher-Aime) (62e2c60)
- Update overlay for livestream (@Adolphe Cher-Aime) (7ac4eaa)
- Implement IOS and Android bandwidth monitoring (@Adolphe Cher-Aime) (1dc1851)
- Merge pull request #6 from zionmedianetwork/fix/production-readiness-p0 (@Adolphe Cher-Aime) (22478d2)
- Offline DRM doc (@Adolphe Cher-Aime) (5ab36ce)
- Proper exception handling (@Adolphe Cher-Aime) (4d9474a)
- Add proguard rules (@Adolphe Cher-Aime) (9def01a)
- Implement crash reporter (@Adolphe Cher-Aime) (677a872)
- Merge pull request #5 from zionmedianetwork/chore/rename-package (@Adolphe Cher-Aime) (2329d1b)
- Production readiness analysis (@Adolphe Cher-Aime) (9f5d378)
- Clean unused field (@Adolphe Cher-Aime) (54ab527)
- Update ignore (@Adolphe Cher-Aime) (a3f0b89)
- Rename package and classes (@Adolphe Cher-Aime) (61fffe8)
- Merge pull request #4 from zionmedianetwork/fix/miscellaneous-bugs (@Adolphe Cher-Aime) (948d7eb)
- Fullscreen issue investigation (@Adolphe Cher-Aime) (9368548)
- Video paint issue (@Adolphe Cher-Aime) (227cdcc)
- Use hybrid composition instead of virtual device on android (@Adolphe Cher-Aime) (6c8a59d)
- Update doc add livestreaming (@Adolphe Cher-Aime) (74f1126)
- Merge pull request #3 from zionmedianetwork/feature/documentation (@Adolphe Cher-Aime) (9604f9c)
- Update readme with links to docs folder (@Adolphe Cher-Aime) (6a9bda0)
- Re-organize documentation (@Adolphe Cher-Aime) (a7fa1e7)
- Restructure docs (@Adolphe Cher-Aime) (ac00cde)
- Merge pull request #2 from zionmedianetwork/feature/testing (@Adolphe Cher-Aime) (0f2e677)
- Add tests for all development phases (@Adolphe Cher-Aime) (c0968dc)
- Merge pull request #1 from zionmedianetwork/feature/phase4 (@Adolphe Cher-Aime) (9cf6bc8)
- DRM implementation (@Adolphe Cher-Aime) (6b133b6)
- Merge branch 'main' of https://github.com/zionmedianetwork/zmedia_player (@Adolphe Cher-Aime) (d1069f4)
- Initial commit (@Adolphe Cher-Aime) (64feb2a)
- Play on IOS (@Adolphe Cher-Aime) (ca03469)
- Add native implementation for phase 3 (@Adolphe Cher-Aime) (60681a2)
- Phase3 dart implementation (@Adolphe Cher-Aime) (a5c7187)
- Documentation (@Adolphe Cher-Aime) (96328a1)
- Implement HLS and Dart support along with caching and subtitle (@Adolphe Cher-Aime) (b21139b)
- Update custom control (@Adolphe Cher-Aime) (6363a83)
- Clean upp (@Adolphe Cher-Aime) (769168b)
- HLS and Dash implementation (@Adolphe Cher-Aime) (570e5f1)
- Custom controls (@Adolphe Cher-Aime) (0acfba6)
- remove overlay (@Adolphe Cher-Aime) (5194a16)
- dep upgrade (@Adolphe Cher-Aime) (0ef98ff)

**Full Changelog**: https://github.com/zionmedianetwork/zmedia_player/commits/v0.1.0

## [Unreleased]

### Added
- CI/CD pipeline with automated testing, linting, and analysis
- Pre-commit hooks for code quality enforcement
- Automated release workflow with semantic versioning

### Fixed
- Deprecated `Color.withOpacity()` replaced with `Color.withValues(alpha:)`
- Deprecated `WillPopScope` replaced with `PopScope`
- Deprecated `onPopInvoked` replaced with `onPopInvokedWithResult`
- Removed unused fields and debug print statements

## [0.1.0] - 2025-01-15

Initial release of ZMedia Player - A comprehensive Flutter media player package.

### Features
- 🎥 Video and audio playback
- 📱 iOS and Android support
- 🔐 DRM support (Widevine, FairPlay)
- 📡 Adaptive streaming (HLS, DASH)
- 📺 Chromecast and AirPlay support
- 🖼️ Picture-in-Picture mode
- 🔴 Live streaming with DVR
- 📝 Subtitle support (SRT, WebVTT, ASS, SSA)
- 📊 Playback analytics and metrics
- 💾 Caching and offline playback
- 🎚️ Customizable player controls
- 📋 Playlist management

### Platform Support
- **Android**: Minimum SDK 21 (Lollipop)
- **iOS**: Minimum iOS 12.0

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
