/// Buffering service for adaptive buffer management
///
/// Coordinates buffer monitoring and adaptive configuration across
/// platforms. Provides real-time buffer health monitoring and
/// recommendations for quality adjustments.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/buffering_config.dart';
import '../models/buffer_health.dart';
import '../models/network_status.dart';

/// Service for managing adaptive buffering behavior
class BufferingService {
  /// Current buffering configuration
  BufferingConfig _config;

  /// Current network quality
  NetworkQuality _networkQuality = NetworkQuality.unknown;

  /// Buffer health stream controller
  final _bufferHealthController = StreamController<BufferHealth>.broadcast();

  /// Buffer statistics tracking
  final _bufferStatisticsTracker = _BufferStatisticsTracker();

  /// Timer for periodic buffer health checks
  Timer? _monitoringTimer;

  /// Callback to fetch current buffer status from platform
  final Future<Map<String, dynamic>> Function()? _platformBufferStatusCallback;

  /// Whether monitoring is active
  bool _isMonitoring = false;

  /// Last known buffer health
  BufferHealth? _lastBufferHealth;

  BufferingService({
    BufferingConfig? config,
    Future<Map<String, dynamic>> Function()? platformBufferStatusCallback,
  })  : _config = config ?? const BufferingConfig(),
        _platformBufferStatusCallback = platformBufferStatusCallback;

  /// Stream of buffer health updates
  Stream<BufferHealth> get bufferHealthStream =>
      _bufferHealthController.stream;

  /// Current buffering configuration
  BufferingConfig get config => _config;

  /// Current network quality
  NetworkQuality get networkQuality => _networkQuality;

  /// Last known buffer health
  BufferHealth? get lastBufferHealth => _lastBufferHealth;

  /// Current buffer statistics
  BufferStatistics get statistics => _bufferStatisticsTracker.getStatistics();

  /// Updates the buffering configuration
  void updateConfig(BufferingConfig newConfig) {
    if (!newConfig.isValid()) {
      debugPrint('BufferingService: Invalid config provided, ignoring');
      return;
    }

    _config = newConfig;
    debugPrint('BufferingService: Config updated - $newConfig');
  }

  /// Updates the network quality and adapts buffering if enabled
  void updateNetworkQuality(NetworkQuality quality) {
    if (_networkQuality == quality) return;

    final previousQuality = _networkQuality;
    _networkQuality = quality;

    debugPrint(
      'BufferingService: Network quality changed: '
      '${previousQuality.name} -> ${quality.name}',
    );

    // Adapt buffering configuration if enabled
    if (_config.enableAdaptiveBuffering) {
      _adaptToNetworkQuality(quality);
    }
  }

  /// Updates network quality from bandwidth measurement
  void updateFromBandwidth(int bytesPerSecond) {
    final quality = NetworkQuality.fromBandwidth(bytesPerSecond);
    updateNetworkQuality(quality);
  }

  /// Starts monitoring buffer health
  void startMonitoring({Duration interval = const Duration(milliseconds: 500)}) {
    if (_isMonitoring) {
      debugPrint('BufferingService: Monitoring already active');
      return;
    }

    _isMonitoring = true;
    _monitoringTimer = Timer.periodic(interval, (_) => _checkBufferHealth());

    debugPrint('BufferingService: Monitoring started (interval: $interval)');
  }

  /// Stops monitoring buffer health
  void stopMonitoring() {
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    _isMonitoring = false;

    debugPrint('BufferingService: Monitoring stopped');
  }

  /// Manually checks and reports buffer health
  Future<BufferHealth?> checkBufferHealth() async {
    if (_platformBufferStatusCallback == null) {
      debugPrint('BufferingService: No platform callback configured');
      return null;
    }

    try {
      final platformData = await _platformBufferStatusCallback!();
      final health = BufferHealth.fromPlatform(platformData, _config);

      _updateBufferHealth(health);
      return health;
    } catch (e) {
      debugPrint('BufferingService: Error checking buffer health - $e');
      return null;
    }
  }

  /// Determines if rebuffering is needed based on current buffer and download speed
  bool shouldRebuffer({
    required Duration currentBuffer,
    required double downloadSpeed, // bytes/sec
  }) {
    // If buffer is below minimum threshold, rebuffer
    if (currentBuffer.inMilliseconds < _config.minBufferMs) {
      return true;
    }

    // If buffer is critically low and download is slow
    if (currentBuffer.inMilliseconds < _config.rebufferMs &&
        downloadSpeed < 100 * 1024) {
      // < 100 KB/s
      return true;
    }

    return false;
  }

  /// Gets adaptive buffer configuration based on current network quality
  BufferingConfig getAdaptiveConfig([NetworkQuality? quality]) {
    final targetQuality = quality ?? _networkQuality;
    return targetQuality.recommendedBufferConfig;
  }

  /// Resets buffer statistics
  void resetStatistics() {
    _bufferStatisticsTracker.reset();
    debugPrint('BufferingService: Statistics reset');
  }

  /// Disposes the service and releases resources
  void dispose() {
    stopMonitoring();
    _bufferHealthController.close();
    _bufferStatisticsTracker.reset();

    debugPrint('BufferingService: Disposed');
  }

  // Private methods

  Future<void> _checkBufferHealth() async {
    await checkBufferHealth();
  }

  void _updateBufferHealth(BufferHealth health) {
    _lastBufferHealth = health;

    // Track statistics
    _bufferStatisticsTracker.recordHealth(health);

    // Emit event
    if (!_bufferHealthController.isClosed) {
      _bufferHealthController.add(health);
    }

    // Log warnings
    if (!health.isHealthy && health.warning != null) {
      debugPrint('BufferingService: ${health.warning}');
    }
  }

  void _adaptToNetworkQuality(NetworkQuality quality) {
    final recommendedConfig = quality.recommendedBufferConfig;

    // Only adapt certain parameters, keep user preferences
    final adaptedConfig = _config.copyWith(
      targetBufferMs: recommendedConfig.targetBufferMs,
      maxBufferMs: recommendedConfig.maxBufferMs,
      rebufferMs: recommendedConfig.rebufferMs,
    );

    updateConfig(adaptedConfig);
  }
}

/// Internal tracker for buffer statistics
class _BufferStatisticsTracker {
  final List<BufferHealth> _healthHistory = [];
  int _totalBufferEvents = 0;
  int _underrunCount = 0;
  Duration _totalBufferTime = Duration.zero;
  DateTime? _lastUnderrunStart;

  void recordHealth(BufferHealth health) {
    // Keep last 100 health checks
    _healthHistory.add(health);
    if (_healthHistory.length > 100) {
      _healthHistory.removeAt(0);
    }

    // Track underrun events
    if (health.status == BufferStatus.underrun) {
      _lastUnderrunStart ??= health.timestamp;
      _underrunCount++;
    } else if (_lastUnderrunStart != null) {
      // Underrun ended
      final underrunDuration = health.timestamp.difference(_lastUnderrunStart!);
      _totalBufferTime += underrunDuration;
      _lastUnderrunStart = null;
      _totalBufferEvents++;
    }

    // Track critical/warning events as buffer events
    if (health.status == BufferStatus.critical ||
        health.status == BufferStatus.warning) {
      _totalBufferEvents++;
    }
  }

  BufferStatistics getStatistics() {
    if (_healthHistory.isEmpty) {
      return BufferStatistics.empty();
    }

    // Calculate average, min, max buffer durations
    final bufferDurations = _healthHistory
        .map((h) => Duration(milliseconds: h.bufferedDurationMs))
        .toList();

    final totalMs = bufferDurations.fold<int>(
      0,
      (sum, d) => sum + d.inMilliseconds,
    );

    final avgDuration = Duration(
      milliseconds: totalMs ~/ bufferDurations.length,
    );

    final minDuration = bufferDurations.reduce(
      (a, b) => a.inMilliseconds < b.inMilliseconds ? a : b,
    );

    final maxDuration = bufferDurations.reduce(
      (a, b) => a.inMilliseconds > b.inMilliseconds ? a : b,
    );

    // Calculate rebuffer ratio (simplified - would need total play time)
    final rebufferRatio = _totalBufferEvents > 0
        ? _totalBufferTime.inMilliseconds /
            (_healthHistory.length * 500.0) // Assuming 500ms sampling
        : 0.0;

    return BufferStatistics(
      totalBufferEvents: _totalBufferEvents,
      totalBufferTime: _totalBufferTime,
      averageBufferDuration: avgDuration,
      minBufferDuration: minDuration,
      maxBufferDuration: maxDuration,
      underrunCount: _underrunCount,
      rebufferRatio: rebufferRatio.clamp(0.0, 1.0),
    );
  }

  void reset() {
    _healthHistory.clear();
    _totalBufferEvents = 0;
    _underrunCount = 0;
    _totalBufferTime = Duration.zero;
    _lastUnderrunStart = null;
  }
}

/// Factory for creating BufferingService instances
class BufferingServiceFactory {
  /// Creates a BufferingService with default configuration
  static BufferingService createDefault() {
    return BufferingService(
      config: const BufferingConfig(),
    );
  }

  /// Creates a BufferingService optimized for fast startup
  static BufferingService createFastStartup() {
    return BufferingService(
      config: BufferingConfig.fastStartup(),
    );
  }

  /// Creates a BufferingService optimized for smooth playback
  static BufferingService createSmoothPlayback() {
    return BufferingService(
      config: BufferingConfig.smoothPlayback(),
    );
  }

  /// Creates a BufferingService for live streaming
  static BufferingService createLiveStreaming({int targetLatencyMs = 3000}) {
    return BufferingService(
      config: BufferingConfig.liveStreaming(targetLatencyMs: targetLatencyMs),
    );
  }

  /// Creates a BufferingService with custom configuration
  static BufferingService createCustom(BufferingConfig config) {
    return BufferingService(config: config);
  }
}
