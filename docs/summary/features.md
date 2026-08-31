# Complete Feature List

Comprehensive list of all implemented features in the ZMedia Player package.

---

## Core Playback Features

### Basic Controls
- **Play** - Start playback
- **Pause** - Pause playback
- **Stop** - Stop and reset player
- **Seek** - Jump to specific position
- **Volume Control** - Adjust volume (0.0 - 1.0)
- **Mute/Unmute** - Toggle audio
- **Playback Speed** - Adjust speed (0.25x - 4.0x)
- **Position Tracking** - Real-time position updates
- **Duration Info** - Total media duration
- **State Management** - Track playback state

**Total:** 10 features

---

## Configuration & Setup

### MediaConfig Options
- **Auto-play** - Start playing automatically
- **Looping** - Repeat media continuously
- **Volume** - Initial volume setting
- **Speed** - Initial playback speed
- **Start Muted** - Begin with audio muted
- **Show Controls** - Display UI controls
- **BoxFit** - Video scaling mode (contain, cover, fill, etc.)
- **HTTP Headers** - Custom request headers
- **Controls Timeout** - Auto-hide controls duration
- **Background Playback** - Continue playing in background
- **Hardware Acceleration** - GPU-accelerated rendering
- **Cache Configuration** - Cache size and behavior
- **Respect Safe Area** - `respectSafeArea` flag to inset around notches/system bars
- **Immersive Landscape** - `immersiveLandscape` flag for edge-to-edge landscape playback
- **Secure Surface** - `secureSurface` flag; **Android** blocks screenshots/screen recording of the video surface, **iOS only detects** (no OS-level block) and reports via the surface state

---

## Streaming & Adaptive Playback

### Protocol Support
- **HLS** - HTTP Live Streaming
- **DASH** - Dynamic Adaptive Streaming over HTTP
- **HLS Live Streaming** - Live HLS with DVR support
- **DASH Live Streaming** - Live DASH with DVR support
- **Low-Latency Live** - Configurable latency targets
- **MP4** - Standard MP4 files
- **Progressive Download** - HTTP progressive streaming
- **Local File Playback** - Play `file://` URLs (`LocalMediaUtils.fileUri` builds them from a filesystem path)

### Quality Management
- **Auto Quality** - Automatic bitrate adaptation
- **Manual Selection** - User-selectable quality
- **Quality Tracks** - Multiple resolution support (360p - 4K)
- **Bandwidth Monitoring** - Real-time network speed tracking
- **Bitrate Display** - Show current bitrate
- **Frame Rate Info** - Display FPS information
- **Codec Information** - Video/audio codec details
- **Resolution Selection** - Choose specific resolutions

### Live Streaming
- **Live Edge Detection** - Automatic positioning at live
- **DVR/Time-Shifting** - `HlsConfig`/`DashConfig.enableDvr` gates seeking on a live stream and
  enables reporting of a DVR-window duration to seek within
- **Explicit Streaming Format** - `MediaItem.streamingFormat`
  (`StreamingFormat.hls`/`.dash`/`.progressive`) selects which of `hlsConfig`/`dashConfig`
  applies, overriding URL inference; `null` infers from the URL's path (`endsWith('.m3u8')`/
  `endsWith('.mpd')`). The two configs are never cross-applied, and a live item that resolves
  to a format with no config logs a debug-only warning
- **Latency Configuration** - `liveLatency` sets a target offset from the live edge (Android;
  iOS 14+ only)
- **Adaptive Segment Caching** - Transparent, read-through HLS/DASH segment cache during playback (**Android only**; caches what has been played for replay, not an offline download)

**Total:** 21 features

---

## Subtitles & Captions

### Format Support
- **SRT** - SubRip subtitle format
- **WebVTT** - Web Video Text Tracks
- **ASS/SSA** - Advanced SubStation Alpha

### Subtitle Features
- **Multiple Tracks** - Support for multiple subtitle files
- **Language Selection** - Choose subtitle language
- **Subtitle Styling** - Custom fonts and colors
- **Track Switching** - Change subtitles during playback
- **Default Track** - Auto-select preferred language
- **Forced Subtitles** - Display forced narrative subtitles

**Total:** 9 features

---

## Audio Management

### Audio Features
- **Multiple Audio Tracks** - Multiple language support
- **Audio Selection** - Switch audio tracks
- **Channel Info** - Display channel configuration
- **Codec Display** - Show audio codec
- **Sample Rate** - Audio quality information
- **Surround Sound** - 5.1, 7.1 audio support

**Total:** 6 features

---

## Playlist Management

### Playlist Features
- **Sequential Playback** - Play in order
- **Shuffle Mode** - Random order playback
- **Repeat None** - Stop at end
- **Repeat All** - Loop entire playlist
- **Repeat Single** - Loop current item
- **Skip Next** - Jump to next item
- **Skip Previous** - Jump to previous item
- **Skip to Index** - Jump to specific item
- **Playlist Navigation** - hasNext, hasPrevious helpers
- **Current Item Tracking** - Track playing item
- **Playlist Metadata** - Custom playlist info

**Total:** 11 features

---

## DRM & Content Protection

### DRM Support
- **Widevine** - Google's DRM for Android
- **FairPlay** - Apple's DRM for iOS
- **Token-Based Auth** - Custom JWT token authentication
- **EZDRM Integration** - Enterprise DRM service
- **License Acquisition** - Automatic license requests
- **License Renewal** - Handle expiring licenses
- **Session Management** - DRM session tracking
- **Minimum Security Level** - `DrmConfig.minWidevineSecurityLevel` sets a floor for Android Widevine (no iOS/FairPlay equivalent)
- **Certificate Handling** - FairPlay certificate management
- **Custom Headers** - DRM request customization

**Total:** 10 features

---

## Media Notifications

### Notification Features
- **System Integration** - Native notification display
- **Play/Pause Button** - Toggle playback
- **Next/Previous** - Skip tracks
- **Seek Forward/Backward** - Opt-in via `NotificationConfig.showSeekForward`/`showSeekBackward` (both default `false`); rendered only when the flag is set **and** the item is seekable. `seekInterval` labels the control on both platforms; the host app performs the seek from `actionEventStream`
- **Stop Button** - Stop playback
- **Media Artwork** - Display thumbnails
- **Auto-Generated Thumbnail** - Derive artwork from a video frame when `MediaItem.artworkUrl` is absent (iOS `AVAssetImageGenerator` / Android `MediaMetadataRetriever`)
- **Progress Bar** - Show playback progress
- **Notification Customization** - Configure buttons
- **Background Support** - Work when app backgrounded
- **Lock Screen Controls** - Control from lock screen

**Total:** 10 features

---

## Picture-in-Picture

### PiP Features
- **PiP Mode** - Floating video window
- **Custom Aspect Ratio** - Set window dimensions
- **Playback Controls** - Control in PiP mode (`PipConfig.showPlaybackControls`; Android gates
  custom actions entirely, iOS partially hides skip/scrub via `requiresLinearPlayback`, iOS 14+)
- **Custom Actions (Android)** - `PipConfig.actions` renders as `RemoteAction` buttons in the
  system PiP window; taps deliver a `PipActionEvent` on `MediaPlayer.pipActionStream`
- **Auto-Enter** - Activate on background
- **Manual Control** - Programmatic PiP toggle
- **State Tracking** - Monitor PiP status
- **Platform Support** - Android & iOS

**Total:** 8 features

---

## Casting & Streaming

### Chromecast (Android)
- **Device Discovery** - Find Chromecast devices
- **Connection Management** - Connect/disconnect
- **Playback Sync** - Synchronized playback
- **Remote Control** - Control from device

### AirPlay (iOS)
- **Device Discovery** - Find AirPlay devices
- **Route Picker** - Native iOS picker integration
- **Connection Management** - Automatic handling
- **Background Support** - Cast in background

### General Casting
- **Cast Status Monitoring** - Track connection state
- **Device List** - Available devices
- **Configurable Discovery** - `CastConfig.discoveryTimeout` bounds Android Chromecast
  discovery; `CastConfig.chromecastAppId` overrides the receiver app ID

**Total:** 11 features

Note: `CastConfig.autoConnect` (remembering/reconnecting to the last-used device) was removed —
this package has no persistence mechanism for a last-used device identifier, so it was never
implemented and would have been a silent no-op.

---

## ListView & Scroll Integration

### ListView Features
- **Auto-Play** - Play when visible
- **Auto-Pause** - Pause when hidden
- **Visibility Detection** - Track scroll position
- **Memory Management** - Efficient resource handling
- **Multiple Players** - Handle multiple instances

**Total:** 5 features

### MediaFeed (Feed / Scroll Playback)
Purpose-built for TikTok/Reels-style vertical feeds, backed by `MediaPlayerPool`:
- **Bounded Decoder Pool** - Hard cap on concurrently live `MediaController`/decoder sessions (`MediaPlayerPool`)
- **Prewarm Window** - Prepares upcoming items ahead of the active one within the pool's capacity
- **Activation Debounce** - Holds off acquiring a pool slot during a fast fling so flown-past items never spin up a player
- **Live Release** - Releases a player once its item leaves the live/prewarm window
- **Network-Aware Autoplay** - Optional `autoPlayPolicy` (e.g. `conservativeAutoPlayPolicy`) withholds autoplay on metered or poor/offline/unknown-quality connections

**Total:** 5 features

---

## Cache & Offline Support

> There is no download-manager UI or offline DRM on either platform. What's here is
> disk-caching of non-DRM media (`CacheService`) and, on Android, a transparent
> playback-time segment cache — not a "download now, watch later" flow for DRM content.

### Cache Features
- **Progressive Download** - Download while playing
- **LRU Eviction** - Least Recently Used removal
- **Cache Size Management** - Set maximum cache size
- **Download Progress** - Track download status (`CacheService.downloadProgressStream`)
- **Offline Playback** - Play a cached file with no network connection (**non-DRM content only**)
- **Cache Clearing** - Manual cache management
- **Android Adaptive Segment Caching** - Read-through HLS/DASH segment cache during playback (Android only; see Streaming section)

**Total:** 7 features

---

## UI & Widgets

### MediaPlayerWidget
- **Video Display** - Native video rendering
- **Built-in Controls** - Play, pause, seek bar
- **Custom Controls** - Build your own UI
- **Fullscreen Mode** - Expand to fullscreen
- **Control Overlay** - Auto-hiding controls
- **Loading Indicator** - Buffering display
- **Error Display** - Show error messages
- **BoxFit Support** - Video scaling options

### Custom Controls
- **MediaControls Widget** - Pre-built control bar
- **Customizable Buttons** - Add custom actions
- **Progress Bar** - Seekable progress indicator
- **Time Display** - Current/total time
- **Volume Slider** - Interactive volume control
- **Speed Selector** - Playback speed options

**Total:** 14 features

---

## Events & Callbacks

### State Events
- **onStateChanged** - Playback state updates
- **onPositionChanged** - Position updates
- **onDurationChanged** - Duration updates
- **onBuffering** - Buffering status
- **onError** - Error notifications

### Track Events
- **onSubtitleTracksChanged** - Subtitle track updates
- **onQualityTracksChanged** - Quality track updates
- **onAudioTracksChanged** - Audio track updates

### Advanced Events
- **onPipStatusChanged** - PiP state changes
- **onCastStatusChanged** - Cast state changes
- **onCastDevicesChanged** - Available devices
- **onDrmSessionChanged** - DRM session updates
- **errorStream / error** - `MediaController` convenience typed-error stream and last-error getter (re-emits `MediaPlayer.errorStream`)

**Total:** 13 events

---

## Developer Features

### API Design
- **Clean Architecture** - Separation of concerns
- **Factory Pattern** - Easy instance creation
- **Stream-Based** - Reactive programming
- **Type Safety** - Full null-safety
- **Error Handling** - Comprehensive exceptions
- **Documentation** - Inline API docs

### Platform Channels
- **Bidirectional Communication** - Flutter ↔ Native
- **Event Propagation** - Native → Flutter events
- **Method Invocation** - Flutter → Native calls
- **Error Propagation** - Exception handling

### Testing Support
- **Mockable APIs** - Easy to test
- **Test Utilities** - Helper functions
- **Example Tests** - Test templates

**Total:** 13 features

---

## Platform-Specific

### Android
- **AndroidX Media3 (ExoPlayer) Integration** - Native playback engine
- **MediaSession API** - System integration
- **PictureInPictureParams** - PiP configuration
- **Google Cast SDK** - Chromecast support
- **Widevine DRM** - Content protection

### iOS
- **AVPlayer Integration** - Native playback engine
- **MPNowPlayingInfoCenter** - Lock screen controls
- **AVPictureInPictureController** - PiP support
- **AVRoutePickerView** - AirPlay integration
- **FairPlay DRM** - Content protection
- **AVAudioSession** - Background playback
- **Swift Package Manager** - SPM support (`ios/zmedia_player/Package.swift`) alongside CocoaPods

---

## Feature Summary

Comprehensive feature set across playback, streaming, subtitles, DRM, casting, PiP, and notifications — see the categorized list below.

### By Category
- Core Playback: 10
- Configuration: 15
- Streaming: 21
- Subtitles: 9
- Audio: 6
- Playlists: 11
- DRM: 10
- Notifications: 11
- Picture-in-Picture: 8
- Casting: 11
- ListView & Feed: 10
- Cache: 7
- UI/Widgets: 14
- Events: 13
- Developer: 13
- Platform-Specific: 12

---

## Completeness

The features listed above are implemented and covered by the Dart test suite. Known gaps not
covered by this list: PlayReady (`DrmScheme.playready` exists but is not functional on either
platform — see the DRM comparison notes), analytics (`AnalyticsService` exists but has no call
sites in `MediaPlayer` — a host app must drive it), accessibility (no `Semantics` on the seek bar,
no D-pad/keyboard navigation), and internationalization (no `intl`/`flutter_localizations`
dependency; control strings are hardcoded English, layouts are not RTL-aware).

---

**Status:** Active development — feature-complete for the items above, native layers need on-device verification
