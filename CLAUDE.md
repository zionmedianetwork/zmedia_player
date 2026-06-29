# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.
a step by step roadmap is available in PLAN.md. Always follow this file for implementation guidance

## Required Agent: flutter-expert

**ALWAYS delegate Flutter/Dart implementation work in this repository to the `flutter-expert` subagent** (via the Agent tool with `subagent_type: "flutter-expert"`). This is mandatory, not optional.

Applies to any task touching `lib/`, `test/`, `example/`, widgets, controllers, services, models, state management, or the native plugin layer (`android/`, `ios/`) — i.e. writing, editing, refactoring, debugging, or reviewing code. Pass the full task context (relevant files, the PLAN.md task, and the UI/UX spec section below) to the agent so it has what it needs.

Narrow exceptions where you may act directly without the agent: pure documentation edits (e.g. this file, `docs/`, `README.md`), git/branch/release operations, and answering questions that require no code changes.

## Project Overview

ZMedia Player is a comprehensive Flutter media player package with advanced features for video and audio playback across Android and iOS platforms. It provides enterprise-grade capabilities including DRM support, adaptive streaming (HLS/DASH), Picture-in-Picture, casting (Chromecast/AirPlay), and live streaming.

**Version:** 0.2.2
**Flutter SDK:** >=3.19.0
**Dart SDK:** >=3.0.0 <4.0.0

## Development Commands

### Testing

```bash
# Run all tests
flutter test

# Run specific test file
flutter test test/core/media_controller_test.dart

# Run tests with coverage
flutter test --coverage

# Run performance tests
flutter test test/performance/

# Run memory leak tests
flutter test test/memory/

# Run crash reporting tests
flutter test test/crash_reporting/
```

### Building
```bash
# Get dependencies
flutter pub get

# Run example app
cd example && flutter run

# Build example app for Android
cd example && flutter build apk

# Build example app for iOS
cd example && flutter build ios

# Analyze code
flutter analyze

# Format code
dart format lib/ test/
```

### Plugin Development
```bash
# Clean build artifacts
flutter clean

# Build plugin
flutter pub get && flutter analyze

# Test on specific platform
cd example && flutter run -d <device-id>
```

### Pre-commit Hooks

This project uses pre-commit hooks to automatically format code, run analysis, and perform checks before committing.

```bash
# Install pre-commit (one-time setup)
pip install pre-commit

# Install the git hooks
pre-commit install

# Run hooks manually on all files
pre-commit run --all-files

# Run hooks on staged files only
pre-commit run

# Skip hooks (not recommended, use only when necessary)
git commit --no-verify -m "message"
```

**Hooks included:**
- Dart code formatting (`dart format`)
- Flutter static analysis (`flutter analyze`)
- Trailing whitespace removal
- End of file fixes
- YAML syntax validation
- Large file detection
- Merge conflict detection
- Debug statement detection (prevents `print()` statements)

**Note:** The hooks will automatically format your Dart code before each commit, ensuring consistency with CI requirements.

## Architecture Overview

### High-Level Structure

The package follows **clean architecture** with clear separation between Flutter/Dart layer and native platform implementations:

```
┌─────────────────────────────────────────────────┐
│           Flutter/Dart Layer                    │
│  ┌──────────────┐  ┌──────────────────────┐    │
│  │ Controllers  │  │  Widgets             │    │
│  │ (Facade)     │  │  (UI Components)     │    │
│  └──────┬───────┘  └──────────────────────┘    │
│         │                                        │
│  ┌──────▼──────────────────────────────────┐   │
│  │   MediaPlayer (Core)                    │   │
│  │   - State Management                    │   │
│  │   - MethodChannel Communication         │   │
│  └──────┬──────────────────────────────────┘   │
└─────────┼──────────────────────────────────────┘
          │ MethodChannel
┌─────────▼──────────────────────────────────────┐
│         Native Platform Layer                   │
│  ┌─────────────────┐  ┌─────────────────────┐  │
│  │ Android (Kotlin)│  │  iOS (Swift)        │  │
│  │ - ExoPlayer     │  │  - AVPlayer         │  │
│  │ - Widevine DRM  │  │  - FairPlay DRM     │  │
│  │ - Chromecast    │  │  - AirPlay          │  │
│  └─────────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────┘
```

### Core Components

#### 1. MediaPlayer (`lib/src/core/media_player.dart`)
- **Primary interface** for all media operations
- Manages MethodChannel communication with native platforms
- Handles state management via broadcast streams
- Singleton per playerId pattern (multiple instances supported)
- Includes crash reporting integration

**Key responsibilities:**
- Load/play/pause/seek operations
- Playlist management
- Quality/subtitle/audio track selection
- DRM session handling
- PiP and casting coordination
- Bandwidth monitoring

#### 2. MediaController (`lib/src/core/media_controller.dart`)
- **Simplified facade** over MediaPlayer
- Follows Observer pattern (extends ChangeNotifier)
- Auto-hiding controls logic
- Prevents race conditions with operation locks
- Throttles position updates (500ms minimum interval)

**Use MediaController when:** Building UI components that need reactive state updates
**Use MediaPlayer when:** Need direct access to advanced features or custom integration

#### 3. Native Platform Managers

**Android:** `MediaPlayerManager.kt`
- ExoPlayer-based implementation
- Handles Widevine DRM
- Manages HLS/DASH adaptive streaming
- Chromecast integration via CastHandler

**iOS:** `MediaPlayerManager.swift`
- AVPlayer-based implementation
- Handles FairPlay DRM
- Manages HLS streaming
- AirPlay integration via AirPlayHandler

Both managers follow identical interface patterns defined by the MethodChannel protocol.

**Native code is decomposed into per-feature handlers** (mirrored across `android/src/main/kotlin/com/zionmedianetwork/zmedia_player/` and `ios/Classes/`): `MediaPlayerManager`, `DrmHandler`, `PipHandler`, `NotificationHandler`, `BufferingHandler`, `CrashHandler`, `NetworkMonitor`, `SecureStorageHandler`, plus the platform view (`MediaPlayerView`/`MediaPlayerViewFactory`). Casting/AirPlay handlers are platform-specific (`CastHandler`/`CastOptionsProvider` on Android; `AirPlayHandler`/`AirPlayButtonFactory` on iOS). The plugin entry points are `ZMediaPlayerPlugin.kt` / `ZMediaPlayerPlugin.swift`. When adding a native capability, add the same handler on both platforms to keep the MethodChannel contract symmetric.

### Public API Surface

`lib/zmedia_player.dart` is the single barrel file that defines the package's public API — **everything a consumer can use is exported here**. When adding a new public class, export it from this file; anything not exported is internal. The file is organized by the PLAN.md phase that introduced each piece (Core, Models, Services, Widgets, Security), which is the fastest map of what exists.

### Data Flow Patterns

#### Playback State Flow
```
User Action → MediaController → MediaPlayer → MethodChannel
                                              ↓
                                    Native Platform
                                              ↓
                                    Event Callbacks
                                              ↓
                        StreamController.broadcast()
                                              ↓
                        UI Updates via Stream Listeners
```

#### DRM License Acquisition
```
MediaItem(drmConfig) → MediaPlayer.load()
                              ↓
              Native Platform (DrmHandler)
                              ↓
         License Server Request (with auth headers)
                              ↓
         DRM Session State → drmSessionStream
```

### Services Layer

**StreamingService** (`lib/src/services/streaming_service.dart`)
- Bandwidth estimation algorithms
- Automatic quality selection based on network conditions
- Quality switch threshold management (default 0.8)

**CacheService** (`lib/src/services/cache_service.dart`)
- Progressive download with progress tracking
- Cache size management (configurable max size)
- Expiration policies (configurable duration)

**SubtitleService** (`lib/src/services/subtitle_service.dart`)
- SRT/WebVTT/ASS/SSA parsing
- Subtitle rendering with customizable styling
- Multi-language subtitle track management

**NotificationService** (`lib/src/services/notification_service.dart`)
- Media playback notifications (Android/iOS)
- Notification actions (play/pause/next/previous)
- Action stream for UI integration

**CastService** (`lib/src/services/cast_service.dart`)
- Device discovery (Chromecast/AirPlay)
- Connection management
- Media session control on cast devices

**BufferingService** (`lib/src/services/buffering_service.dart`)
- Buffer health tracking (`BufferHealth`) and adaptive buffering config (`BufferingConfig`)
- Drives the buffering indicators/badges in the UI layer

**NetworkResilienceService** (`lib/src/services/network_resilience_service.dart`)
- Network status monitoring (`NetworkStatus`) and reconnection/retry logic
- Backed natively by `NetworkMonitor` on each platform

**AnalyticsService** (`lib/src/services/analytics_service.dart`)
- Playback analytics/QoE metrics (`AnalyticsMetrics`): startup time, rebuffering, bitrate

### Security Layer (`lib/src/security/`)

A separate exported module — not to be confused with `CrashReporter` in core:
- **CertificatePinning** (`certificate_pinning.dart`) — pins TLS certs for license/media endpoints
- **SecureStorage** (`secure_storage.dart`) — Dart wrapper over native `SecureStorageHandler` (Keychain/Keystore) for DRM tokens and credentials
- **InputValidation** (`input_validation.dart`) — validates/sanitizes URLs and config before they reach native code (enforces the HTTPS-for-DRM rule)

## Key Patterns and Conventions

### Instance Management
- **MediaPlayer uses factory pattern with instance registry**
- Each playerId gets a unique instance stored in `_instances` map
- Background cleanup timer removes stale instances (15min inactivity)
- Always dispose controllers to prevent memory leaks

### Error Handling
- Custom exceptions in `lib/src/core/exceptions.dart`
- Platform-specific error mapping (PlatformException → MediaPlayerException)
- CrashReporter integration for production error tracking
- Error state propagated via PlaybackState.state = PlayerState.error

### State Management
- **All state is broadcast via StreamControllers**
- Streams are broadcast type to allow multiple listeners
- Position updates throttled to prevent excessive notifications
- State transitions follow defined lifecycle: idle → loading → playing/paused → completed/error

### Native Communication Protocol

**MethodChannel calls (Dart → Native):**
- `initialize`: Setup player instance
- `load`: Load media with configuration
- `play/pause/stop`: Playback control
- `seekTo`: Position seeking
- `setQualityTrack`: Manual quality selection
- `enterPictureInPicture`: PiP mode activation
- `setDrmConfig`: DRM configuration

**Event callbacks (Native → Dart):**
- `onPlaybackStateChanged`: State transitions
- `onPositionChanged`: Playback position updates
- `onDurationChanged`: Media duration
- `onQualityTracksChanged`: Available quality tracks
- `onDrmSessionUpdate`: DRM session state
- `onBandwidthUpdate`: Network bandwidth estimation

## Testing Strategy

### Test Organization
- **Unit tests:** `test/core/`, `test/models/`, `test/services/`
- **Performance tests:** `test/performance/` (with specific targets)
- **Memory tests:** `test/memory/` (leak detection)
- **Integration tests:** `example/` app for manual testing

### Mock Strategy
- Use mocks for native platform communication in unit tests
- Memory leak tests use actual StreamController/Timer to verify cleanup
- Performance tests have specific latency targets (e.g., <100ms for DRM init)

### Test Coverage
- Run `flutter test` for the current pass count (the suite has grown well past the
  original 113 as audit-remediation work added regression coverage)
- Coverage is strongest in the Dart layer: state management, playlist logic, DRM/
  config models, MethodChannel event routing, subtitle parsing, retry/backoff, and
  value-model equality
- **Gaps:** native Android/Kotlin and iOS/Swift code has no automated tests; several
  native features (DRM decryption, certificate pinning, casting, bandwidth metering)
  are implemented but still require on-device verification
- Performance benchmarks included for critical paths

## Important Implementation Details

### DRM Multi-Platform Support
- **Android:** Widevine L1/L3 via ExoPlayer's DefaultDrmSessionManager
- **iOS:** FairPlay via AVContentKeySession
- **EZDRM integration:** Simplified license server configuration
- Token-based auth: Custom headers with JWT support

### Live Streaming DVR
- `enableDvr: true` allows seeking in live streams
- `liveLatency` configures target latency (default: 3s)
- Live edge detection via isLive flag
- Segment prefetching for smooth playback

### Picture-in-Picture
- Android: Uses `enterPictureInPictureMode()` API
- iOS: Uses `AVPictureInPictureController`
- Availability check before attempting PiP
- PiP state tracked via pipStatusStream

### Playlist Management
- Sequential and shuffle playback modes
- Repeat modes: none, single, all
- Auto-advance on completion
- Skip next/previous with boundary checks

## Common Gotchas

1. **Always initialize MediaPlayer before use** - Call `initialize()` explicitly or use MediaController.create() factory
2. **Dispose controllers in State.dispose()** - Prevents memory leaks and native resource cleanup
3. **DRM requires HTTPS** - License and media URLs must use secure connections
4. **PiP availability is platform/device dependent** - Always check `checkPipAvailability()` first
5. **Live streams need specific configuration** - Set `enableLiveStream: true` in HlsConfig/DashConfig
6. **Subtitle styling uses ARGB color format** - e.g., 0xFFFFFFFF for white, 0x80000000 for semi-transparent black
7. **Multiple instances are supported** - Use unique playerIds for concurrent players (e.g., ListView)
8. **MethodChannel calls are async** - Always await native operations to prevent race conditions

## UI/UX Design Specifications

All control overlays and layouts MUST strictly follow the design specifications shown in `docs/images/screenshots/controls_*`. These screenshots define the canonical UI/UX implementation.

### Control Overlay Structure

**Reference:** `controls_full_size.png`, `controls_normal_size.png`

The control overlay consists of three main zones:

#### Top Bar (Always visible when controls are shown)
- **Position:** Top edge of video player
- **Left side:** Collapse/Exit fullscreen button (chevron down icon)
- **Right side (in order):**
  1. Settings icon (gear icon)
  2. Cast icon (Chromecast/AirPlay icon)
  3. Picture-in-Picture icon (PiP icon)
- **Styling:**
  - Icons: White, semi-transparent background
  - Size: Consistent icon sizing (~24-28dp/pt)
  - Spacing: Equal horizontal spacing between right-side icons
  - Padding: 16dp/pt from edges

#### Center Controls (Overlaid on video)
- **Position:** Vertically and horizontally centered on video
- **Layout:** Horizontal row with three buttons
  1. **Rewind 10 seconds** (left)
     - Icon: Circular arrow counterclockwise with "10" label
     - Size: Medium (~48-56dp/pt)
  2. **Play/Pause** (center)
     - Icon: Circular background with play/pause icon
     - Size: Large (~64-72dp/pt), larger than side buttons
     - Style: Prominent, filled circle background
  3. **Forward 10 seconds** (right)
     - Icon: Circular arrow clockwise with "10" label
     - Size: Medium (~48-56dp/pt)
- **Styling:**
  - All buttons: White icons with semi-transparent dark background
  - Spacing: Equal spacing between buttons (~24-32dp/pt)
  - Visual hierarchy: Center button is largest

#### Bottom Bar (Seek controls)
- **Position:** Bottom edge of video player
- **Layout:** Stacked vertically
  1. **Seek bar**
     - Progress indicator with draggable thumb
     - Buffered progress (secondary color)
     - Played progress (primary/accent color)
     - Remaining progress (gray/dim)
  2. **Time display**
     - Format: "current / duration" (e.g., "0:00 / 0:14")
     - Position: Below or integrated with seek bar, left-aligned
     - Typography: Small, monospace or tabular numbers
- **Styling:**
  - Padding: 16dp/pt from edges
  - Seek bar height: ~4-6dp/pt (inactive), ~8-10dp/pt (active/dragging)
  - Thumb size: ~12-16dp/pt
  - Colors: White/accent for progress, gray for remaining

### Fullscreen vs Normal Mode

**Reference:** Compare `controls_full_size.png` vs `controls_normal_size.png`

- **Fullscreen mode:**
  - Video occupies entire screen
  - Controls overlay on top of video
  - Larger control elements for easier touch targets

- **Normal mode:**
  - Video in constrained container
  - Same control layout, proportionally scaled
  - Collapse button changes to expand/fullscreen button

### Settings Menu Design

**Reference:** `controls_settings.png`

#### Main Settings Bottom Sheet
- **Presentation:** Modal bottom sheet with rounded top corners
- **Background:** Dark gray overlay (rgba(0, 0, 0, 0.85) or similar)
- **Border radius:** 16-20dp/pt on top corners
- **Header:**
  - Title: "Settings" (bold, large text ~20-24sp/pt)
  - Close button: X icon (top-right corner)
  - Padding: 20-24dp/pt
- **Menu Items:** List of navigation items, each containing:
  - **Icon** (left): Relevant icon for the option
    - Subtitles: CC/closed captions icon
    - Video: Play/video icon
    - Playback speed: Gauge/speedometer icon
  - **Label** (center-left): Option name (medium weight)
  - **Current value** (center-right): Current selection in gray text
  - **Chevron** (right): Right-pointing arrow (›)
  - **Divider:** Optional subtle line between items
  - **Height:** 56-64dp/pt per item
  - **Padding:** 16-20dp/pt horizontal, 12-16dp/pt vertical
- **Interaction:**
  - Tap to navigate to submenu
  - Smooth slide-in animation from bottom
  - Backdrop: Semi-transparent black overlay (rgba(0, 0, 0, 0.5))

#### Video Quality Submenu

**Reference:** `controls_settings_video_quality.png`

- **Header:** "Video Quality" title with close button
- **List items:** Quality options presented vertically
  - **Auto (Recommended)** - with "Recommended" as subtitle
  - **Full HD** - 1080p resolution label
  - **High** - 720p resolution label
  - **Medium** - 480p resolution label
  - (Additional options as needed: Low, SD, etc.)
- **Selected state:**
  - **Background:** Rounded pill/capsule background (border-radius: 28-32dp/pt)
  - **Color:** Lighter gray than sheet background (rgba(255, 255, 255, 0.15))
  - **Checkmark:** Right-aligned checkmark icon
  - **Padding:** Item padding creates pill shape (12-16dp/pt vertical, 20-24dp/pt horizontal)
- **Non-selected state:**
  - Transparent background
  - No checkmark
  - Same text styling

#### Subtitles Submenu

**Reference:** `controls_settings_subtitle.png`

- **Header:** "Subtitles" title with close button
- **List items:** Language/subtitle track options
  - **Off** - Disables subtitles
  - **English** - Language options
  - (Additional languages as available)
- **Selected state:** Same rounded pill style as Video Quality
  - Rounded pill background
  - Checkmark on right
- **Item height:** 56-64dp/pt
- **Typography:** Language names in regular weight, ~16-18sp/pt

#### Playback Speed Submenu

**Reference:** `controls_settings_speed_vertical.png`

- **Header:** "Speed" title with close button
- **List items:** Speed multiplier options presented vertically
  - **Slowest** - 0.5x
  - **Slow** - 0.75x
  - **Normal** - 1.0x (default)
  - **Fast** - 1.25x
  - **Fastest** - 1.5x
  - (Additional speeds as needed: 1.5x, 2.0x, etc.)
- **Layout:**
  - **Label** (left): Descriptive name (Slowest, Slow, Normal, etc.)
  - **Multiplier** (right of label): Speed value in gray (0.5x, 1.0x, etc.)
  - **Checkmark** (far right): For selected item
- **Selected state:** Same rounded pill background as other submenus
- **Default selection:** "Normal (1.0x)"

### Design System Specifications

#### Color Palette
- **Background overlays:**
  - Semi-transparent black: rgba(0, 0, 0, 0.6-0.7) for video overlay
  - Dark gray: rgba(40, 40, 40, 0.95) or similar for bottom sheets
- **Text:**
  - Primary: White (#FFFFFF) or near-white
  - Secondary: Light gray (#B0B0B0, #808080)
  - Accent: Use theme accent color for interactive elements
- **Selection state:**
  - Pill background: rgba(255, 255, 255, 0.1-0.15)
  - Checkmark: White or accent color

#### Typography
- **Bottom sheet titles:** Bold, 20-24sp/pt
- **Menu item labels:** Medium weight, 16-18sp/pt
- **Secondary text (values, multipliers):** Regular, 14-16sp/pt, gray color
- **Time display:** Regular or medium, 12-14sp/pt, monospace recommended

#### Spacing & Layout
- **Bottom sheet padding:**
  - Horizontal: 20-24dp/pt
  - Vertical (header): 20-24dp/pt
  - Between items: 8-12dp/pt
- **Menu item padding:**
  - Horizontal: 16-20dp/pt
  - Vertical: 12-16dp/pt
  - Icon spacing: 12-16dp/pt from left edge
  - Value spacing: 12-16dp/pt from right edge
- **Icon sizes:**
  - Menu icons: 24dp/pt
  - Checkmarks: 20-24dp/pt
  - Control buttons: 24-32dp/pt (top bar), 48-72dp/pt (center controls)

#### Animation & Transitions
- **Bottom sheet appearance:**
  - Duration: 250-300ms
  - Easing: Deceleration curve (ease-out)
  - Motion: Slide up from bottom
- **Submenu navigation:**
  - Duration: 200-250ms
  - Easing: Standard curve
  - Motion: Slide right (to submenu), slide left (back to main)
- **Selection state:**
  - Duration: 150-200ms
  - Easing: Standard curve
  - Visual feedback: Immediate pill background appearance

#### Accessibility Requirements
- **Touch targets:** Minimum 48x48dp/pt for all interactive elements
- **Contrast ratios:**
  - Text on dark backgrounds: Minimum 4.5:1 (WCAG AA)
  - Icons: Minimum 3:1
- **Screen reader support:**
  - All buttons must have semantic labels
  - Bottom sheet must announce content changes
  - Selection state must be announced
- **Keyboard navigation:** Support for D-pad and keyboard navigation on TV/tablet devices

### Implementation Notes

1. **Strict adherence required:** All implementations MUST match the screenshots exactly
   - Layout structure and positioning
   - Visual styling (colors, borders, shadows)
   - Typography and spacing
   - Animation behavior

2. **Platform adaptation:**
   - Android: Use Material Design 3 components where applicable (BottomSheet, ListTile, etc.)
   - iOS: Use Cupertino components for iOS styling variant
   - Maintain same UX patterns across platforms, adapt visual styling only

3. **Responsive behavior:**
   - Controls scale proportionally with video size
   - Touch targets maintain minimum size requirements
   - Text remains legible at all sizes

4. **Testing requirements:**
   - Visual regression tests against reference screenshots
   - Interaction tests for all menu navigation
   - Accessibility audits (TalkBack, VoiceOver)
   - Performance: Animations must maintain 60fps

5. **Design assets location:** `docs/images/screenshots/controls_*`
   - Use as reference during implementation
   - Compare final implementation against screenshots
   - Update screenshots if design evolves (with documentation)

## Platform-Specific Notes

### Android
- Min SDK: 21 (Lollipop)
- Uses ExoPlayer 2.x
- Requires INTERNET and ACCESS_NETWORK_STATE permissions
- Chromecast requires Google Play Services

### iOS
- Min iOS: 13.0 (Swift concurrency; Flutter 3.44+ dropped iOS 12)
- Plugin supports both Swift Package Manager (`ios/zmedia_player/Package.swift`) and CocoaPods
- Uses AVPlayer/AVFoundation
- Requires NSAppTransportSecurity configuration for HTTP
- Background audio requires UIBackgroundModes in Info.plist
- FairPlay requires valid certificate from Apple

## Documentation Structure

- **`docs/api-reference/`** - User-facing API documentation and guides
- **`docs/implementation/`** - Architecture, testing, security documentation
- **`docs/summary/`** - Project status, metrics, feature lists
- **`example/`** - Full-featured demo app with all capabilities

## Development Workflow

1. Make changes in `lib/src/` or native code
2. Run `flutter analyze` to check for issues
3. Write/update tests in `test/`
4. Run `flutter test` to verify
5. Test in example app: `cd example && flutter run`
6. Update relevant documentation in `docs/` if adding features
7. Ensure no breaking changes to public API

## Branching Strategy

### Main Branch
- **main** - Production-ready code (protected)
- All feature branches are created from and merged back to main
- Requires passing CI checks and code review before merge

### Git Configuration (CRITICAL)

**⚠️ IMPORTANT: Commit Ownership**

All commits MUST be owned by the local GitHub user, never by automated tools or AI assistants.

#### First-Time Setup

```bash
# Set your GitHub username and email (one-time setup)
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"

# Verify configuration
git config --global user.name
git config --global user.email

# Ensure commits are signed (recommended)
git config --global commit.gpgsign true  # if you have GPG key
```

#### Verify Before Every Commit

```bash
# Check current Git identity
git config user.name
git config user.email

# If these show incorrect values, fix them:
git config user.name "Your Name"
git config user.email "your.email@example.com"
```

**❌ NEVER commit as:**
- Claude <noreply@anthropic.com>
- Any automated user
- Generic/placeholder names

**✅ ALWAYS commit as:**
- Your actual GitHub username and email
- The account that will push to the repository

### Automated Branch Creation for PLAN.md Tasks

For each task in PLAN.md, create a feature branch from main following this workflow:

#### Branch Naming Convention

**Format:** `feat/<ticket-title>` (kebab-case, lowercase)

**Examples:**
- "Material Design 3 controls" → `feat/material-design-3-controls`
- "Quality/Resolution selection UI" → `feat/quality-resolution-selection-ui`
- "Settings bottom sheet with animations" → `feat/settings-bottom-sheet-animations`

**Prefix by Type:**
- `feat/` - New features from PLAN.md
- `fix/` - Bug fixes
- `docs/` - Documentation updates
- `chore/` - Refactoring, maintenance
- `test/` - Test additions

#### Creating Branch for a PLAN.md Task

```bash
# 1. Ensure you're on main and up to date
git checkout main
git pull origin main

# 2. Create branch for task (example: Phase 2 Material Design 3 controls)
git checkout -b feat/material-design-3-controls

# 3. Push branch to remote
git push -u origin feat/material-design-3-controls

# 4. Verify your Git identity before making commits
git config user.name   # Should show YOUR name
git config user.email  # Should show YOUR email
```

#### Batch Branch Creation Script

Create `scripts/create_plan_branches.sh` for creating multiple branches:

```bash
#!/bin/bash
# Create all branches for a PLAN.md phase
# Usage: ./scripts/create_plan_branches.sh 2

PHASE=$1

# Verify Git identity first
echo "Git User: $(git config user.name) <$(git config user.email)>"
read -p "Is this correct? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Please configure Git with your credentials first:"
  echo "  git config user.name 'Your Name'"
  echo "  git config user.email 'your.email@example.com'"
  exit 1
fi

# Ensure on main
git checkout main
git pull origin main

# Phase 2 UI/UX Enhancement tasks
if [ "$PHASE" = "2" ]; then
  branches=(
    "feat/quality-resolution-selection-ui"
    "feat/audio-track-selection-ui"
    "feat/subtitle-controls-enhancement"
    "feat/speed-controls-enhancement"
    "feat/settings-bottom-sheet-animations"
    "feat/reusable-component-extraction"
    "feat/material-design-3-controls"
    "feat/cupertino-controls"
    "feat/adaptive-widget-selection"
    "feat/fullscreen-widget-variants"
    "feat/custom-controls-base-class"
    "feat/buffering-indicator-enhancement"
    "feat/error-overlay-enhancement"
    "feat/status-badges-indicators"
    "feat/visual-feedback-enhancements"
    "feat/media-theme-design-system"
    "feat/typography-scale"
    "feat/spacing-layout-tokens"
    "feat/animation-library"
    "feat/icon-set-standardization"
    "feat/accessibility-features-basic"
  )

  for branch in "${branches[@]}"; do
    echo "Creating branch: $branch"
    git checkout -b "$branch" main
    git push -u origin "$branch"
    git checkout main
  done

  echo "✅ Created ${#branches[@]} branches for Phase $PHASE"
fi
```


#### Development Workflow for PLAN.md Tasks

```bash
# 1. Pick a task from PLAN.md
# Example: Phase 2, Week 3-4: "Material Design 3 controls"

# 2. Verify your Git identity (CRITICAL)
git config user.name   # Must show YOUR name
git config user.email  # Must show YOUR email

# 3. Create and switch to feature branch
git checkout -b feat/material-design-3-controls main

# 4. Implement the task following PLAN.md specifications
# (Write code, create files, etc.)

# 5. Stage changes
git add lib/src/widgets/controls/material_controls.dart
git add lib/src/widgets/components/

# 6. YOU create the commit (not automated tools)
git commit -m "feat: implement Material Design 3 controls

- Create MaterialMediaControls widget with M3 design language
- Implement Material 3 components (seek bar, buttons, sheets)
- Add Material color scheme integration
- Add elevation and shadows per M3 spec
- Integrate with Material ThemeData

Implements: Phase 2, Week 3-4 task from PLAN.md"

# 7. Verify commit author BEFORE pushing
git log -1 --format="%an <%ae>"
# Should show YOUR name and email, NOT Claude's

# 8. If commit author is wrong, amend it:
git commit --amend --reset-author

# 9. Push to remote
git push -u origin feat/material-design-3-controls

# 10. Create pull request (YOU create it, not automated)
gh pr create --title "feat: Material Design 3 controls" \
  --body "## Summary
Implements Material Design 3 controls widget from Phase 2, Week 3-4 of PLAN.md.

## Changes
- MaterialMediaControls widget with M3 design
- Material-specific components
- Theme integration
- Accessibility compliance

## Testing
- Tested on Android devices
- Material theme switching verified
- Accessibility with TalkBack tested

Closes #[issue-number] (if applicable)"

# 11. After merge, clean up
git checkout main
git pull origin main
git branch -d feat/material-design-3-controls
```

### Tasks and Plan

For each completed task in PLAN.md, you MUST update the following:

#### 1. Mark Tasks as Complete
Check the box next to the task and all its sub-tasks to mark them as completed in PLAN.md.

#### 2. Update PLAN.md Metadata (REQUIRED)
After completing ANY task, always update the metadata section at the top of PLAN.md:

```markdown
**Last Updated:** [Current Date in format: Month DD, YYYY]
**Current Phase:** Phase X - [Phase Name] (Week Y [Status] - Z%)
```

**Examples:**
- `**Last Updated:** November 29, 2025`
- `**Current Phase:** Phase 2 - UI/UX Enhancement (Week 5 Complete - 68%)`

**Update triggers:**
- ✅ After completing a task or sub-task
- ✅ After updating progress percentages
- ✅ After adding/modifying deliverables
- ✅ After creating/modifying files listed in PLAN.md

#### 3. Update Progress Tracking
Update the following sections when applicable:
- Phase completion percentage in the progress table
- File counts in "Files Created" sections
- Task counts (e.g., "14/22 tasks complete")
- Overall completion percentage

**Example workflow:**
```bash
# After completing "Visual feedback enhancements" task:
# 1. Mark task as complete with [x]
# 2. Update: Phase 2: 64% → 68%
# 3. Update: Files Created: 10/22 → 15/22
# 4. Update: Last Updated: November 29, 2025
# 5. Update: Current Phase: Phase 2 - UI/UX Enhancement (Week 5 Complete - 68%)
```

#### 4. Document Changes in Files Created/Modified
When you create or modify files as part of task completion:
- Add new files to the "Files Created" list with [x]
- Update the "Files Modified" list with descriptions
- Keep accurate counts of total files created

### Commit Authorship Rules

**✅ CORRECT Commit Process:**
1. Developer writes code locally
2. Developer stages changes: `git add .`
3. Developer creates commit: `git commit -m "..."`
4. Developer verifies authorship: `git log -1 --format="%an <%ae>"`
5. Developer pushes: `git push`

**❌ INCORRECT - DO NOT DO THIS:**
1. ~~AI assistant creates commit automatically~~
2. ~~Commits with Claude's email~~
3. ~~Automated commits without user verification~~
4. ~~Co-authored-by Claude in commit message~~ (unless explicitly requested by user)

**Exception:**
The ONLY time "Co-Authored-By: Claude" should appear is in the automated release workflow (`.github/workflows/release.yml`) which is explicitly designed for that purpose.

### Branch Protection Rules

Configure on GitHub repository settings:

- ✅ Require pull request before merging
- ✅ Require status checks (CI tests, linting, analysis)
- ✅ Require code review (minimum 1 approval)
- ✅ Require branches up to date before merge
- ✅ Require signed commits (recommended)
- ❌ No force push to main
- ❌ No direct commits to main
- ❌ No deletion of main

### Tips for Branch Management

1. **One task = one branch** - Each branch corresponds to one PLAN.md task
2. **Keep branches short-lived** - Merge within 1-3 days
3. **Sync with main regularly** - Rebase/merge main frequently to avoid conflicts
4. **Delete merged branches** - Clean up after PR merge
5. **Verify authorship always** - Check `git log` before pushing
6. **Use conventional commits** - Follow format: `type: description`

### Branch Naming Reference

```bash
# Phase 2 UI/UX Enhancement Examples
feat/quality-resolution-selection-ui      # Week 1-2
feat/audio-track-selection-ui             # Week 1-2
feat/subtitle-controls-enhancement        # Week 1-2
feat/speed-controls-enhancement           # Week 1-2
feat/settings-bottom-sheet-animations     # Week 1-2
feat/reusable-component-extraction        # Week 1-2
feat/material-design-3-controls           # Week 3-4
feat/cupertino-controls                   # Week 3-4
feat/adaptive-widget-selection            # Week 3-4
feat/fullscreen-widget-variants           # Week 3-4
feat/custom-controls-base-class           # Week 3-4
feat/buffering-indicator-enhancement      # Week 5
feat/error-overlay-enhancement            # Week 5
feat/status-badges-indicators             # Week 5
feat/visual-feedback-enhancements         # Week 5
feat/media-theme-design-system            # Week 6
feat/typography-scale                     # Week 6
feat/spacing-layout-tokens                # Week 6
feat/animation-library                    # Week 6
feat/icon-set-standardization             # Week 6
feat/accessibility-features-basic         # Week 6
```

## Commit Verification and Best Practices

### Pre-Commit Checklist

Before EVERY commit, verify:

```bash
# 1. Check Git identity
git config user.name && git config user.email

# 2. Review staged changes
git status
git diff --cached

# 3. Run pre-commit hooks manually (if needed)
pre-commit run

# 4. Run tests
flutter test

# 5. Run analysis
flutter analyze

# 6. Create commit with YOUR credentials
git commit -m "feat: your feature description"

# 7. Verify commit author
git log -1 --format="Author: %an <%ae>"

# 8. If author is wrong, fix immediately
git commit --amend --reset-author
```

### Fixing Incorrect Commit Authorship

If you accidentally commit with wrong author:

```bash
# For the last commit (not yet pushed)
git commit --amend --reset-author

# For multiple commits (not yet pushed)
git rebase -i HEAD~3  # Replace 3 with number of commits
# Mark commits as 'edit', then for each:
git commit --amend --reset-author
git rebase --continue

# For already pushed commits (AVOID if possible)
# Contact repository maintainer for guidance
```

### Conventional Commit Format

All commits should follow this format:

```
<type>: <description>

[optional body]

[optional footer]
```

**Types:**
- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation changes
- `style:` Code style (formatting, no logic change)
- `refactor:` Code refactoring
- `perf:` Performance improvement
- `test:` Test additions/changes
- `chore:` Maintenance tasks

**Examples:**

```bash
# Simple feature
git commit -m "feat: add quality selection menu"

# With body
git commit -m "feat: implement Material Design 3 controls

- Add MaterialMediaControls widget
- Implement M3 design language
- Add theme integration

Implements Phase 2, Week 3-4 from PLAN.md"

# Breaking change
git commit -m "feat!: refactor MediaControls API

BREAKING CHANGE: MediaControls now requires theme parameter
See migration guide for details"
```

## Release Workflow

ZMedia Player uses automated semantic versioning with customizable release notes generation.

### Creating a Release

#### Option 1: GitHub Actions UI (Recommended)
1. Go to **Actions** → **Release** workflow
2. Click **Run workflow**
3. Select options:
   - **Version bump**: `auto` (detect from commits) or `major`/`minor`/`patch`
   - **Manual version**: Optional - specify exact version (e.g., `1.2.3`) to override version bump
   - **Pre-release**: `none` (stable) or `alpha`/`beta`/`rc`
   - **Dry run**: Test without creating actual release
4. Click **Run workflow**

#### Option 2: GitHub CLI
```bash
# Stable release (auto-detect version)
gh workflow run release.yml --ref main -f version_bump=auto -f pre_release=none

# Manual version (overrides version_bump)
gh workflow run release.yml --ref main -f manual_version=1.2.3 -f pre_release=none

# Pre-release (beta)
gh workflow run release.yml --ref main -f version_bump=minor -f pre_release=beta

# Manual version with pre-release
gh workflow run release.yml --ref main -f manual_version=2.0.0 -f pre_release=beta

# Dry run (test only)
gh workflow run release.yml --ref main -f version_bump=auto -f dry_run=true
```

### Semantic Versioning

The workflow uses **conventional commits** to automatically determine version bumps:

- `feat:` → MINOR version bump (new features)
- `fix:` → PATCH version bump (bug fixes)
- `perf:` → PATCH version bump (performance)
- `BREAKING CHANGE:` → MAJOR version bump (breaking changes)
- `docs:`, `style:`, `test:`, `chore:` → No version bump

**Example commits:**
```bash
# Feature (bumps MINOR)
git commit -m "feat: Add Chromecast support for Android"

# Bug fix (bumps PATCH)
git commit -m "fix: Resolve memory leak in MediaController"

# Breaking change (bumps MAJOR)
git commit -m "refactor!: Remove deprecated autoLoop parameter

BREAKING CHANGE: The autoLoop parameter has been removed.
Use repeatMode: MediaRepeatMode.all instead."
```

### Release Process

The release workflow respects branch protection rules on `main` by creating a pull request for version bumps:

1. **Commit Analysis**: Analyzes commits since last release
2. **Version Calculation**: Determines new version using semantic versioning (or uses manual version if specified)
3. **Changelog Generation**: Auto-generates categorized changelog
4. **Version Bump**: Updates `pubspec.yaml`, `CHANGELOG.md`, and `README.md` version badge
5. **Release Branch**: Creates a `release/vX.Y.Z` branch with version bump commits
6. **Pull Request**: Creates PR to `main` with version changes (triggers required status checks)
7. **Git Tag**: Creates annotated tag `v{version}` from release branch
8. **GitHub Release**: Creates release with generated notes

**Branch Protection Compatibility:**

- Release workflow creates a PR instead of pushing directly to `main`
- This allows required status checks to run before merging version bumps
- The Git tag and GitHub release are created immediately from the release branch
- After the PR passes checks, merge it to update `main` with the new version

**Post-Release Steps:**

1. Workflow creates the release and tag automatically
2. A PR is created for the version bump (e.g., `release/v1.2.3 → main`)
3. Wait for required status checks to pass on the PR
4. Merge the PR to update `main` with the new version
5. Delete the release branch after merge (optional)

**Manual Version Override:**

- If `manual_version` is specified (e.g., `1.2.3`), it overrides automatic version calculation
- Manual version must follow MAJOR.MINOR.PATCH format
- Allows creating releases without new commits (useful for hotfixes or corrections)
- Pre-release suffixes are still applied if `pre_release` is set

**Files Updated During Release:**

- `pubspec.yaml` - Package version
- `CHANGELOG.md` - Version history with categorized changes
- `README.md` - Version badge (`[![Version](https://img.shields.io/badge/version-X.Y.Z-blue.svg)]`)

**Release Branch:**

- Created as `release/vX.Y.Z` (e.g., `release/v1.2.3`)
- Contains version bump commits
- Used as source for git tag
- Can be deleted after PR is merged to `main`

### Pre-releases

Create pre-release versions for testing:

```bash
# Alpha (early development)
gh workflow run release.yml --ref main -f pre_release=alpha

# Beta (feature complete)
gh workflow run release.yml --ref main -f pre_release=beta

# Release Candidate (final testing)
gh workflow run release.yml --ref main -f pre_release=rc
```

Pre-release versions: `v1.2.0-alpha.1`, `v1.2.0-beta.1`, `v1.2.0-rc.1`

### Version History

All versions are preserved:

- ✅ Git tags (never deleted)
- ✅ GitHub releases (permanent)
- ✅ CHANGELOG.md (complete history)
- ✅ Git repository (install any version via Git reference)

> **Note**: Package is currently distributed via GitHub releases. pub.dev publishing is planned for future releases.

### Customizing Release Notes

Edit `.github/workflows/release.yml` to customize:

- Changelog format
- Sections and categories
- Commit filtering
- Release body template

See `.github/RELEASE_PLAN.md` for comprehensive release documentation.
