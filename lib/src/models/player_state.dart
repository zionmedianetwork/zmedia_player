/// Represents the current state of the media player
enum PlayerState {
  /// Player is idle, no media loaded
  idle,

  /// Player is loading/buffering media
  buffering,

  /// Player is ready to play
  ready,

  /// Player is currently playing
  playing,

  /// Player is paused
  paused,

  /// Player has completed playback
  completed,

  /// Player encountered an error
  error,
}

/// Which timeline [PlaybackState.position] is currently measured against.
///
/// Reported by the native layer on every `onPositionChanged` event (see the
/// `positionBasis` key in `docs/api-reference/events.md`) so a host never has
/// to *infer* the basis from its own `MediaConfig`. Getting this wrong is a
/// real production hazard: a stall watchdog that samples [PlaybackState.position]
/// and escalates when it stops advancing will escalate forever against a
/// perfectly healthy live edge, because in a sliding window the playhead and
/// the window start advance together and the window-relative position stays
/// roughly *constant*.
///
/// See `docs/api-reference/live-streaming.md` ("Stall watchdog for live
/// streams") for the worked pattern that uses this together with
/// [PlaybackState.liveEdgeOffset].
enum PositionBasis {
  /// [PlaybackState.position] is measured from a fixed zero point that does
  /// not move: the start of the media.
  ///
  /// Reported for VOD on both platforms, and for a live stream on iOS when
  /// DVR is not enabled (in which case position is the `AVPlayerItem`'s own
  /// absolute timeline and keeps advancing during healthy playback).
  ///
  /// Position advancing is a meaningful liveness signal on this basis.
  absolute,

  /// [PlaybackState.position] is measured from the start of the currently
  /// available live/DVR window, which itself slides forward in wall-clock
  /// time.
  ///
  /// Reported for a live stream on Android (ExoPlayer's
  /// `Player.getCurrentPosition()` is always window-relative for a live
  /// item, DVR enabled or not), and for a live stream with `enableDvr: true`
  /// on iOS (where the plugin explicitly translates the absolute item time
  /// to window-relative so position and [PlaybackState.duration] share one
  /// zero point for a DVR scrubber).
  ///
  /// **Position staying constant on this basis is not a stall.** It is what
  /// a healthy playhead riding the live edge of a sliding window looks like.
  /// Use [PlaybackState.liveEdgeOffset] / [PlaybackState.isAtLiveEdge] to
  /// tell a healthy edge from a frozen playhead.
  liveWindow,
}

/// Represents the current playback information
class PlaybackState {
  /// Current player state
  final PlayerState state;

  /// Current playback position
  final Duration position;

  /// Total duration of current media
  final Duration duration;

  /// Current playback speed
  final double speed;

  /// Current volume (0.0 to 1.0)
  final double volume;

  /// Whether the player is muted
  final bool isMuted;

  /// Whether the player is in buffering state
  final bool isBuffering;

  /// Current buffer percentage (0.0 to 1.0)
  final double bufferPercentage;

  /// Error message if state is error
  final String? errorMessage;

  final Duration bufferedPosition;

  /// How far behind the live edge the playhead currently is, or `null` when
  /// the question does not apply or the answer is not yet known.
  ///
  /// `null` for VOD, for a live stream before the native layer has enough
  /// information to answer (e.g. the playlist has only just loaded), and on
  /// any older cached native build that predates this field. Non-`null` for a
  /// live stream — with **or without** `enableDvr` — once the platform can
  /// answer.
  ///
  /// Sourced natively, not computed in Dart — and **the two platforms measure
  /// different quantities under this one name** (issue #120):
  ///  - **Android** — `Player.getCurrentLiveOffset()`, falling back to
  ///    "window length minus window-relative position" when that returns
  ///    `C.TIME_UNSET`. This is distance from the *published* live edge as the
  ///    manifest's own segment timeline describes it, and commonly reads
  ///    15-30s during healthy playback of a standard (non-low-latency)
  ///    stream — a *healthy* Android live player does not sit at an offset of
  ///    zero.
  ///  - **iOS** — the end of `AVPlayerItem.seekableTimeRanges.last` (the live
  ///    edge) minus `AVPlayerItem.currentTime()`. During live playback AVPlayer
  ///    keeps the playhead pinned to that end, so this reads **under a second,
  ///    by construction** — not because iOS plays measurably closer to the
  ///    edge, but because both operands share the same loaded range. One
  ///    consequence: [isAtLiveEdge] is effectively always `true` on iOS.
  ///    Another: a `liveLatency` cushion configured on iOS is not observable
  ///    through this field — the gap it maintains lives between the seekable
  ///    range's end and the published edge, outside what this subtraction can
  ///    see.
  ///
  /// The values are therefore **not comparable across platforms**. What does
  /// hold on both: a genuinely frozen playhead in a sliding window grows this
  /// value without bound, which is why it (not `position`) is the reliable
  /// live-stall signal, and DVR scrub-back grows it correctly on both. See
  /// `docs/api-reference/live-streaming.md`'s "Platform divergence" section
  /// for the full explanation.
  ///
  /// Delivered on the existing `onPositionChanged` event under the
  /// `liveEdgeOffset` key (milliseconds); see `docs/api-reference/events.md`.
  final Duration? liveEdgeOffset;

  /// Which timeline [position] is currently measured against — see
  /// [PositionBasis].
  ///
  /// Defaults to [PositionBasis.absolute], which is also what is reported
  /// between a `MediaPlayer.load()` and the first native `onPositionChanged` event, and on
  /// any older cached native build that predates this field.
  final PositionBasis positionBasis;

  /// Default tolerance used by [isAtLiveEdge]: **15 seconds**.
  ///
  /// A healthy live player is not at offset zero. Standard (non-low-latency)
  /// HLS/DASH players deliberately sit roughly three target segment durations
  /// behind the live edge, so a tolerance of a second or two would report
  /// `false` for a perfectly healthy stream. 15 seconds is the same default
  /// video.js uses for its equivalent `liveTolerance` option, and it is wide
  /// enough to absorb ordinary edge jitter (an ABR switch, a segment boundary)
  /// without flapping a LIVE badge, while still going `false` once a viewer
  /// has scrubbed meaningfully back into a DVR window.
  ///
  /// Low-latency streams should tighten this via [isAtLiveEdgeWithin];
  /// long-segment streams may need to widen it the same way.
  ///
  /// This reasoning is calibrated to Android's measurement of [liveEdgeOffset]
  /// (distance from the *published* live edge). On iOS, where that field sits
  /// under a second by construction during live playback, this tolerance is
  /// not the discriminator doing the work — see [liveEdgeOffset]'s dartdoc.
  static const Duration defaultLiveEdgeTolerance = Duration(seconds: 15);

  const PlaybackState({
    required this.state,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.speed = 1.0,
    this.volume = 1.0,
    this.isMuted = false,
    this.isBuffering = false,
    this.bufferPercentage = 0.0,
    this.bufferedPosition = Duration.zero,
    this.errorMessage,
    this.liveEdgeOffset,
    this.positionBasis = PositionBasis.absolute,
  });

  /// Creates a copy of this playback state with updated values
  PlaybackState copyWith({
    PlayerState? state,
    Duration? position,
    Duration? duration,
    double? speed,
    double? volume,
    bool? isMuted,
    bool? isBuffering,
    double? bufferPercentage,
    Duration? bufferedPosition,
    String? errorMessage,
    Duration? liveEdgeOffset,
    PositionBasis? positionBasis,
    bool clearLiveEdgeOffset = false,
  }) {
    return PlaybackState(
      state: state ?? this.state,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      speed: speed ?? this.speed,
      volume: volume ?? this.volume,
      isMuted: isMuted ?? this.isMuted,
      isBuffering: isBuffering ?? this.isBuffering,
      bufferPercentage: bufferPercentage ?? this.bufferPercentage,
      bufferedPosition: bufferedPosition ?? this.bufferedPosition,
      errorMessage: errorMessage ?? this.errorMessage,
      // `liveEdgeOffset` is legitimately nullable (VOD, or a live item whose
      // offset native cannot answer yet), so `?? this.liveEdgeOffset` alone
      // could never clear a previously-reported value back to null — hence the
      // explicit [clearLiveEdgeOffset] flag, which wins over any passed value.
      liveEdgeOffset:
          clearLiveEdgeOffset ? null : (liveEdgeOffset ?? this.liveEdgeOffset),
      positionBasis: positionBasis ?? this.positionBasis,
    );
  }

  /// Whether the player can play
  bool get canPlay => state == PlayerState.ready || state == PlayerState.paused;

  /// Whether the player can pause
  bool get canPause => state == PlayerState.playing;

  /// Whether the player can seek
  bool get canSeek =>
      state == PlayerState.ready ||
      state == PlayerState.playing ||
      state == PlayerState.paused;

  /// Whether the playhead is currently riding the live edge, within
  /// [defaultLiveEdgeTolerance] (15 seconds).
  ///
  /// `false` whenever [liveEdgeOffset] is `null` — VOD, or a live item whose
  /// offset the platform cannot answer yet. "Am I at the live edge" is not a
  /// meaningful question for VOD, so it is answered `false` rather than
  /// thrown or `null`.
  ///
  /// **Near-degenerate on iOS.** [liveEdgeOffset] sits under a second there by
  /// construction during live playback (see its dartdoc), so this reads
  /// effectively always `true` on iOS — a `false` reading is the informative
  /// signal there, not a steady `true`. On Android, where the offset tracks
  /// distance from the published live edge, this behaves as documented above.
  ///
  /// Use [isAtLiveEdgeWithin] to apply a different tolerance.
  bool get isAtLiveEdge => isAtLiveEdgeWithin(defaultLiveEdgeTolerance);

  /// Whether the playhead is within [tolerance] of the live edge.
  ///
  /// `false` when [liveEdgeOffset] is `null`. A negative offset (the playhead
  /// momentarily reported slightly *ahead* of the last known edge, which
  /// happens transiently on both platforms as the edge advances between
  /// samples) counts as at the edge.
  ///
  /// See [liveEdgeOffset]'s dartdoc for why this is near-degenerately `true`
  /// on iOS for any reasonable [tolerance].
  bool isAtLiveEdgeWithin(Duration tolerance) {
    final offset = liveEdgeOffset;
    if (offset == null) return false;
    return offset <= tolerance;
  }

  /// Whether [position] is measured against a moving zero point, i.e.
  /// [positionBasis] is [PositionBasis.liveWindow].
  ///
  /// When this is `true`, a constant [position] is **not** evidence of a
  /// stall — see [PositionBasis.liveWindow] and [liveEdgeOffset].
  bool get isPositionWindowRelative =>
      positionBasis == PositionBasis.liveWindow;

  /// Progress percentage (0.0 to 1.0)
  double get progress {
    if (duration.inMilliseconds <= 0) return 0.0;
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PlaybackState &&
        other.state == state &&
        other.position == position &&
        other.duration == duration &&
        other.speed == speed &&
        other.volume == volume &&
        other.isMuted == isMuted &&
        other.isBuffering == isBuffering &&
        other.bufferPercentage == bufferPercentage &&
        other.bufferedPosition == bufferedPosition &&
        other.errorMessage == errorMessage &&
        other.liveEdgeOffset == liveEdgeOffset &&
        other.positionBasis == positionBasis;
  }

  @override
  int get hashCode {
    return Object.hash(
      state,
      position,
      duration,
      speed,
      volume,
      isMuted,
      isBuffering,
      bufferPercentage,
      bufferedPosition,
      errorMessage,
      liveEdgeOffset,
      positionBasis,
    );
  }

  @override
  String toString() {
    return 'PlaybackState(state: $state, position: $position, duration: $duration, speed: $speed, positionBasis: $positionBasis, liveEdgeOffset: $liveEdgeOffset)';
  }
}
