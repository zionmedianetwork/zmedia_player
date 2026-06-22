/// Analytics and QoE (Quality of Experience) metrics
///
/// Provides comprehensive playback metrics for monitoring and analysis.
/// Used for tracking playback quality, errors, and user engagement.
library;

/// Quality of Experience metrics for a playback session
class QoEMetrics {
  /// Total playback time (excluding buffering)
  final Duration totalPlayTime;

  /// Number of buffer events
  final int bufferCount;

  /// Total time spent buffering
  final Duration totalBufferTime;

  /// Average bitrate during playback (bps)
  final double averageBitrate;

  /// Number of quality switches
  final int qualitySwitches;

  /// Time from load to first frame (seconds)
  final double startupTime;

  /// Rebuffer ratio (bufferTime / playTime)
  final double rebufferRatio;

  /// Number of seeks performed
  final int seekCount;

  /// Average seek latency (seconds)
  final double averageSeekLatency;

  /// Session completion rate (0.0 - 1.0)
  final double completionRate;

  /// Number of errors encountered
  final int errorCount;

  /// Session start timestamp
  final DateTime sessionStart;

  /// Session end timestamp
  final DateTime? sessionEnd;

  /// Media URL
  final String mediaUrl;

  /// Total session duration (including pauses)
  final Duration sessionDuration;

  const QoEMetrics({
    required this.totalPlayTime,
    required this.bufferCount,
    required this.totalBufferTime,
    required this.averageBitrate,
    required this.qualitySwitches,
    required this.startupTime,
    required this.rebufferRatio,
    this.seekCount = 0,
    this.averageSeekLatency = 0.0,
    this.completionRate = 0.0,
    this.errorCount = 0,
    required this.sessionStart,
    this.sessionEnd,
    required this.mediaUrl,
    required this.sessionDuration,
  });

  /// Creates empty metrics
  factory QoEMetrics.empty(String mediaUrl) {
    return QoEMetrics(
      totalPlayTime: Duration.zero,
      bufferCount: 0,
      totalBufferTime: Duration.zero,
      averageBitrate: 0.0,
      qualitySwitches: 0,
      startupTime: 0.0,
      rebufferRatio: 0.0,
      sessionStart: DateTime.now(),
      mediaUrl: mediaUrl,
      sessionDuration: Duration.zero,
    );
  }

  /// Converts to map for serialization
  Map<String, dynamic> toMap() {
    return {
      'totalPlayTime': totalPlayTime.inMilliseconds,
      'bufferCount': bufferCount,
      'totalBufferTime': totalBufferTime.inMilliseconds,
      'averageBitrate': averageBitrate,
      'qualitySwitches': qualitySwitches,
      'startupTime': startupTime,
      'rebufferRatio': rebufferRatio,
      'seekCount': seekCount,
      'averageSeekLatency': averageSeekLatency,
      'completionRate': completionRate,
      'errorCount': errorCount,
      'sessionStart': sessionStart.millisecondsSinceEpoch,
      'sessionEnd': sessionEnd?.millisecondsSinceEpoch,
      'mediaUrl': mediaUrl,
      'sessionDuration': sessionDuration.inMilliseconds,
    };
  }

  /// Creates from map
  factory QoEMetrics.fromMap(Map<String, dynamic> map) {
    return QoEMetrics(
      totalPlayTime: Duration(milliseconds: map['totalPlayTime'] as int),
      bufferCount: map['bufferCount'] as int,
      totalBufferTime: Duration(milliseconds: map['totalBufferTime'] as int),
      averageBitrate: (map['averageBitrate'] as num).toDouble(),
      qualitySwitches: map['qualitySwitches'] as int,
      startupTime: (map['startupTime'] as num).toDouble(),
      rebufferRatio: (map['rebufferRatio'] as num).toDouble(),
      seekCount: map['seekCount'] as int? ?? 0,
      averageSeekLatency:
          (map['averageSeekLatency'] as num?)?.toDouble() ?? 0.0,
      completionRate: (map['completionRate'] as num?)?.toDouble() ?? 0.0,
      errorCount: map['errorCount'] as int? ?? 0,
      sessionStart:
          DateTime.fromMillisecondsSinceEpoch(map['sessionStart'] as int),
      sessionEnd: map['sessionEnd'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['sessionEnd'] as int)
          : null,
      mediaUrl: map['mediaUrl'] as String,
      sessionDuration: Duration(milliseconds: map['sessionDuration'] as int),
    );
  }

  /// Calculates quality score (0-100)
  int get qualityScore {
    var score = 100.0;

    // Penalize buffering
    if (rebufferRatio > 0) {
      score -= (rebufferRatio * 50).clamp(0, 50);
    }

    // Penalize startup time
    if (startupTime > 2.0) {
      score -= ((startupTime - 2.0) * 10).clamp(0, 20);
    }

    // Penalize excessive quality switches
    if (qualitySwitches > 5) {
      score -= ((qualitySwitches - 5) * 2).clamp(0, 10);
    }

    // Penalize errors
    score -= (errorCount * 5).clamp(0, 20);

    return score.clamp(0, 100).round();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is QoEMetrics &&
        other.totalPlayTime == totalPlayTime &&
        other.bufferCount == bufferCount &&
        other.totalBufferTime == totalBufferTime &&
        other.averageBitrate == averageBitrate &&
        other.qualitySwitches == qualitySwitches &&
        other.startupTime == startupTime &&
        other.rebufferRatio == rebufferRatio &&
        other.seekCount == seekCount &&
        other.averageSeekLatency == averageSeekLatency &&
        other.completionRate == completionRate &&
        other.errorCount == errorCount &&
        other.sessionStart == sessionStart &&
        other.sessionEnd == sessionEnd &&
        other.mediaUrl == mediaUrl &&
        other.sessionDuration == sessionDuration;
  }

  @override
  int get hashCode => Object.hash(
        totalPlayTime,
        bufferCount,
        totalBufferTime,
        averageBitrate,
        qualitySwitches,
        startupTime,
        rebufferRatio,
        seekCount,
        averageSeekLatency,
        completionRate,
        errorCount,
        sessionStart,
        sessionEnd,
        mediaUrl,
        sessionDuration,
      );

  @override
  String toString() {
    return 'QoEMetrics(score: $qualityScore, playTime: ${totalPlayTime.inSeconds}s, '
        'buffers: $bufferCount, startup: ${startupTime.toStringAsFixed(2)}s)';
  }
}

/// Reason for playback ending
enum PlaybackEndReason {
  /// Playback completed successfully
  completed,

  /// User stopped playback
  stopped,

  /// Error occurred
  error,

  /// App backgrounded
  backgrounded,

  /// Disposed/cleaned up
  disposed,

  /// Skipped to next item
  skipped,

  /// Unknown reason
  unknown;

  String get displayName {
    switch (this) {
      case PlaybackEndReason.completed:
        return 'Completed';
      case PlaybackEndReason.stopped:
        return 'Stopped';
      case PlaybackEndReason.error:
        return 'Error';
      case PlaybackEndReason.backgrounded:
        return 'Backgrounded';
      case PlaybackEndReason.disposed:
        return 'Disposed';
      case PlaybackEndReason.skipped:
        return 'Skipped';
      case PlaybackEndReason.unknown:
        return 'Unknown';
    }
  }
}

/// Type of buffer event
enum BufferEventType {
  /// Started buffering
  started,

  /// Finished buffering
  completed,

  /// Buffer underrun occurred
  underrun,

  /// Proactive rebuffering
  rebuffer;

  String get displayName {
    switch (this) {
      case BufferEventType.started:
        return 'Started';
      case BufferEventType.completed:
        return 'Completed';
      case BufferEventType.underrun:
        return 'Underrun';
      case BufferEventType.rebuffer:
        return 'Rebuffer';
    }
  }
}

/// Performance metrics for a specific operation
class PerformanceMetrics {
  /// Operation name
  final String operation;

  /// Time taken (milliseconds)
  final double duration;

  /// Timestamp
  final DateTime timestamp;

  /// Additional context
  final Map<String, dynamic>? context;

  const PerformanceMetrics({
    required this.operation,
    required this.duration,
    required this.timestamp,
    this.context,
  });

  /// Converts to map
  Map<String, dynamic> toMap() {
    return {
      'operation': operation,
      'duration': duration,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'context': context,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PerformanceMetrics &&
        other.operation == operation &&
        other.duration == duration &&
        other.timestamp == timestamp;
  }

  @override
  int get hashCode => Object.hash(operation, duration, timestamp);

  @override
  String toString() {
    return 'PerformanceMetrics($operation: ${duration.toStringAsFixed(2)}ms)';
  }
}

/// Engagement metrics
class EngagementMetrics {
  /// Watch time (actual viewing time)
  final Duration watchTime;

  /// Total session time (including pauses)
  final Duration sessionTime;

  /// Number of pauses
  final int pauseCount;

  /// Number of seeks
  final int seekCount;

  /// Percentage watched (0.0 - 1.0)
  final double percentageWatched;

  /// Whether video was completed
  final bool completed;

  const EngagementMetrics({
    required this.watchTime,
    required this.sessionTime,
    required this.pauseCount,
    required this.seekCount,
    required this.percentageWatched,
    required this.completed,
  });

  /// Engagement score (0-100)
  int get engagementScore {
    var score = 0.0;

    // Base score from percentage watched
    score += percentageWatched * 60;

    // Bonus for completion
    if (completed) {
      score += 20;
    }

    // Penalize excessive pauses
    if (pauseCount > 5) {
      score -= ((pauseCount - 5) * 2).clamp(0, 10);
    }

    // Bonus for minimal seeking (engaged viewing)
    if (seekCount < 3) {
      score += 10;
    }

    // Penalize excessive seeking
    if (seekCount > 10) {
      score -= ((seekCount - 10) * 1).clamp(0, 10);
    }

    return score.clamp(0, 100).round();
  }

  /// Converts to map
  Map<String, dynamic> toMap() {
    return {
      'watchTime': watchTime.inMilliseconds,
      'sessionTime': sessionTime.inMilliseconds,
      'pauseCount': pauseCount,
      'seekCount': seekCount,
      'percentageWatched': percentageWatched,
      'completed': completed,
      'engagementScore': engagementScore,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EngagementMetrics &&
        other.watchTime == watchTime &&
        other.sessionTime == sessionTime &&
        other.pauseCount == pauseCount &&
        other.seekCount == seekCount &&
        other.percentageWatched == percentageWatched &&
        other.completed == completed;
  }

  @override
  int get hashCode => Object.hash(
        watchTime,
        sessionTime,
        pauseCount,
        seekCount,
        percentageWatched,
        completed,
      );

  @override
  String toString() {
    return 'EngagementMetrics(score: $engagementScore, watched: ${(percentageWatched * 100).toStringAsFixed(1)}%)';
  }
}
