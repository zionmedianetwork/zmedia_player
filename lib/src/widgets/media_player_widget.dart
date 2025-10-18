import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/media_controller.dart';
import '../models/player_state.dart';
import '../services/subtitle_service.dart';
import '../services/cache_service.dart';
import '../core/media_config.dart';
import '../models/subtitle_track.dart';
import 'media_controls.dart';
import 'subtitle_view.dart';

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

  /// Subtitle service for managing subtitle tracks
  late final SubtitleService _subtitleService;

  /// Cache service for media caching
  late final CacheService _cacheService;

  /// Whether we're currently in fullscreen mode
  bool _isInFullscreen = false;

  /// Keep alive for performance
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    // Initialize services
    _subtitleService = SubtitleService();
    _cacheService = CacheService(
        widget.controller.config?.cacheConfig ?? const CacheConfig());

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

  /// Force resize the native view to fix sizing issues
  void _forceResizeNativeView() {
    if (!_isDisposed && mounted) {
      debugPrint('Force resizing native view...');
      setState(() {
        // Force a rebuild to ensure proper sizing
      });

      // Additional resize after a delay to ensure the platform view gets the correct size
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && !_isDisposed) {
          setState(() {
            // Final resize to ensure video is properly sized
          });
        }
      });
    }
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

    // Force resize if we detect potential sizing issues
    if (oldWidget.key != widget.key) {
      debugPrint('Widget key changed, forcing resize...');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isDisposed && mounted) {
          _forceResizeNativeView();
        }
      });
    }
  }

  @override
  void dispose() {
    _isDisposed = true;

    // Clean up observers and listeners
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onControllerChanged);

    // Clean up services
    _subtitleService.dispose();
    _cacheService.dispose();

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

    // Don't force rebuild here - let the native view creation handle it
    // This prevents race conditions between media loading and UI updates
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

    // Listen to orientation changes for responsive behavior
    final orientation = MediaQuery.of(context).orientation;
    final isLandscape = orientation == Orientation.landscape;

    // In landscape mode, prioritize video display
    if (isLandscape && widget.expandToFill) {
      return Container(
        color: widget.backgroundColor,
        child: _buildPlayerContent(),
      );
    }

    return _buildPlayerContent();
  }

  Widget _buildPlayerContent() {
    Widget content;

    // Add debugging information
    debugPrint(
        'Building player content - State: ${widget.controller.state.state}, HasNativeView: $_hasNativeView, NativeView: ${_nativeView != null}');

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

          // Subtitle overlay - show when subtitles are enabled
          if (widget.controller.config?.enableSubtitles == true)
            _buildSubtitleOverlay(),

          // Controls overlay - only show when needed
          if (widget.showControls && widget.controller.controlsVisible)
            Positioned.fill(child: _buildControlsOverlay()),
        ],
      ),
    );
  }

  /// Build subtitle overlay
  Widget _buildSubtitleOverlay() {
    if (widget.controller.currentItem == null) {
      return const SizedBox.shrink();
    }

    return SubtitleView(
      subtitleService: _subtitleService,
      position: widget.controller.state.position,
      config:
          widget.controller.config?.subtitleConfig ?? const SubtitleConfig(),
      enabled: widget.controller.config?.enableSubtitles ?? true,
      onTrackChanged: (track) {
        // Handle subtitle track change
        debugPrint('Subtitle track changed to: ${track.title}');
      },
    );
  }

  Widget _buildVideoSurface() {
    // Check if we have media loaded
    if (widget.controller.currentItem == null) {
      debugPrint('No media loaded, showing placeholder...');
      return _buildPlaceholder();
    }

    final playerState = widget.controller.state.state;
    debugPrint(
        'Building video surface - State: $playerState, HasNativeView: $_hasNativeView, NativeView: ${_nativeView != null}');

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

    // If we have a native view, return it with proper sizing and ensure it's visible
    return Container(
      color: Colors.black, // Ensure background is black for video
      child: SizedBox.expand(
        child: _nativeView!,
      ),
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

      // Add a small delay to ensure media is properly loaded
      await Future.delayed(const Duration(milliseconds: 100));

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

      // Set the native view with proper sizing and ensure it's visible
      if (mounted && !_isDisposed) {
        setState(() {
          _hasNativeView = true;
          _nativeView = Container(
            color: Colors.black, // Ensure black background
            child: SizedBox.expand(
              child: nativeView,
            ),
          );
        });
      }

      debugPrint(
          'Native view state set: _hasNativeView=$_hasNativeView, _nativeView=${_nativeView != null}');
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

    // Platform view is ready - trigger a rebuild to ensure it's displayed
    if (mounted && !_isDisposed) {
      // Add a small delay to ensure the platform view is fully initialized
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted && !_isDisposed) {
          setState(() {
            // Force a rebuild to ensure the native view is displayed
          });

          // Additional delay and rebuild to ensure visibility
          Future.delayed(const Duration(milliseconds: 200), () {
            if (mounted && !_isDisposed) {
              setState(() {
                // Final rebuild to ensure video is visible
              });
            }
          });
        }
      });
    }

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Check if we're returning from fullscreen and refresh video surface
    if (!_isDisposed && mounted) {
      // Small delay to ensure we're back from fullscreen
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted && !_isDisposed) {
          refreshVideoSurface();
        }
      });
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

  /// Force recreate the native view (useful for debugging video display issues)
  void forceRecreateNativeView() {
    if (!_isDisposed) {
      debugPrint('Force recreating native view...');
      _cleanupNativeView();
      _createNativeView();
    }
  }

  /// Refresh video surface (useful after returning from fullscreen)
  void refreshVideoSurface() {
    if (!_isDisposed && mounted) {
      debugPrint('Refreshing video surface...');
      setState(() {
        // Force rebuild of video surface
      });

      // Additional refresh after a short delay
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && !_isDisposed) {
          setState(() {
            // Final refresh to ensure video is visible
          });
        }
      });
    }
  }

  /// Update box fit for the current video
  Future<void> updateBoxFit(BoxFit newBoxFit) async {
    if (_isDisposed || !_hasNativeView) return;

    debugPrint('Updating box fit to: $newBoxFit');

    try {
      // Update the box fit through the method channel
      await widget.controller.player.setBoxFit(newBoxFit);

      // Force a refresh of the video surface to apply the new box fit
      await _forceRefreshVideoSurface();
    } catch (e) {
      debugPrint('Error updating box fit: $e');
    }
  }

  /// Force refresh video surface to fix black screen issues
  Future<void> _forceRefreshVideoSurface() async {
    if (_isDisposed) return;

    debugPrint('Force refreshing video surface...');

    // Clean up existing view
    _cleanupNativeView();

    // Wait a bit before recreating
    await Future.delayed(const Duration(milliseconds: 300));

    // Recreate if we still have media
    if (widget.controller.currentItem != null && !_isDisposed) {
      await _createNativeView();
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
