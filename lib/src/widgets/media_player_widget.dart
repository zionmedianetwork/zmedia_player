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

class _MediaPlayerWidgetState extends State<MediaPlayerWidget>
    with WidgetsBindingObserver {
  /// Whether we have a native view
  bool _hasNativeView = false;

  /// The native view widget
  Widget? _nativeView;

  /// Flag to track if native view has changed and needs rebuild
  bool _nativeViewChanged = false;
  @override
  void initState() {
    super.initState();

    // Listen to app lifecycle changes
    WidgetsBinding.instance.addObserver(this);

    // Initialize player after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializePlayer();
    });

    // Listen for media loading events
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    // Check if media is loaded and we need to create a native view
    if (widget.controller.currentItem != null && !_hasNativeView) {
      print('Media loaded, creating native view...');
      _createNativeView();
    }

    // Only rebuild when necessary - not on every controller change
    // setState(() {}); // ❌ This was causing infinite rebuilds
  }

  void _refreshVideoSurface() {
    print('Refreshing video surface...');
    setState(() {
      // Reset native view state to force recreation
      _hasNativeView = false;
      _nativeView = null;
    });

    // Recreate the native view
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _createNativeView();
    });
  }

  Future<void> _initializePlayer() async {
    try {
      if (!widget.controller.player.isInitialized) {
        await widget.controller.initialize();
      }

      // Don't create native view yet - wait for media to be loaded
      print('Player initialized, waiting for media to be loaded...');
    } catch (e) {
      print('Error initializing player: $e');
      setState(() {
        _hasNativeView = false;
        _nativeView = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only rebuild when necessary - not on every controller change
    return _buildPlayerContent();
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
          // Video content - ensure it fills the available space
          Positioned.fill(child: content),

          // Controls overlay - only show when needed
          if (widget.showControls && widget.controller.controlsVisible)
            Positioned.fill(child: _buildControlsOverlay()),
        ],
      ),
    );
  }

  Widget _buildVideoSurface() {
    print(
        'Building video surface: _hasNativeView=$_hasNativeView, _nativeView=${_nativeView != null}, playerState=${widget.controller.state.state}');

    // Check if we have media loaded
    if (widget.controller.currentItem == null) {
      print('No media loaded, showing placeholder...');
      return _buildPlaceholder();
    }

    // Check player state to determine what to show
    final playerState = widget.controller.state.state;

    if (playerState == PlayerState.buffering) {
      print('Player is buffering, showing buffering...');
      return _buildBuffering();
    }

    if (playerState == PlayerState.error) {
      print('Player has error, showing error...');
      return _buildError();
    }

    // Only show loading if we don't have a native view yet
    if (!_hasNativeView || _nativeView == null) {
      print('No native view available, showing buffering...');
      return _buildBuffering();
    }

    print('Returning native view with type: ${_nativeView.runtimeType}');
    // If we have a native view, return it with proper sizing
    return SizedBox.expand(
      child: _nativeView!,
    );
  }

  Future<void> _createNativeView() async {
    try {
      print('Creating native view...');

      // Ensure player is initialized before creating native view
      if (!widget.controller.player.isInitialized) {
        print('Player not initialized, initializing...');
        await widget.controller.initialize();
        print('Player initialized successfully');
      }

      // Check if we have a current media item
      if (widget.controller.currentItem == null) {
        print('No current media item, cannot create native view');
        setState(() {
          _hasNativeView = false;
          _nativeView = null;
        });
        return;
      }

      print(
          'Creating platform view for media: ${widget.controller.currentItem?.title}');

      // Create platform-specific video surface
      final viewType = 'flutter_media_player_view';
      final creationParams = {
        'playerId': widget.controller.player.playerId,
        'boxFit':
            _boxFitToString(widget.boxFit ?? widget.controller.config.boxFit),
      };

      print('View type: $viewType, params: $creationParams');

      Widget nativeView;
      if (Theme.of(context).platform == TargetPlatform.android) {
        print('Creating Android view...');
        nativeView = SizedBox.expand(
          child: AndroidView(
            viewType: viewType,
            creationParams: creationParams,
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: _onPlatformViewCreated,
          ),
        );
      } else if (Theme.of(context).platform == TargetPlatform.iOS) {
        print('Creating iOS view...');
        nativeView = SizedBox.expand(
          child: UiKitView(
            viewType: viewType,
            creationParams: creationParams,
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: _onPlatformViewCreated,
          ),
        );
      } else {
        print('Unsupported platform: ${Theme.of(context).platform}');
        setState(() {
          _hasNativeView = false;
          _nativeView = null;
        });
        return;
      }

      print('Native view created successfully, setting state...');

      // Set the native view
      setState(() {
        _hasNativeView = true;
        _nativeView = nativeView;
        _nativeViewChanged = true; // Mark that native view has changed
      });

      print(
          'Native view state set: _hasNativeView=$_hasNativeView, _nativeView=${_nativeView != null}');

      // Force a rebuild to ensure the video surface updates with the new native view
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_nativeViewChanged) {
          setState(() {
            _nativeViewChanged = false; // Reset the flag
          });
        }
      });
    } catch (e) {
      print('Error creating native view: $e');
      // Set error state if platform view creation fails
      setState(() {
        _hasNativeView = false;
        _nativeView = null;
      });
    }
  }

  void _onPlatformViewCreated(int viewId) {
    print('Platform view created with ID: $viewId');
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        // Hide controls when app goes to background
        widget.controller.forceHideControls();
        break;
      case AppLifecycleState.resumed:
        // Refresh video surface when app comes back to foreground
        _refreshVideoSurface();
        break;
      default:
        break;
    }
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
