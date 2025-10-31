/// Analytics service for tracking playback metrics
///
/// Abstract interface for collecting and reporting playback analytics.
/// Apps can implement this to integrate with their analytics platform
/// (Firebase, Mixpanel, etc.) or use the provided implementations.
library;

import 'package:flutter/foundation.dart';
import '../models/analytics_metrics.dart';
import '../models/streaming_config.dart';
import '../core/exceptions.dart';
import '../core/media_config.dart';

/// Abstract analytics service interface
///
/// Implement this interface to integrate with your analytics platform.
/// The service will be called automatically by MediaPlayer for tracking.
abstract class AnalyticsService {
  /// Tracks when playback starts
  void trackPlaybackStart(
    String mediaUrl,
    MediaConfig config, {
    Map<String, dynamic>? metadata,
  });

  /// Tracks when playback ends
  void trackPlaybackEnd(
    Duration watchTime,
    PlaybackEndReason reason, {
    Map<String, dynamic>? metadata,
  });

  /// Tracks a buffer event
  void trackBufferEvent(
    BufferEventType type,
    Duration duration, {
    Map<String, dynamic>? metadata,
  });

  /// Tracks a quality change
  void trackQualityChange(
    QualityTrack? from,
    QualityTrack to, {
    bool automatic = false,
  });

  /// Tracks an error
  void trackError(
    MediaPlayerException error,
    Map<String, dynamic> context,
  );

  /// Tracks startup time (time from load to first frame)
  void trackStartupTime(Duration startupTime);

  /// Tracks seek operation
  void trackSeekTime(
    Duration seekTime,
    Duration from,
    Duration to,
  );

  /// Tracks complete QoE session
  void trackQoESession(QoEMetrics metrics);

  /// Tracks engagement metrics
  void trackEngagement(EngagementMetrics metrics);

  /// Tracks performance metric
  void trackPerformance(PerformanceMetrics metrics);

  /// Tracks custom event
  void trackCustomEvent(
    String eventName,
    Map<String, dynamic>? properties,
  );

  /// Flushes any pending events (optional)
  Future<void> flush() async {}

  /// Disposes the service (optional)
  void dispose() {}
}

/// Console-based analytics service for development
///
/// Logs all analytics events to the console. Useful for debugging
/// and development.
class ConsoleAnalyticsService implements AnalyticsService {
  final bool verbose;

  ConsoleAnalyticsService({this.verbose = true});

  @override
  void trackPlaybackStart(
    String mediaUrl,
    MediaConfig config, {
    Map<String, dynamic>? metadata,
  }) {
    _log('📺 Playback Started', {
      'url': _truncateUrl(mediaUrl),
      'autoPlay': config.autoPlay,
      'metadata': metadata,
    });
  }

  @override
  void trackPlaybackEnd(
    Duration watchTime,
    PlaybackEndReason reason, {
    Map<String, dynamic>? metadata,
  }) {
    _log('🛑 Playback Ended', {
      'watchTime': '${watchTime.inSeconds}s',
      'reason': reason.displayName,
      'metadata': metadata,
    });
  }

  @override
  void trackBufferEvent(
    BufferEventType type,
    Duration duration, {
    Map<String, dynamic>? metadata,
  }) {
    final icon = type == BufferEventType.underrun ? '⚠️' : '⏸️';
    _log('$icon Buffer Event', {
      'type': type.displayName,
      'duration': '${duration.inMilliseconds}ms',
      'metadata': metadata,
    });
  }

  @override
  void trackQualityChange(
    QualityTrack? from,
    QualityTrack to, {
    bool automatic = false,
  }) {
    _log('🎬 Quality Change', {
      'from': from?.name ?? 'none',
      'to': to.name,
      'automatic': automatic,
    });
  }

  @override
  void trackError(
    MediaPlayerException error,
    Map<String, dynamic> context,
  ) {
    _log('❌ Error', {
      'type': error.runtimeType.toString(),
      'message': error.message,
      'context': context,
    });
  }

  @override
  void trackStartupTime(Duration startupTime) {
    final status = startupTime.inMilliseconds < 500 ? '✅' : '⚠️';
    _log('$status Startup Time', {
      'duration': '${startupTime.inMilliseconds}ms',
    });
  }

  @override
  void trackSeekTime(
    Duration seekTime,
    Duration from,
    Duration to,
  ) {
    _log('⏩ Seek', {
      'duration': '${seekTime.inMilliseconds}ms',
      'from': '${from.inSeconds}s',
      'to': '${to.inSeconds}s',
    });
  }

  @override
  void trackQoESession(QoEMetrics metrics) {
    _log('📊 QoE Session', {
      'score': metrics.qualityScore,
      'playTime': '${metrics.totalPlayTime.inSeconds}s',
      'bufferCount': metrics.bufferCount,
      'rebufferRatio': '${(metrics.rebufferRatio * 100).toStringAsFixed(1)}%',
      'startupTime': '${metrics.startupTime.toStringAsFixed(2)}s',
      'qualitySwitches': metrics.qualitySwitches,
      'errorCount': metrics.errorCount,
    });
  }

  @override
  void trackEngagement(EngagementMetrics metrics) {
    _log('👤 Engagement', {
      'score': metrics.engagementScore,
      'watched': '${(metrics.percentageWatched * 100).toStringAsFixed(1)}%',
      'completed': metrics.completed,
      'pauses': metrics.pauseCount,
      'seeks': metrics.seekCount,
    });
  }

  @override
  void trackPerformance(PerformanceMetrics metrics) {
    _log('⚡ Performance', {
      'operation': metrics.operation,
      'duration': '${metrics.duration.toStringAsFixed(2)}ms',
      'context': metrics.context,
    });
  }

  @override
  void trackCustomEvent(String eventName, Map<String, dynamic>? properties) {
    _log('🔔 Custom Event: $eventName', properties ?? {});
  }

  @override
  Future<void> flush() async {
    // Console service has nothing to flush
  }

  @override
  void dispose() {
    // Console service has nothing to dispose
  }

  void _log(String event, Map<String, dynamic> data) {
    if (!verbose && kReleaseMode) return;

    final timestamp = DateTime.now().toIso8601String();
    debugPrint('[$timestamp] Analytics: $event');

    if (data.isNotEmpty) {
      data.forEach((key, value) {
        debugPrint('  $key: $value');
      });
    }
  }

  String _truncateUrl(String url) {
    if (url.length <= 50) return url;
    return '${url.substring(0, 47)}...';
  }
}

/// No-op analytics service
///
/// Does nothing with analytics events. Use this when you don't want
/// any analytics tracking.
class NoOpAnalyticsService implements AnalyticsService {
  const NoOpAnalyticsService();

  @override
  void trackPlaybackStart(
    String mediaUrl,
    MediaConfig config, {
    Map<String, dynamic>? metadata,
  }) {}

  @override
  void trackPlaybackEnd(
    Duration watchTime,
    PlaybackEndReason reason, {
    Map<String, dynamic>? metadata,
  }) {}

  @override
  void trackBufferEvent(
    BufferEventType type,
    Duration duration, {
    Map<String, dynamic>? metadata,
  }) {}

  @override
  void trackQualityChange(
    QualityTrack? from,
    QualityTrack to, {
    bool automatic = false,
  }) {}

  @override
  void trackError(
    MediaPlayerException error,
    Map<String, dynamic> context,
  ) {}

  @override
  void trackStartupTime(Duration startupTime) {}

  @override
  void trackSeekTime(
    Duration seekTime,
    Duration from,
    Duration to,
  ) {}

  @override
  void trackQoESession(QoEMetrics metrics) {}

  @override
  void trackEngagement(EngagementMetrics metrics) {}

  @override
  void trackPerformance(PerformanceMetrics metrics) {}

  @override
  void trackCustomEvent(String eventName, Map<String, dynamic>? properties) {}

  @override
  Future<void> flush() async {}

  @override
  void dispose() {}
}

/// Batching analytics service wrapper
///
/// Wraps another analytics service and batches events before sending.
/// Useful for reducing network requests and improving performance.
class BatchingAnalyticsService implements AnalyticsService {
  final AnalyticsService _delegate;
  final int _batchSize;
  final Duration _flushInterval;
  final List<Map<String, dynamic>> _eventQueue = [];
  DateTime? _lastFlush;

  BatchingAnalyticsService(
    this._delegate, {
    int batchSize = 10,
    Duration flushInterval = const Duration(seconds: 30),
  })  : _batchSize = batchSize,
        _flushInterval = flushInterval;

  @override
  void trackPlaybackStart(
    String mediaUrl,
    MediaConfig config, {
    Map<String, dynamic>? metadata,
  }) {
    _queueEvent('playback_start', {
      'mediaUrl': mediaUrl,
      'autoPlay': config.autoPlay,
      'metadata': metadata,
    });
    _delegate.trackPlaybackStart(mediaUrl, config, metadata: metadata);
  }

  @override
  void trackPlaybackEnd(
    Duration watchTime,
    PlaybackEndReason reason, {
    Map<String, dynamic>? metadata,
  }) {
    _queueEvent('playback_end', {
      'watchTime': watchTime.inMilliseconds,
      'reason': reason.name,
      'metadata': metadata,
    });
    _delegate.trackPlaybackEnd(watchTime, reason, metadata: metadata);
  }

  @override
  void trackBufferEvent(
    BufferEventType type,
    Duration duration, {
    Map<String, dynamic>? metadata,
  }) {
    _queueEvent('buffer_event', {
      'type': type.name,
      'duration': duration.inMilliseconds,
      'metadata': metadata,
    });
    _delegate.trackBufferEvent(type, duration, metadata: metadata);
  }

  @override
  void trackQualityChange(
    QualityTrack? from,
    QualityTrack to, {
    bool automatic = false,
  }) {
    _queueEvent('quality_change', {
      'from': from?.name,
      'to': to.name,
      'automatic': automatic,
    });
    _delegate.trackQualityChange(from, to, automatic: automatic);
  }

  @override
  void trackError(
    MediaPlayerException error,
    Map<String, dynamic> context,
  ) {
    _queueEvent('error', {
      'type': error.runtimeType.toString(),
      'message': error.message,
      'context': context,
    });
    _delegate.trackError(error, context);
    _checkFlush(force: true); // Flush immediately on errors
  }

  @override
  void trackStartupTime(Duration startupTime) {
    _queueEvent('startup', {'duration': startupTime.inMilliseconds});
    _delegate.trackStartupTime(startupTime);
  }

  @override
  void trackSeekTime(
    Duration seekTime,
    Duration from,
    Duration to,
  ) {
    _queueEvent('seek', {
      'duration': seekTime.inMilliseconds,
      'from': from.inMilliseconds,
      'to': to.inMilliseconds,
    });
    _delegate.trackSeekTime(seekTime, from, to);
  }

  @override
  void trackQoESession(QoEMetrics metrics) {
    _queueEvent('qoe_session', metrics.toMap());
    _delegate.trackQoESession(metrics);
    _checkFlush(force: true); // Flush session metrics immediately
  }

  @override
  void trackEngagement(EngagementMetrics metrics) {
    _queueEvent('engagement', metrics.toMap());
    _delegate.trackEngagement(metrics);
  }

  @override
  void trackPerformance(PerformanceMetrics metrics) {
    _queueEvent('performance', metrics.toMap());
    _delegate.trackPerformance(metrics);
  }

  @override
  void trackCustomEvent(String eventName, Map<String, dynamic>? properties) {
    _queueEvent(eventName, properties ?? {});
    _delegate.trackCustomEvent(eventName, properties);
  }

  void _queueEvent(String type, Map<String, dynamic> data) {
    _eventQueue.add({
      'type': type,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'data': data,
    });

    _checkFlush();
  }

  void _checkFlush({bool force = false}) {
    final now = DateTime.now();
    final shouldFlushSize = _eventQueue.length >= _batchSize;
    final shouldFlushTime =
        _lastFlush == null || now.difference(_lastFlush!) >= _flushInterval;

    if (force || shouldFlushSize || shouldFlushTime) {
      flush();
    }
  }

  @override
  Future<void> flush() async {
    if (_eventQueue.isEmpty) return;

    debugPrint(
      'BatchingAnalyticsService: Flushing ${_eventQueue.length} events',
    );

    _eventQueue.clear();
    _lastFlush = DateTime.now();

    await _delegate.flush();
  }

  @override
  void dispose() {
    flush();
    _delegate.dispose();
  }
}
