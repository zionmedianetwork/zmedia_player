import 'package:flutter/material.dart';
import '../core/media_controller.dart';
import 'media_player_widget.dart';

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

  /// Whether to pause other players when this one plays
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

  @override
  void initState() {
    super.initState();
    // Listen to controller state changes
    widget.controller.addListener(_handleControllerStateChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerStateChange);
    super.dispose();
  }

  void _handleControllerStateChange() {
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
