import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/media_controller.dart';
import '../models/player_state.dart';
import 'media_controls.dart';

/// Main widget for displaying video content with optional controls
///
/// This widget provides the video surface and integrates with the media controls.
/// It handles touch interactions, aspect ratio, and control visibility.
class MediaPlayerWidget extends StatefulWidget {
  /// Media controller for this player widget
  final MediaController controller;

  /// Whether to show media controls overlay
  final bool showControls;

  /// Custom controls widget (if null, default controls will be used)
  final Widget? customControls;

  /// Placeholder widget shown when no media is loaded
  final Widget? placeholder;

  /// Widget shown when an error occurs
  final Widget? errorWidget;

  /// Widget shown during buffering
  final Widget? bufferingWidget;

  /// How the video should fit within the available space
  final BoxFit? boxFit;

  /// Background color of the player
  final Color backgroundColor;

  /// Callback when the player widget is tapped
  final VoidCallback? onTap;

  /// Callback when the player widget is double-tapped
  final VoidCallback? onDoubleTap;

  /// Callback when the player widget is long-pressed
  final VoidCallback? onLongPress;

  /// Whether to allow fullscreen mode
  final bool allowFullscreen;

  /// Aspect ratio for the video (if null, uses video's natural aspect ratio)
  final double? aspectRatio;

  /// Whether to expand to fill available space
  final bool expandToFill;

  const MediaPlayerWidget({
    super.key,
    required this.controller,
    this.showControls = true,
    this.customControls,
    this.placeholder,
    this.errorWidget,
    this.bufferingWidget,
    this.boxFit,
    this.backgroundColor = Colors.black,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.allowFullscreen = true,
    this.aspectRatio,
    this.expandToFill = false,
  });

  @override
  State<MediaPlayerWidget> createState() => _MediaPlayerWidgetState();
}

class _MediaPlayerWidgetState extends State<MediaPlayerWidget> {
  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _initializePlayer() async {
    if (!widget.controller.player.isInitialized) {
      await widget.controller.initialize();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, child) {
        return _buildPlayerContent();
      },
    );
  }

  Widget _buildPlayerContent() {
    Widget content;

    // Determine what content to show based on player state
    switch (widget.controller.state.state) {
      case PlayerState.idle:
        content = _buildPlaceholder();
        break;
      case PlayerState.buffering:
        content = _buildBuffering();
        break;
      case PlayerState.error:
        content = _buildError();
        break;
      case PlayerState.ready:
      case PlayerState.playing:
      case PlayerState.paused:
      case PlayerState.completed:
        content = _buildVideoSurface();
        break;
    }

    // Wrap content with gesture detection and controls
    content = _buildInteractiveContent(content);

    // Apply aspect ratio if specified or if we should expand to fill
    if (widget.aspectRatio != null) {
      content = AspectRatio(
        aspectRatio: widget.aspectRatio!,
        child: content,
      );
    } else if (!widget.expandToFill) {
      // Use video's natural aspect ratio (16:9 as fallback)
      final aspectRatio = _getVideoAspectRatio();
      content = AspectRatio(
        aspectRatio: aspectRatio,
        child: content,
      );
    }

    return Container(
      color: widget.backgroundColor,
      child: content,
    );
  }

  Widget _buildInteractiveContent(Widget content) {
    return GestureDetector(
      onTap: widget.onTap ?? _handleTap,
      onDoubleTap: widget.onDoubleTap ?? _handleDoubleTap,
      onLongPress: widget.onLongPress,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Video content
          Positioned.fill(child: content),

          // Controls overlay
          if (widget.showControls)
            Positioned.fill(child: _buildControlsOverlay()),
        ],
      ),
    );
  }

  Widget _buildVideoSurface() {
    return FutureBuilder<Widget>(
      future: _createNativeView(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return snapshot.data!;
        } else {
          return _buildBuffering();
        }
      },
    );
  }

  Future<Widget> _createNativeView() async {
    // Ensure player is initialized before creating native view
    if (!widget.controller.player.isInitialized) {
      await widget.controller.initialize();
    }

    // Create platform-specific video surface
    final viewType = 'flutter_media_player_view';
    final creationParams = {
      'playerId': widget.controller.player.playerId,
      'boxFit':
          _boxFitToString(widget.boxFit ?? widget.controller.config.boxFit),
    };

    if (Theme.of(context).platform == TargetPlatform.android) {
      return AndroidView(
        viewType: viewType,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
      );
    } else if (Theme.of(context).platform == TargetPlatform.iOS) {
      return UiKitView(
        viewType: viewType,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
      );
    } else {
      return _buildPlaceholder();
    }
  }

  void _onPlatformViewCreated(int viewId) {
    // Platform view created, can perform additional setup if needed
  }

  Widget _buildControlsOverlay() {
    if (widget.customControls != null) {
      return widget.customControls!;
    }

    return AnimatedOpacity(
      opacity: widget.controller.controlsVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: GestureDetector(
        onTap: () {
          // Toggle controls visibility on tap
          widget.controller.toggleControls();
        },
        child: MediaControls(
          controller: widget.controller,
          allowFullscreen: widget.allowFullscreen,
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    if (widget.placeholder != null) {
      return widget.placeholder!;
    }

    return Container(
      color: widget.backgroundColor,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.play_circle_outline,
              size: 64,
              color: Colors.white70,
            ),
            SizedBox(height: 16),
            Text(
              'No media loaded',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBuffering() {
    if (widget.bufferingWidget != null) {
      return widget.bufferingWidget!;
    }

    return Container(
      color: widget.backgroundColor,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: Colors.white,
            ),
            SizedBox(height: 16),
            Text(
              'Loading...',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    if (widget.errorWidget != null) {
      return widget.errorWidget!;
    }

    return Container(
      color: widget.backgroundColor,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            const Text(
              'Playback Error',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.controller.state.errorMessage ?? 'Unknown error occurred',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                // Retry loading current item
                final currentItem = widget.controller.currentItem;
                if (currentItem != null) {
                  widget.controller.load(currentItem);
                }
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  void _handleTap() {
    widget.controller.toggleControls();
  }

  void _handleDoubleTap() {
    widget.controller.togglePlayPause();
  }

  double _getVideoAspectRatio() {
    // In a real implementation, this would get the actual video aspect ratio
    // For now, return 16:9 as default
    return 16 / 9;
  }

  String _boxFitToString(BoxFit boxFit) {
    switch (boxFit) {
      case BoxFit.contain:
        return 'contain';
      case BoxFit.cover:
        return 'cover';
      case BoxFit.fill:
        return 'fill';
      case BoxFit.fitWidth:
        return 'fitWidth';
      case BoxFit.fitHeight:
        return 'fitHeight';
      case BoxFit.none:
        return 'none';
      case BoxFit.scaleDown:
        return 'scaleDown';
    }
  }
}

/// Fullscreen media player widget
class FullscreenMediaPlayer extends StatefulWidget {
  /// Media controller for the fullscreen player
  final MediaController controller;

  /// Custom controls widget
  final Widget? customControls;

  const FullscreenMediaPlayer({
    super.key,
    required this.controller,
    this.customControls,
  });

  @override
  State<FullscreenMediaPlayer> createState() => _FullscreenMediaPlayerState();
}

class _FullscreenMediaPlayerState extends State<FullscreenMediaPlayer> {
  @override
  void initState() {
    super.initState();
    // Set fullscreen orientation and hide system UI
    _enterFullscreen();
  }

  @override
  void dispose() {
    // Restore system UI and orientation
    _exitFullscreen();
    super.dispose();
  }

  void _enterFullscreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  void _exitFullscreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: MediaPlayerWidget(
        controller: widget.controller,
        showControls: true,
        customControls: widget.customControls,
        expandToFill: true,
        onTap: () {
          widget.controller.toggleControls();
        },
        onDoubleTap: () {
          widget.controller.togglePlayPause();
        },
      ),
    );
  }
}
