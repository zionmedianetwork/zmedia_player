/// Configuration for streaming protocols (HLS, DASH)
class StreamingConfig {
  /// Whether to enable adaptive bitrate streaming
  final bool enableAdaptiveBitrate;

  /// Initial bitrate selection strategy
  final BitrateSelectionStrategy bitrateStrategy;

  /// Maximum bitrate to allow
  final int? maxBitrate;

  /// Minimum bitrate to allow
  final int? minBitrate;

  /// Whether to enable automatic quality switching
  final bool enableAutoQualitySwitch;

  /// Quality switch threshold (percentage of buffer)
  final double qualitySwitchThreshold;

  /// Whether to enable bandwidth estimation
  final bool enableBandwidthEstimation;

  /// Custom streaming headers
  final Map<String, String>? streamingHeaders;

  const StreamingConfig({
    this.enableAdaptiveBitrate = true,
    this.bitrateStrategy = BitrateSelectionStrategy.auto,
    this.maxBitrate,
    this.minBitrate,
    this.enableAutoQualitySwitch = true,
    this.qualitySwitchThreshold = 0.8,
    this.enableBandwidthEstimation = true,
    this.streamingHeaders,
  });

  /// Creates a copy of this config with updated values
  StreamingConfig copyWith({
    bool? enableAdaptiveBitrate,
    BitrateSelectionStrategy? bitrateStrategy,
    int? maxBitrate,
    int? minBitrate,
    bool? enableAutoQualitySwitch,
    double? qualitySwitchThreshold,
    bool? enableBandwidthEstimation,
    Map<String, String>? streamingHeaders,
  }) {
    return StreamingConfig(
      enableAdaptiveBitrate:
          enableAdaptiveBitrate ?? this.enableAdaptiveBitrate,
      bitrateStrategy: bitrateStrategy ?? this.bitrateStrategy,
      maxBitrate: maxBitrate ?? this.maxBitrate,
      minBitrate: minBitrate ?? this.minBitrate,
      enableAutoQualitySwitch:
          enableAutoQualitySwitch ?? this.enableAutoQualitySwitch,
      qualitySwitchThreshold:
          qualitySwitchThreshold ?? this.qualitySwitchThreshold,
      enableBandwidthEstimation:
          enableBandwidthEstimation ?? this.enableBandwidthEstimation,
      streamingHeaders: streamingHeaders ?? this.streamingHeaders,
    );
  }
}

/// Strategy for selecting initial bitrate
enum BitrateSelectionStrategy {
  /// Automatic selection based on bandwidth
  auto,

  /// Start with lowest quality
  lowest,

  /// Start with highest quality
  highest,

  /// Start with medium quality
  medium,
}

/// Represents a quality track in streaming content
class QualityTrack {
  /// Unique identifier for the track
  final String id;

  /// Display name for the track
  final String name;

  /// Bitrate in bits per second
  final int bitrate;

  /// Resolution width
  final int? width;

  /// Resolution height
  final int? height;

  /// Frame rate
  final double? frameRate;

  /// Whether this track is currently selected
  final bool isSelected;

  /// Whether this track is available
  final bool isAvailable;

  /// Codec information
  final String? codec;

  const QualityTrack({
    required this.id,
    required this.name,
    required this.bitrate,
    this.width,
    this.height,
    this.frameRate,
    this.isSelected = false,
    this.isAvailable = true,
    this.codec,
  });

  /// Creates a copy of this track with updated values
  QualityTrack copyWith({
    String? id,
    String? name,
    int? bitrate,
    int? width,
    int? height,
    double? frameRate,
    bool? isSelected,
    bool? isAvailable,
    String? codec,
  }) {
    return QualityTrack(
      id: id ?? this.id,
      name: name ?? this.name,
      bitrate: bitrate ?? this.bitrate,
      width: width ?? this.width,
      height: height ?? this.height,
      frameRate: frameRate ?? this.frameRate,
      isSelected: isSelected ?? this.isSelected,
      isAvailable: isAvailable ?? this.isAvailable,
      codec: codec ?? this.codec,
    );
  }

  @override
  String toString() {
    return 'QualityTrack(id: $id, name: $name, bitrate: ${bitrate ~/ 1000}kbps, resolution: ${width}x$height)';
  }
}

/// Represents an audio track in streaming content
class AudioTrack {
  /// Unique identifier for the track
  final String id;

  /// Display name for the track
  final String name;

  /// Language code (e.g., 'en', 'es', 'fr')
  final String? language;

  /// Whether this track is currently selected
  final bool isSelected;

  /// Whether this track is available
  final bool isAvailable;

  /// Codec information
  final String? codec;

  /// Channel count
  final int? channels;

  /// Sample rate
  final int? sampleRate;

  const AudioTrack({
    required this.id,
    required this.name,
    this.language,
    this.isSelected = false,
    this.isAvailable = true,
    this.codec,
    this.channels,
    this.sampleRate,
  });

  /// Creates a copy of this track with updated values
  AudioTrack copyWith({
    String? id,
    String? name,
    String? language,
    bool? isSelected,
    bool? isAvailable,
    String? codec,
    int? channels,
    int? sampleRate,
  }) {
    return AudioTrack(
      id: id ?? this.id,
      name: name ?? this.name,
      language: language ?? this.language,
      isSelected: isSelected ?? this.isSelected,
      isAvailable: isAvailable ?? this.isAvailable,
      codec: codec ?? this.codec,
      channels: channels ?? this.channels,
      sampleRate: sampleRate ?? this.sampleRate,
    );
  }

  @override
  String toString() {
    return 'AudioTrack(id: $id, name: $name, language: $language)';
  }
}

/// Configuration for HLS (HTTP Live Streaming)
class HlsConfig extends StreamingConfig {
  /// Whether to enable live stream support
  final bool enableLiveStream;

  /// Whether to enable DVR functionality for live streams
  final bool enableDvr;

  /// Live stream latency target
  final Duration? liveLatency;

  /// Whether to enable segment prefetching
  final bool enableSegmentPrefetch;

  /// Maximum number of segments to prefetch
  final int maxPrefetchSegments;

  const HlsConfig({
    super.enableAdaptiveBitrate,
    super.bitrateStrategy,
    super.maxBitrate,
    super.minBitrate,
    super.enableAutoQualitySwitch,
    super.qualitySwitchThreshold,
    super.enableBandwidthEstimation,
    super.streamingHeaders,
    this.enableLiveStream = false,
    this.enableDvr = false,
    this.liveLatency,
    this.enableSegmentPrefetch = true,
    this.maxPrefetchSegments = 3,
  });

  /// Creates a copy of this config with updated values
  @override
  HlsConfig copyWith({
    bool? enableAdaptiveBitrate,
    BitrateSelectionStrategy? bitrateStrategy,
    int? maxBitrate,
    int? minBitrate,
    bool? enableAutoQualitySwitch,
    double? qualitySwitchThreshold,
    bool? enableBandwidthEstimation,
    Map<String, String>? streamingHeaders,
    bool? enableLiveStream,
    bool? enableDvr,
    Duration? liveLatency,
    bool? enableSegmentPrefetch,
    int? maxPrefetchSegments,
  }) {
    return HlsConfig(
      enableAdaptiveBitrate:
          enableAdaptiveBitrate ?? this.enableAdaptiveBitrate,
      bitrateStrategy: bitrateStrategy ?? this.bitrateStrategy,
      maxBitrate: maxBitrate ?? this.maxBitrate,
      minBitrate: minBitrate ?? this.minBitrate,
      enableAutoQualitySwitch:
          enableAutoQualitySwitch ?? this.enableAutoQualitySwitch,
      qualitySwitchThreshold:
          qualitySwitchThreshold ?? this.qualitySwitchThreshold,
      enableBandwidthEstimation:
          enableBandwidthEstimation ?? this.enableBandwidthEstimation,
      streamingHeaders: streamingHeaders ?? this.streamingHeaders,
      enableLiveStream: enableLiveStream ?? this.enableLiveStream,
      enableDvr: enableDvr ?? this.enableDvr,
      liveLatency: liveLatency ?? this.liveLatency,
      enableSegmentPrefetch:
          enableSegmentPrefetch ?? this.enableSegmentPrefetch,
      maxPrefetchSegments: maxPrefetchSegments ?? this.maxPrefetchSegments,
    );
  }
}

/// Configuration for DASH (Dynamic Adaptive Streaming over HTTP)
class DashConfig extends StreamingConfig {
  /// Whether to enable live stream support
  final bool enableLiveStream;

  /// Whether to enable DVR functionality for live streams
  final bool enableDvr;

  /// Live stream latency target
  final Duration? liveLatency;

  /// Whether to enable segment prefetching
  final bool enableSegmentPrefetch;

  /// Maximum number of segments to prefetch
  final int maxPrefetchSegments;

  /// Whether to enable MPD (Media Presentation Description) caching
  final bool enableMpdCaching;

  /// MPD cache expiration duration
  final Duration mpdCacheExpiration;

  const DashConfig({
    super.enableAdaptiveBitrate,
    super.bitrateStrategy,
    super.maxBitrate,
    super.minBitrate,
    super.enableAutoQualitySwitch,
    super.qualitySwitchThreshold,
    super.enableBandwidthEstimation,
    super.streamingHeaders,
    this.enableLiveStream = false,
    this.enableDvr = false,
    this.liveLatency,
    this.enableSegmentPrefetch = true,
    this.maxPrefetchSegments = 3,
    this.enableMpdCaching = true,
    this.mpdCacheExpiration = const Duration(minutes: 5),
  });

  /// Creates a copy of this config with updated values
  @override
  DashConfig copyWith({
    bool? enableAdaptiveBitrate,
    BitrateSelectionStrategy? bitrateStrategy,
    int? maxBitrate,
    int? minBitrate,
    bool? enableAutoQualitySwitch,
    double? qualitySwitchThreshold,
    bool? enableBandwidthEstimation,
    Map<String, String>? streamingHeaders,
    bool? enableLiveStream,
    bool? enableDvr,
    Duration? liveLatency,
    bool? enableSegmentPrefetch,
    int? maxPrefetchSegments,
    bool? enableMpdCaching,
    Duration? mpdCacheExpiration,
  }) {
    return DashConfig(
      enableAdaptiveBitrate:
          enableAdaptiveBitrate ?? this.enableAdaptiveBitrate,
      bitrateStrategy: bitrateStrategy ?? this.bitrateStrategy,
      maxBitrate: maxBitrate ?? this.maxBitrate,
      minBitrate: minBitrate ?? this.minBitrate,
      enableAutoQualitySwitch:
          enableAutoQualitySwitch ?? this.enableAutoQualitySwitch,
      qualitySwitchThreshold:
          qualitySwitchThreshold ?? this.qualitySwitchThreshold,
      enableBandwidthEstimation:
          enableBandwidthEstimation ?? this.enableBandwidthEstimation,
      streamingHeaders: streamingHeaders ?? this.streamingHeaders,
      enableLiveStream: enableLiveStream ?? this.enableLiveStream,
      enableDvr: enableDvr ?? this.enableDvr,
      liveLatency: liveLatency ?? this.liveLatency,
      enableSegmentPrefetch:
          enableSegmentPrefetch ?? this.enableSegmentPrefetch,
      maxPrefetchSegments: maxPrefetchSegments ?? this.maxPrefetchSegments,
      enableMpdCaching: enableMpdCaching ?? this.enableMpdCaching,
      mpdCacheExpiration: mpdCacheExpiration ?? this.mpdCacheExpiration,
    );
  }
}
