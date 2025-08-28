import 'package:flutter/material.dart';
import '../models/drm_config.dart';
import '../models/subtitle_track.dart';

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
    this.showControls = true,
    this.controlsTimeout = const Duration(seconds: 3),
    this.allowBackgroundPlayback = false,
    this.useHardwareAcceleration = true,
    this.bufferConfig,
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
    bool? showControls,
    Duration? controlsTimeout,
    bool? allowBackgroundPlayback,
    bool? useHardwareAcceleration,
    BufferConfig? bufferConfig,
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
      showControls: showControls ?? this.showControls,
      controlsTimeout: controlsTimeout ?? this.controlsTimeout,
      allowBackgroundPlayback:
          allowBackgroundPlayback ?? this.allowBackgroundPlayback,
      useHardwareAcceleration:
          useHardwareAcceleration ?? this.useHardwareAcceleration,
      bufferConfig: bufferConfig ?? this.bufferConfig,
    );
  }

  @override
  String toString() {
    return 'MediaConfig(autoPlay: $autoPlay, boxFit: $boxFit, volume: $volume, speed: $speed)';
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

/// Configuration for media notifications
class NotificationConfig {
  /// Whether to show notifications
  final bool enabled;

  /// Notification channel name
  final String channelName;

  /// Notification channel description
  final String channelDescription;

  /// Whether to show playback controls in notification
  final bool showControls;

  /// Whether to show progress in notification
  final bool showProgress;

  const NotificationConfig({
    this.enabled = true,
    this.channelName = 'Media Player',
    this.channelDescription = 'Media playback notifications',
    this.showControls = true,
    this.showProgress = true,
  });

  /// Creates a copy of this notification config with updated values
  NotificationConfig copyWith({
    bool? enabled,
    String? channelName,
    String? channelDescription,
    bool? showControls,
    bool? showProgress,
  }) {
    return NotificationConfig(
      enabled: enabled ?? this.enabled,
      channelName: channelName ?? this.channelName,
      channelDescription: channelDescription ?? this.channelDescription,
      showControls: showControls ?? this.showControls,
      showProgress: showProgress ?? this.showProgress,
    );
  }
}

/// Configuration for Picture-in-Picture mode
class PipConfig {
  /// Whether PiP is enabled
  final bool enabled;

  /// Whether to automatically enter PiP when app goes to background
  final bool autoEnterOnBackground;

  /// Aspect ratio for PiP window
  final double aspectRatio;

  /// Whether to show controls in PiP mode
  final bool showControls;

  const PipConfig({
    this.enabled = true,
    this.autoEnterOnBackground = false,
    this.aspectRatio = 16 / 9,
    this.showControls = true,
  });

  /// Creates a copy of this PiP config with updated values
  PipConfig copyWith({
    bool? enabled,
    bool? autoEnterOnBackground,
    double? aspectRatio,
    bool? showControls,
  }) {
    return PipConfig(
      enabled: enabled ?? this.enabled,
      autoEnterOnBackground:
          autoEnterOnBackground ?? this.autoEnterOnBackground,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      showControls: showControls ?? this.showControls,
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
