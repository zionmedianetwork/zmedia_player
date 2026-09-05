/// Configuration for streaming protocols (HLS, DASH).
///
/// Wave D wiring status (be precise about what actually reaches native code
/// via [MediaConfig.hlsConfig] / [MediaConfig.dashConfig] and
/// `MediaPlayer._configToMap`, vs. what is serialized but not yet consumed):
///
///  - [enableAdaptiveBitrate], [maxBitrate], [minBitrate]: wired — see their
///    individual dartdocs for the Android/iOS specifics (and the one
///    documented iOS gap: no faithful `minBitrate` there).
///  - [enableAutoQualitySwitch], [qualitySwitchThreshold],
///    [enableBandwidthEstimation], [bitrateStrategy]: cross the platform
///    channel (part of the serialized config map) but are **not read by
///    either native platform**. They only reach `StreamingService`
///    (`lib/src/services/streaming_service.dart`), a separate Dart-only
///    bandwidth-recommendation helper that nothing in this package
///    instantiates automatically — see that class's dartdoc. Constructing a
///    `StreamingService` yourself and wiring it to
///    `MediaPlayer.bandwidthStream`/`setQualityTrack` is the only way these
///    currently have any effect.
///
/// **Which config applies to which item** (issue #87): exactly one of
/// [MediaConfig.hlsConfig] / [MediaConfig.dashConfig] applies to a loaded
/// [MediaItem], chosen by that item's [MediaItem.resolvedStreamingFormat] —
/// its explicit [MediaItem.streamingFormat] when set, else inferred from the
/// URL's *path* (`endsWith('.m3u8')` -> HLS, `endsWith('.mpd')` -> DASH,
/// anything else -> progressive, query string and fragment ignored). The two
/// configs are never cross-applied, so an app whose backend serves HLS to one
/// platform and DASH to another must set **both**; a live item that resolves
/// to a format whose config is `null` logs a debug-only warning explaining
/// that `enableDvr` has fallen back to `false`.
class StreamingConfig {
  /// Whether to enable adaptive bitrate streaming.
  ///
  /// **Android:** when `false`, `DefaultTrackSelector.Parameters
  /// .forceHighestSupportedBitrate` is set, which locks video track
  /// selection to a single fixed track (the highest bitrate within
  /// [maxBitrate]/[minBitrate] bounds) instead of letting ExoPlayer adapt
  /// between renditions.
  ///
  /// **iOS: not honored.** AVPlayer/AVFoundation exposes no API to force
  /// selection onto a single non-adaptive HLS variant — `preferredPeakBitRate`
  /// (see [maxBitrate]) only caps the ceiling ABR is allowed to pick from, it
  /// does not disable ABR itself. This field has no effect on iOS.
  final bool enableAdaptiveBitrate;

  /// Initial bitrate selection strategy.
  ///
  /// Not read by either native platform today — see the class-level dartdoc.
  final BitrateSelectionStrategy bitrateStrategy;

  /// Maximum bitrate to allow, in bits per second.
  ///
  /// **Android:** `DefaultTrackSelector.Parameters.setMaxVideoBitrate`.
  /// **iOS:** `AVPlayerItem.preferredPeakBitRate`.
  final int? maxBitrate;

  /// Minimum bitrate to allow, in bits per second.
  ///
  /// **Android:** `DefaultTrackSelector.Parameters.setMinVideoBitrate`.
  /// **iOS: not honored — there is no faithful equivalent.** AVPlayer has no
  /// API to set a bitrate floor (`preferredPeakBitRate` only caps a
  /// *maximum*); this field is never read on iOS.
  final int? minBitrate;

  /// Whether to enable automatic quality switching.
  ///
  /// Not read by either native platform today — see the class-level dartdoc.
  final bool enableAutoQualitySwitch;

  /// Quality switch threshold (percentage of buffer).
  ///
  /// Not read by either native platform today — see the class-level dartdoc.
  final double qualitySwitchThreshold;

  /// Whether to enable bandwidth estimation.
  ///
  /// Not read by either native platform today — see the class-level dartdoc.
  final bool enableBandwidthEstimation;

  const StreamingConfig({
    this.enableAdaptiveBitrate = true,
    this.bitrateStrategy = BitrateSelectionStrategy.auto,
    this.maxBitrate,
    this.minBitrate,
    this.enableAutoQualitySwitch = true,
    this.qualitySwitchThreshold = 0.8,
    this.enableBandwidthEstimation = true,
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
    );
  }

  /// Converts the base [StreamingConfig] fields to a map for platform
  /// communication. [HlsConfig.toMap] / [DashConfig.toMap] extend this with
  /// their own subclass-specific keys.
  Map<String, dynamic> toMap() {
    return {
      'enableAdaptiveBitrate': enableAdaptiveBitrate,
      'bitrateStrategy': bitrateStrategy.name,
      'maxBitrate': maxBitrate,
      'minBitrate': minBitrate,
      'enableAutoQualitySwitch': enableAutoQualitySwitch,
      'qualitySwitchThreshold': qualitySwitchThreshold,
      'enableBandwidthEstimation': enableBandwidthEstimation,
    };
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
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is QualityTrack && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

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
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AudioTrack && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'AudioTrack(id: $id, name: $name, language: $language)';
  }
}

/// Configuration for HLS (HTTP Live Streaming)
class HlsConfig extends StreamingConfig {
  /// Whether to enable live stream support.
  ///
  /// This duplicates [MediaItem.isLive] (from `lib/src/models/media_item.dart`),
  /// which is already the fully-wired, canonical way to mark a [MediaItem] as
  /// live — it drives `MediaPlayer.isLive`, `MediaPlayer.isSeekable`, and
  /// every other live-aware code path in this package.
  @Deprecated(
    'Duplicates MediaItem.isLive, which is already fully wired into '
    'MediaPlayer.isLive/isSeekable and every other live-aware code path in '
    'this package. Set MediaItem.isLive instead. Kept only so an '
    'already-true value here does not silently stop marking media as live '
    'during the deprecation period: MediaPlayer.load() ORs this into the '
    'effective isLive determination alongside MediaItem.isLive.',
  )
  final bool enableLiveStream;

  /// Whether to enable DVR functionality for live streams.
  ///
  /// Wired: `MediaPlayer.load()` reads this field (when the loaded item's
  /// [MediaItem.resolvedStreamingFormat] is [StreamingFormat.hls] — i.e. it
  /// declared `streamingFormat: StreamingFormat.hls`, or its URL *path* ends
  /// in `.m3u8`) and uses it to gate `MediaPlayer.isSeekable` /
  /// `MediaPlayer.seekTo` for that live item. It is never applied to a DASH
  /// item: an app serving HLS on one platform and DASH on another must set
  /// both [HlsConfig] and [DashConfig] (a live item that resolves to a format
  /// whose config is missing logs a debug-only warning).
  ///
  /// This is a Dart-side gate only — it does not change what ExoPlayer /
  /// AVPlayer themselves do with the live window; it only decides whether
  /// this package lets a seek request through to native at all. Whether a
  /// seek within the DVR window actually succeeds still depends entirely on
  /// the manifest's own live/DVR window (its sliding window /
  /// `EXT-X-PLAYLIST-TYPE`).
  final bool enableDvr;

  /// Live stream latency target.
  ///
  /// **Android:** `MediaItem.LiveConfiguration.Builder.setTargetOffsetMs`.
  /// ExoPlayer actively maintains this cushion via playback-speed
  /// adjustment, so it drifts *toward* the target over time (subject to the
  /// manifest's own live/DVR window — see issue #110, still open, for a
  /// case where the manifest itself defeats this).
  ///
  /// **iOS:** `AVPlayerItem.configuredTimeOffsetFromLive` — iOS 14+ only;
  /// silently has no effect on iOS 13, where the API does not exist. This is
  /// a **join-time** setting, not a maintained target: per the AVFoundation
  /// header, it "indicates how close to the latest content in a live stream
  /// playback will begin after a live start or a seek to
  /// `kCMTimePositiveInfinity`". This package additionally sets
  /// `automaticallyPreservesTimeOffsetFromLive = false`, which per the same
  /// header controls a *different, independent* behavior — whether the
  /// player "skip[s] forward if necessary to restore the playhead's
  /// distance from the live edge" after a rebuffer. `false` does not
  /// disable `configuredTimeOffsetFromLive`; it only means the cushion is
  /// honoured once at join/seek and then is never restored, so the playhead
  /// drifts *away* from the live edge after every rebuffer (the opposite
  /// direction from Android's ExoPlayer, which drifts *toward* its target).
  /// `true` would trade that drift for a visible forward skip after each
  /// rebuffer; this package currently chooses `false` (steady, no skip) but
  /// that is a revisitable trade-off, not a settled one — track
  /// `liveEdgeOffset`/`isAtLiveEdge` (see `docs/api-reference/live-streaming.md`,
  /// "Stall watchdog for live streams") if a consumer needs to detect the
  /// drift this causes.
  final Duration? liveLatency;

  const HlsConfig({
    super.enableAdaptiveBitrate,
    super.bitrateStrategy,
    super.maxBitrate,
    super.minBitrate,
    super.enableAutoQualitySwitch,
    super.qualitySwitchThreshold,
    super.enableBandwidthEstimation,
    // ignore: deprecated_member_use_from_same_package
    this.enableLiveStream = false,
    this.enableDvr = false,
    this.liveLatency,
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
    bool? enableLiveStream,
    bool? enableDvr,
    Duration? liveLatency,
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
      // ignore: deprecated_member_use_from_same_package
      enableLiveStream: enableLiveStream ?? this.enableLiveStream,
      enableDvr: enableDvr ?? this.enableDvr,
      liveLatency: liveLatency ?? this.liveLatency,
    );
  }

  /// Converts this config to a map for platform communication. Consumed by
  /// `MediaPlayerInstance.loadMediaItem` (Android) and
  /// `MediaPlayerInstance.loadMediaItem` (iOS) when the loaded item resolves
  /// to [StreamingFormat.hls] — explicit [MediaItem.streamingFormat] first,
  /// else a URL whose path ends in `.m3u8`.
  @override
  Map<String, dynamic> toMap() {
    return {
      ...super.toMap(),
      // ignore: deprecated_member_use_from_same_package
      'enableLiveStream': enableLiveStream,
      'enableDvr': enableDvr,
      'liveLatencyMs': liveLatency?.inMilliseconds,
    };
  }
}

/// Configuration for DASH (Dynamic Adaptive Streaming over HTTP)
class DashConfig extends StreamingConfig {
  /// Whether to enable live stream support.
  ///
  /// This duplicates [MediaItem.isLive] (from `lib/src/models/media_item.dart`),
  /// which is already the fully-wired, canonical way to mark a [MediaItem] as
  /// live — see [HlsConfig.enableLiveStream] for the full rationale (this
  /// field is the DASH equivalent, same deprecation and same OR-based
  /// fallback behavior in `MediaPlayer.load()`).
  @Deprecated(
    'Duplicates MediaItem.isLive, which is already fully wired into '
    'MediaPlayer.isLive/isSeekable and every other live-aware code path in '
    'this package. Set MediaItem.isLive instead. Kept only so an '
    'already-true value here does not silently stop marking media as live '
    'during the deprecation period: MediaPlayer.load() ORs this into the '
    'effective isLive determination alongside MediaItem.isLive.',
  )
  final bool enableLiveStream;

  /// Whether to enable DVR functionality for live streams. See
  /// [HlsConfig.enableDvr] for the full wiring description — this is the
  /// same Dart-side seek gate, applied when the loaded item's
  /// [MediaItem.resolvedStreamingFormat] is [StreamingFormat.dash] (explicit
  /// `streamingFormat: StreamingFormat.dash`, or a URL whose path ends in
  /// `.mpd`). [HlsConfig] is never substituted for a DASH item.
  final bool enableDvr;

  /// Live stream latency target. See [HlsConfig.liveLatency] for the
  /// Android/iOS wiring — identical, applied when the loaded item resolves to
  /// [StreamingFormat.dash]. Note DASH itself has no iOS playback path at all
  /// (AVPlayer/AVFoundation has no MPEG-DASH support), so this only ever has
  /// an effect on Android in practice.
  final Duration? liveLatency;

  const DashConfig({
    super.enableAdaptiveBitrate,
    super.bitrateStrategy,
    super.maxBitrate,
    super.minBitrate,
    super.enableAutoQualitySwitch,
    super.qualitySwitchThreshold,
    super.enableBandwidthEstimation,
    // ignore: deprecated_member_use_from_same_package
    this.enableLiveStream = false,
    this.enableDvr = false,
    this.liveLatency,
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
    bool? enableLiveStream,
    bool? enableDvr,
    Duration? liveLatency,
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
      // ignore: deprecated_member_use_from_same_package
      enableLiveStream: enableLiveStream ?? this.enableLiveStream,
      enableDvr: enableDvr ?? this.enableDvr,
      liveLatency: liveLatency ?? this.liveLatency,
    );
  }

  /// Converts this config to a map for platform communication. Consumed by
  /// `MediaPlayerInstance.loadMediaItem` (Android only — see [liveLatency])
  /// when the loaded item resolves to [StreamingFormat.dash] — explicit
  /// [MediaItem.streamingFormat] first, else a URL whose path ends in
  /// `.mpd`.
  @override
  Map<String, dynamic> toMap() {
    return {
      ...super.toMap(),
      // ignore: deprecated_member_use_from_same_package
      'enableLiveStream': enableLiveStream,
      'enableDvr': enableDvr,
      'liveLatencyMs': liveLatency?.inMilliseconds,
    };
  }
}
