/// Buffer health monitoring models
///
/// Provides real-time information about buffer status to enable
/// predictive rebuffering and quality adaptation.
library;

import 'buffering_config.dart';

/// Current health status of the playback buffer
class BufferHealth {
  /// Amount of content currently buffered (in milliseconds)
  final int bufferedDurationMs;

  /// Current playback position (in milliseconds)
  final int currentPositionMs;

  /// Total duration of the media (in milliseconds)
  final int totalDurationMs;

  /// Ratio of buffered content to target buffer (0.0 - 1.0+)
  final double bufferRatio;

  /// Current buffer status
  final BufferStatus status;

  /// Whether the buffer is healthy for continuous playback
  final bool isHealthy;

  /// Warning message if buffer is not healthy
  final String? warning;

  /// Estimated time until buffer underrun (null if healthy)
  final Duration? estimatedTimeToUnderrun;

  /// Whether quality should be reduced to prevent underrun
  final bool shouldReduceQuality;

  /// Current download speed (bytes per second), if available
  final int? currentDownloadSpeed;

  /// Timestamp when this health status was captured
  final DateTime timestamp;

  const BufferHealth({
    required this.bufferedDurationMs,
    required this.currentPositionMs,
    required this.totalDurationMs,
    required this.bufferRatio,
    required this.status,
    required this.isHealthy,
    this.warning,
    this.estimatedTimeToUnderrun,
    this.shouldReduceQuality = false,
    this.currentDownloadSpeed,
    required this.timestamp,
  });

  /// Creates a BufferHealth instance from platform data
  factory BufferHealth.fromPlatform(
    Map<String, dynamic> data,
    BufferingConfig config,
  ) {
    final bufferedMs = data['bufferedDurationMs'] as int? ?? 0;
    final currentMs = data['currentPositionMs'] as int? ?? 0;
    final totalMs = data['totalDurationMs'] as int? ?? 0;
    final downloadSpeed = data['downloadSpeed'] as int?;

    // Calculate buffer ratio relative to target
    final bufferRatio = config.targetBufferMs > 0
        ? bufferedMs / config.targetBufferMs
        : 0.0;

    // Determine status based on buffer ratio
    final status = _determineStatus(bufferRatio, bufferedMs, config);

    // Check if buffer is healthy
    final isHealthy = status == BufferStatus.healthy;

    // Estimate time to underrun
    Duration? timeToUnderrun;
    bool shouldReduce = false;

    if (bufferedMs > 0 && downloadSpeed != null && downloadSpeed > 0) {
      // Simple estimation: buffer duration / playback rate
      // If download speed is slower than playback, calculate time until empty
      final estimatedMs = bufferedMs; // Simplified
      if (estimatedMs < config.minBufferMs * 2) {
        timeToUnderrun = Duration(milliseconds: estimatedMs);
        shouldReduce = estimatedMs < config.minBufferMs * 3;
      }
    }

    return BufferHealth(
      bufferedDurationMs: bufferedMs,
      currentPositionMs: currentMs,
      totalDurationMs: totalMs,
      bufferRatio: bufferRatio,
      status: status,
      isHealthy: isHealthy,
      warning: isHealthy ? null : _getWarningMessage(status),
      estimatedTimeToUnderrun: timeToUnderrun,
      shouldReduceQuality: shouldReduce,
      currentDownloadSpeed: downloadSpeed,
      timestamp: DateTime.now(),
    );
  }

  /// Creates a healthy buffer state
  factory BufferHealth.healthy({
    required int bufferedDurationMs,
    required int currentPositionMs,
    required int totalDurationMs,
    int? downloadSpeed,
  }) {
    return BufferHealth(
      bufferedDurationMs: bufferedDurationMs,
      currentPositionMs: currentPositionMs,
      totalDurationMs: totalDurationMs,
      bufferRatio: 1.0,
      status: BufferStatus.healthy,
      isHealthy: true,
      currentDownloadSpeed: downloadSpeed,
      timestamp: DateTime.now(),
    );
  }

  /// Creates an underrun buffer state
  factory BufferHealth.underrun({
    required int currentPositionMs,
    required int totalDurationMs,
  }) {
    return BufferHealth(
      bufferedDurationMs: 0,
      currentPositionMs: currentPositionMs,
      totalDurationMs: totalDurationMs,
      bufferRatio: 0.0,
      status: BufferStatus.underrun,
      isHealthy: false,
      warning: 'Buffer empty - rebuffering required',
      shouldReduceQuality: true,
      timestamp: DateTime.now(),
    );
  }

  static BufferStatus _determineStatus(
    double ratio,
    int bufferedMs,
    BufferingConfig config,
  ) {
    if (bufferedMs == 0) {
      return BufferStatus.underrun;
    } else if (bufferedMs < config.minBufferMs * 0.5) {
      return BufferStatus.critical;
    } else if (ratio < 0.5) {
      return BufferStatus.warning;
    } else {
      return BufferStatus.healthy;
    }
  }

  static String _getWarningMessage(BufferStatus status) {
    switch (status) {
      case BufferStatus.healthy:
        return '';
      case BufferStatus.warning:
        return 'Buffer running low';
      case BufferStatus.critical:
        return 'Buffer critically low - consider reducing quality';
      case BufferStatus.underrun:
        return 'Buffer empty - rebuffering';
    }
  }

  /// Converts to map for logging/analytics
  Map<String, dynamic> toMap() {
    return {
      'bufferedDurationMs': bufferedDurationMs,
      'currentPositionMs': currentPositionMs,
      'totalDurationMs': totalDurationMs,
      'bufferRatio': bufferRatio,
      'status': status.name,
      'isHealthy': isHealthy,
      'warning': warning,
      'estimatedTimeToUnderrunMs': estimatedTimeToUnderrun?.inMilliseconds,
      'shouldReduceQuality': shouldReduceQuality,
      'currentDownloadSpeed': currentDownloadSpeed,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  @override
  String toString() {
    return 'BufferHealth('
        'buffered: ${bufferedDurationMs}ms, '
        'ratio: ${(bufferRatio * 100).toStringAsFixed(1)}%, '
        'status: ${status.name}, '
        'healthy: $isHealthy'
        ')';
  }
}

/// Buffer status levels
enum BufferStatus {
  /// Buffer is healthy (> 80% of target)
  healthy,

  /// Buffer is running low (50-80% of target)
  warning,

  /// Buffer is critically low (< 50% of target)
  critical,

  /// Buffer is empty (underrun event)
  underrun,
}

extension BufferStatusExtension on BufferStatus {
  /// Whether this status indicates a problem
  bool get isProblematic =>
      this == BufferStatus.warning ||
      this == BufferStatus.critical ||
      this == BufferStatus.underrun;

  /// Severity level (0-3, higher is worse)
  int get severity {
    switch (this) {
      case BufferStatus.healthy:
        return 0;
      case BufferStatus.warning:
        return 1;
      case BufferStatus.critical:
        return 2;
      case BufferStatus.underrun:
        return 3;
    }
  }

  /// Color code for UI display
  String get colorCode {
    switch (this) {
      case BufferStatus.healthy:
        return '#4CAF50'; // Green
      case BufferStatus.warning:
        return '#FFC107'; // Amber
      case BufferStatus.critical:
        return '#FF9800'; // Orange
      case BufferStatus.underrun:
        return '#F44336'; // Red
    }
  }
}

/// Statistics for buffer behavior over a session
class BufferStatistics {
  /// Total number of buffer events
  final int totalBufferEvents;

  /// Total time spent buffering
  final Duration totalBufferTime;

  /// Average buffer duration maintained
  final Duration averageBufferDuration;

  /// Minimum buffer duration observed
  final Duration minBufferDuration;

  /// Maximum buffer duration observed
  final Duration maxBufferDuration;

  /// Number of buffer underrun events
  final int underrunCount;

  /// Rebuffer ratio (totalBufferTime / totalPlayTime)
  final double rebufferRatio;

  const BufferStatistics({
    required this.totalBufferEvents,
    required this.totalBufferTime,
    required this.averageBufferDuration,
    required this.minBufferDuration,
    required this.maxBufferDuration,
    required this.underrunCount,
    required this.rebufferRatio,
  });

  /// Creates empty statistics
  factory BufferStatistics.empty() {
    return const BufferStatistics(
      totalBufferEvents: 0,
      totalBufferTime: Duration.zero,
      averageBufferDuration: Duration.zero,
      minBufferDuration: Duration.zero,
      maxBufferDuration: Duration.zero,
      underrunCount: 0,
      rebufferRatio: 0.0,
    );
  }

  /// Converts to map for analytics
  Map<String, dynamic> toMap() {
    return {
      'totalBufferEvents': totalBufferEvents,
      'totalBufferTimeMs': totalBufferTime.inMilliseconds,
      'averageBufferDurationMs': averageBufferDuration.inMilliseconds,
      'minBufferDurationMs': minBufferDuration.inMilliseconds,
      'maxBufferDurationMs': maxBufferDuration.inMilliseconds,
      'underrunCount': underrunCount,
      'rebufferRatio': rebufferRatio,
    };
  }

  @override
  String toString() {
    return 'BufferStatistics('
        'events: $totalBufferEvents, '
        'totalTime: ${totalBufferTime.inMilliseconds}ms, '
        'underruns: $underrunCount, '
        'rebufferRatio: ${(rebufferRatio * 100).toStringAsFixed(2)}%'
        ')';
  }
}
