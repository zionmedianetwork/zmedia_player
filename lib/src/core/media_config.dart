import 'package:flutter/material.dart';
import '../models/drm_config.dart';
import '../models/subtitle_track.dart';
import '../models/streaming_config.dart';
import '../models/notification_config.dart';
import '../models/pip_config.dart';
import '../models/cast_device.dart';

/// Configuration class for the media player
class MediaConfig {
  /// Whether to start playing automatically when media is loaded
  final bool autoPlay;

  /// Whether to loop the current media item
  final bool looping;

  /// How the video should be inscribed into the available space
  final BoxFit boxFit;

  /// Initial volume level (0.0 to 1.0)
  final double volume;

  /// Initial playback speed
  final double speed;

  /// Whether to start muted
  final bool startMuted;

  /// Custom HTTP headers for media requests
  final Map<String, String>? httpHeaders;

  /// DRM configuration
  final DrmConfig? drmConfig;

  /// Subtitle configuration
  final SubtitleConfig? subtitleConfig;

  /// Cache configuration
  final CacheConfig? cacheConfig;

  /// Notification configuration
  final NotificationConfig? notificationConfig;

  /// Picture-in-Picture configuration
  final PipConfig? pipConfig;

  /// Cast configuration
  final CastConfig? castConfig;

  /// Whether to show media controls
  final bool showControls;

  /// Control timeout duration
  final Duration controlsTimeout;

  /// Whether to allow background playback
  final bool allowBackgroundPlayback;

  /// Whether to use hardware acceleration when available
  final bool useHardwareAcceleration;

  /// Buffer configuration
  final BufferConfig? bufferConfig;

  /// HLS configuration
  final HlsConfig? hlsConfig;

  /// DASH configuration
  final DashConfig? dashConfig;

  /// Transparent Media3 segment cache configuration for adaptive (HLS/DASH)
  /// streams (C-03b). **Android-only** — see [AdaptiveCacheConfig] for the
  /// full contract, including why this has no iOS equivalent today.
  final AdaptiveCacheConfig? adaptiveCacheConfig;

  /// Whether to enable subtitles by default
  final bool enableSubtitles;

  /// When true, the player insets its video below system intrusions
  /// (status bar / notch) via a [SafeArea] wrap; when false the video is
  /// edge-to-edge (current default behaviour).
  final bool respectSafeArea;

  /// When true, the player hides the system status bar (immersive sticky
  /// mode) while the device is in landscape orientation, and restores it
  /// when the device returns to portrait.  Has no effect in portrait.
  final bool immersiveLandscape;

  /// Opt-in screen-capture protection for this player's video surface
  /// (B-12). Defaults to `false` — no existing consumer's behaviour changes
  /// unless this is explicitly set.
  ///
  /// Sets the initial value applied at [MediaPlayer.initialize]; toggle it
  /// afterwards via [MediaPlayer.setSecureSurface]. See
  /// `lib/src/security/screen_capture_protection.dart` for the full,
  /// deliberately-asymmetric Android (hard block via `FLAG_SECURE`) vs iOS
  /// (`UIScreen.isCaptured` detection only) behaviour this controls.
  final bool secureSurface;

  const MediaConfig({
    this.autoPlay = false,
    this.looping = false,
    this.boxFit = BoxFit.contain,
    this.volume = 1.0,
    this.speed = 1.0,
    this.startMuted = false,
    this.httpHeaders,
    this.drmConfig,
    this.subtitleConfig,
    this.cacheConfig,
    this.notificationConfig,
    this.pipConfig,
    this.castConfig,
    this.showControls = true,
    this.controlsTimeout = const Duration(seconds: 3),
    this.allowBackgroundPlayback = false,
    this.useHardwareAcceleration = true,
    this.bufferConfig,
    this.hlsConfig,
    this.dashConfig,
    this.adaptiveCacheConfig,
    this.enableSubtitles = true,
    this.respectSafeArea = false,
    this.immersiveLandscape = false,
    this.secureSurface = false,
  });

  /// Creates a copy of this config with updated values
  MediaConfig copyWith({
    bool? autoPlay,
    bool? looping,
    BoxFit? boxFit,
    double? volume,
    double? speed,
    bool? startMuted,
    Map<String, String>? httpHeaders,
    DrmConfig? drmConfig,
    SubtitleConfig? subtitleConfig,
    CacheConfig? cacheConfig,
    NotificationConfig? notificationConfig,
    PipConfig? pipConfig,
    CastConfig? castConfig,
    bool? showControls,
    Duration? controlsTimeout,
    bool? allowBackgroundPlayback,
    bool? useHardwareAcceleration,
    BufferConfig? bufferConfig,
    HlsConfig? hlsConfig,
    DashConfig? dashConfig,
    AdaptiveCacheConfig? adaptiveCacheConfig,
    bool? enableSubtitles,
    bool? respectSafeArea,
    bool? immersiveLandscape,
    bool? secureSurface,
  }) {
    return MediaConfig(
      autoPlay: autoPlay ?? this.autoPlay,
      looping: looping ?? this.looping,
      boxFit: boxFit ?? this.boxFit,
      volume: volume ?? this.volume,
      speed: speed ?? this.speed,
      startMuted: startMuted ?? this.startMuted,
      httpHeaders: httpHeaders ?? this.httpHeaders,
      drmConfig: drmConfig ?? this.drmConfig,
      subtitleConfig: subtitleConfig ?? this.subtitleConfig,
      cacheConfig: cacheConfig ?? this.cacheConfig,
      notificationConfig: notificationConfig ?? this.notificationConfig,
      pipConfig: pipConfig ?? this.pipConfig,
      castConfig: castConfig ?? this.castConfig,
      showControls: showControls ?? this.showControls,
      controlsTimeout: controlsTimeout ?? this.controlsTimeout,
      allowBackgroundPlayback:
          allowBackgroundPlayback ?? this.allowBackgroundPlayback,
      useHardwareAcceleration:
          useHardwareAcceleration ?? this.useHardwareAcceleration,
      bufferConfig: bufferConfig ?? this.bufferConfig,
      hlsConfig: hlsConfig ?? this.hlsConfig,
      dashConfig: dashConfig ?? this.dashConfig,
      adaptiveCacheConfig: adaptiveCacheConfig ?? this.adaptiveCacheConfig,
      enableSubtitles: enableSubtitles ?? this.enableSubtitles,
      respectSafeArea: respectSafeArea ?? this.respectSafeArea,
      immersiveLandscape: immersiveLandscape ?? this.immersiveLandscape,
      secureSurface: secureSurface ?? this.secureSurface,
    );
  }

  @override
  String toString() {
    return 'MediaConfig(autoPlay: $autoPlay, boxFit: $boxFit, volume: $volume, '
        'speed: $speed, respectSafeArea: $respectSafeArea, '
        'immersiveLandscape: $immersiveLandscape, secureSurface: $secureSurface)';
  }
}

/// Configuration for transparent segment caching of adaptive (HLS/DASH)
/// streams (C-03b).
///
/// **Android-only.** On Android this wraps ExoPlayer/Media3's data source
/// chain in a `CacheDataSource` backed by a single, process-wide
/// `SimpleCache` (see `AdaptiveCacheHolder.kt`): segments, init segments and
/// manifests/playlists are transparently written to disk as they're
/// downloaded during normal playback, and served from disk on any
/// subsequent playback of the same URL — including with no network
/// connection, as long as the requested byte ranges are already cached.
/// There is no download-ahead/prefetch here; only what has actually played
/// gets cached.
///
/// iOS has **no** equivalent today. AVFoundation has no transparent
/// read-through segment cache comparable to Media3's `CacheDataSource`;
/// offline HLS on iOS requires the explicit-download `AVAssetDownloadTask`
/// API (producing a `.movpkg`), which is a fundamentally different,
/// explicit-download model and a separate, not-yet-implemented piece of
/// work. Setting this config has **no effect whatsoever on iOS** — it is
/// simply never read there. This mirrors how [DashConfig] is Android-only
/// today: an honestly asymmetric, documented gap rather than a silent no-op
/// masquerading as cross-platform.
///
/// This is opt-in and **off by default** ([enabled] defaults to `false`):
/// transparent caching writes to the user's device storage without an
/// explicit per-request prompt, so a host app must deliberately turn it on
/// via this config rather than have it happen as a surprise side effect of
/// upgrading the package.
///
/// **DRM interaction:** regardless of this config, a media item that
/// carries a `drmConfig` is never wrapped in `CacheDataSource` on the
/// native side — protected segments are always fetched directly from the
/// upstream `DataSource.Factory` and never written to the plaintext segment
/// cache. This is a deliberate fail-safe: Media3's `CacheDataSource` caches
/// the raw (still-encrypted-on-disk, for most DRM schemes) bytes it reads
/// from its upstream, but ExoPlayer's DRM session is wired at the
/// `MediaSource` level, not the `DataSource` level — nothing in the
/// `CacheDataSource` layer itself re-validates that a caller decrypting
/// cached bytes later still holds a valid license. Rather than depend on
/// that distinction holding for every current and future DRM scheme this
/// package supports (Widevine, ClearKey, FairPlay-via-EZDRM), DRM-configured
/// items simply never enter the segment cache at all.
class AdaptiveCacheConfig {
  /// Opt-in switch. Defaults to `false` — must be explicitly enabled.
  final bool enabled;

  /// Maximum size, in bytes, of the shared on-disk segment cache before the
  /// LRU evictor (`LeastRecentlyUsedCacheEvictor` on Android) starts
  /// removing the least-recently-used cached spans to make room for new
  /// ones. Defaults to 250MB — larger than the progressive-download
  /// [CacheConfig.maxCacheSize] default (100MB) since a single adaptive
  /// stream can accumulate cached segments across multiple quality
  /// renditions as ABR switches tracks.
  ///
  /// Because the underlying native cache is a single process-wide instance
  /// shared by every player (Media3 requires exactly one `SimpleCache` per
  /// cache directory, per process — see `AdaptiveCacheHolder.kt`), only the
  /// value supplied by whichever player *first* enables caching in a given
  /// app process actually takes effect; a later player enabling caching
  /// with a different [maxCacheSizeBytes] has no effect on the already-sized
  /// cache (a warning is logged natively when this happens). Configure this
  /// consistently across players in the same app if it matters.
  final int maxCacheSizeBytes;

  const AdaptiveCacheConfig({
    this.enabled = false,
    this.maxCacheSizeBytes = 250 * 1024 * 1024, // 250MB default
  });

  /// Creates a copy of this config with updated values
  AdaptiveCacheConfig copyWith({
    bool? enabled,
    int? maxCacheSizeBytes,
  }) {
    return AdaptiveCacheConfig(
      enabled: enabled ?? this.enabled,
      maxCacheSizeBytes: maxCacheSizeBytes ?? this.maxCacheSizeBytes,
    );
  }

  /// Converts this config to a map for platform communication. Consumed
  /// only by the Android native layer (`MediaPlayerInstance.loadMediaItem`
  /// in `MediaPlayerManager.kt`) — iOS never reads this key.
  Map<String, dynamic> toMap() {
    return {
      'enabled': enabled,
      'maxCacheSizeBytes': maxCacheSizeBytes,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AdaptiveCacheConfig &&
        other.enabled == enabled &&
        other.maxCacheSizeBytes == maxCacheSizeBytes;
  }

  @override
  int get hashCode => Object.hash(enabled, maxCacheSizeBytes);

  @override
  String toString() {
    return 'AdaptiveCacheConfig(enabled: $enabled, '
        'maxCacheSizeBytes: $maxCacheSizeBytes)';
  }
}

/// Configuration for media caching
class CacheConfig {
  /// Maximum cache size in bytes
  final int maxCacheSize;

  /// Cache expiration duration
  final Duration cacheExpiration;

  /// Whether to enable cache
  final bool enabled;

  /// Directory for cache storage
  final String? cacheDirectory;

  const CacheConfig({
    this.maxCacheSize = 100 * 1024 * 1024, // 100MB default
    this.cacheExpiration = const Duration(days: 7),
    this.enabled = true,
    this.cacheDirectory,
  });

  /// Creates a copy of this cache config with updated values
  CacheConfig copyWith({
    int? maxCacheSize,
    Duration? cacheExpiration,
    bool? enabled,
    String? cacheDirectory,
  }) {
    return CacheConfig(
      maxCacheSize: maxCacheSize ?? this.maxCacheSize,
      cacheExpiration: cacheExpiration ?? this.cacheExpiration,
      enabled: enabled ?? this.enabled,
      cacheDirectory: cacheDirectory ?? this.cacheDirectory,
    );
  }
}

/// Configuration for buffering behavior
class BufferConfig {
  /// Minimum buffer duration before playback starts
  final Duration minBufferDuration;

  /// Maximum buffer duration
  final Duration maxBufferDuration;

  /// Buffer duration for rebuffering
  final Duration rebufferDuration;

  /// Target buffer duration
  final Duration targetBufferDuration;

  const BufferConfig({
    this.minBufferDuration = const Duration(seconds: 2),
    this.maxBufferDuration = const Duration(seconds: 30),
    this.rebufferDuration = const Duration(seconds: 1),
    this.targetBufferDuration = const Duration(seconds: 10),
  });

  /// Creates a copy of this buffer config with updated values
  BufferConfig copyWith({
    Duration? minBufferDuration,
    Duration? maxBufferDuration,
    Duration? rebufferDuration,
    Duration? targetBufferDuration,
  }) {
    return BufferConfig(
      minBufferDuration: minBufferDuration ?? this.minBufferDuration,
      maxBufferDuration: maxBufferDuration ?? this.maxBufferDuration,
      rebufferDuration: rebufferDuration ?? this.rebufferDuration,
      targetBufferDuration: targetBufferDuration ?? this.targetBufferDuration,
    );
  }
}
