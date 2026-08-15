import 'package:flutter/material.dart';
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
        continue;
      }
      if (other.isPlaying) {
        other.pause();
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

  const MediaListPlayerConfig({
    this.visibilityThreshold = 0.6,
    this.autoPlay = true,
    this.autoPause = true,
    this.muteWhenNotVisible = false,
    this.pauseOthersOnPlay = true,
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

    if (widget.config.autoPause && widget.controller.isPlaying) {
      widget.controller.pause();
    }
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key('media_list_player_${widget.controller.hashCode}'),
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
        ),
      ),
    );
  }
}

/// A simple visibility detector widget
/// Note: In production, consider using the visibility_detector package
class VisibilityDetector extends StatefulWidget {
  final Widget child;
  final Function(VisibilityInfo) onVisibilityChanged;

  const VisibilityDetector({
    required super.key,
    required this.child,
    required this.onVisibilityChanged,
  });

  @override
  State<VisibilityDetector> createState() => _VisibilityDetectorState();
}

class _VisibilityDetectorState extends State<VisibilityDetector> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkVisibility();
    });
  }

  @override
  void didUpdateWidget(VisibilityDetector oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkVisibility();
    });
  }

  void _checkVisibility() {
    if (!mounted) return;

    final RenderObject? renderObject = context.findRenderObject();
    if (renderObject == null || renderObject is! RenderBox) return;

    final RenderBox renderBox = renderObject;
    final Size size = renderBox.size;
    final Offset position = renderBox.localToGlobal(Offset.zero);

    final double screenHeight = MediaQuery.of(context).size.height;
    final double top = position.dy;
    final double bottom = top + size.height;

    // Calculate visible fraction
    double visibleHeight = 0;
    if (bottom < 0 || top > screenHeight) {
      visibleHeight = 0;
    } else if (top >= 0 && bottom <= screenHeight) {
      visibleHeight = size.height;
    } else if (top < 0 && bottom > 0) {
      visibleHeight = bottom;
    } else if (top < screenHeight && bottom > screenHeight) {
      visibleHeight = screenHeight - top;
    }

    final double visibleFraction = visibleHeight / size.height;

    widget.onVisibilityChanged(VisibilityInfo(
      key: widget.key!,
      size: size,
      visibleBounds: Rect.fromLTWH(
          0, top.clamp(0, screenHeight), size.width, visibleHeight),
      visibleFraction: visibleFraction,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _checkVisibility();
        });
        return false;
      },
      child: widget.child,
    );
  }
}

/// Information about the visibility of a widget
class VisibilityInfo {
  final Key key;
  final Size size;
  final Rect visibleBounds;
  final double visibleFraction;

  const VisibilityInfo({
    required this.key,
    required this.size,
    required this.visibleBounds,
    required this.visibleFraction,
  });
}
