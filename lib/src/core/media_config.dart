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
