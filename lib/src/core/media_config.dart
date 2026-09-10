import 'package:flutter/material.dart';
import '../models/drm_config.dart';
import '../models/subtitle_track.dart';
import '../models/streaming_config.dart';
import '../models/pip_config.dart';
import '../models/cast_device.dart';

/// Configuration class for the media player
///
/// Note: media playback notifications are **not** configured here. Use
/// [NotificationService] with its own `NotificationConfig` — that path
/// drives the real native notification channel methods. (A prior
/// `MediaConfig.notificationConfig` field was removed because nothing ever
/// read it.)
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

  /// Custom HTTP headers for media requests.
  ///
  /// **Deprecated and inert — this field has never had any effect.** It is
  /// serialized onto the `config` payload of `initialize`/`updateConfig`/
  /// `load` exactly as before (the wire shape is unchanged), but *neither*
  /// native implementation reads that key: Android's
  /// `MediaPlayerManager.loadMediaItem` reads `mediaItem["httpHeaders"]` and
  /// iOS's reads `mediaItem["httpHeaders"]` — the per-item map — and nothing
  /// anywhere reads `config["httpHeaders"]`.
  ///
  /// Use [MediaItem.httpHeaders] instead; that is the canonical, wired path
  /// for request headers (it becomes `DefaultHttpDataSource.Factory`'s
  /// default request properties on Android and
  /// `AVURLAssetHTTPHeaderFieldsKey` on iOS).
  ///
  /// Kept (rather than removed) so existing code keeps compiling, and
  /// deprecated (rather than wired) because wiring it would be a silent
  /// behavior change for anyone currently setting it. This mirrors how
  /// `HlsConfig`/`DashConfig.enableLiveStream` was deprecated in favor of the
  /// canonical `MediaItem.isLive`.
  @Deprecated(
    'MediaConfig.httpHeaders is never read by either native platform, so it '
    'has no effect. Use MediaItem.httpHeaders — the canonical, wired header '
    'path — instead. This field will be removed in a future major release.',
  )
  final Map<String, String>? httpHeaders;

  /// DRM configuration
  final DrmConfig? drmConfig;

  /// Subtitle configuration
  final SubtitleConfig? subtitleConfig;

  /// Cache configuration
  final CacheConfig? cacheConfig;

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

  /// Issue #125: how long `MediaPlayer.load()` will wait for the platform to
  /// report *any* outcome for the item it just handed over, before
  /// synthesizing a [NetworkException] (category
  /// `MediaErrorCategory.network`) onto `MediaPlayer.errorStream` and
  /// moving `PlaybackState.state` to `PlayerState.error`.
  ///
  /// This exists because `load()` completing successfully only means "the
  /// item was handed to the platform" — ExoPlayer/AVPlayer accept a media
  /// item synchronously and only discover network/HTTP/DRM/decoder problems
  /// afterwards, asynchronously. A load that never resolves either way (no
  /// `onError`, no `ready`/`playing`) would otherwise leave the player in
  /// `buffering` forever with nothing on any stream — the exact "spinner
  /// that spins until the user gives up" failure #125 reported.
  ///
  /// Defaults to 30 seconds — deliberately generous. A slow manifest fetch
  /// on a poor connection, a multi-round-trip DRM licence handshake, or a
  /// cold CDN can all legitimately take many seconds, and a false "this
  /// stream is dead" is a worse failure than a late one. The watchdog adds
  /// a second guard on top of this: when the timer fires it only reports an
  /// error if the player is *still* in `PlayerState.buffering` **and**
  /// `PlaybackState.position` has not advanced since the load was issued,
  /// so a slow-but-progressing load is never killed.
  ///
  /// Set to `null` to disable the watchdog entirely (restoring the
  /// pre-#125 "wait forever" behaviour) — e.g. for a host app that runs its
  /// own, smarter stall detection. Note `copyWith` cannot null this field by
  /// passing `null`; use `copyWith(clearLoadTimeout: true)`.
  ///
  /// **Dart-side only.** This value is never serialized across the
  /// MethodChannel and neither native platform reads it; the timer lives
  /// entirely in `MediaPlayer`. It is cancelled by the first
  /// `ready`/`playing`/`completed`/`error` event, by `pause()`/`stop()`, and
  /// by `dispose()`.
  final Duration? loadTimeout;

  const MediaConfig({
    this.autoPlay = false,
    this.looping = false,
    this.boxFit = BoxFit.contain,
    this.volume = 1.0,
    this.speed = 1.0,
    this.startMuted = false,
    // The parameter stays (removing it would break existing callers), but
    // is annotated so the deprecation surfaces at the call site rather than
    // only on a field read.
    @Deprecated(
      'MediaConfig.httpHeaders is never read by either native platform, so '
      'it has no effect. Use MediaItem.httpHeaders instead.',
    )
    // ignore: deprecated_member_use_from_same_package
    this.httpHeaders,
    this.drmConfig,
    this.subtitleConfig,
    this.cacheConfig,
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
    this.loadTimeout = const Duration(seconds: 30),
  });

  /// Creates a copy of this config with updated values
  MediaConfig copyWith({
    bool? autoPlay,
    bool? looping,
    BoxFit? boxFit,
    double? volume,
    double? speed,
    bool? startMuted,
    @Deprecated(
      'MediaConfig.httpHeaders is never read by either native platform, so '
      'it has no effect. Use MediaItem.httpHeaders instead.',
    )
    Map<String, String>? httpHeaders,
    DrmConfig? drmConfig,
    SubtitleConfig? subtitleConfig,
    CacheConfig? cacheConfig,
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
    Duration? loadTimeout,
    bool clearLoadTimeout = false,
  }) {
    return MediaConfig(
      autoPlay: autoPlay ?? this.autoPlay,
      looping: looping ?? this.looping,
      boxFit: boxFit ?? this.boxFit,
      volume: volume ?? this.volume,
      speed: speed ?? this.speed,
      startMuted: startMuted ?? this.startMuted,
      // Deliberately still copied: deprecating the field must not silently
      // drop a value a caller already set (the wire shape is unchanged).
      // ignore: deprecated_member_use_from_same_package
      httpHeaders: httpHeaders ?? this.httpHeaders,
      drmConfig: drmConfig ?? this.drmConfig,
      subtitleConfig: subtitleConfig ?? this.subtitleConfig,
      cacheConfig: cacheConfig ?? this.cacheConfig,
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
      // [loadTimeout] is the one nullable field here whose `null` is
      // meaningful (it *disables* the #125 load watchdog) rather than
      // "leave unchanged", so it cannot be cleared by passing `null` — the
      // `??` idiom every other field uses would read that as "keep the
      // current value". Clearing goes through the explicit
      // [clearLoadTimeout] flag instead, which wins over any passed value.
      // Same convention as `PlaybackState.copyWith`'s `clearLiveEdgeOffset`.
      loadTimeout: clearLoadTimeout ? null : (loadTimeout ?? this.loadTimeout),
    );
  }

  @override
  String toString() {
    return 'MediaConfig(autoPlay: $autoPlay, boxFit: $boxFit, volume: $volume, '
        'speed: $speed, respectSafeArea: $respectSafeArea, '
        'immersiveLandscape: $immersiveLandscape, secureSurface: $secureSurface, '
        'loadTimeout: $loadTimeout)';
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
