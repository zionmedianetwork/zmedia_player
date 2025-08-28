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
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  /// Whether we have a native view
  bool _hasNativeView = false;

  /// The native view widget
  Widget? _nativeView;

  /// Platform view ID for cleanup
  int? _platformViewId;

  /// Whether the widget is disposed
  bool _isDisposed = false;

  /// Whether we're currently creating a native view
  bool _isCreatingNativeView = false;

  /// Current media item ID to track changes
  String? _currentMediaId;

  /// Keep alive for performance
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    // Listen to app lifecycle changes
    WidgetsBinding.instance.addObserver(this);

    // Initialize player after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isDisposed) {
        _initializePlayer();
      }
    });

    // Listen for media loading events
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(MediaPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Handle controller changes
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _refreshVideoSurface();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;

    // Clean up observers and listeners
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onControllerChanged);

    // Clean up native view
    _cleanupNativeView();

    super.dispose();
  }

  void _onControllerChanged() {
    if (_isDisposed) return;

    final currentItem = widget.controller.currentItem;
    final currentMediaId = currentItem?.id ?? currentItem?.title;

    // Only recreate native view if media changed or we don't have one
    if (currentMediaId != _currentMediaId) {
      _currentMediaId = currentMediaId;

      if (currentItem != null && !_hasNativeView && !_isCreatingNativeView) {
        debugPrint(
            'Media changed, creating native view for: ${currentItem.title}');
        _createNativeView();
      } else if (currentItem == null) {
        debugPrint('No media item, cleaning up native view');
        _cleanupNativeView();
      }
    }

    // Update UI state if mounted
    if (mounted && !_isDisposed) {
      setState(() {
        // State updated
      });
    }
  }

  void _refreshVideoSurface() {
    if (_isDisposed) return;

    debugPrint('Refreshing video surface...');

    // Clean up existing view
    _cleanupNativeView();

    // Recreate the native view if we have media
    if (widget.controller.currentItem != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isDisposed) {
          _createNativeView();
        }
      });
    }
  }

  Future<void> _initializePlayer() async {
    if (_isDisposed) return;

    try {
      if (!widget.controller.player.isInitialized) {
        await widget.controller.initialize();
      }

      debugPrint(
          'Player initialized, current item: ${widget.controller.currentItem?.title}');

      // Create native view if we have media
      if (widget.controller.currentItem != null && !_hasNativeView) {
        await _createNativeView();
      }
    } catch (e) {
      debugPrint('Error initializing player: $e');
      if (mounted && !_isDisposed) {
        setState(() {
          _hasNativeView = false;
          _nativeView = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
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
    // Check if we have media loaded
    if (widget.controller.currentItem == null) {
      debugPrint('No media loaded, showing placeholder...');
      return _buildPlaceholder();
    }

    final playerState = widget.controller.state.state;

    if (playerState == PlayerState.buffering && !_hasNativeView) {
      debugPrint(
          'Player is buffering and no native view, showing buffering...');
      return _buildBuffering();
    }

    if (playerState == PlayerState.error) {
      debugPrint('Player has error, showing error...');
      return _buildError();
    }

    // Only show loading if we don't have a native view yet
    if (!_hasNativeView || _nativeView == null) {
      debugPrint('No native view available, showing buffering...');
      return _buildBuffering();
    }

    debugPrint('Returning native view with type: ${_nativeView.runtimeType}');
    // If we have a native view, return it with proper sizing
    return SizedBox.expand(
      child: _nativeView!,
    );
  }

  Future<void> _createNativeView() async {
    if (_isDisposed || _isCreatingNativeView) return;

    _isCreatingNativeView = true;

    try {
      debugPrint('Creating native view...');

      // Ensure player is initialized before creating native view
      if (!widget.controller.player.isInitialized) {
        debugPrint('Player not initialized, initializing...');
        await widget.controller.initialize();
        if (_isDisposed) return;
        debugPrint('Player initialized successfully');
      }

      // Check if we have a current media item
      final currentItem = widget.controller.currentItem;
      if (currentItem == null) {
        debugPrint('No current media item, cannot create native view');
        if (mounted && !_isDisposed) {
          setState(() {
            _hasNativeView = false;
            _nativeView = null;
          });
        }
        return;
      }

      debugPrint('Creating platform view for media: ${currentItem.title}');

      // Create platform-specific video surface
      const viewType = 'flutter_media_player_view';
      final creationParams = {
        'playerId': widget.controller.player.playerId,
        'boxFit':
            _boxFitToString(widget.boxFit ?? widget.controller.config.boxFit),
      };

      debugPrint('View type: $viewType, params: $creationParams');

      Widget nativeView;
      final platform = Theme.of(context).platform;

      if (platform == TargetPlatform.android) {
        debugPrint('Creating Android view...');
        nativeView = AndroidView(
          viewType: viewType,
          creationParams: creationParams,
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _onPlatformViewCreated,
        );
      } else if (platform == TargetPlatform.iOS) {
        debugPrint('Creating iOS view...');
        nativeView = UiKitView(
          viewType: viewType,
          creationParams: creationParams,
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _onPlatformViewCreated,
        );
      } else {
        debugPrint('Unsupported platform: $platform');
        return;
      }

      debugPrint('Native view created successfully, setting state...');

      // Set the native view
      if (mounted && !_isDisposed) {
        setState(() {
          _hasNativeView = true;
          _nativeView = SizedBox.expand(child: nativeView);
        });
      }

      debugPrint('Native view state set: _hasNativeView=$_hasNativeView');
    } catch (e) {
      debugPrint('Error creating native view: $e');
      // Set error state if platform view creation fails
      if (mounted && !_isDisposed) {
        setState(() {
          _hasNativeView = false;
          _nativeView = null;
        });
      }
    } finally {
      _isCreatingNativeView = false;
    }
  }

  void _cleanupNativeView() {
    debugPrint('Cleaning up native view...');

    if (mounted && !_isDisposed) {
      setState(() {
        _hasNativeView = false;
        _nativeView = null;
        _platformViewId = null;
      });
    } else {
      _hasNativeView = false;
      _nativeView = null;
      _platformViewId = null;
    }
  }

  void _onPlatformViewCreated(int viewId) {
    if (_isDisposed) return;

    _platformViewId = viewId;
    debugPrint('Platform view created with ID: $viewId');

    // Platform view is ready - any additional setup can be done here
    // The MediaController will handle platform communication through method channels
  }

  Widget _buildControlsOverlay() {
    if (widget.customControls != null) {
      return widget.customControls!;
    }

    return AnimatedOpacity(
      opacity: widget.controller.controlsVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: IgnorePointer(
        ignoring: !widget.controller.controlsVisible,
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
              strokeWidth: 2,
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                widget.controller.state.errorMessage ??
                    'Unknown error occurred',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _handleRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  void _handleTap() {
    if (!_isDisposed) {
      widget.controller.toggleControls();
    }
  }

  void _handleDoubleTap() {
    if (!_isDisposed) {
      widget.controller.togglePlayPause();
    }
  }

  void _handleRetry() {
    final currentItem = widget.controller.currentItem;
    if (currentItem != null && !_isDisposed) {
      // Clean up current view before retry
      _cleanupNativeView();
      // Reload the media
      widget.controller.load(currentItem);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (_isDisposed) return;

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        // Hide controls when app goes to background
        widget.controller.forceHideControls();
        break;
      case AppLifecycleState.resumed:
        // Refresh video surface when app comes back to foreground
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_isDisposed) {
            _refreshVideoSurface();
          }
        });
        break;
      case AppLifecycleState.detached:
        // Clean up when app is detached
        _cleanupNativeView();
        break;
      default:
        break;
    }
  }

  double _getVideoAspectRatio() {
    // Try to get actual video aspect ratio from controller state
    try {
      final state = widget.controller.state;
      // Check if we have video dimensions in the state
      // Note: This would need to be added to PlaybackState if video dimensions are needed
      // For now, we'll use a reasonable default based on the media type or duration

      // If we have a current media item, we could potentially get aspect ratio from metadata
      final currentItem = widget.controller.currentItem;
      if (currentItem != null) {
        // Check if the media item has aspect ratio metadata
        // This would depend on how MediaItem is structured
        // For now, assume standard video aspect ratios based on common formats

        // You could potentially add aspectRatio as a property to MediaItem
        // and return currentItem.aspectRatio ?? (16 / 9);
      }
    } catch (e) {
      debugPrint('Error getting video aspect ratio: $e');
    }

    // Return 16:9 as default (most common video aspect ratio)
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

  /// Background color
  final Color backgroundColor;

  const FullscreenMediaPlayer({
    super.key,
    required this.controller,
    this.customControls,
    this.backgroundColor = Colors.black,
  });

  @override
  State<FullscreenMediaPlayer> createState() => _FullscreenMediaPlayerState();
}

class _FullscreenMediaPlayerState extends State<FullscreenMediaPlayer>
    with WidgetsBindingObserver {
  List<DeviceOrientation>? _previousOrientations;
  SystemUiMode? _previousSystemUiMode;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Set fullscreen orientation and hide system UI
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isDisposed) {
        _enterFullscreen();
      }
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);

    // Restore system UI and orientation
    _exitFullscreen();
    super.dispose();
  }

  Future<void> _enterFullscreen() async {
    if (_isDisposed) return;

    try {
      // Store previous settings for restoration
      _previousSystemUiMode = null; // Cannot retrieve current mode

      // Set fullscreen mode
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

      // Set landscape orientation
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } catch (e) {
      debugPrint('Error entering fullscreen: $e');
    }
  }

  Future<void> _exitFullscreen() async {
    if (_isDisposed) return;

    try {
      // Restore system UI
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

      // Restore all orientations
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } catch (e) {
      debugPrint('Error exiting fullscreen: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed && !_isDisposed) {
      // Re-enter fullscreen mode when app resumes
      _enterFullscreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvoked: (didPop) {
        if (didPop && !_isDisposed) {
          _exitFullscreen();
        }
      },
      child: Scaffold(
        backgroundColor: widget.backgroundColor,
        body: SafeArea(
          child: MediaPlayerWidget(
            controller: widget.controller,
            showControls: true,
            customControls: widget.customControls,
            expandToFill: true,
            backgroundColor: widget.backgroundColor,
            onTap: () => widget.controller.toggleControls(),
            onDoubleTap: () => widget.controller.togglePlayPause(),
          ),
        ),
      ),
    );
  }
}
