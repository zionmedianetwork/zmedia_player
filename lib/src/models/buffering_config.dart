/// Buffering configuration for adaptive buffer management
///
/// Defines buffer sizes and thresholds for optimal playback under
/// varying network conditions. Used by both Android (ExoPlayer) and
/// iOS (AVPlayer) to configure platform-specific buffering behavior.
library;

/// Configuration for buffering behavior
class BufferingConfig {
  /// Minimum buffer duration before playback can start (in milliseconds)
  final int minBufferMs;

  /// Maximum buffer duration to maintain (in milliseconds)
  final int maxBufferMs;

  /// Target buffer duration for optimal playback (in milliseconds)
  final int targetBufferMs;

  /// Buffer duration to maintain after rebuffering (in milliseconds)
  final int rebufferMs;

  /// Whether to enable adaptive buffering based on network conditions
  final bool enableAdaptiveBuffering;

  /// Whether to prioritize fast startup over buffer size
  final bool prioritizeFastStartup;

  const BufferingConfig({
    this.minBufferMs = 2500,
    this.maxBufferMs = 50000,
    this.targetBufferMs = 15000,
    this.rebufferMs = 5000,
    this.enableAdaptiveBuffering = true,
    this.prioritizeFastStartup = false,
  });

  /// Creates a configuration optimized for fast startup
  factory BufferingConfig.fastStartup() {
    return const BufferingConfig(
      minBufferMs: 1000,
      maxBufferMs: 30000,
      targetBufferMs: 10000,
      rebufferMs: 2500,
      prioritizeFastStartup: true,
    );
  }

  /// Creates a configuration optimized for smooth playback
  factory BufferingConfig.smoothPlayback() {
    return const BufferingConfig(
      minBufferMs: 5000,
      maxBufferMs: 60000,
      targetBufferMs: 20000,
      rebufferMs: 7500,
      prioritizeFastStartup: false,
    );
  }

  /// Creates a configuration optimized for poor network conditions
  factory BufferingConfig.poorNetwork() {
    return const BufferingConfig(
      minBufferMs: 10000,
      maxBufferMs: 90000,
      targetBufferMs: 30000,
      rebufferMs: 15000,
      prioritizeFastStartup: false,
    );
  }

  /// Creates a configuration for live streaming (smaller buffers)
  factory BufferingConfig.liveStreaming({int targetLatencyMs = 3000}) {
    return BufferingConfig(
      minBufferMs: targetLatencyMs ~/ 2,
      maxBufferMs: targetLatencyMs * 3,
      targetBufferMs: targetLatencyMs,
      rebufferMs: targetLatencyMs,
      enableAdaptiveBuffering: true,
      prioritizeFastStartup: true,
    );
  }

  /// Validates the configuration
  bool isValid() {
    return minBufferMs > 0 &&
        maxBufferMs > minBufferMs &&
        targetBufferMs >= minBufferMs &&
        targetBufferMs <= maxBufferMs &&
        rebufferMs >= minBufferMs &&
        rebufferMs <= targetBufferMs;
  }

  /// Creates a copy with modified values
  BufferingConfig copyWith({
    int? minBufferMs,
    int? maxBufferMs,
    int? targetBufferMs,
    int? rebufferMs,
    bool? enableAdaptiveBuffering,
    bool? prioritizeFastStartup,
  }) {
    return BufferingConfig(
      minBufferMs: minBufferMs ?? this.minBufferMs,
      maxBufferMs: maxBufferMs ?? this.maxBufferMs,
      targetBufferMs: targetBufferMs ?? this.targetBufferMs,
      rebufferMs: rebufferMs ?? this.rebufferMs,
      enableAdaptiveBuffering:
          enableAdaptiveBuffering ?? this.enableAdaptiveBuffering,
      prioritizeFastStartup: prioritizeFastStartup ?? this.prioritizeFastStartup,
    );
  }

  /// Converts to a map for platform channel communication
  Map<String, dynamic> toMap() {
    return {
      'minBufferMs': minBufferMs,
      'maxBufferMs': maxBufferMs,
      'targetBufferMs': targetBufferMs,
      'rebufferMs': rebufferMs,
      'enableAdaptiveBuffering': enableAdaptiveBuffering,
      'prioritizeFastStartup': prioritizeFastStartup,
    };
  }

  /// Creates from a map received from platform channel
  factory BufferingConfig.fromMap(Map<String, dynamic> map) {
    return BufferingConfig(
      minBufferMs: map['minBufferMs'] as int? ?? 2500,
      maxBufferMs: map['maxBufferMs'] as int? ?? 50000,
      targetBufferMs: map['targetBufferMs'] as int? ?? 15000,
      rebufferMs: map['rebufferMs'] as int? ?? 5000,
      enableAdaptiveBuffering:
          map['enableAdaptiveBuffering'] as bool? ?? true,
      prioritizeFastStartup: map['prioritizeFastStartup'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is BufferingConfig &&
        other.minBufferMs == minBufferMs &&
        other.maxBufferMs == maxBufferMs &&
        other.targetBufferMs == targetBufferMs &&
        other.rebufferMs == rebufferMs &&
        other.enableAdaptiveBuffering == enableAdaptiveBuffering &&
        other.prioritizeFastStartup == prioritizeFastStartup;
  }

  @override
  int get hashCode {
    return Object.hash(
      minBufferMs,
      maxBufferMs,
      targetBufferMs,
      rebufferMs,
      enableAdaptiveBuffering,
      prioritizeFastStartup,
    );
  }

  @override
  String toString() {
    return 'BufferingConfig('
        'min: ${minBufferMs}ms, '
        'max: ${maxBufferMs}ms, '
        'target: ${targetBufferMs}ms, '
        'rebuffer: ${rebufferMs}ms, '
        'adaptive: $enableAdaptiveBuffering, '
        'fastStartup: $prioritizeFastStartup)';
  }
}

/// Network quality levels for adaptive buffering
enum NetworkQuality {
  /// Excellent network (> 5 Mbps) - can use high quality with large buffers
  excellent,

  /// Good network (1-5 Mbps) - can use medium-high quality
  good,

  /// Fair network (500 Kbps - 1 Mbps) - should use medium quality
  fair,

  /// Poor network (< 500 Kbps) - should use low quality with larger buffers
  poor,

  /// Offline/no network - cannot stream
  offline,

  /// Unknown - network quality not yet determined
  unknown,
}

extension NetworkQualityExtension on NetworkQuality {
  /// Gets recommended buffer configuration for this network quality
  BufferingConfig get recommendedBufferConfig {
    switch (this) {
      case NetworkQuality.excellent:
        return BufferingConfig.fastStartup();
      case NetworkQuality.good:
        return const BufferingConfig(); // Default
      case NetworkQuality.fair:
        return BufferingConfig.smoothPlayback();
      case NetworkQuality.poor:
        return BufferingConfig.poorNetwork();
      case NetworkQuality.offline:
      case NetworkQuality.unknown:
        return const BufferingConfig(); // Default
    }
  }

  /// Minimum bandwidth for this quality level (in bytes/sec)
  int get minBandwidth {
    switch (this) {
      case NetworkQuality.excellent:
        return 5 * 1024 * 1024; // 5 MB/s
      case NetworkQuality.good:
        return 1024 * 1024; // 1 MB/s
      case NetworkQuality.fair:
        return 500 * 1024; // 500 KB/s
      case NetworkQuality.poor:
        return 100 * 1024; // 100 KB/s
      case NetworkQuality.offline:
        return 0;
      case NetworkQuality.unknown:
        return 0;
    }
  }

  /// Determines network quality from bandwidth measurement
  static NetworkQuality fromBandwidth(int bytesPerSecond) {
    if (bytesPerSecond >= 5 * 1024 * 1024) {
      return NetworkQuality.excellent;
    } else if (bytesPerSecond >= 1024 * 1024) {
      return NetworkQuality.good;
    } else if (bytesPerSecond >= 500 * 1024) {
      return NetworkQuality.fair;
    } else if (bytesPerSecond > 0) {
      return NetworkQuality.poor;
    } else {
      return NetworkQuality.offline;
    }
  }
}
