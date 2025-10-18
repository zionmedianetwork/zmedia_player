import 'dart:async';
import '../models/streaming_config.dart';

/// Service for managing streaming protocols and quality selection
class StreamingService {
  /// Current streaming configuration
  StreamingConfig _config;

  /// Available quality tracks
  List<QualityTrack> _availableQualityTracks = [];

  /// Current quality track
  QualityTrack? _currentQualityTrack;

  /// Bandwidth estimation in bits per second
  int _estimatedBandwidth = 0;

  /// Bandwidth history for moving average
  final List<int> _bandwidthHistory = [];

  /// Maximum bandwidth history size
  static const int _maxBandwidthHistorySize = 10;

  /// Stream controller for bandwidth updates
  final StreamController<int> _bandwidthController =
      StreamController<int>.broadcast();

  /// Stream controller for quality changes
  final StreamController<QualityTrack?> _qualityController =
      StreamController<QualityTrack?>.broadcast();

  /// Whether the service is disposed
  bool _isDisposed = false;

  /// Timer for bandwidth estimation updates
  Timer? _bandwidthTimer;

  StreamingService(this._config) {
    _startBandwidthMonitoring();
  }

  /// Get current configuration
  StreamingConfig get config => _config;

  /// Get available quality tracks
  List<QualityTrack> get availableQualityTracks =>
      List.unmodifiable(_availableQualityTracks);

  /// Get current quality track
  QualityTrack? get currentQualityTrack => _currentQualityTrack;

  /// Get estimated bandwidth
  int get estimatedBandwidth => _estimatedBandwidth;

  /// Stream of bandwidth updates
  Stream<int> get bandwidthStream => _bandwidthController.stream;

  /// Stream of quality changes
  Stream<QualityTrack?> get qualityStream => _qualityController.stream;

  /// Update streaming configuration
  void updateConfig(StreamingConfig config) {
    if (_isDisposed) return;
    _config = config;
  }

  /// Set available quality tracks
  void setAvailableQualityTracks(List<QualityTrack> tracks) {
    if (_isDisposed) return;

    _availableQualityTracks = List.from(tracks);

    // Sort tracks by bitrate (lowest to highest)
    _availableQualityTracks.sort((a, b) => a.bitrate.compareTo(b.bitrate));

    // Auto-select initial quality if enabled
    if (_config.enableAdaptiveBitrate && _currentQualityTrack == null) {
      _selectInitialQuality();
    }
  }

  /// Select quality track manually
  void selectQualityTrack(QualityTrack track) {
    if (_isDisposed) return;

    if (!_availableQualityTracks.any((t) => t.id == track.id)) {
      throw StreamingException('Quality track not found: ${track.id}');
    }

    _currentQualityTrack = track;
    _notifyQualityChange();
  }

  /// Enable automatic quality selection
  void enableAutoQuality() {
    if (_isDisposed) return;

    _currentQualityTrack = null;
    _notifyQualityChange();

    if (_config.enableAdaptiveBitrate) {
      _selectOptimalQuality();
    }
  }

  /// Update bandwidth estimation
  void updateBandwidth(int bandwidth) {
    if (_isDisposed) return;

    if (!_config.enableBandwidthEstimation) return;

    // Add to history
    _bandwidthHistory.add(bandwidth);

    // Keep history size limited
    if (_bandwidthHistory.length > _maxBandwidthHistorySize) {
      _bandwidthHistory.removeAt(0);
    }

    // Calculate moving average
    _estimatedBandwidth = _calculateMovingAverage();

    // Notify listeners
    if (!_bandwidthController.isClosed) {
      _bandwidthController.add(_estimatedBandwidth);
    }

    // Auto-switch quality if enabled
    if (_config.enableAutoQualitySwitch && _currentQualityTrack == null) {
      _selectOptimalQuality();
    }
  }

  /// Get recommended quality based on current bandwidth
  QualityTrack? getRecommendedQuality() {
    if (_availableQualityTracks.isEmpty || _estimatedBandwidth == 0) {
      return null;
    }

    // Apply quality switch threshold (e.g., 80% of bandwidth)
    final targetBitrate =
        (_estimatedBandwidth * _config.qualitySwitchThreshold).toInt();

    // Find highest quality that fits within bandwidth
    QualityTrack? recommended;
    for (final track in _availableQualityTracks) {
      // Skip if not available
      if (!track.isAvailable) continue;

      // Check bitrate constraints
      if (_config.minBitrate != null && track.bitrate < _config.minBitrate!) {
        continue;
      }
      if (_config.maxBitrate != null && track.bitrate > _config.maxBitrate!) {
        continue;
      }

      // Select track if it fits within bandwidth
      if (track.bitrate <= targetBitrate) {
        recommended = track;
      } else {
        break; // Tracks are sorted, no need to check further
      }
    }

    // If no track found within bandwidth, use lowest quality
    if (recommended == null && _availableQualityTracks.isNotEmpty) {
      recommended = _availableQualityTracks.first;
    }

    return recommended;
  }

  /// Check if should switch quality
  bool shouldSwitchQuality() {
    if (!_config.enableAutoQualitySwitch) return false;
    if (_currentQualityTrack == null) return false;

    final recommended = getRecommendedQuality();
    if (recommended == null) return false;

    // Switch if recommended quality is different and significantly better or worse
    if (recommended.id != _currentQualityTrack!.id) {
      final bitrateDiff =
          (recommended.bitrate - _currentQualityTrack!.bitrate).abs();
      final threshold = _currentQualityTrack!.bitrate * 0.2; // 20% difference

      return bitrateDiff > threshold;
    }

    return false;
  }

  /// Get quality track by ID
  QualityTrack? getQualityTrackById(String id) {
    try {
      return _availableQualityTracks.firstWhere((track) => track.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Get quality tracks by resolution
  List<QualityTrack> getQualityTracksByResolution(int width, int height) {
    return _availableQualityTracks
        .where((track) =>
            track.width == width && track.height == height && track.isAvailable)
        .toList();
  }

  /// Get highest quality track
  QualityTrack? getHighestQuality() {
    final availableTracks =
        _availableQualityTracks.where((t) => t.isAvailable).toList();

    if (availableTracks.isEmpty) return null;

    return availableTracks.reduce((a, b) => a.bitrate > b.bitrate ? a : b);
  }

  /// Get lowest quality track
  QualityTrack? getLowestQuality() {
    final availableTracks =
        _availableQualityTracks.where((t) => t.isAvailable).toList();

    if (availableTracks.isEmpty) return null;

    return availableTracks.reduce((a, b) => a.bitrate < b.bitrate ? a : b);
  }

  /// Select initial quality based on strategy
  void _selectInitialQuality() {
    QualityTrack? selected;

    switch (_config.bitrateStrategy) {
      case BitrateSelectionStrategy.auto:
        selected = getRecommendedQuality();
        break;
      case BitrateSelectionStrategy.lowest:
        selected = getLowestQuality();
        break;
      case BitrateSelectionStrategy.highest:
        selected = getHighestQuality();
        break;
      case BitrateSelectionStrategy.medium:
        final mid = _availableQualityTracks.length ~/ 2;
        if (_availableQualityTracks.isNotEmpty) {
          selected = _availableQualityTracks[mid];
        }
        break;
    }

    if (selected != null) {
      _currentQualityTrack = selected;
      _notifyQualityChange();
    }
  }

  /// Select optimal quality based on current bandwidth
  void _selectOptimalQuality() {
    final recommended = getRecommendedQuality();
    if (recommended != null &&
        (shouldSwitchQuality() || _currentQualityTrack == null)) {
      _currentQualityTrack = recommended;
      _notifyQualityChange();
    }
  }

  /// Calculate moving average of bandwidth
  int _calculateMovingAverage() {
    if (_bandwidthHistory.isEmpty) return 0;

    final sum = _bandwidthHistory.reduce((a, b) => a + b);
    return sum ~/ _bandwidthHistory.length;
  }

  /// Notify quality change to listeners
  void _notifyQualityChange() {
    if (!_qualityController.isClosed) {
      _qualityController.add(_currentQualityTrack);
    }
  }

  /// Start bandwidth monitoring
  void _startBandwidthMonitoring() {
    if (!_config.enableBandwidthEstimation) return;

    _bandwidthTimer?.cancel();
    _bandwidthTimer = Timer.periodic(
      const Duration(seconds: 5),
      (timer) {
        if (_isDisposed) {
          timer.cancel();
          return;
        }

        // Check if quality switching is needed
        if (_config.enableAutoQualitySwitch && shouldSwitchQuality()) {
          _selectOptimalQuality();
        }
      },
    );
  }

  /// Dispose the service
  void dispose() {
    if (_isDisposed) return;

    _isDisposed = true;
    _bandwidthTimer?.cancel();

    _bandwidthController.close();
    _qualityController.close();

    _availableQualityTracks.clear();
    _bandwidthHistory.clear();
  }

  /// Reset bandwidth estimation
  void resetBandwidth() {
    _bandwidthHistory.clear();
    _estimatedBandwidth = 0;
  }

  /// Get formatted bandwidth string
  String getFormattedBandwidth() {
    if (_estimatedBandwidth < 1000) {
      return '${_estimatedBandwidth} bps';
    } else if (_estimatedBandwidth < 1000000) {
      return '${(_estimatedBandwidth / 1000).toStringAsFixed(1)} Kbps';
    } else {
      return '${(_estimatedBandwidth / 1000000).toStringAsFixed(2)} Mbps';
    }
  }

  /// Get quality track display name with details
  String getQualityDisplayName(QualityTrack track) {
    final parts = <String>[track.name];

    if (track.width != null && track.height != null) {
      parts.add('${track.width}x${track.height}');
    }

    parts.add('${(track.bitrate / 1000).toStringAsFixed(0)} Kbps');

    return parts.join(' • ');
  }
}

/// Exception thrown by StreamingService
class StreamingException implements Exception {
  final String message;

  const StreamingException(this.message);

  @override
  String toString() => 'StreamingException: $message';
}
