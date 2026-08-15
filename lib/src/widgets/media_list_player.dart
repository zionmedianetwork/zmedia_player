import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../core/media_controller.dart';
import 'media_player_widget.dart';

/// Coordinates mutual exclusion of playback across every live
/// [MediaListPlayer] whose [MediaListPlayerConfig.pauseOthersOnPlay] is
/// enabled (e.g. a vertical feed where only one item should play at a time).
///
/// This follows the same shape as the native single-owner/reference-count
/// coordinators used elsewhere in the plugin for process-wide singleton
/// resources (`NotificationHandler.Ownership` on iOS coordinates
/// `MPRemoteCommandCenter`/`MPNowPlayingInfoCenter`; `AudioSessionCoordinator`
/// coordinates `AVAudioSession`): a private lock-free registry that live
/// instances explicitly register with on `initState` and explicitly
/// unregister from on `dispose`, rather than relying on garbage collection or
/// weak references to avoid retaining disposed controllers.
///
/// Unlike those "single owner" coordinators, this one does not pick or track
/// a single owner — it simply reacts to a *play starting* edge on any
/// registered controller and pauses every other registered controller that
/// is currently playing. This keeps the policy symmetric: any list item can
/// start playback and evict the others, and there is no persistent "current
/// owner" state to get out of sync.
class _MediaListPlaybackCoordinator {
  _MediaListPlaybackCoordinator._();

  /// Process-wide singleton, mirroring `.shared` on the native coordinators.
  static final _MediaListPlaybackCoordinator instance =
      _MediaListPlaybackCoordinator._();

  /// Controllers belonging to currently-mounted [MediaListPlayer] widgets.
  /// Populated explicitly in `initState`/removed explicitly in `dispose` —
  /// never inferred from GC, so a disposed controller can never be retained
  /// here past its widget's teardown.
  final Set<MediaController> _registered = <MediaController>{};

  /// Controllers currently counted as "live" — i.e. visible per their
  /// widget's [MediaListPlayerConfig.visibilityThreshold] — ordered
  /// oldest-became-visible first. This is the LRU queue [_evictExcess] trims
  /// against a caller-supplied `maxConcurrentPlayers` ceiling.
  ///
  /// This is a *policy* cap on how many list items may be simultaneously
  /// active, independent of [MediaListPlayerConfig.pauseOthersOnPlay]: that
  /// flag only reacts to a "just started playing" edge and does nothing for
  /// players that are visible-and-loaded but not (yet) playing, or when the
  /// app disables it (e.g. a muted-preview grid where several items are
  /// expected to play concurrently, just not unboundedly many). Hardware
  /// decoder sessions are a scarce, process-wide resource on both platforms,
  /// so this ceiling is enforced here rather than left to however many the
  /// device happens to tolerate before failing with a generic error.
  final List<MediaController> _liveOrder = <MediaController>[];

  /// Registers [controller] as a participant so it can be paused by (and can
  /// pause) other participants. Safe to call multiple times for the same
  /// controller.
  void register(MediaController controller) {
    _registered.add(controller);
  }

  /// Removes [controller] from the registry. Must be called from `dispose()`
  /// so a torn-down widget's controller is never retained or paused later.
  void unregister(MediaController controller) {
    _registered.remove(controller);
    _liveOrder.remove(controller);
  }

  /// Call when [controller] has just transitioned from not-playing to
  /// playing (an edge, not a level) and its widget's
  /// `pauseOthersOnPlay` is enabled. Pauses every other registered,
  /// currently-playing controller.
  ///
  /// Driven strictly by the play edge — callers must not invoke this on
  /// every state notification, only when playback has just started — so
  /// unrelated state ticks (position updates, buffering, volume changes)
  /// never re-trigger a pause sweep and fight the user.
  void onDidStartPlaying(MediaController controller) {
    // Snapshot before iterating: pausing a controller synchronously updates
    // its own state and could otherwise mutate `_registered` mid-iteration
    // if a listener reacts by unregistering.
    for (final other in _registered.toList()) {
      if (identical(other, controller)) continue;
      if (other.isDisposed) {
        // Defensive cleanup: a controller can be disposed by its owner
        // without going through this widget's dispose() first (e.g. the
        // host app disposes it directly after unmounting the widget).
        _registered.remove(other);
        _liveOrder.remove(other);
        continue;
      }
      if (other.isPlaying) {
        other.pause();
      }
    }
  }

  /// Marks [controller] as live (visible) and enforces [maxConcurrentPlayers]
  /// by pausing the least-recently-became-visible controller(s) once the
  /// live set exceeds it.
  ///
  /// Called on every visibility-threshold crossing into view (not just
  /// once), so scrolling quickly past many items in a row cannot leave the
  /// live set transiently over the cap before an individual item's own
  /// pause-on-invisible has a chance to run.
  void onDidBecomeVisible(
    MediaController controller, {
    required int maxConcurrentPlayers,
  }) {
    _liveOrder.remove(controller);
    _liveOrder.add(controller);
    _evictExcess(maxConcurrentPlayers);
  }

  /// Removes [controller] from the live set. Does not itself pause the
  /// controller — [_MediaListPlayerState._onBecameInvisible] already does
  /// that via `autoPause` before calling this.
  void onDidBecomeInvisible(MediaController controller) {
    _liveOrder.remove(controller);
  }

  /// Pauses the oldest entries in [_liveOrder] until its length is at most
  /// [maxConcurrentPlayers]. Values <= 0 disable the cap.
  void _evictExcess(int maxConcurrentPlayers) {
    if (maxConcurrentPlayers <= 0) return;
    while (_liveOrder.length > maxConcurrentPlayers) {
      final evicted = _liveOrder.removeAt(0);
      if (evicted.isDisposed) continue;
      if (evicted.isPlaying) {
        evicted.pause();
      }
    }
  }
}

/// Configuration for media player behavior in lists
class MediaListPlayerConfig {
  /// Minimum visibility percentage to start playing (0.0 to 1.0)
  final double visibilityThreshold;

  /// Whether to automatically play when visible
  final bool autoPlay;

  /// Whether to automatically pause when not visible
  final bool autoPause;

  /// Whether to mute when scrolled past
  final bool muteWhenNotVisible;

  /// Whether starting playback on this player pauses every other currently
  /// playing [MediaListPlayer] in the app (e.g. a vertical feed where only
  /// one item should ever play at once). Coordination is scoped to
  /// [MediaListPlayer]-hosted controllers only, keyed by controller
  /// identity, and is edge-triggered on "playback just started" — it never
  /// re-pauses on unrelated state ticks (position updates, buffering,
  /// volume changes) while a player is already playing.
  final bool pauseOthersOnPlay;

  /// Hard ceiling on how many [MediaListPlayer] instances (registered with
  /// the shared playback coordinator) may be counted as "live" — currently
  /// visible per [visibilityThreshold] — at once.
  ///
  /// When a player becomes visible and the live set already has
  /// [maxConcurrentPlayers] members, the least-recently-became-visible one
  /// is paused to make room. This bounds concurrent hardware-decoder usage
  /// by policy rather than by however many the device happens to tolerate
  /// before failing with a generic error, and applies even when
  /// [pauseOthersOnPlay] is `false` or a player is visible-and-loaded but
  /// not (yet) playing.
  ///
  /// Values <= 0 disable the cap. Defaults to 2 (the currently-focused item
  /// plus one adjacent/preloading item), matching a typical single-column
  /// vertical feed.
  final int maxConcurrentPlayers;

  const MediaListPlayerConfig({
    this.visibilityThreshold = 0.6,
    this.autoPlay = true,
    this.autoPause = true,
    this.muteWhenNotVisible = false,
    this.pauseOthersOnPlay = true,
    this.maxConcurrentPlayers = 2,
  });
}

/// A media player widget optimized for use in ListView and ScrollView
///
/// Automatically manages playback based on visibility:
/// - Plays when scrolled into view
/// - Pauses when scrolled out of view
/// - Optionally mutes when partially visible
class MediaListPlayer extends StatefulWidget {
  /// The media controller
  final MediaController controller;

  /// Configuration for list behavior
  final MediaListPlayerConfig config;

  /// Whether to show controls
  final bool showControls;

  /// Custom controls widget
  final Widget? customControls;

  /// Placeholder widget shown before video loads
  final Widget? placeholder;

  /// Error widget shown on playback errors
  final Widget? errorWidget;

  /// Aspect ratio of the player
  final double aspectRatio;

  /// Callback when player becomes visible
  final VoidCallback? onVisible;

  /// Callback when player becomes invisible
  final VoidCallback? onInvisible;

  /// Callback when player is tapped
  final VoidCallback? onTap;

  const MediaListPlayer({
    super.key,
    required this.controller,
    this.config = const MediaListPlayerConfig(),
    this.showControls = true,
    this.customControls,
    this.placeholder,
    this.errorWidget,
    this.aspectRatio = 16 / 9,
    this.onVisible,
    this.onInvisible,
    this.onTap,
  });

  @override
  State<MediaListPlayer> createState() => _MediaListPlayerState();
}

class _MediaListPlayerState extends State<MediaListPlayer> {
  bool _isVisible = false;
  double _visibilityFraction = 0.0;
  bool _hasPlayedOnce = false;

  /// Tracks the controller's playing state as of the last notification, so
  /// [_handleControllerStateChange] can detect a play *edge* (not-playing →
  /// playing) rather than reacting to every state tick while already
  /// playing (position updates, buffering, volume/mute changes, etc.).
  bool _wasPlaying = false;

  @override
  void initState() {
    super.initState();
    _wasPlaying = widget.controller.isPlaying;
    // Register with the mutual-exclusion coordinator so this controller can
    // participate in pauseOthersOnPlay — both as a pauser (if its own config
    // enables it) and as something other players can pause. Registration is
    // independent of this widget's own pauseOthersOnPlay value because that
    // flag governs whether *this* player pauses others, not whether it can
    // itself be paused by another list item.
    _MediaListPlaybackCoordinator.instance.register(widget.controller);
    // Listen to controller state changes
    widget.controller.addListener(_handleControllerStateChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerStateChange);
    // Explicit, synchronous removal — never rely on GC to drop a disposed
    // controller from the shared registry.
    _MediaListPlaybackCoordinator.instance.unregister(widget.controller);
    super.dispose();
  }

  void _handleControllerStateChange() {
    final isPlayingNow = widget.controller.isPlaying;
    // Edge-triggered: only act the instant playback starts, never on
    // subsequent notifications while it continues playing. This is what
    // keeps pauseOthersOnPlay from fighting the user — it fires once per
    // genuine "this item started playing" event, not on arbitrary ticks.
    if (isPlayingNow && !_wasPlaying && widget.config.pauseOthersOnPlay) {
      _MediaListPlaybackCoordinator.instance
          .onDidStartPlaying(widget.controller);
    }
    _wasPlaying = isPlayingNow;

    // Handle any controller state changes if needed
    if (mounted) {
      setState(() {});
    }
  }

  /// Driven by the `visibility_detector` package's composition-callback
  /// based detection (see [build]), which genuinely fires on scroll —
  /// unlike the previous hand-rolled `NotificationListener<ScrollNotification>`
  /// implementation this replaced, which was a descendant of the enclosing
  /// `Scrollable` and therefore structurally could never receive its scroll
  /// notifications (they only bubble upward).
  void _handleVisibilityChanged(VisibilityInfo info) {
    final previouslyVisible = _isVisible;

    _visibilityFraction = info.visibleFraction;
    _isVisible = _visibilityFraction >= widget.config.visibilityThreshold;

    // Visibility threshold crossed
    if (_isVisible != previouslyVisible) {
      if (_isVisible) {
        _onBecameVisible();
      } else {
        _onBecameInvisible();
      }
    }

    // Handle muting based on visibility
    if (widget.config.muteWhenNotVisible) {
      if (_visibilityFraction < widget.config.visibilityThreshold &&
          !widget.controller.isMuted) {
        widget.controller.toggleMute();
      } else if (_visibilityFraction >= widget.config.visibilityThreshold &&
          widget.controller.isMuted) {
        widget.controller.toggleMute();
      }
    }
  }

  void _onBecameVisible() {
    debugPrint('MediaListPlayer: Became visible');
    widget.onVisible?.call();

    // Enforce the maxConcurrentPlayers policy cap before considering
    // autoPlay, so a player that would push the live set over the cap is
    // evicted immediately rather than only after autoPlay's own delay.
    _MediaListPlaybackCoordinator.instance.onDidBecomeVisible(
      widget.controller,
      maxConcurrentPlayers: widget.config.maxConcurrentPlayers,
    );

    if (widget.config.autoPlay && !_hasPlayedOnce) {
      _hasPlayedOnce = true;
      // Small delay to ensure smooth scrolling
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && _isVisible) {
          widget.controller.play();
        }
      });
    } else if (widget.config.autoPlay && widget.controller.isPaused) {
      // Resume if it was paused
      widget.controller.play();
    }
  }

  void _onBecameInvisible() {
    debugPrint('MediaListPlayer: Became invisible');
    widget.onInvisible?.call();

    _MediaListPlaybackCoordinator.instance
        .onDidBecomeInvisible(widget.controller);

    if (widget.config.autoPause && widget.controller.isPlaying) {
      widget.controller.pause();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Uses the `visibility_detector` package rather than a hand-rolled
    // NotificationListener<ScrollNotification> (see the removed
    // in-tree VisibilityDetector this replaced, and _handleVisibilityChanged
    // above for why that approach never actually fired on scroll). The
    // package detects visibility via a compositor/layer callback that is
    // independent of the widget's position relative to the enclosing
    // Scrollable, so it fires correctly regardless of ancestor/descendant
    // relationships.
    //
    // Keyed by playerId (stable, unique per controller) rather than
    // `hashCode`/`Object.hashCode`, which is not guaranteed stable or
    // collision-free across the process.
    return VisibilityDetector(
      key: ValueKey('media_list_player_${widget.controller.playerId}'),
      onVisibilityChanged: _handleVisibilityChanged,
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: MediaPlayerWidget(
          controller: widget.controller,
          showControls: widget.showControls,
          customControls: widget.customControls,
          placeholder: widget.placeholder,
          errorWidget: widget.errorWidget,
          onTap: widget.onTap,
          // A list of players must not keep every item's State (and its
          // native decoder/platform view) alive forever once mounted — see
          // MediaPlayerWidget.wantKeepAlive's doc comment.
          wantKeepAlive: false,
        ),
      ),
    );
  }
}
